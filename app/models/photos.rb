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
  # handful that came in -- forty on a busy day. Half a second between them and
  # two hundred at most, so a backlog is spread over days instead of arriving
  # as five requests a second: the pictures are not urgent and nobody has to
  # notice us fetching them.
  MOST_PER_ROUND = 200
  DELAY = 0.5

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
    wanted = Car.on_offer.where.not(image_url: [nil, ""]).reject(&:photo_stored?).first(limit)
    return 0 if wanted.empty?

    report.call "fetching #{wanted.size} #{"photograph".pluralize(wanted.size)}..."

    kept     = 0
    refusals = 0

    wanted.each do |car|
      name = download(car)

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
        previous = car.photo
        car.update_columns(photo: name)
        delete_unless_shared(previous) if previous.present? && previous != name
        kept += 1
      end

      # Also after a failure: a run of misses used to go out at full speed,
      # which is exactly when slowing down matters.
      sleep DELAY
    end

    kept
  end

  def download(car)
    response = HTTParty.get(car.unwrapped_image_url,
                            headers: { "User-Agent" => Scrapers::Base::USER_AGENT },
                            timeout: 15)
    return :refused if [401, 403, 429].include?(response.code)
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
