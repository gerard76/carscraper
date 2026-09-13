# Shared plumbing for the scrapers: fetching pages, pacing the requests,
# cleaning up the text the sites hand us and turning a listing into a Car.
class Scrapers::Base
  USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36".freeze

  # Sellers write the make in whatever form they like, and the sites disagree
  # about it too -- 12gebrauchtwagen files Volkswagen under "vw".
  MAKE_ALIASES = {
    "volkswagen"    => %w[volkswagen vw],
    "mercedes-benz" => ["mercedes-benz", "mercedes"],
  }.freeze

  # Seat count the way sellers write it: "7-s", "6-Sitzer", "3 seter",
  # "7-zits", "6p.". Norwegian ads in particular shorten it to a bare "3s".
  SEATS = /\b(\d)\s*-?\s*(?:p\.|pers(?:onen|oons)?|zit(?:s|ter|plaatsen)?|sitze(?:r)?|seter|seater|s)\b/i

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
    response = HTTParty.get(url, headers: { "User-Agent" => USER_AGENT })

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
  def save_car(url:, price:, year:, km: nil, version: nil, country: nil, currency: nil, location: nil, exclude_on: nil)
    if model.excluded_version?(exclude_on || version)
      counts[:excluded] += 1
      return :excluded
    end

    if too_few_seats?(exclude_on || version)
      counts[:too_few_seats] += 1
      return :too_few_seats
    end

    car = model.cars.new
    car.country  = country  if country
    car.currency = currency if currency
    car.url      = url
    car.location = location if location.present?
    car.version  = version
    car.km       = km
    car.year     = year
    car.price    = price

    outcome = if car.save
                :saved
              elsif car.errors.of_kind?(:url, :taken)
                :known
              else
                :rejected
              end

    counts[outcome] += 1
    outcome
  end

  def report
    puts "saved #{counts[:saved]}, already had #{counts[:known]}"
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
    return false unless (seats = text.to_s[SEATS, 1])

    seats.to_i < minimum
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
