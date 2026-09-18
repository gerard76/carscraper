# 12gebrauchtwagen.de is an aggregator: it searches mobile.de, heycar,
# autohero, carwow and a few others, so its stock hardly overlaps with what
# AutoScout24 shows us.
#
# Beware that the site also lists leasing offers, whose price is a monthly
# rate. s[price_or_rate]=price leaves those out; the card is checked again
# below in case that filter ever stops working.
class Scrapers::GebrauchtwagenDe < Scrapers::Base
  BASE_URL  = "https://www.12gebrauchtwagen.de".freeze
  COUNTRY   = "d".freeze
  MAX_PAGES = 80

  SORT_NEWEST_FIRST = 6

  # The site files some makes under a short name of its own.
  SITE_MAKES = { "volkswagen" => "vw" }.freeze

  # "EZ 11/2023", or "EZ -/2022" when only the year is known.
  REGISTRATION = %r{EZ\s*(?:(\d{1,2})|-)\s*/\s*(\d{4})}
  MILEAGE      = /\A[\d.,\s]+km\z/

  def scrape(max_pages: MAX_PAGES)
    (1..max_pages).each do |page|
      document = fetch(page_url(page)) or break

      cards = document.css("a.offer-card-link")
      if cards.empty?
        puts "no offers on page #{page}, that was the last one"
        break
      end

      cards.each { |card| import(card) }
      pause
    end

    report
  end

  private

  def page_url(page)
    query = {
      "s[sort]"           => SORT_NEWEST_FIRST,
      "s[price_or_rate]"  => "price",
      "page"              => page,
    }

    "#{BASE_URL}/auto/#{make_slug}/#{model_slug}?#{URI.encode_www_form(query)}"
  end

  def make_slug
    SITE_MAKES.fetch(model.make.to_s.downcase) { super }
  end

  def import(card)
    title = squish(card["title"])

    # The slug only filters when the make is spelled the way the site spells
    # it; without that it quietly returns every car it has.
    unless matches_model?(title)
      counts[:off_model] += 1
      return
    end

    price = squish(card.at_css(".offer-card-price")&.text)
    if leasing?(card, price)
      counts[:leasing] += 1
      return
    end

    pills = card.css(".offer-card-pill.primary-spec").map { |pill| squish(pill.text) }
    year  = registered_on(pills.find { |pill| pill.match?(REGISTRATION) })

    # A car that has never been registered has no EZ date -- the card shows
    # its energy use in that spot instead. Around one in ten offers here is
    # such a car, and without a year there is nothing to plot it against.
    if year.nil?
      counts[:not_registered] += 1
      return
    end

    location = squish(card.at_css(".offer-card-location")&.text)

    save_car(
      url:        card["href"],
      location:   location,
      image:      card.at_css("img")&.[]("src"),
      version:    strip_make_and_model(title),
      exclude_on: title,
      price:      price,
      km:         pills.find { |pill| pill.match?(MILEAGE) },
      year:       year,
      # This is a German site, but it searches mobile.de and heycar and those
      # carry sellers who are not: a Willemstad car came in as German and was
      # charged 1700 euro to fetch from a country it was already in. Believe
      # the postcode over the letterhead, and fall back to the site when no
      # table we have recognises it.
      country:    Postcode.country_of(location) || COUNTRY,
      currency:   "EUR",
    )
  end

  def leasing?(card, price)
    price.match?(/monat/i) || squish(card.css(".offer-type-pill").text).match?(/leasing/i)
  end

  def registered_on(text)
    return nil unless (match = REGISTRATION.match(text.to_s))

    Date.new(match[2].to_i, (match[1] || 1).to_i, 1)
  rescue Date::Error
    nil
  end
end
