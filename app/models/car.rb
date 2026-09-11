class Car < ApplicationRecord

  ### ASSOCIATIONS:
  belongs_to :model

  # Validations
  validates :model,   presence: true
  validates :eur,     presence: true, numericality: { greater_than: 5000 }
  validates :year,    presence: true
  validates :url,     uniqueness: true

  # Placeholder ads read 999999: a number no real car reaches, and one that
  # stretches the colour scale so far that every other car looks the same.
  validates :km, numericality: { less_than: 500_000 }, allow_nil: true

  # Defaults:
  attribute :currency, :string, default: 'EUR'
  attribute :country,  :string, default: 'NL'

  # Anything at or below this has delivery mileage: it is a new car, not a
  # used one.
  AS_NEW_KM = 100

  # What it costs to get a car onto Dutch plates, on top of the asking price.
  # These are estimates, not quotes: change them and the graph follows.
  #
  # Each one is the same paperwork -- RDW identification and inspection (~200),
  # registration (~50), and the BPM a zero emission car owes, which is the
  # fixed base amount only (~700) -- plus what it costs to go and collect the
  # car, which is the whole difference between Belgium and Spain.
  #
  # `share` is a slice of the asking price, for a country outside the EU where
  # customs duty and VAT are owed on the value of the car itself.
  IMPORT_COSTS = {
    "nl" => { fixed:     0 },                  # already here
    "b"  => { fixed: 1_200 },
    "l"  => { fixed: 1_300 },
    "d"  => { fixed: 1_400 },
    "f"  => { fixed: 1_700 },
    "a"  => { fixed: 1_900 },
    "e"  => { fixed: 2_400 },
    # Norway is outside the EU, so 10% duty and 21% VAT are owed on import and
    # a fixed amount cannot cover it. Worth checking before you trust it.
    "no" => { fixed: 1_500, share: 0.33 },
  }.freeze

  # A country we have no figure for is treated like Germany.
  DEFAULT_IMPORT_COSTS = { fixed: 1_400 }.freeze

  # Rates per euro, looked up on 2026-09-10. They drift, so a car scraped much
  # later than that is converted at a stale rate -- update these now and then,
  # and run Car.recalculate_eur! afterwards to fix the cars already stored.
  NOK_PER_EUR = 10.7635
  SEK_PER_EUR = 11.1995

  ### CALLBACKS:
  before_validation :cleanup
  before_validation :set_eur
  before_validation :hide_when_as_good_as_new, on: :create

  ### SCOPES:
  scope :visible,   -> { where(visible: true) }

  ### DELEGATIONS:
  delegate :make, to: :model

  # Searching in json with Ransack: one ransacker per key present in the `data`
  # column. This needs the database while the class loads, so it is skipped when
  # there is no database to talk to yet -- eager loading during
  # `assets:precompile`, `db:create` on an empty server, and so on.
  begin
    if table_exists?
      pluck(Arel.sql("distinct json_object_keys(data)")).each do |key|
        ransacker key do |parent|
          Arel::Nodes::InfixOperation.new('->>', parent.table[:data], Arel::Nodes.build_quoted(key))
        end
      end
    end
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger&.warn "Car: skipping the `data` JSON ransackers (#{e.class}: #{e.message})"
  end

  # Lets the search form filter on the price with import costs included, the
  # same price the graph plots. The country codes come from IMPORT_COSTS, which
  # is ours, so there is nothing to quote here.
  ransacker :landed_eur do
    branches = IMPORT_COSTS.map do |country, costs|
      "WHEN '#{country}' THEN #{costs.fetch(:fixed).to_i} + cars.eur * #{costs.fetch(:share, 0).to_f}"
    end

    Arel.sql("(cars.eur + CASE cars.country #{branches.join(' ')} ELSE #{DEFAULT_IMPORT_COSTS.fetch(:fixed).to_i} END)")
  end

  ### CLASS METHODS:
  def self.ransackable_associations(auth_object = nil)
    %w[model]
  end

  # A car keeps the eur it was given when it was scraped, so changing
  # NOK_PER_EUR or SEK_PER_EUR leaves everything already stored on the old
  # rate. This works those out again. Returns the number of cars it changed.
  def self.recalculate_eur!
    changed = 0

    where.not(currency: 'EUR').find_each do |car|
      was = car.eur
      car.send(:set_eur)
      next if car.eur == was

      car.update_column(:eur, car.eur)
      changed += 1
    end

    changed
  end

  def self.ransackable_attributes(auth_object = nil)
    ["country", "created_at", "currency", "data", "eur", "id", "id_value", "km", "landed_eur", "model_id", "price", "updated_at", "url", "version", "visible", "year"]
  end

  # Instance methods:

  # What getting this car here costs on top of the asking price.
  def import_costs
    costs = IMPORT_COSTS.fetch(country.to_s.downcase, DEFAULT_IMPORT_COSTS)

    (costs.fetch(:fixed) + costs.fetch(:share, 0) * eur.to_i).round
  end

  # The asking price plus those costs: what the car actually costs you.
  def landed_eur
    return nil if eur.nil?

    eur + import_costs
  end

  def type
    @type ||= model.type
  end

  def available?
    response = HTTParty.head(url)
    response.code == 200
  end

  def price=(value)
    version ||= ""
    # `value` arrives as a string from the scraper, but can be a number when set
    # by hand. Ruby 4 removed Object#=~, so cast before matching.
    version += " ex btw" if value.to_s =~ /ex.*(btw|vat)/i
    price = value.to_s.gsub(/[^0-9]/, '').to_i

    self.write_attribute(:price, price)
  end

  def km=(value)
    digits = value.to_s.gsub(/[^0-9]/, '')

    # AutoScout24 writes "unknown" when the seller left the mileage out, and
    # the other sites simply leave it off the card. That is not the same as
    # zero: such a car must not be plotted as barely driven, and it is not a
    # new car either.
    return self.write_attribute(:km, nil) if digits.empty?

    km = digits.to_i
    km *= 10 if country == 'SE'
    self.write_attribute(:km, km)
  end

  private

  def cleanup
    self.version = version.strip.sub(/^#{type}/, '').strip unless version.nil?
  end

  # New cars are kept but left out of the graph. Only on create, so one that
  # is switched back on by hand stays on.
  def hide_when_as_good_as_new
    self.visible = false if km && km <= AS_NEW_KM
  end

  def set_eur
    return unless price

    case currency
    when 'NOK'
      self.eur = price / NOK_PER_EUR
    when 'SEK'
      self.eur = price / SEK_PER_EUR
    when 'EUR'
      self.eur = price

      if country == 'NL' && (version =~ /ex.*(btw|vat)/i)
        self.eur = price * 1.21
      end
    end
  end
end
