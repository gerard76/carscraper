# Fetching our own copies of the photographs, on a clock of its own.
#
# It is also the tail of a scrape, and that is where it kept going missing: a
# round that falls over anywhere -- a site down, a timeout, a bad page -- stops
# before it, and the newest cars sit on the wall as grey boxes until the next
# one. Which is the half of the wall you look at, sorted newest first.
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
