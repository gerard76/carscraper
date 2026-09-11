# AutoScout24 is searched once per country: the same car can be a lot cheaper
# a border away, which is the whole reason to compare them.
#
# The detail url is not in the markup -- the title link carries no href at all
# -- so it is read from the JSON-LD search results, where every entry ends
# with the same guid the <article> carries.
class Scrapers::Autoscout24 < Scrapers::Base
  BASE_URL  = "https://www.autoscout24.nl".freeze
  CURRENCY  = "EUR".freeze
  MAX_PAGES = 40

  # AutoScout24's own country codes. All of these are in the eurozone, so the
  # prices need no conversion.
  COUNTRIES = %w[NL A B D E F L].freeze

  GUID  = /[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/
  TITLE = ".//*[contains(@class, 'ListItemTitle_title')]".freeze

  # The version, in the line under the model name.
  SUBTITLE = ".//*[contains(@class, 'ListItemTitle_subtitle')]".freeze

  # "04-2025": the month the car was first registered.
  REGISTRATION = %r{\A(\d{1,2})-(\d{4})\z}

  def scrape(max_pages: MAX_PAGES)
    COUNTRIES.each do |country|
      (1..max_pages).each do |page|
        document = fetch(page_url(country, page)) or break

        items = document.xpath("//article")
        if items.empty?
          puts "no offers on page #{page}, that was the last one for #{country}"
          break
        end

        urls = listing_urls(document)
        items.each { |item| import(item, urls) }
        pause
      end
    end

    report
  end

  private

  def page_url(country, page)
    query = {
      "sort"   => "age",
      "desc"   => 1,
      "ustate" => "N,U",
      "size"   => 100,
      "page"   => page,
      "cy"     => country,
      "atype"  => "C",
      "ac"     => 0,
    }

    "#{BASE_URL}/lst/#{make_slug}/#{model_slug}?#{URI.encode_www_form(query)}"
  end

  def import(item, urls)
    # Without a url there is nothing to store, and no way back to the ad.
    url = urls[item["data-guid"]]
    if url.nil?
      counts[:no_url] += 1
      return
    end

    # Sellers park other cars in a model's category, and the site reports them
    # under this model, so the full name is what the exclude terms are matched
    # against -- an ID.3 filed under ID. Buzz says so in its own title.
    name = squish("#{item.at_xpath(TITLE)&.text} #{item.at_xpath(SUBTITLE)&.text}")
    unless matches_model?(name)
      counts[:off_model] += 1
      return
    end

    year = registered_on(item["data-first-registration"])
    if year.nil?
      counts[:not_registered] += 1
      return
    end

    save_car(
      url:        url,
      version:    strip_make_and_model(item.at_xpath(SUBTITLE)&.text),
      exclude_on: name,
      price:      item["data-price"],
      km:         item["data-mileage"],
      year:       year,
      country:    item["data-listing-country"],
      currency:   CURRENCY,
    )
  end

  # Maps guid => listing url for every car on the page.
  def listing_urls(document)
    document.xpath("//script[@type='application/ld+json']").each do |script|
      elements = begin
        JSON.parse(script.text).dig("@graph", 0, "mainEntity", "itemListElement")
      rescue JSON::ParserError, TypeError
        nil
      end
      next unless elements.is_a?(Array)

      return elements.each_with_object({}) do |element, urls|
        path = element["url"].to_s
        guid = path[GUID]
        urls[guid] = URI.join(BASE_URL, path).to_s if guid
      end
    end

    puts "  no JSON-LD search results on this page, the layout changed"
    {}
  end

  def registered_on(text)
    return nil unless (match = REGISTRATION.match(text.to_s))

    Date.new(match[2].to_i, match[1].to_i, 1)
  rescue Date::Error
    nil
  end
end
