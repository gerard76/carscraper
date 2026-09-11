# finn.no is the Norwegian marketplace. Prices are in kroner, so Car#set_eur
# converts them.
#
# finn has no make/model slug we can build a url from -- its filters run on
# internal ids -- so this searches on free text and then throws away anything
# that came back as a different model.
#
# Price and version come from the schema.org block; year and mileage are only
# in the cards, so those are read per listing from the spec line
# ("2023 . 43 000 km . El . 418 km rekkevidde"). Careful with that line: the
# second distance is the range of the battery, not the odometer.
class Scrapers::FinnNo < Scrapers::Base
  BASE_URL  = "https://www.finn.no/mobility/search/car".freeze
  COUNTRY   = "no".freeze
  CURRENCY  = "NOK".freeze
  MAX_PAGES = 20

  SPECS = /\A(\d{4})\D{1,3}(?:([\d][\d.[[:space:]]]*?)[[:space:]]*km\b)?/
  ITEM  = %r{/item/(\d+)}

  # finn lists leasing offers among the cars for sale, and the schema.org data
  # does not say so -- only the card gives it away, by quoting the price per
  # month. Without this those turn up as an ID. Buzz of a few thousand euro.
  MONTHLY = %r{kr\s*/\s*mnd}i

  def scrape(max_pages: MAX_PAGES)
    seen = Set.new

    (1..max_pages).each do |page|
      document = fetch(page_url(page)) or break

      items = listed_items(document)
      if items.empty?
        puts "no results on page #{page}, that was the last one"
        break
      end

      specs = specs_by_id(document)
      fresh = items.reject { |item| seen.include?(item["url"]) }

      # finn answers a page number past the last one with results again
      # instead of an empty page, so stop as soon as nothing is new.
      if fresh.empty?
        puts "page #{page} only repeated listings we already saw, stopping"
        break
      end

      fresh.each do |item|
        seen << item["url"]
        import(item, specs)
      end
      pause
    end

    report
  end

  private

  def page_url(page)
    query = { "q" => "#{model.make} #{model.model}", "sort" => "PUBLISHED_DESC", "page" => page }

    "#{BASE_URL}?#{URI.encode_www_form(query)}"
  end

  def listed_items(document)
    script = document.at_css("script#seoStructuredData")
    unless script
      # Past the last page finn drops the block altogether, so an empty page
      # is expected here; only complain when it did show us cars.
      puts "no schema.org results found, the page layout changed" if document.at_css("article.sf-search-ad")
      return []
    end

    (JSON.parse(script.text).dig("mainEntity", "itemListElement") || []).filter_map { |element| element["item"] }
  rescue JSON::ParserError
    puts "could not read the schema.org results"
    []
  end

  # Maps the finn listing id => [year, mileage] taken from the card's spec
  # line. The line is found by its shape rather than by class name, because
  # the class names on this page are generated.
  def specs_by_id(document)
    document.css("article.sf-search-ad").each_with_object({}) do |article, specs|
      link = article.at_css('a[href*="/mobility/item/"]') or next
      id   = link["href"][ITEM, 1] or next

      line = article.css("span, div, p").find do |node|
        node.element_children.empty? && squish(node.text).match?(SPECS)
      end
      next unless line

      match = squish(line.text).match(SPECS)
      specs[id] = { year: match[1], km: match[2], monthly: squish(article.text).match?(MONTHLY) }
    end
  end

  def import(item, specs)
    unless matches_model?(item["model"])
      counts[:off_model] += 1
      return
    end

    url  = item["url"].to_s
    card = specs[url[ITEM, 1]] || {}

    if card[:monthly]
      counts[:leasing] += 1
      return
    end

    version = squish(item["description"])

    save_car(
      url:        url,
      version:    version,
      exclude_on: squish("#{item['model']} #{version}"),
      price:      item.dig("offers", "price"),
      km:         card[:km],
      year:       registered_on(card[:year]),
      country:    COUNTRY,
      currency:   CURRENCY,
    )
  end

  # The cards only carry the year, not the month.
  def registered_on(year)
    return nil unless year.to_s.match?(/\A\d{4}\z/)

    Date.new(year.to_i, 1, 1)
  end
end
