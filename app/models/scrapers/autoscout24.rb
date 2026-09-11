class Scrapers::Autoscout24
  BASE_URL  = "https://www.autoscout24.nl".freeze
  USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/68.0.3440.84 Safari/537.36".freeze

  # The guid an <article> carries also ends the listing url in the JSON-LD.
  GUID = /[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/

  def initialize(model)
    @model = model
    countries = %w[NL A B D E F L]
    @urls = countries.map do |c|
       "#{BASE_URL}/lst/#{model.make.downcase}/#{model.model.downcase}?sort=age&desc=1&ustate=N%2CU&size=100&page=1&cy=#{c}&atype=C&ac=0"
    end
  end

  def scrape(urls = @urls)
    urls.each do |url|
      puts "scraping #{url}"
      response = HTTParty.get(url, {
          headers: {
            "User-Agent" => USER_AGENT,
          },
        })
      document = Nokogiri::HTML(response.body)
      urls_by_guid = listing_urls(document)
      items = document.xpath("//article")
      excluded = 0
      items.each do |item|
        car = @model.cars.new

        # The listing url is no longer in an <a href>, it only lives in the
        # JSON-LD search results, so look it up by the article's guid.
        car.url = urls_by_guid[item['data-guid']]
        next if car.url.nil?

        car.version = item.at_xpath(".//*[contains(@class, 'ListItemTitle_subtitle')]")&.text.to_s

        # Not the car we are looking for, just parked in its category.
        if @model.excluded_version?(car.version)
          excluded += 1
          next
        end

        car.price   = item['data-price']
        car.km      = item['data-mileage']
        car.year    = Date.parse("01-#{item['data-first-registration']}")
        car.country = item['data-listing-country']

        car.save
      end

      puts "skipped #{excluded} listings matching #{@model.exclude_terms.join(', ')}" if excluded > 0

      unless items.empty?
        puts "trying next page..."
        page = url[/page=(\d+)/, 1].to_i
        urls << url.sub("page=#{page}", "page=#{page + 1}") if page > 0
      end
      puts "sleeping..."
      sleep 3
    end
  end

  private

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

    puts "no JSON-LD search results found, the page layout changed"
    {}
  end
end
