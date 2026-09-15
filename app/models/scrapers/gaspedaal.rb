# Gaspedaal.nl is the Dutch aggregator: it collects from Marktplaats, the ANWB,
# dealer sites and a few dozen others, so its stock is wider than AutoTrack's.
#
# The whole result set sits in a schema.org ItemList on the model's page --
# there is no second page to fetch. What it does not give is a build month, so
# the year lands in the middle of the year, or a postcode, so the seller's town
# stands in for one.
class Scrapers::Gaspedaal < Scrapers::Base
  BASE_URL = "https://www.gaspedaal.nl".freeze
  COUNTRY  = "nl".freeze

  # The model page holds every listing at once.
  def scrape(max_pages: 1)
    path = model_path
    if path.nil?
      puts "gaspedaal has no page for a #{model.type}"
      return report
    end

    document = fetch("#{BASE_URL}#{path}")
    return report if document.nil?

    listings(document).each { |listing| import(listing) }

    report
  end

  private

  # Gaspedaal's slugs are its own -- "id.buzz", but "id3" and "id-buzz-cargo"
  # -- so rather than guess, the make's page is asked which one is this model.
  # It has to be the model itself: "ID. Buzz Cargo" sits right next to it.
  def model_path
    document = fetch("#{BASE_URL}/#{make_slug}")
    return nil if document.nil?

    wanted = compact(model.model)
    link = document.css("a[href]").find do |anchor|
      anchor["href"].to_s.start_with?("/#{make_slug}/") && compact(anchor.text) == wanted
    end

    link && link["href"]
  end

  # "ID.Buzz", "ID-Buzz" and "id buzz" all have to meet.
  def compact(text)
    I18n.transliterate(text.to_s).downcase.gsub(/[^a-z0-9]/, "")
  end

  def listings(document)
    document.xpath("//script[@type='application/ld+json']").each do |script|
      data = JSON.parse(script.text) rescue next
      next unless data.is_a?(Hash) && data["@type"] == "ItemList"

      return Array(data["itemListElement"]).map { |element| element["item"] || element }
    end

    puts "no schema.org results found, the page layout changed"
    []
  end

  def import(listing)
    unless matches_model?("#{listing['brand']} #{listing['model']}")
      counts[:off_model] += 1
      return
    end

    price = listing.dig("offers", "price")
    if price.nil?
      counts[:no_price] += 1
      return
    end

    year = built_in_year(listing["vehicleModelDate"] || listing["productionDate"])
    if year.nil?
      counts[:not_registered] += 1
      return
    end

    save_car(
      url:        listing["@id"],
      version:    strip_make_and_model(listing["name"]),
      exclude_on: listing["name"],
      price:      price,
      km:         listing.dig("mileageFromOdometer", "value"),
      year:       year,
      location:   listing.dig("offers", "seller", "address", "addressLocality"),
      image:      Array(listing["image"]).first,
      country:    COUNTRY,
      currency:   "EUR",
    )
  end
end
