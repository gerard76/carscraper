class Scrapers::Autoscout24

  def initialize(model)
    @model = model
    countries = %w[NL A B D E F L]
    @urls = countries.map do |c|
       "https://www.autoscout24.nl/lst/#{model.make.downcase}/#{model.model.downcase}?sort=age&desc=1&ustate=N%2CU&size=100&page=1&cy=#{c}&atype=C&ac=0"
    end
  end

  def scrape(urls = @urls)
    urls.each do |url|
      puts "scraping #{url}"
      response = HTTParty.get(url, {
          headers: {
            "User-Agent" => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/68.0.3440.84 Safari/537.36",
          },
        })
      document = Nokogiri::HTML(response.body)
      document = Nokogiri::HTML(response.body)
      items = document.xpath("//article")
      items.each do |item|
        car = @model.cars.new

        a = item.at_xpath(".//a")
        car.url = URI.join(url, a[:href]).to_s.split('?').first

        car.version = item.at_xpath(".//span[contains(@class, 'ListItem_version')]").text

        car.price   = item['data-price']
        car.km      = item['data-mileage']
        car.year    = Date.parse("01-#{item['data-first-registration']}")
        car.country = item['data-listing-country']

        car.save
      end

      unless items.empty?
        puts "trying next page..."
        match = url.match(/page=(\d)&.*/)
        binding.break if match.nil?
        page = url.match(/page=(\d)&.*/)[1].to_i
        urls << url.gsub("page=#{page}", "page=#{page + 1}")
      end
      puts "sleeping..."
      sleep 3
    end
  end
end
