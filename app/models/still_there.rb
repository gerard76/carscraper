# Is the advert still there?
#
# A listing that stops turning up in a round is usually sold, and the link
# usually says so outright: 12gebrauchtwagen answers 410 Gone the moment an
# offer is withdrawn. Waiting SEEN_WINDOW for silence to add up means three
# days of a car on the pages whose link opens nothing, which is how cars 5092
# and 4501 were found -- by clicking them.
#
# So a round asks, once, about the listings it did not see this time, and takes
# a 410 or a 404 for the answer it is. Anything else leaves the car alone: a
# redirect, a timeout, or a 403 from a site that refuses data centres says
# nothing about whether the car is sold, and then the three-day window does its
# slower work.
class StillThere
  # A round asks about the ones it missed, which is a handful on a normal day
  # and a few dozen after a site has had a clear-out. A second between them --
  # this is one request per car and the answer is a header.
  MOST_PER_ROUND = 60
  DELAY = 1.0

  # The site saying the offer is gone. Nothing else counts: a 500 is the site
  # having a bad day.
  GONE_CODES = [404, 410].freeze

  # The door, rather than an answer about this car. Same bargain Details makes.
  REFUSED = [403, 429].freeze
  REFUSALS_BEFORE_GIVING_UP = 5

  # A hard ceiling per car, redirects and all: a partner link goes through two
  # hops and can end up at a dealer's own site that answers in a trickle.
  MAX_SECONDS = 10

  def self.call(...)
    new(...).call
  end

  # `missing` is what this round did not see, of one source it did reach.
  def initialize(missing, report: Rails.logger.method(:info), limit: MOST_PER_ROUND)
    @missing = Array(missing)
    @report  = report
    @limit   = limit
  end

  def call
    # Never a car you crossed off yourself, and never one already written off:
    # those would be asked about again every round, for ever.
    wanted = missing.reject { |car| car.hidden_by_hand? || car.hidden_by == Car::GONE }.first(limit)
    return 0 if wanted.empty?

    report.call "asking #{wanted.size} #{"listing".pluralize(wanted.size)} this round did not see whether they are still there..."

    gone     = 0
    refusals = 0

    wanted.each do |car|
      case ask(car)
      when :gone
        car.update_columns(hidden_by: Car::GONE)
        gone += 1
        refusals = 0
      when :refused
        refusals += 1
        if refusals >= REFUSALS_BEFORE_GIVING_UP
          report.call "  turned away #{refusals} times running, so that is the door and not the adverts. Leaving the rest."
          break
        end
      else
        refusals = 0
      end

      sleep DELAY
    end

    report.call "  #{gone} said gone" if gone.positive?
    gone
  end

  private

  attr_reader :missing, :report, :limit

  def ask(car)
    response = Timeout.timeout(MAX_SECONDS) do
      HTTParty.get(car.url, headers: Scrapers::Base::PAGE_HEADERS, timeout: 8, limit: 4)
    end

    return :gone if GONE_CODES.include?(response.code)
    return :refused if REFUSED.include?(response.code)

    :there
  rescue HTTParty::Error, SocketError, Timeout::Error, Errno::ECONNRESET, URI::InvalidURIError => e
    report.call "  #{car.id}: #{e.class}"
    :unknown
  end
end
