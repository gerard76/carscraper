namespace :cars do
  desc "Scrape every source for every model, then tidy up after it"
  task scrape: :environment do
    # Scrape itself is autoloaded, so it cannot be named at the top of this
    # file: rake reads its task files before Rails is loaded.
    #
    # PHOTOS=elsewhere scrapes everything but the pictures. That is for the one
    # caller whose database and whose picture directory are on different
    # machines -- this laptop scraping into the droplet -- and it fetches them
    # over there afterwards instead. See mise.toml.
    Scrape.call(report: method(:puts), photos: ENV["PHOTOS"] != "elsewhere")
  end

  desc "Find the duplicates and the trims you do not want, without scraping"
  task tidy: :environment do
    # Asks the sites nothing. Removes nothing either: what looks gone can only
    # be judged by a round that has just been past the sites.
    Scrape.new(report: method(:puts)).tidy_up
  end
end

namespace :cars do
  desc "Fill in seats and battery: off the stored titles first, then off the listing pages"
  task details: :environment do
    Details.call(report: method(:puts))
  end

  desc "Fetch our own copy of any photograph this machine is missing, and sweep the rest"
  task photos: :environment do
    # Asks the picture servers and nobody else -- no search page, no listing
    # page -- so this is cheap to run on its own and safe to run often.
    #
    # Run it where the pictures are kept: what counts as missing is decided by
    # what is on this machine's disk (Car#photo_stored?), and the sweep at the
    # end deletes from this machine's disk too.
    Photos.call(report: method(:puts))
  end
end
