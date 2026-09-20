module CarsHelper
  # What a select sends when you ask for the cars that say nothing. Ransack
  # asks that with _null rather than _eq, so CarsController#search_params
  # swaps it over.
  NOT_STATED = "none".freeze

  # The values the adverts actually name, and then the cars that name none.
  #
  # Most of them name none: three in five say nothing about their battery.
  # "Any" hides those in with the rest and an exact match drops them without a
  # word, which is the opposite of what the rules do -- a car that does not
  # state its battery is not judged on it. So silence gets an entry of its own,
  # with the count in the label, because the number is the point.
  def stated_options(field, labels: {})
    values = Car.on_offer.distinct.pluck(field).compact.sort
    silent = Car.on_offer.where(field => nil).count

    options = values.map { |value| [labels.fetch(value, value).to_s, value.to_s] }
    options << ["Not stated (#{silent})", NOT_STATED] if silent.positive?
    options
  end

  # Selects are read back from the url rather than from the ransack object,
  # because "none" never reaches ransack under that name -- by the time the
  # search runs it is a _null predicate in a grouping.
  def chosen_many(field)
    Array(search_query&.dig("#{field}_in"))
  end

  # The tags a seller's description is allowed to keep. Their advert is their
  # markup, not ours -- see Car#description -- and it arrives as a bulleted
  # equipment list with headings in bold, which is all of the meaning in it.
  #
  # No attributes at all, which is the point of naming the tags by hand rather
  # than taking the sanitiser's own list: that one keeps `a` and `img`, and an
  # image would have our page fetching a file from a stranger's server every
  # time you open a car.
  SELLERS_TAGS = %w[p br strong b em i u ul ol li h2 h3 h4 h5 table thead tbody tr th td].freeze

  def sellers_words(html)
    sanitize(html, tags: SELLERS_TAGS, attributes: [])
  end
end
