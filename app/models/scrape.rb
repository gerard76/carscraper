# Everything a scrape is: every source for every model, and then the tidying
# up that none of it survives on its own -- listings arrive that are already
# here under another url, and the bargain of every car moves when a single car
# is added. `bin/rails cars:scrape` and the twice-daily ScrapeJob both come
# through here.
class Scrape
  # A source that has been blocked, or whose markup has changed, returns
  # nothing at all -- and every car it had would then be written off at once.
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
  #
  # `photos: false` leaves the pictures for somebody else to fetch. Photos
  # writes files, and files live on one machine: it has to run where they are.
  # When this laptop scrapes into the droplet's database that is not here --
  # see the `scrape:production` task in mise.toml, which turns this off and
  # then tells the droplet to go and get them.
  def initialize(report: Rails.logger.method(:info), photos: true)
    @report = report
    @photos = photos
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

    fit = tidy_up(since: started)

    # After the tidying up, so nothing is fetched for a car that was just
    # hidden as a duplicate or thrown away as gone. That does mean a battery
    # only Details knows about is not judged by hide_small_batteries! until
    # the next round, which is a round's patience against a few hundred
    # requests spent on cars we were about to drop.
    Details.call(report: report)
    if photos
      Photos.call(report: report)
    else
      report.call "leaving the photographs to the machine that keeps them"
    end

    fit
  end

  # The tidying up on its own, for when something has to be found again without
  # asking the sites anything: `bin/rails cars:tidy`. Without `since:` nothing
  # is removed -- that decision needs to know what a round has just seen.
  def tidy_up(since: nil)
    report.call "== tidying up =="
    report.call "merged away #{Car.merge_relisted!} rows that were the same listing twice"
    report.call "merged away #{Car.merge_retitled!} rows that were one car under several titles"
    report.call "carried what you had said about a car to #{Car.carry_decisions!} other rows of it"

    # Counts every copy, not the ones new since last round: the reasons are
    # dropped and worked out again each time -- see forget_duplicate_reasons!.
    report.call "#{Car.hide_duplicates!} listings are a copy of one that stays"
    report.call "hid #{Car.hide_small_batteries!} listings whose battery is too small"
    report.call "hid #{Car.hide_cargo!} listings that are the van without the seats"

    report.call "put #{Car.show_driven!} cars back that are no longer factory new"
    report.call "read #{Car.settle_gross_batteries!} batteries as the gross figure they are"
    report.call "worked out the battery of #{Car.infer_batteries!} cars whose advert does not say"

    remove_vanished(since) if since

    forgotten = Car.forget_long_gone!
    report.call "forgot #{forgotten} listings gone for #{Car::FORGET_AFTER.inspect} with nothing of yours on them" if forgotten.positive?

    # Twice around: the Pure is spotted by how far under the line it sits, and
    # taking a couple of dozen of them out moves the line the rest are judged
    # against.
    Car.recalculate_bargains!
    report.call "hid #{Car.hide_pures!} listings that are the cheap Pure model"

    fit = Car.recalculate_bargains!
    report.call "worked the bargains out again: #{fit.coefficients.inspect}"
    report.call "#{Car.shown.count} cars on the pages of #{Car.count}"

    fit
  end

  private

  attr_reader :report, :photos

  # Left out on purpose: finn.no. Norway is too far to drive to.
  def scrapers
    [Scrapers::Autoscout24, Scrapers::GebrauchtwagenDe, Scrapers::Autotrack, Scrapers::Gaspedaal]
  end

  def remove_vanished(started)
    by_source = Car.all.group_by(&:source)
    seen      = Car.where(seen_at: started..).group_by(&:source).transform_values(&:size)

    by_source.each do |source, cars|
      missing = cars.reject { |car| car.seen_at && car.seen_at >= started }
      next if missing.empty?

      # A source that answered nothing this round has not told us anything
      # about its cars, and taking them off the pages would empty the site.
      if seen.fetch(source, 0) < cars.size * MOST_OF_THEM
        report.call "left #{missing.size} #{source} #{"listing".pluralize(missing.size)} that look gone alone: " \
                    "this round saw only #{seen.fetch(source, 0)} of its #{cars.size}, so it is the scrape " \
                    "that is broken there, not the site"
        next
      end

      # The site itself can settle most of it in one request each: an offer
      # that is withdrawn answers 410 Gone, and there is no reason to show a
      # dead link for three days waiting to be sure.
      StillThere.call(missing, report: report)

      vanished = missing.select { |car| car.seen_at.nil? || car.seen_at < Car::SEEN_WINDOW.ago }
      vanished = vanished.reject { |car| car.hidden_by_hand? || car.hidden_by == Car::GONE }
      next if vanished.empty?

      vanished.each { |car| car.update_columns(hidden_by: Car::GONE) }
      report.call "took #{vanished.size} #{source} #{"listing".pluralize(vanished.size)} off the pages: nothing has seen them for #{Car::SEEN_WINDOW.inspect}"
    end
  end
end
