# The twice-daily scrape. config/initializers/good_job.rb says when, Scrape
# says what.
class ScrapeJob < ApplicationJob
  include GoodJob::ActiveJobExtensions::Concurrency

  # A scrape takes minutes rather than hours, but if one ever hangs the next
  # must not start on top of it: both would be writing the same rows and both
  # would be asking the same sites at once.
  good_job_control_concurrency_with(total_limit: 1, key: "scrape")

  def perform
    Scrape.call
  end
end
