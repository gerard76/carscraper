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

  def self.locate(country, code)
    digits = digits(code)
    return nil if digits.blank?

    find_by(country: iso_code(country), code: digits)
  end

  # Sellers write a postcode however they like: "8606 JS", "74523", "1234 ab".
  # GeoNames keys them on the digits, which is as precise as this needs to be.
  def self.digits(code)
    code.to_s.scan(/\d/).join
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
      upsert_all(rows, unique_by: [:country, :code]) if rows.any?
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
        parse(entry.get_input_stream.read)
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

      [fields[0], code, fields[9].to_f, fields[10].to_f]
    end

    places.group_by { |country, code, _, _| [country, code] }.map do |(country, code), rows|
      {
        country: country,
        code: code,
        latitude: rows.sum { |row| row[2] } / rows.size,
        longitude: rows.sum { |row| row[3] } / rows.size
      }
    end
  end

  private

  def radians(degrees)
    degrees * Math::PI / 180
  end
end
