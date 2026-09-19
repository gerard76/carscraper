# What the search pages leave out.
#
# An AutoScout24 card carries the price, the mileage and the power, and not a
# word about how many people fit in the car -- so a six seater and a five
# seater look the same until you open one. The seat count had to be picked out
# of whatever the seller typed in the title, and only one listing in ten says
# anything there.
#
# The listing's own page does say, in a field of its own, and it is the same
# field on every advert. So this asks for that page once per car, the way
# Photos asks for the picture once per car, and fills in what the card could
# not tell us.
#
# Only AutoScout24: it is where four fifths of the cars come from, and it is
# the only one of the four whose detail page we know how to read.
class Details
  # The site whose advert pages this knows how to read. Its German sister
  # serves the same application, so the same reader gets the same answer.
  HOSTS = %w[www.autoscout24.nl www.autoscout24.de].freeze

  # And the way in for a car that is not filed under one of those. A
  # 12gebrauchtwagen link is a redirect to whoever actually has the car, and
  # three out of four of them land on AutoScout24 -- so following it costs one
  # request and reads like any other advert. Of a sample of twelve: nine
  # AutoScout24, two mobile.de (which answers 403 to anyone) and one dealer's
  # own site.
  VIA = "https://www.12gebrauchtwagen.de/c/partner%".freeze

  # The first round has a few hundred to read and every round after it has the
  # handful that came in. A second between them -- slower than Photos, because
  # this is a full page and not a thumbnail, and faster than the three seconds
  # between search pages, because it is one request and not a crawl.
  MOST_PER_ROUND = 300
  DELAY = 1.0

  # When to stop knocking. From the droplet AutoScout24 answers 403 to every
  # listing page -- see "The droplet is blocked" in the README -- so the
  # twice-daily round there would work through three hundred refusals and fill
  # in nothing, which is pointless on our side and rude on theirs.
  #
  # This many in a row with nothing in between ends the round. One 403 among
  # answers is a listing that has been taken down; five in a row is the door.
  REFUSALS_BEFORE_GIVING_UP = 5

  # A hard ceiling on one car, redirects and all. HTTParty's own timeout is per
  # hop and starts again on every chunk that arrives, so a server that answers
  # in a trickle holds the round for minutes: of 110 cars read, two took 273
  # and 196 seconds between them -- eight of the ten minutes -- while the
  # median was 1.3. Both were dealers' own sites at the end of a partner link.
  MAX_SECONDS = 15

  # What a closed door looks like: 403 outright, or 429 asking us to slow down
  # further than a round has patience for.
  REFUSED = [403, 429].freeze

  # Where the whole listing sits, as JSON, on every AutoScout24 advert.
  DATA = "script#__NEXT_DATA__".freeze

  # The battery, where the description names it for this car: VW's own
  # equipment line ("Hochvolt-Batterie 91 kWh (brutto)") or a dealer spelling
  # it out ("Nutzbare Batteriekapazität: 79,0kWh").
  #
  # Labelled on purpose, and read before the text at large. A few lines above
  # sits the disclaimer on bidirectional charging -- "nur in Verbindung mit
  # Hochvolt-Batterien 79 kWh und 86 kWh" -- which names two packs the car may
  # not have, and simply taking the first kWh in the description filed seven
  # long wheelbase cars as short ones. Hence the (?!n): the plural is the
  # disclaimer, the singular is the car.
  LABELLED = /(?:hochvolt-batterie(?!n)|batteriekapazit)\D{0,20}(\d{2,3})(?:[.,]\d)?\s*kwh\b/i

  def self.call(...)
    new(...).call
  end

  def initialize(report: Rails.logger.method(:info), limit: MOST_PER_ROUND)
    @report = report
    @limit  = limit
  end

  def call
    before = counts

    read = from_titles + from_pages
    gained = counts.map { |field, after| [field, before[field] - after] }.to_h

    if gained.values.any?(&:positive?)
      report.call "that is #{gained[:seats]} more seat #{"count".pluralize(gained[:seats])} and #{gained[:kwh]} more #{"battery".pluralize(gained[:kwh])}"
    end

    read
  end

  # What is still missing, to say afterwards what the round actually bought --
  # every page now stores what it said, so "filled in" counts pages read and
  # not answers gained.
  def counts
    { seats: Car.on_offer.where(seats: nil).count, kwh: Car.on_offer.where(kwh: nil).count }
  end

  private

  attr_reader :report, :limit

  # What the adverts already told us and nobody wrote down: the rows scraped
  # before there were columns to put this in. Costs no requests, so it is not
  # capped, and it runs first -- a title that says "6-SITZER" saves a page
  # fetch.
  def from_titles
    filled = Car.where(seats: nil).or(Car.where(kwh: nil)).where.not(version: [nil, ""]).count do |car|
      changes = {}
      changes[:seats] = car.version[Scrapers::Base::SEATS, 1]&.to_i if car.seats.nil?
      changes[:kwh]   = Car.usable_kwh(car.version[Scrapers::Base::BATTERY, 1]&.to_i) if car.kwh.nil?
      changes.compact!

      next false if changes.empty?

      car.update_columns(changes)
      true
    end

    report.call "read seats or battery off #{filled} stored #{"title".pluralize(filled)}" if filled.positive?
    filled
  end

  def from_pages
    wanted = unread.limit(limit).to_a
    return 0 if wanted.empty?

    report.call "reading #{wanted.size} listing #{"page".pluralize(wanted.size)} for seats and battery..."

    filled   = 0
    refusals = 0

    wanted.each do |car|
      case read(car)
      when :refused
        refusals += 1
        if refusals >= REFUSALS_BEFORE_GIVING_UP
          report.call "  turned away #{refusals} times running, so that is the door and not the listings. " \
                      "Leaving the rest; run this from a machine it answers."
          break
        end
      when true
        refusals = 0
        filled += 1
      else
        refusals = 0
      end

      sleep DELAY
    end

    report.call "read #{filled} of them"
    filled
  end

  # A listing whose seat count or battery we do not have, and whose page we
  # have not already asked.
  #
  # Both halves were learned the hard way. Picking cars by a missing seat count
  # alone left a hole -- the page nearly always states the seats, so a car that
  # named its seats in the title but not its battery was never asked at all,
  # 236 of the 583 on offer. And then asking those 236 turned up a battery on
  # only 32 of them, because AutoScout24 mostly does not print one: without
  # details_at the next round would have asked the other 204 all over again,
  # twice a day, for nothing. A page that does not say today does not say
  # tomorrow.
  #
  # RE_READ_AFTER is for the listing that is edited later. A refusal is not an
  # answer, so a blocked round stamps nothing and changes none of this.
  RE_READ_AFTER = 30.days

  def unread
    readable = HOSTS.map { |host| "url like 'https://#{host}/%'" }.join(" or ")

    Car.on_offer.where(seats: nil).or(Car.on_offer.where(kwh: nil))
       .where("#{readable} or url like ?", VIA)
       .where("details_at is null or details_at < ?", RE_READ_AFTER.ago)
       .where("data->>'refused_by' is null")
  end

  def read(car)
    @landed = @refused_by = nil
    listing = fetch(car)
    return listing if listing == :refused

    # Fetched and useless -- a dealer's own site, a listing taken down -- is
    # still a request spent, so it is stamped and not asked again for a month.
    if listing.nil?
      # Where it ended up, so the next question about this car -- why have we
      # nothing on it -- is answerable without asking anyone. A site that
      # refuses everyone is never asked again, not even after RE_READ_AFTER:
      # mobile.de will still be refusing everyone next month.
      car.update_columns(details_at: Time.current,
                         data: { "read_at" => Time.current, "landed_on" => @landed, "refused_by" => @refused_by }.compact)
      return false
    end

    vehicle = listing["vehicle"] || {}

    changes = {}
    changes[:seats] = vehicle["numberOfSeats"] unless car.corrected?(:seats)

    changes[:kwh] = battery(vehicle, listing["description"].to_s) if car.kwh.nil? && !car.corrected?(:kwh)

    # Keep what the page said, not only the two numbers we came for. The
    # request has been made and the answer is full of things worth asking
    # later -- wheelBase and bodyColor, the equipment list, whether it has been
    # in an accident, how many owners, the seller's own text. Reading it again
    # in a month costs another request; a few kilobytes of json does not.
    #
    # Left out: financingAndInsurance (15 kB of loan offers), the tracking
    # parameters, and vehicle.rawData, which is the same facts again in the
    # site's own shorthand.
    changes[:data] = {
      "read_at"     => Time.current,
      "description" => listing["description"],
      "vehicle"     => vehicle.except("rawData")
    }

    changes.compact!

    # Stamped whether or not the page told us anything: what it cost was the
    # request, and that is the thing not to spend twice.
    car.update_columns(changes.merge(details_at: Time.current))
    changes.any?
  end

  # The battery is not a field of its own here, so it is read off three things
  # in turn, most trustworthy first.
  def battery(vehicle, description)
    # The seller's own title: whatever else is on the page, this line is about
    # this car.
    stated = vehicle["modelVersionInput"].to_s[Scrapers::Base::BATTERY, 1]
    return Car.usable_kwh(stated.to_i) if stated

    # VW's equipment line, which names the pack outright.
    stated = description[LABELLED, 1]
    return Car.usable_kwh(stated.to_i) if stated

    # Failing both, every capacity the description mentions -- but only when
    # they are all the same pack. Two different ones means the text is the
    # disclaimer talking, not the car.
    mentioned = description.scan(Scrapers::Base::BATTERY).flatten.map { |kwh| Car.usable_kwh(kwh.to_i) }.uniq
    mentioned.first if mentioned.one?
  end

  def fetch(car)
    response = Timeout.timeout(MAX_SECONDS) do
      HTTParty.get(car.url,
                   headers: { "User-Agent" => Scrapers::Base::USER_AGENT },
                   timeout: 10,
                   limit: 4)
    end
    # A refusal only counts as the door being shut on us when it comes from the
    # site we are a guest of. Following a 12gebrauchtwagen link can end up at
    # mobile.de, which answers 403 to everyone; that is one listing we cannot
    # read, not a reason to end the round.
    @landed = response.request.last_uri.host.to_s

    if REFUSED.include?(response.code)
      # Our own door being shut, or a site we were only passing through.
      return :refused if HOSTS.include?(@landed)

      @refused_by = @landed
      return nil
    end

    return nil unless response.code == 200

    script = Nokogiri::HTML(response.body).at_css(DATA) or return nil

    JSON.parse(script.text).dig("props", "pageProps", "listingDetails")
  rescue HTTParty::Error, SocketError, Timeout::Error, Errno::ECONNRESET, JSON::ParserError => e
    report.call "  #{car.id}: #{e.class}"
    nil
  end
end
