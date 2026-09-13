# AutoTrack is DPG Media's marketplace, so unlike AutoTrader.nl -- which
# resells AutoScout24's stock under its own name -- these are listings we do
# not have yet.
#
# The hard numbers come from the schema.org block, which is far more stable
# than the markup around it. Only the version has to be read from the card,
# because the schema.org data describes the car in generic terms
# ("Elektriciteit, Automaat, MPV") instead of naming the trim.
class Scrapers::Autotrack < Scrapers::Base
  BASE_URL  = "https://www.autotrack.nl".freeze
  COUNTRY   = "nl".freeze
  PER_PAGE  = 30
  MAX_PAGES = 40

  def scrape(max_pages: MAX_PAGES)
    (1..max_pages).each do |page|
      document = fetch(page_url(page)) or break

      listing = item_list(document)
      items   = listing["itemListElement"] || []
      if items.empty?
        puts "no results on page #{page}, that was the last one"
        break
      end

      versions = versions_by_path(document)
      items.each { |element| import(element["item"], versions) }

      pause
      break if page * PER_PAGE >= listing["numberOfItems"].to_i
    end

    report
  end

  private

  # Only pageNumber may be added here. Passing pageSize or sortField as well
  # makes the site drop the make/model filter and return its whole stock.
  def page_url(page)
    url = "#{BASE_URL}/aanbod/merk/#{make_slug}/model/#{model_slug}"
    page > 1 ? "#{url}?pageNumber=#{page}" : url
  end

  def item_list(document)
    document.css('script[type="application/ld+json"]').each do |script|
      data = begin
        JSON.parse(script.text)
      rescue JSON::ParserError
        next
      end

      return data if data["@type"] == "ItemList"
    end

    puts "no schema.org results found, the page layout changed"
    {}
  end

  # Maps "/a/volkswagen-id-buzz-..." => "Pro 8 Intro 77kWh" for every card.
  # The card is found by walking up from its link until the smallest block
  # that holds a heading and links to this listing only.
  def versions_by_path(document)
    document.css('a[href^="/a/"]').each_with_object({}) do |link, versions|
      path    = link["href"].split("?").first
      heading = nil
      node    = link

      6.times do
        node = node.parent or break
        heading = node.at_css("h3")
        break if heading && node.css('a[href^="/a/"]').map { |a| a["href"].split("?").first }.uniq == [path]
        heading = nil
      end
      next unless heading

      subtitle = heading.next_element
      versions[path] = squish(subtitle.text) if subtitle&.name == "p"
    end
  end

  def import(item, versions)
    unless matches_model?(item["model"])
      counts[:off_model] += 1
      return
    end

    # Cars that are still on their way are listed as "prijs verwacht" and
    # carry no price at all.
    price = item.dig("offers", "price")
    if price.nil?
      counts[:no_price] += 1
      return
    end

    url     = item["url"].to_s
    version = versions[URI.parse(url).path] || squish(item["vehicleConfiguration"])

    save_car(
      url:        url,
      # AutoTrack names the seller's town, not a postcode.
      location:   item.dig("offers", "seller", "address", "addressLocality"),
      version:    version,
      exclude_on: squish("#{item['model']} #{version}"),
      price:      price,
      km:         item.dig("mileageFromOdometer", "value"),
      year:       built_on(item["vehicleModelDate"] || item["productionDate"]),
      country:    COUNTRY,
      currency:   "EUR",
    )
  rescue URI::InvalidURIError
    counts[:rejected] += 1
  end

  # AutoTrack only publishes the year on its result pages, not the month.
  def built_on(year)
    return nil unless year.to_s.match?(/\A\d{4}\z/)

    Date.new(year.to_i, 1, 1)
  end
end
