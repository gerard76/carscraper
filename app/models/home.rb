# Where the car has to end up, so that distances mean something.
#
# It lives in config/home.yml, which is deliberately not in git: a postcode
# says roughly where you live, and this repository has a public remote.
#
#   postcode: "1234"
#   country: NL
#
# Without that file there are simply no distances.
class Home
  CONFIG = Rails.root.join("config", "home.yml")

  class << self
    def postcode = settings["postcode"]
    def country  = settings["country"] || "NL"

    def located?
      coordinates.present?
    end

    # The Postcode row for home, or nil when it is not set or not in the
    # imported tables.
    def coordinates
      return nil if postcode.blank?

      Postcode.locate(country, postcode)
    end

    def settings
      return {} unless CONFIG.exist?

      (YAML.safe_load_file(CONFIG) || {}).to_h
    end
  end
end
