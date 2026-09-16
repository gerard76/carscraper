namespace :cars do
  desc "Scrape every source for every model, then tidy up after it"
  task scrape: :environment do
    # Scrape itself is autoloaded, so it cannot be named at the top of this
    # file: rake reads its task files before Rails is loaded.
    Scrape.call(report: method(:puts))
  end
end
