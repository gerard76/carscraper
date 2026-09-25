# When the scrape runs, and which process is allowed to schedule it.
#
# Twice a day: Car::SEEN_WINDOW is three days, so once would keep the pages
# full, but a good price is gone quickly and this way a listing is in the graph
# within twelve hours of appearing. More often than this asks the four sites
# for the same thing over and over.
#
# Only the process started with GOOD_JOB_ENABLE_CRON=1 schedules anything --
# the job role in config/deploy.yml -- so the web container cannot enqueue a
# scrape of its own, and neither can a console.
Rails.application.configure do
  config.good_job.enable_cron = ENV["GOOD_JOB_ENABLE_CRON"] == "1"

  config.good_job.cron = {
    scrape: {
      cron: "0 7,19 * * * Europe/Amsterdam",
      class: "ScrapeJob",
      description: "Every source for every model, and the tidying up after it"
    },

    # Four times an hour, and almost always nothing to do: Photos asks the
    # database what it is missing and asks the picture servers only for that.
    # It is here rather than at the end of a scrape because that is where it
    # kept being skipped -- see PhotosJob.
    photos: {
      cron: "*/15 * * * *",
      class: "PhotosJob",
      description: "Our own copy of any photograph this machine is missing"
    }
  }
end
