# Where a postcode is, so we can work out how far away a car is.
#
# The tables come from GeoNames (CC BY 4.0), one file per country, and are
# imported with `bin/rails postcodes:import`. After that the lookup is a local
# query: nothing about where you live leaves this machine.
class Postcode < ApplicationRecord
  SOURCE_URL = "https://download.geonames.org/export/zip/%<country>s.zip".freeze

  # The countries the scrapers search. Add one here and re-run the import.
  COUNTRIES = %w[NL DE BE LU].freeze

  # The sites use their own country codes; GeoNames uses ISO.
  ISO_CODES = {
    "nl" => "NL", "d" => "DE", "b" => "BE", "l" => "LU",
    "a"  => "AT", "e" => "ES", "f" => "FR", "no" => "NO"
  }.freeze

  EARTH_RADIUS_IN_KM = 6371.0

  # The listing says where the car is in whatever way its site does: a postcode
  # ("8606 JS", "40233 Düsseldorf") or just a town ("Harderwijk").
  def self.locate(country, location)
    iso  = iso_code(country)
    code = digits(location)

    return find_by(country: iso, code: code) if code.present?

    centre_of(iso, location)
  end

  # Sellers write a town the way people say it, the tables the way the post
  # office does.
  ALIASES = {
    "den haag"  => "s gravenhage",
    "den bosch" => "s hertogenbosch"
  }.freeze

  # A town covers several postcodes, so its middle is the average of them.
  def self.centre_of(iso, place)
    key = place_key(place)
    return nil if key.blank?

    rows = rows_for(iso, key)
    return nil if rows.empty?

    # The name the tables use, not the one the seller wrote: "Hengelo Ov" and
    # "Hengelo" have to come out as the same place, or the same car listed on
    # two sites counts twice.
    new(
      latitude: rows.average(:latitude).to_f,
      longitude: rows.average(:longitude).to_f,
      place_key: rows.first.place_key
    )
  end

  # The name as written, else the everyday name, else without the province the
  # seller tacked on: "Hengelo Ov" is the Hengelo in Overijssel, and the tables
  # call that one simply "hengelo".
  def self.rows_for(iso, key)
    [key, ALIASES[key], key.sub(/ [a-z]{1,3}\z/, "")].compact.uniq.each do |candidate|
      rows = where(country: iso, place_key: candidate)
      return rows if rows.any?
    end

    none
  end

  # "Köln-Mülheim" and "koln-mulheim" have to meet, so both sides go through
  # this before they are compared.
  def self.place_key(place)
    I18n.transliterate(place.to_s).downcase.gsub(/[^a-z0-9]+/, " ").strip
  end

  # Sellers write a postcode however they like: "8606 JS", "74523", "1234 ab".
  # GeoNames keys them on the digits, which is as precise as this needs to be.
  def self.digits(code)
    code.to_s.scan(/\d/).join
  end

  # Which country a location is in, as the scrapers' own country codes, or nil
  # when no table we have has that postcode.
  #
  # An aggregator files every listing under its own country: 12gebrauchtwagen
  # is German, so a seller in Willemstad arrived here as German and had 1700
  # euro of import costs added to a car that was already in the country. The
  # postcode is better evidence than the site's letterhead.
  def self.country_of(location)
    code = digits(location)
    return nil if code.blank?

    found = where(code: code).distinct.pluck(:country)
    return site_code(found.first) if found.one?
    return nil if found.empty?

    # Four digits is Belgium and Luxembourg alike, so the town decides.
    key = place_key(town_in(location))
    site_code(where(code: code, place_key: key).pick(:country)) if key.present?
  end

  # "8830 Hooglede" -> "Hooglede", "4797SG Willemstad" -> "Willemstad". The
  # postcode leads and the town follows, letters of a Dutch one included.
  def self.town_in(location)
    location.to_s.sub(/\A\s*\d[\d\s]*([A-Za-z]{2}\b)?\s*/, "").strip
  end

  def self.site_code(iso)
    return nil if iso.blank?

    ISO_CODES.key(iso.to_s.upcase) || iso.to_s.downcase
  end

  def self.iso_code(country)
    ISO_CODES.fetch(country.to_s.strip.downcase, country.to_s.strip.upcase)
  end

  # Great circle distance in kilometres: as the crow flies, so roughly a fifth
  # short of what the road will be.
  def distance_to(other)
    lat1, lon1 = radians(latitude), radians(longitude)
    lat2, lon2 = radians(other.latitude), radians(other.longitude)

    half = Math.sin((lat2 - lat1) / 2)**2 +
           Math.cos(lat1) * Math.cos(lat2) * Math.sin((lon2 - lon1) / 2)**2

    EARTH_RADIUS_IN_KM * 2 * Math.asin(Math.sqrt(half))
  end

  def self.import!(countries: COUNTRIES)
    countries.each do |country|
      rows = download(country)
      upsert_all(rows, unique_by: [:country, :code], update_only: [:latitude, :longitude, :place_key]) if rows.any?
      puts "#{country}: #{rows.size} postcodes"
    end

    count
  end

  def self.download(country)
    url = format(SOURCE_URL, country: country)
    puts "downloading #{url}"
    response = HTTParty.get(url)
    raise "GeoNames answered #{response.code} for #{country}" unless response.code == 200

    Tempfile.create([country, ".zip"], binmode: true) do |file|
      file.write(response.body)
      file.flush

      Zip::File.open(file.path) do |zip|
        entry = zip.find_entry("#{country}.txt") or raise "no #{country}.txt in the archive"

        # The archive hands its contents back as bytes, and place names are
        # full of umlauts and accents.
        parse(entry.get_input_stream.read.force_encoding(Encoding::UTF_8))
      end
    end
  end

  # The file is tab separated: country, postcode, place, and the coordinates in
  # columns 10 and 11. A postcode spanning several places gets several rows, so
  # they are averaged into the middle of the area.
  def self.parse(text)
    places = text.each_line.filter_map do |line|
      fields = line.split("\t")
      code   = digits(fields[1])
      next if code.blank? || fields[9].blank? || fields[10].blank?

      [fields[0], code, fields[9].to_f, fields[10].to_f, place_key(fields[2])]
    end

    places.group_by { |country, code, _, _, _| [country, code] }.map do |(country, code), rows|
      {
        country: country,
        code: code,
        latitude: rows.sum { |row| row[2] } / rows.size,
        longitude: rows.sum { |row| row[3] } / rows.size,
        place_key: rows.first[4]
      }
    end
  end

  private

  def radians(degrees)
    degrees * Math::PI / 180
  end
end
