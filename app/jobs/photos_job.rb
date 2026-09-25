# Fetching our own copies of the photographs, on a clock of its own.
#
# It used to be the tail of a scrape, and that is where it kept going missing.
# A scrape from the laptop writes into the droplet's database but cannot write
# to the droplet's disk, so it hands the fetching over -- `mise run
# scrape:production` ends by telling the droplet to go and get them -- and
# anything that stops before that last line leaves the newest cars on the wall
# as grey boxes until the next cron round. Which is the half of the wall you
# look at, sorted newest first.
#
# So this does not depend on anybody finishing anything. Every quarter of an
# hour it asks what is missing; nearly always that is nothing and it makes no
# requests at all.
class PhotosJob < ApplicationJob
  include GoodJob::ActiveJobExtensions::Concurrency

  # Never two at once: they would fetch the same missing pictures twice over,
  # and the sweep at the end of one would run while the other is still writing.
  good_job_control_concurrency_with(total_limit: 1, key: "photos")

  def perform
    Photos.call
  end
end
