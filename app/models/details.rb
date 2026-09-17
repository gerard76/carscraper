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
  HOST = "www.autoscout24.nl".freeze

  # The first round has a few hundred to read and every round after it has the
  # handful that came in. A second between them -- slower than Photos, because
  # this is a full page and not a thumbnail, and faster than the three seconds
  # between search pages, because it is one request and not a crawl.
  MOST_PER_ROUND = 300
  DELAY = 1.0

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
    from_titles + from_pages
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

    filled = wanted.count do |car|
      found = read(car)
      sleep DELAY
      found
    end

    report.call "filled in #{filled} of them"
    filled
  end

  # A listing whose seat count we do not have yet. A car whose page turns out
  # not to state one is asked again next round; that is the same bargain
  # Photos makes with a picture that will not download, and a listing that
  # answers nothing twice is usually one that is about to be removed anyway.
  def unread
    Car.on_offer.where(seats: nil).where("url like ?", "https://#{HOST}/%")
  end

  def read(car)
    listing = fetch(car) or return false

    vehicle = listing["vehicle"] || {}

    changes = {}
    changes[:seats] = vehicle["numberOfSeats"]

    changes[:kwh] = battery(vehicle, listing["description"].to_s) if car.kwh.nil?

    changes.compact!
    return false if changes.empty?

    car.update_columns(changes)
    true
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
    response = HTTParty.get(car.url,
                            headers: { "User-Agent" => Scrapers::Base::USER_AGENT },
                            timeout: 20)
    return nil unless response.code == 200

    script = Nokogiri::HTML(response.body).at_css(DATA) or return nil

    JSON.parse(script.text).dig("props", "pageProps", "listingDetails")
  rescue HTTParty::Error, SocketError, Timeout::Error, Errno::ECONNRESET, JSON::ParserError => e
    report.call "  #{car.id}: #{e.class}"
    nil
  end
end
