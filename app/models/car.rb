class Car < ApplicationRecord

  ### ASSOCIATIONS:
  belongs_to :model

  # Validations
  validates :model,   presence: true
  validates :eur,     presence: true, numericality: { greater_than: 5000 }
  validates :year,    presence: true
  validates :url,     uniqueness: true

  # Defaults:
  attribute :currency, :string, default: 'EUR'
  attribute :country,  :string, default: 'NL'

  ### CALLBACKS:
  before_validation :cleanup
  before_validation :set_eur

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

  ### CLASS METHODS:
  def self.ransackable_associations(auth_object = nil)
    %w[model]
  end

  def self.ransackable_attributes(auth_object = nil)
    ["country", "created_at", "currency", "data", "eur", "id", "id_value", "km", "model_id", "price", "updated_at", "url", "version", "visible", "year"]
  end

  # Instance methods:
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
    km = value.to_s.gsub(/[^0-9]/, '').to_i
    km *= 10 if country == 'SE'
    self.write_attribute(:km, km)
  end

  private

  def cleanup
    self.version = version.strip.sub(/^#{type}/, '').strip unless version.nil?
  end

  def set_eur
    return unless price

    case currency
    when 'NOK'
      self.eur = price / 10.0132423
    when 'SEK'
      self.eur = price / 10.805452
    when 'EUR'
      self.eur = price

      if country == 'NL' && (version =~ /ex.*(btw|vat)/i)
        self.eur = price * 1.21
      end
    end
  end
end
