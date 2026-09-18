namespace :cars do
  desc "Scrape every source for every model, then tidy up after it"
  task scrape: :environment do
    # Scrape itself is autoloaded, so it cannot be named at the top of this
    # file: rake reads its task files before Rails is loaded.
    Scrape.call(report: method(:puts))
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
end
