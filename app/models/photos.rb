# Our own copies of the photographs.
#
# The wall at /cars/photos shows every car at once, and each card used to point
# straight at the site the car came from -- so opening that page asked their
# servers for six hundred pictures, every time. This asks them once per car,
# ever, and the page is served from here after that.
#
# Two sizes, both ours. The card on the wall is whatever the search page
# showed -- 250x188 and 8 kB from AutoScout24, 1280x960 and 84 kB from
# 12gebrauchtwagen -- and a car's own page wants something better than a
# thumbnail, so the big one is fetched here as well and served from here too.
# A page of ours asks a seller's server for nothing at all; the scrapers ask,
# once per car, for each size we do not already have.
#
# Which is at most one extra request per car, and for the 455 that arrive at
# 1280x960 it is none: that file is already bigger than the 1024x768 we would
# ask for.
class Photos
  DIRECTORY = Rails.root.join("public", "photos")

  # Where the browser asks for them.
  PATH = "/photos".freeze

  # The first round has six hundred to fetch and every round after it has the
  # handful that came in -- forty on a busy day. Half a second between them and
  # two hundred at most, so a backlog is spread over days instead of arriving
  # as five requests a second: the pictures are not urgent and nobody has to
  # notice us fetching them.
  MOST_PER_ROUND = 200
  DELAY = 0.5

  # The two sizes, and where each one is read and written. Card pictures come
  # first in a round: they are what the wall needs, and a car that arrived this
  # round has no picture of any size until one is here.
  SIZES = {
    card: { url: :unwrapped_image_url, digest: :photo_digest,       column: :photo },
    big:  { url: :large_image_url,     digest: :large_photo_digest, column: :large_photo }
  }.freeze

  # A picture server that starts saying no is saying it about us, not about
  # this picture. Same bargain as Details makes with the listing pages.
  REFUSALS_BEFORE_GIVING_UP = 5

  # The extension follows what the bytes actually are, not what the url says:
  # AutoScout24 serves ".jpg/250x188.webp", which is a webp.
  TYPES = {
    "image/webp" => "webp",
    "image/jpeg" => "jpg",
    "image/png"  => "png",
    "image/gif"  => "gif"
  }.freeze

  def self.call(...)
    new(...).call
  end

  def initialize(report: Rails.logger.method(:info), limit: MOST_PER_ROUND)
    @report = report
    @limit  = limit
  end

  def call
    FileUtils.mkdir_p(DIRECTORY)

    fetched = fetch_missing
    report.call "kept #{fetched} #{"photograph".pluralize(fetched)} of our own" if fetched.positive?
    swept = sweep
    report.call "threw away #{swept} #{"photograph".pluralize(swept)} nothing points at any more" if swept.positive?

    fetched
  end

  private

  attr_reader :report, :limit

  def fetch_missing
    wanted = missing
    return 0 if wanted.empty?

    report.call "fetching #{wanted.size} #{"photograph".pluralize(wanted.size)}..."

    kept     = 0
    refusals = 0

    wanted.each do |car, size|
      name = download(car, size)

      case name
      when :refused
        refusals += 1
        if refusals >= REFUSALS_BEFORE_GIVING_UP
          report.call "  turned away #{refusals} times running, so that is us and not the pictures. Leaving the rest."
          break
        end
      when nil
        refusals = 0
      else
        refusals = 0
        column   = SIZES.fetch(size)[:column]
        previous = car.public_send(column)
        car.update_columns(column => name)
        delete_unless_shared(previous) if previous.present? && previous != name
        kept += 1
      end

      # Also after a failure: a run of misses used to go out at full speed,
      # which is exactly when slowing down matters.
      sleep DELAY
    end

    kept
  end

  # The round's work, card pictures first and the big ones filling whatever is
  # left of it. A first pass has 562 big ones waiting, so at 200 a round and
  # two rounds a day it is a day and a half before every car has one -- and
  # until then its page shows the card picture, not the seller's server.
  def missing
    # Newest first: a car that came in this round is the one at the top of the
    # wall, and the top of the wall is what anybody looks at.
    cards = Car.on_offer.where.not(image_url: [nil, ""]).order(created_at: :desc)
               .reject(&:photo_stored?).map { |car| [car, :card] }
    return cards.first(limit) if cards.size >= limit

    big = Car.on_offer.select(&:wants_large_photo?).map { |car| [car, :big] }
    (cards + big).first(limit)
  end

  def download(car, size)
    response = HTTParty.get(car.public_send(SIZES.fetch(size)[:url]),
                            headers: Scrapers::Base::IMAGE_HEADERS,
                            timeout: 15)
    return :refused if [401, 403, 429].include?(response.code)
    return nil unless response.code == 200

    type = TYPES[response.headers["content-type"].to_s.split(";").first.to_s.strip]
    return nil if type.nil?

    name = "#{car.public_send(SIZES.fetch(size)[:digest])}.#{type}"
    File.binwrite(DIRECTORY.join(name), response.body)
    name
  rescue HTTParty::Error, SocketError, Timeout::Error, Errno::ECONNRESET, URI::InvalidURIError => e
    report.call "  #{car.id}: #{e.class}"
    nil
  end

  # A file no car points at is a car that was removed or whose listing changed
  # its picture.
  def sweep
    keep = (Car.where.not(photo: nil).pluck(:photo) +
            Car.where.not(large_photo: nil).pluck(:large_photo)).to_set

    Dir.children(DIRECTORY).count do |name|
      next false if name == ".keep" || keep.include?(name)

      File.delete(DIRECTORY.join(name))
      true
    end
  end

  def delete_unless_shared(name)
    return if Car.exists?(photo: name) || Car.exists?(large_photo: name)

    File.delete(DIRECTORY.join(name))
  rescue Errno::ENOENT
    nil
  end
end
