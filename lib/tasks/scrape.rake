namespace :cars do
  desc "Scrape every source for every model, then tidy up after it"
  task scrape: :environment do
    # Named in here rather than at the top of the file: rake reads its task
    # files before Rails is loaded, and these are Rails' to autoload.
    #
    # Left out on purpose: finn.no. Norway is too far to drive to.
    scrapers = [
      Scrapers::Autoscout24,
      Scrapers::GebrauchtwagenDe,
      Scrapers::Autotrack,
      Scrapers::Gaspedaal
    ]

    Model.find_each do |model|
      scrapers.each do |scraper|
        puts "== #{scraper.name.split("::").last} for #{model.type} =="
        scraper.new(model).scrape
      rescue StandardError => e
        puts "  fell over: #{e.class}: #{e.message}"
      end
    end

    # None of this survives a scrape on its own: listings arrive that are
    # already here under another url, and the bargain of every car moves when
    # a single car is added.
    puts "== tidying up =="
    puts "merged away #{Car.merge_relisted!} rows that were the same listing twice"
    puts "hid #{Car.hide_duplicates!} listings that were already here"
    puts "hid #{Car.hide_small_batteries!} listings whose battery is too small"

    fit = Car.recalculate_bargains!
    puts "worked the bargains out again: #{fit.coefficients.inspect}"
    puts "#{Car.visible.count} cars visible of #{Car.count}"
  end
end
