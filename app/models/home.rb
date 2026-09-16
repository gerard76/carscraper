# Where the car has to end up, so that distances mean something.
#
# It lives in config/home.yml, which is deliberately not in git, and every
# setting can come from the environment instead -- which is how the deployed
# copy is told, without the file ever leaving this machine:
#
#   postcode: "1234"          HOME_POSTCODE=1234
#   country: NL               HOME_COUNTRY=NL
#   latitude: 50.941          HOME_LATITUDE=50.941
#   longitude: 5.801          HOME_LONGITUDE=5.801
#
# Give it coordinates or a postcode. Coordinates win, and they are the better
# thing to hand to a server: a point you picked yourself says exactly as much
# as you want it to, where a postcode is a fact about you. A town name is not
# offered on purpose -- there are three Beeks in the Netherlands and their
# average is 70 km from any of them.
#
# Without any of it there are simply no distances.
class Home
  CONFIG = Rails.root.join("config", "home.yml")

  class << self
    def postcode  = settings["postcode"]
    def country   = settings["country"] || "NL"
    def latitude  = settings["latitude"]
    def longitude = settings["longitude"]

    def located?
      coordinates.present?
    end

    # Somewhere with a latitude and a longitude: either the point that was set
    # by hand, or the Postcode row the postcode lands on. nil when neither is
    # there, or the postcode is not in the imported tables.
    def coordinates
      if latitude.present? && longitude.present?
        Postcode.new(country: Postcode.iso_code(country), latitude: latitude.to_f, longitude: longitude.to_f)
      elsif postcode.present?
        Postcode.locate(country, postcode)
      end
    end

    def settings
      file = CONFIG.exist? ? (YAML.safe_load_file(CONFIG) || {}).to_h : {}

      file.merge(environment)
    end

    private

    # Only the ones that are actually set, so an empty variable does not wipe
    # out what the file says.
    def environment
      {
        "postcode"  => ENV["HOME_POSTCODE"],
        "country"   => ENV["HOME_COUNTRY"],
        "latitude"  => ENV["HOME_LATITUDE"],
        "longitude" => ENV["HOME_LONGITUDE"]
      }.compact_blank
    end
  end
end
