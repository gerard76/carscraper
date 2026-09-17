# Everything a scrape is: every source for every model, and then the tidying
# up that none of it survives on its own -- listings arrive that are already
# here under another url, and the bargain of every car moves when a single car
# is added. `bin/rails cars:scrape` and the twice-daily ScrapeJob both come
# through here.
class Scrape
  # A source that has been blocked, or whose markup has changed, returns
  # nothing at all -- and remove_vanished! would then delete every car it had.
  # So a source's listings are only removed when this round saw most of what
  # that source already had.
  #
  # Per source, because the sources fail one at a time: from the droplet
  # AutoScout24 and AutoTrack answer 403 while 12gebrauchtwagen hands over
  # fifty pages, and a count over the whole database would let 12gebrauchtwagen
  # vouch for a site nobody could reach.
  MOST_OF_THEM = 0.5

  def self.call(...)
    new(...).call
  end

  # Somewhere to write to: the rake task passes `puts`, the job passes the log.
  def initialize(report: Rails.logger.method(:info))
    @report = report
  end

  def call
    started = Time.current

    Model.find_each do |model|
      scrapers.each do |scraper|
        report.call "== #{scraper.name.split("::").last} for #{model.type} =="
        scraper.new(model).scrape
      rescue StandardError => e
        report.call "  fell over: #{e.class}: #{e.message}"
      end
    end

    fit = tidy_up(started)

    # After the tidying up, so nothing is fetched for a car that was just
    # hidden as a duplicate or thrown away as gone. That does mean a battery
    # only Details knows about is not judged by hide_small_batteries! until
    # the next round, which is a round's patience against a few hundred
    # requests spent on cars we were about to drop.
    Details.call(report: report)
    Photos.call(report: report)

    fit
  end

  private

  attr_reader :report

  # Left out on purpose: finn.no. Norway is too far to drive to.
  def scrapers
    [Scrapers::Autoscout24, Scrapers::GebrauchtwagenDe, Scrapers::Autotrack, Scrapers::Gaspedaal]
  end

  def tidy_up(started)
    report.call "== tidying up =="
    report.call "merged away #{Car.merge_relisted!} rows that were the same listing twice"
    report.call "hid #{Car.hide_duplicates!} listings that were already here"
    report.call "hid #{Car.hide_small_batteries!} listings whose battery is too small"

    remove_vanished(started)

    # Twice around: the Pure is spotted by how far under the line it sits, and
    # taking a couple of dozen of them out moves the line the rest are judged
    # against.
    Car.recalculate_bargains!
    report.call "hid #{Car.hide_pures!} listings that are the cheap Pure model"

    fit = Car.recalculate_bargains!
    report.call "worked the bargains out again: #{fit.coefficients.inspect}"
    report.call "#{Car.visible.count} cars visible of #{Car.count}"

    fit
  end

  def remove_vanished(started)
    by_source = Car.all.group_by(&:source)
    seen      = Car.where(seen_at: started..).group_by(&:source).transform_values(&:size)

    by_source.each do |source, cars|
      vanished = cars.select { |car| Car.vanished.exists?(car.id) }
      next if vanished.empty?

      if seen.fetch(source, 0) < cars.size * MOST_OF_THEM
        report.call "left #{vanished.size} #{source} #{"listing".pluralize(vanished.size)} that look gone alone: " \
                    "this round saw only #{seen.fetch(source, 0)} of its #{cars.size}, so it is the scrape " \
                    "that is broken there, not the site"
      else
        vanished.each(&:destroy)
        report.call "removed #{vanished.size} #{source} #{"listing".pluralize(vanished.size)} that are no longer on the site"
      end
    end
  end
end
