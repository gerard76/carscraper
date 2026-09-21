# Shared plumbing for the scrapers: fetching pages, pacing the requests,
# cleaning up the text the sites hand us and turning a listing into a Car.
class Scrapers::Base
  # What a browser of Gerard's sends, because that is who this is browsing for.
  # Looking at these pages by hand is the same act as looking at them from
  # here, and it went out under one lonely header claiming to be a Chrome from
  # November 2024 while sending none of the fifteen a Chrome actually sends.
  #
  # Captured on 21 September 2026 from his own Chrome, by pointing it at a
  # listener on localhost and writing down what arrived -- not invented, and
  # not lifted out of anyone's session either: no cookies, and no Referer we
  # did not actually come from.
  #
  # This ages. Chrome ships about ten versions a year, so a number left here
  # long enough starts saying "old browser" out loud. Recapture it now and
  # then; CHROME is the only place it is written down.
  CHROME = "153".freeze

  USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
               "(KHTML, like Gecko) Chrome/#{CHROME}.0.0.0 Safari/537.36".freeze

  # On every request, whatever it is for.
  #
  # Accept-Encoding is deliberately absent. Chrome offers "gzip, deflate, br,
  # zstd", and Net::HTTP stops unzipping for you the moment you set that header
  # yourself -- so copying it would hand Nokogiri a bag of compressed bytes,
  # and we could not read brotli or zstd anyway. Left alone, Net::HTTP sends
  # its own gzip/deflate line and unpacks the answer.
  BROWSER_HEADERS = {
    "User-Agent"         => USER_AGENT,
    "Accept-Language"    => "en-GB,en-US;q=0.9,en;q=0.8",
    "sec-ch-ua"          => %("Google Chrome";v="#{CHROME}", "Not_A Brand";v="8", "Chromium";v="#{CHROME}"),
    "sec-ch-ua-mobile"   => "?0",
    "sec-ch-ua-platform" => %("macOS")
  }.freeze

  # A page you open: a search page, or a listing's own page.
  PAGE_HEADERS = BROWSER_HEADERS.merge(
    "Accept"                    => "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif," \
                                   "image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
    "Upgrade-Insecure-Requests" => "1",
    "Sec-Fetch-Site"            => "none",
    "Sec-Fetch-Mode"            => "navigate",
    "Sec-Fetch-User"            => "?1",
    "Sec-Fetch-Dest"            => "document"
  ).freeze

  # A picture. Chrome asks for images with a different Accept and says on the
  # envelope that it is a picture it is after, not a page.
  IMAGE_HEADERS = BROWSER_HEADERS.merge(
    "Accept"         => "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8",
    "Sec-Fetch-Site" => "cross-site",
    "Sec-Fetch-Mode" => "no-cors",
    "Sec-Fetch-Dest" => "image"
  ).freeze

  # Sellers write the make in whatever form they like, and the sites disagree
  # about it too -- 12gebrauchtwagen files Volkswagen under "vw".
  MAKE_ALIASES = {
    "volkswagen"    => %w[volkswagen vw],
    "mercedes-benz" => ["mercedes-benz", "mercedes"],
  }.freeze

  # Seat count the way sellers write it: "7-s", "6-Sitzer", "3 seter",
  # "7-zits", "6p.". Norwegian ads in particular shorten it to a bare "3s".
  SEATS = /\b(\d)\s*-?\s*(?:p\.|pers(?:onen|oons)?|zit(?:s|ter|plaatsen)?|sitze(?:r)?|seter|seater|s)\b/i

  # The battery, as "86 kWh", "79kWh" or "79,0 kWh". Whether that is the gross
  # or the net figure is the seller's choice and they make both; Car.usable_kwh
  # sorts that out.
  #
  # Not a slash after it: "0,00 kWh/100 km" is what the car uses, not what it
  # holds, and without this the energy label on a listing reads as a battery
  # of nought.
  # Not followed by /100: that is consumption, "18,5 kWh/100 km", and not the
  # pack. It used to refuse any slash at all, which also threw away the way
  # sellers write a title -- "Pro 86 kWh / 286 PK LWB 7 persoons", "91KWh / 6
  # Seats / Carplay" -- and those are unmistakably the battery.
  BATTERY = %r{(\d{2,3})(?:[.,]\d)?\s*kwh\b(?!\s*/\s*100)}i

  DELAY     = 3
  MAX_PAGES = 40

  def initialize(model)
    @model  = model
    @counts = Hash.new(0)
  end

  def scrape
    raise NotImplementedError, "#{self.class} has to implement #scrape"
  end

  private

  attr_reader :model, :counts

  def fetch(url)
    puts "scraping #{url}"
    response = HTTParty.get(url, headers: PAGE_HEADERS)

    unless response.code == 200
      puts "  got HTTP #{response.code}, giving up on this page"
      return nil
    end

    Nokogiri::HTML(response.body)
  rescue HTTParty::Error, SocketError, Timeout::Error, Errno::ECONNRESET => e
    puts "  request failed (#{e.class}: #{e.message})"
    nil
  end

  def pause
    puts "sleeping..."
    sleep DELAY
  end

  # Order matters: Car#km= looks at country, so that has to be set first.
  def save_car(url:, price:, year:, km: nil, version: nil, country: nil, currency: nil, location: nil, image: nil, exclude_on: nil)
    if model.excluded_version?(exclude_on || version)
      counts[:excluded] += 1
      return :excluded
    end

    if too_few_seats?(exclude_on || version)
      counts[:too_few_seats] += 1
      return :too_few_seats
    end

    car = model.cars.new
    car.seen_at = Time.current
    car.country  = country  if country
    car.currency = currency if currency
    car.url      = url
    car.location = location if location.present?
    car.image_url = image if image.present?
    car.version  = version
    car.km       = km
    car.year     = year
    car.price    = price

    # Whatever the ad happens to say. Most say nothing, and nothing is what
    # they get: a blank here means "not stated", never "none".
    car.seats = seats_in(exclude_on || version)
    car.kwh   = battery_in(exclude_on || version)

    # The same listing can come back under a new url -- 12gebrauchtwagen's
    # redirect rotates its offer_id -- so it is looked up by what it is, not
    # by where it lives today.
    outcome = if (stored = Car.find_by(fingerprint: car.identity_digest))
                refresh(car, stored)
              elsif car.save
                :saved
              elsif car.errors.of_kind?(:url, :taken)
                refresh(car)
              else
                :rejected
              end

    counts[outcome] += 1
    outcome
  end

  # A listing we already have. The seller may have dropped the price since, or
  # the car may have driven on, and a stale price is worse than no price on a
  # graph you read for bargains. Only what the site owns is touched: whether a
  # car is in the bin, and any note on it, are yours.
  def refresh(fresh, stored = nil)
    stored ||= Car.find_by(url: fresh.url)
    return :known if stored.nil?

    # Seen on the site today, whether or not anything about it changed. What
    # stops being stamped has been sold.
    stored.update_columns(seen_at: Time.current)

    stored.url      = fresh.url
    stored.price    = fresh.price
    stored.km       = fresh.km
    stored.version  = fresh.version if fresh.version.present?
    stored.location = fresh.location if fresh.location.present? && stored.location.blank?
    stored.image_url = fresh.image_url if fresh.image_url.present?

    # Only ever filled in, never wiped: Details reads these off the listing's
    # own page, which knows far more than the search card, and a re-scrape of
    # that card must not throw its answer away.
    stored.seats = fresh.seats if fresh.seats.present? && !stored.corrected?(:seats)
    stored.kwh   = fresh.kwh   if fresh.kwh.present? && !stored.corrected?(:kwh)

    return :known unless stored.changed?

    stored.save ? :updated : :rejected
  end

  def report
    puts "saved #{counts[:saved]}, already had #{counts[:known]}, updated #{counts[:updated]}"
    puts "skipped #{counts[:excluded]} listings matching #{model.exclude_terms.join(', ')}" if counts[:excluded] > 0
    puts "skipped #{counts[:leasing]} leasing offers, whose price is a monthly rate" if counts[:leasing] > 0
    puts "skipped #{counts[:no_price]} listings without a price" if counts[:no_price] > 0
    puts "skipped #{counts[:not_registered]} listings with no registration date (never registered)" if counts[:not_registered] > 0
    puts "skipped #{counts[:too_few_seats]} listings advertised with fewer than #{model.min_seats} seats" if counts[:too_few_seats] > 0
    puts "#{counts[:rejected]} listings did not pass validation (price too low, missing year, ...)" if counts[:rejected] > 0
    puts "ignored #{counts[:off_model]} listings that were not a #{model.type}" if counts[:off_model] > 0
    puts "skipped #{counts[:no_url]} listings that came without a link" if counts[:no_url] > 0
    counts
  end

  # Some sites give a build year and no month. The middle of the year is the
  # honest guess: January would put every one of those cars up to half a year
  # older than it is, which on the graph reads as half a year of depreciation
  # too little, and they would all look overpriced.
  def built_in_year(year)
    return nil unless year.to_s.match?(/\A\d{4}\z/)

    Date.new(year.to_i, 7, 1)
  end

  # Collapses runs of whitespace, including the non breaking spaces finn.no
  # puts inside its numbers.
  def squish(text)
    text.to_s.gsub(/[[:space:]]+/, " ").strip
  end

  # None of the sites can be asked for a seat count. AutoScout24 can, but that
  # also throws away every listing where the seller left the field empty, so
  # the cargo van -- which is not always advertised as a Cargo -- is spotted in
  # the ad text instead. Only a listing that names a seat count can be judged;
  # the rest are kept.
  def too_few_seats?(text)
    minimum = model.min_seats.to_i
    return false if minimum.zero?
    return false unless (seats = seats_in(text))

    seats < minimum
  end

  def seats_in(text)
    text.to_s[SEATS, 1]&.to_i
  end

  # The net capacity, so that the two ways of quoting one pack -- 84 kWh gross
  # and 79 net are the same battery -- do not read as two different cars.
  def battery_in(text)
    Car.usable_kwh(text.to_s[BATTERY, 1]&.to_i)
  end

  # Guards against a site quietly dropping our filter and handing back its
  # whole stock -- better to import nothing than to import every car listed.
  def matches_model?(text)
    return false if text.to_s.empty?

    squish(text).match?(/#{model_pattern}/i)
  end

  # The sites repeat make and model in the ad title; the version is whatever
  # is left. "VW ID.BUZZ 79 kWh 210 kW Pro KR" -> "79 kWh 210 kW Pro KR"
  def strip_make_and_model(text)
    version = squish(text)

    loop do
      before  = version
      version = version.sub(/\A#{make_pattern}[\s.\-]*/i, "")
      version = version.sub(/\A#{model_pattern}[\s.\-]*/i, "")
      break if version == before
    end

    version
  end

  def make_pattern
    @make_pattern ||= begin
      names = MAKE_ALIASES.fetch(model.make.to_s.downcase, [model.make.to_s])
      "(?:#{names.map { |name| loose_pattern(name) }.join('|')})"
    end
  end

  def model_pattern
    @model_pattern ||= "(?:#{loose_pattern(model.model)})"
  end

  # "ID-Buzz" should also match "ID.Buzz", "ID. Buzz" and "id buzz".
  def loose_pattern(name)
    name.to_s.scan(/[[:alnum:]]+/).map { |token| Regexp.escape(token) }.join('[\s.\-]*')
  end

  def slug(text)
    text.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
  end

  def make_slug  = slug(model.make)
  def model_slug = slug(model.model)
end
