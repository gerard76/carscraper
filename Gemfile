source "https://rubygems.org"

ruby "4.0.2"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3", ">= 8.1.3.1"

# The original asset pipeline for Rails [https://github.com/rails/sprockets-rails]
gem "sprockets-rails"

# Use postgresql as the database for Active Record
gem "pg", "~> 1.6"

# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 6.0"

# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"

# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Rails 8.1.3.1 still calls JSON.parse with a positional options hash, which the
# json 3.x series no longer accepts (it breaks dumping json columns, among other
# things), so stay on json 2.x -- the version Ruby 4.0 ships with.
gem "json", "~> 2.18"

# Scraping the listings
gem "httparty"
gem "nokogiri"

# Unpacks the GeoNames postcode tables, for Car#distance_km
gem "rubyzip", require: false

# Search/filter forms on top of Active Record
gem "ransack"

# Serves the assets, compresses what it serves and terminates the connection in
# front of Puma, so kamal-proxy can talk to one port [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Deploy with Docker in a zero-downtime way [https://kamal-deploy.org]
gem "kamal", require: false

# Background jobs in the database, with a cron that scrapes twice a day
# [https://github.com/bensheldon/good_job]
gem "good_job"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  gem "better_errors"
  gem "binding_of_caller"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
end
