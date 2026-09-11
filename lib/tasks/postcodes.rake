namespace :postcodes do
  desc "Download the GeoNames postcode tables and import them, for Car#distance_km"
  task import: :environment do
    require "zip"

    total = Postcode.import!
    puts "#{total} postcodes stored"
    puts "run Car.recalculate_distances! to work the cars already stored out again"
  end
end
