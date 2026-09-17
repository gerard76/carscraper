class Model < ApplicationRecord

  ### ASSOCIATIONS:
  has_many :cars,
    dependent: :destroy

  # Makes that go by a shorter name when the room is tight.
  SHORT_MAKES = { "volkswagen" => "VW" }.freeze

  ### INSTANCE METHODS:
  def type
    "#{make} #{model}"
  end

  # The same thing for a filter box. "Volkswagen ID-Buzz" is most of the width
  # of the models select on its own, and that select shares a row with nine
  # other filters.
  def short_type
    "#{SHORT_MAKES.fetch(make.to_s.downcase, make)} #{model}"
  end

  # Sellers regularly park a different car in this model's category on
  # AutoScout24 -- an ID.3 listed as an ID. Buzz, for instance. The listings
  # look genuine (the site itself reports them under this model), so they can
  # only be spotted by their advertised version. Comma separated, e.g.
  # "ID.3, ID.4, ID.5".
  def exclude_terms
    exclude_versions.to_s.split(",").map(&:strip).reject(&:empty?)
  end

  def excluded_version?(version)
    terms = exclude_terms
    return false if terms.empty?

    version.to_s.match?(/\b(?:#{terms.map { |term| Regexp.escape(term) }.join("|")})\b/i)
  end

  # Cars scraped before the terms were set are not removed automatically;
  # call this to clean them up. Returns the number of cars removed.
  def remove_excluded_cars
    cars.select { |car| excluded_version?(car.version) }.each(&:destroy).size
  end

end
