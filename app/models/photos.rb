# Our own copies of the photographs.
#
# The wall at /cars/photos shows every car at once, and each card used to point
# straight at the site the car came from -- so opening that page asked their
# servers for six hundred pictures, every time. This asks them once per car,
# ever, and the page is served from here after that.
#
# Only what the grid needs: a card picture is 250x188 and a few kilobytes. The
# big one on a car's own page is a single request for a single car, so that one
# is still theirs.
class Photos
  DIRECTORY = Rails.root.join("public", "photos")

  # Where the browser asks for them.
  PATH = "/photos".freeze

  # The first round has six hundred to fetch and every round after it has the
  # handful that came in. A fifth of a second between them, in the same spirit
  # as the pause between scraped pages.
  MOST_PER_ROUND = 500
  DELAY = 0.2

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
    wanted = Car.on_offer.where.not(image_url: [nil, ""]).reject(&:photo_stored?).first(limit)
    return 0 if wanted.empty?

    report.call "fetching #{wanted.size} #{"photograph".pluralize(wanted.size)}..."

    wanted.count do |car|
      name = download(car)
      next false if name.nil?

      previous = car.photo
      car.update_columns(photo: name)
      delete_unless_shared(previous) if previous.present? && previous != name
      sleep DELAY
      true
    end
  end

  def download(car)
    response = HTTParty.get(car.unwrapped_image_url,
                            headers: { "User-Agent" => Scrapers::Base::USER_AGENT },
                            timeout: 15)
    return nil unless response.code == 200

    type = TYPES[response.headers["content-type"].to_s.split(";").first.to_s.strip]
    return nil if type.nil?

    name = "#{car.photo_digest}.#{type}"
    File.binwrite(DIRECTORY.join(name), response.body)
    name
  rescue HTTParty::Error, SocketError, Timeout::Error, Errno::ECONNRESET, URI::InvalidURIError => e
    report.call "  #{car.id}: #{e.class}"
    nil
  end

  # A file no car points at is a car that was removed or whose listing changed
  # its picture.
  def sweep
    keep = Car.where.not(photo: nil).pluck(:photo).to_set

    Dir.children(DIRECTORY).count do |name|
      next false if name == ".keep" || keep.include?(name)

      File.delete(DIRECTORY.join(name))
      true
    end
  end

  def delete_unless_shared(name)
    return if Car.exists?(photo: name)

    File.delete(DIRECTORY.join(name))
  rescue Errno::ENOENT
    nil
  end
end
