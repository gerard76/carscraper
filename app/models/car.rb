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

  # How far apart two listings for the same car may be in price. The sites
  # copy each other's asking price but not always to the euro.
  PRICE_SPREAD = 0.02

  # A commercial vehicle -- a three seater on grey plates, say -- is quoted
  # without VAT to the trade and with VAT to everybody else, so the same car
  # shows up at two prices exactly 21% apart, on two sites that each took one
  # of them. Buying it privately, the higher one is what you pay.
  VAT = 1.21
  VAT_SPREAD = 0.015

  # A seller who re-advertises a car writes the same title and asks the same
  # money, but the odometer has moved on: the one you spotted was the same
  # taxi at 10800 and 11500 km. How far apart two of those may be.
  #
  # Absolute rather than a percentage, because dealers do keep several alike
  # cars -- one in Kiel has three under one title, 12500 km apart -- and it is
  # that distance which tells them from a car listed twice.
  RELISTED_KM = 1_500

  # What it costs to get a car onto Dutch plates, on top of the asking price.
  #
  # 1700 is Das Import's standard package, all-in: purchase handling, all-risk
  # transport on a trailer, the RDW inspection, the BPM declaration, the plates
  # and the storage. 1699,99 including VAT at the time of writing.
  #
  # They quote the same package for Belgium, so that one is their number too
  # rather than a guess -- with their own caveat attached: "omdat de Belgische
  # markt echter een net iets andere markt is dan de Duitse markt waar wij
  # voornamelijk in actief zijn, vragen wij u altijd eerst even overleg te
  # plegen". So treat it as the right order of magnitude and ring them before
  # you count on it to the euro.
  #
  # Luxembourg is the one that is still an assumption: no quote, just a country
  # that is no further away.
  #
  # There is no tax to add on top of it: a fully electric car owes no BPM.
  # That is what makes one flat figure enough. A Cargo on grey plates is a
  # bestelauto, which the Belastingdienst taxes by its own tariff, but those
  # are filtered out before they reach the graph.
  #
  # `share` is a slice of the asking price, for a country outside the EU where
  # customs duty and VAT are owed on the value of the car itself.
  IMPORT_COSTS = {
    "nl" => { fixed:     0 },                  # already here
    "b"  => { fixed: 1_700 },
    "d"  => { fixed: 1_700 },
    "l"  => { fixed: 1_700 },
    # Norway is outside the EU, so 10% duty and 21% VAT are owed on import and
    # a fixed amount cannot cover it. Not searched any more; worth checking
    # before you trust it.
    "no" => { fixed: 1_700, share: 0.33 },
  }.freeze

  # Any other country: the same trip, the same paperwork.
  DEFAULT_IMPORT_COSTS = { fixed: 1_700 }.freeze

  # Rates per euro, looked up on 2026-09-10. They drift, so a car scraped much
  # later than that is converted at a stale rate -- update these now and then,
  # and run Car.recalculate_eur! afterwards to fix the cars already stored.
  NOK_PER_EUR = 10.7635
  SEK_PER_EUR = 11.1995

  ### CALLBACKS:
  before_validation :cleanup
  before_validation :set_eur
  before_validation :hide_when_as_good_as_new, on: :create
  before_validation :set_distance
  before_validation :set_wheelbase
  before_validation :set_fingerprint

  # Why a car is not on the pages. Nil while it is. BY_HAND is the one that
  # matters: you clicked it away, and no rule of mine may overrule that or
  # bury it among its own leavings.
  BY_HAND = "you".freeze

  ### SCOPES:
  # Yours: a car you have put in the bin stays there. hidden_by carries the
  # reason and is the whole truth -- there was a `visible` boolean beside it
  # saying the same thing in reverse, and two columns that must agree are one
  # column and a bug waiting.
  scope :binned,    -> { where.not(hidden_by: nil) }
  scope :shown,     -> { where(hidden_by: nil) }
  scope :hidden_by_hand, -> { where(hidden_by: BY_HAND) }
  scope :hidden_by_rule, -> { binned.where.not(hidden_by: BY_HAND) }

  # Theirs: a listing that is sold disappears from the search pages, so a
  # scraper stops stamping it. 12gebrauchtwagen's links go 410 Gone within
  # days. Kept apart from the bin on purpose -- one is your decision, the
  # other is the market's -- so a listing that briefly drops off a page and
  # comes back needs no undoing.
  SEEN_WINDOW = 3.days
  scope :listed,    -> { where(seen_at: SEEN_WINDOW.ago..) }
  scope :on_offer,  -> { shown.listed }

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
  # The same car is often for sale on two sites at once -- 12gebrauchtwagen
  # carries a lot of what AutoScout24 has -- and two listings for one car
  # count twice in the graph and twice in the trend line.
  #
  # Two listings are taken to be one car when they agree on build month,
  # odometer reading and location, sit within PRICE_SPREAD of each other, and
  # come from different sites. That last one matters: a dealer with several
  # similar cars on one site is not a duplicate, and there are such dealers.
  #
  # The cheapest of the set stays and the rest are binned, so they
  # stay hidden through the next scrape -- except where the difference is the
  # VAT, and then the price you would actually pay stays. Returns the number
  # hidden.
  def self.hide_duplicates!
    hidden = 0

    duplicates.each do |group|
      keep = if quoted_without_vat?(group.map(&:eur))
               group.max_by { |car| [car.eur, car.direct_link? ? 1 : 0] }
             else
               group.min_by { |car| [car.eur, car.direct_link? ? 0 : 1] }
             end

      hidden += hide_all_but(keep, group, "listed on two sites")
    end

    photo_twins.each do |group|
      keep = group.min_by { |car| [car.eur, car.direct_link? ? 0 : 1] }

      hidden += hide_all_but(keep, group, "same photograph")
    end

    retitled.each do |group|
      # Both adverts are equally fresh, so keep the one that still has a
      # picture, and of those the one seen most recently.
      keep = group.max_by { |car| [car.image_url.present? ? 1 : 0, car.seen_at || Time.at(0), car.id] }

      hidden += hide_all_but(keep, group, "advertised twice")
    end

    relisted.each do |group|
      # The freshest reading of the same car: the advert that has been seen
      # most recently, and of those the one with the most on the clock.
      hidden += hide_all_but(group.max_by { |car| [car.seen_at || Time.at(0), car.km] }, group, "advertised twice")
    end

    hidden
  end

  def self.hide_all_but(keep, group, reason)
    gone = (group - [keep]).reject(&:hidden_by_hand?)

    # The cheapest listing is the one that stays, star or no star -- but a star
    # is about the car and not about the advert, so it moves to the one that
    # stays rather than disappearing with the one that goes.
    keep.update_columns(favourite: true) if gone.any?(&:favourite) && !keep.favourite

    gone.each { |car| car.update_columns(hidden_by: reason) }.size
  end

  def hidden_by_hand?
    hidden_by == BY_HAND
  end

  # Two sites carrying one car, where the asking prices are too far apart for
  # the price to vouch for it -- 38830 against 37460 on a Reutlingen car, 3.7%
  # -- but the listings point at the same photograph.
  #
  # The photograph alone proves nothing, so everything else still has to
  # agree: the same build month, the same town, mileage within RELISTED_KM,
  # two different sites, and a group small enough that it cannot be a
  # placeholder handed out to every car without a picture.
  MOST_SITES_WITH_ONE_CAR = 3

  def self.photo_twins
    on_offer.where.not(image_url: nil).where.not(km: nil)
            .group_by(&:photo_key).filter_map do |key, group|
      next if key.nil? || group.size < 2 || group.size > MOST_SITES_WITH_ONE_CAR
      next if group.map(&:source).uniq.size < 2
      next if group.map { |car| [car.year, car.place_key] }.uniq.size > 1

      mileages = group.map(&:km)
      next if mileages.max - mileages.min > RELISTED_KM

      group
    end
  end

  # The same listing back under a different title. 12gebrauchtwagen rewrites
  # them -- "(+NAVI) Bluetooth" became "(+NAVI) LED", and plenty were simply
  # cut shorter -- and the title is part of Car#identity, so the car returns as
  # a new row instead of refreshing the old one. 576 arrived in one round on 18
  # September 2026, and 29 of them were sitting beside their older selves.
  #
  # relisted cannot see these: it asks for the same title to the character,
  # which is the one thing that changed. So this asks for everything else, and
  # asks for it exactly -- the same site, the same build month, the same price
  # to the euro, the same odometer reading to the kilometre, the same town. Two
  # different cars from one dealer do not match all five; of the 14 groups this
  # found, not one had two titles that agreed, and every pair was plainly one
  # car ("Pro LR lang | AHK | LED | NAVI | ACC |" against "86 kWh 210 kW
  # ENERGY LR 5 Türen", both 49370 euro at 16174 km in Plattling).
  def self.retitled
    on_offer.where.not(km: nil).where.not(location: nil)
            .group_by { |car| [car.source, car.year, car.km, car.place_key, car.eur] }
            .filter_map do |key, group|
      next if key.any?(&:nil?) || group.size < 2

      group
    end
  end

  # One seller advertising one car twice: the same title, the same money, the
  # same town, and the odometer a few hundred kilometres further on.
  def self.relisted
    on_offer.where.not(km: nil).where.not(location: nil).where.not(version: [nil, ""])
            .group_by { |car| [car.source, car.year&.year, car.place_key, car.version.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip] }
            .filter_map do |key, group|
      next if key.any?(&:nil?) || group.size < 2
      next unless one_price?(group.map(&:eur))

      mileages = group.map(&:km)
      next if mileages.max - mileages.min > RELISTED_KM

      group
    end
  end

  # Two listings are for one car when they ask the same, or when they ask the
  # same but for the VAT.
  def self.same_car?(prices)
    one_price?(prices) || quoted_without_vat?(prices)
  end

  def self.one_price?(prices)
    prices.max - prices.min <= prices.min * PRICE_SPREAD
  end

  def self.quoted_without_vat?(prices)
    return false if prices.min.to_i.zero?

    (prices.max.to_f / prices.min - VAT).abs <= VAT_SPREAD
  end

  # The Pure is the cheap Buzz: 59 kWh where the Pro has 79, and 125 kW where
  # the Pro has 150. Its ad rarely states a battery, so hide_small_batteries!
  # never sees it, but the graph does: priced against Pros it looks like the
  # steal of the year. Every one of the 23 in here sat above the whole fleet's
  # ninth decile of bargain, the cheapest at 8679 where the decile was 9365.
  #
  # Neither half would do on its own. "Pure" turns up in paint names, and a car
  # can honestly be PURE_BARGAIN under the going rate. Together they are as
  # certain as this gets while the seller says nothing about the battery.
  PURE = /\bpure\b/i
  PURE_BARGAIN = 8_000

  def self.hide_pures!
    hidden = 0

    on_offer.each do |car|
      next if car.favourite
      next unless car.version.to_s.match?(PURE)
      next unless car.bargain_eur.to_i >= PURE_BARGAIN

      car.update_columns(hidden_by: "pure model")
      hidden += 1
    end

    hidden
  end

  # One battery, two numbers: sellers quote the gross capacity of the pack and
  # they quote the net capacity you can actually use, and they do not say
  # which. Left alone, the same car reads as 84 kWh in one ad and 79 in the
  # next, and no filter can tell a short wheelbase from a long one.
  #
  # So every gross figure is written down as its net one. For the ID. Buzz
  # that leaves three packs, and they are exactly the three generations:
  #
  #   77  the 2022-2024 car, short wheelbase only
  #   79  the 2024 update, short wheelbase
  #   86  the long wheelbase
  #
  # Add a model with another battery and its gross figures belong here too;
  # anything not listed is passed through as it was advertised, on the grounds
  # that a number we do not recognise is better than a wrong one.
  BATTERY_PACKS = {
    58 => 59,  # Pure, a seller a kilowatt-hour shy
    63 => 59,  # Pure, gross
    82 => 77,
    84 => 79,
    87 => 86,  # a seller rounding the long wheelbase's 86 the wrong way
    91 => 86,
  }.freeze

  # No car this side of a milk float has a pack outside this, so anything that
  # lands here from outside it was never a battery: a consumption figure, a
  # charger rating, a number out of the financing table.
  PLAUSIBLE_KWH = (20..250).freeze

  def self.usable_kwh(stated)
    return nil if stated.nil?
    return nil unless PLAUSIBLE_KWH.cover?(stated)

    BATTERY_PACKS.fetch(stated, stated)
  end

  # Adding a pack to the table above leaves every car already stored on the
  # old answer, the same way changing NOK_PER_EUR does. This works them out
  # again; it is safe to run twice, because the table maps a gross figure to
  # a net one and a net one to itself. Returns the number it changed.
  def self.renormalise_kwh!
    where.not(kwh: nil).count do |car|
      corrected = usable_kwh(car.kwh)
      next false if corrected == car.kwh

      car.update_columns(kwh: corrected)
      true
    end
  end

  # Hides the cars whose ad names a battery smaller than the model asks for.
  # Only those: a car that does not state its battery is not judged, the same
  # way min_seats leaves a listing alone when it names no seat count. Belongs
  # after a scrape. Returns the number hidden.
  def self.hide_small_batteries!
    hidden = 0

    on_offer.includes(:model).each do |car|
      next if car.favourite

      minimum = car.model.min_kwh.to_i
      next if minimum.zero?

      stated = car.battery_kwh
      next if stated.nil? || stated >= minimum

      car.update_columns(hidden_by: "battery too small")
      hidden += 1
    end

    hidden
  end

  # A listing no scraper has seen for SEEN_WINDOW is sold or withdrawn: the
  # link is dead -- 12gebrauchtwagen answers 410 Gone -- so the row goes.
  #
  # The window is the safety margin: a source that falls over, or a listing
  # that slips off the last page for a round, is not thrown away on one miss.
  # A car that comes back after being removed comes back as a new row, so any
  # note on it is gone with it.
  def self.remove_vanished!
    vanished.destroy_all.size
  end

  def self.vanished
    where("seen_at is null or seen_at < ?", SEEN_WINDOW.ago)
  end

  # Rows that are the same listing re-arrived under a new url. Keeps the one
  # that is not binned, or the oldest when all are, and carries over any note.
  # Returns the number of rows removed.
  def self.merge_relisted!
    removed = 0

    where.not(fingerprint: nil).group_by(&:fingerprint).each do |_, group|
      next if group.size < 2

      keep = group.find(&:shown?) || group.min_by(&:id)
      note = group.filter_map { |car| car.comments.presence }.first
      keep.update_columns(comments: note) if note && keep.comments.blank?

      (group - [keep]).each do |car|
        car.destroy
        removed += 1
      end
    end

    removed
  end

  def self.duplicates
    on_offer.where.not(km: nil).where.not(location: nil).group_by(&:duplicate_key).filter_map do |key, group|
      next if key.any?(&:nil?)
      next if group.size < 2
      next if group.map(&:source).uniq.size < 2

      next unless same_car?(group.map(&:eur))

      group
    end
  end

  # bargain_eur says how much less a car asks than comparable cars of its age
  # and mileage: the distance from the plane PriceFit lays through the lot.
  #
  # It has to be worked out for every car at once, because the plane is drawn
  # from all of them -- one car arriving moves it, and with it everybody's
  # number. So this belongs after a scrape, next to hide_duplicates!. Cars
  # scraped since are left on nil until it runs.
  def self.recalculate_bargains!
    fit = PriceFit.new(on_offer.to_a)

    find_each { |car| car.update_columns(bargain_eur: fit.bargain(car)) }

    fit
  end

  # Moving house, or importing more postcode tables, leaves the distances
  # already stored on the old answer.
  def self.recalculate_distances!
    find_each { |car| car.update_columns(distance_km: car.distance_from_home) }
  end

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
    ["country", "created_at", "currency", "data", "distance_km", "eur", "favourite", "id", "id_value", "bargain_eur", "km", "kwh", "landed_eur", "location", "model_id", "price", "seats", "updated_at", "url", "version", "wheelbase", "year"]
  end

  # Instance methods:

  # What getting this car here costs on top of the asking price.
  def import_costs
    costs = IMPORT_COSTS.fetch(country.to_s.downcase, DEFAULT_IMPORT_COSTS)

    (costs.fetch(:fixed) + costs.fetch(:share, 0) * eur.to_i).round
  end

  # What two listings for one car have to agree on. Build month is out: some
  # sites only know the year. So is the wording of the location: one names a
  # postcode and the next the town, so both are resolved to the same place.
  # A car registered this month would divide by nearly nothing.
  MIN_AGE_IN_YEARS = 0.25

  # How hard it has been driven for its age: what the graph colours by.
  def km_per_year
    return nil if km.nil? || year.nil?

    (km / [(Date.current - year).to_f / 365.25, MIN_AGE_IN_YEARS].max).round
  end

  # The photo at a size worth looking at. What the scrapers store is whatever
  # the search page showed -- AutoScout24 hands out a 250x188 thumbnail, and
  # 12gebrauchtwagen wraps a 1280x960 one in a proxy that shrinks it.
  def large_image_url
    return nil if unwrapped_image_url.nil?

    unwrapped_image_url.sub(%r{/\d+x\d+\.(webp|jpg|jpeg|png)\z}, '/1024x768.\1')
  end

  # 12gebrauchtwagen serves its pictures through a proxy, and what it wraps for
  # a car it found on AutoScout24 is AutoScout24's own picture. Unwrapping it
  # is what makes the two comparable.
  def unwrapped_image_url
    return nil if image_url.blank?

    image_url[%r{/v7/(.+?)(?:\?|\z)}, 1].then { |inner| inner ? CGI.unescape(inner) : image_url }
  end

  # The picture the pages show: our own copy when we have one, and the site's
  # own until then, so a car that arrived a minute ago still has a photograph.
  # In the bin, or on the pages. hidden_by says which, and why.
  def binned?
    hidden_by.present?
  end

  def shown?
    hidden_by.nil?
  end

  def photo_url
    photo_stored? ? "#{Photos::PATH}/#{photo}" : image_url
  end

  # Named after the url it came from, so a listing that swaps its picture gets
  # a new file rather than a stale one.
  def photo_digest
    return nil if unwrapped_image_url.nil?

    Digest::SHA256.hexdigest(unwrapped_image_url)[0, 16]
  end

  # The name in the column is only half of it: the file has to be there too.
  # A database restored onto a machine without the pictures -- this laptop,
  # carrying a dump of the droplet -- would otherwise show six hundred broken
  # images and never fetch them, because the column says they are already
  # here. Checking costs one stat per car, and it means a wiped volume heals
  # itself on the next scrape.
  def photo_stored?
    return false if photo.blank? || photo_digest.blank?
    return false unless photo.start_with?(photo_digest)

    File.exist?(Photos::DIRECTORY.join(photo))
  end

  # AutoScout24 files its pictures under the advert they belong to, so the first
  # half of listing-images/<advert>_<picture> is the advert's own id. Two
  # listings whose photographs sit in the same folder are the same advert, even
  # when the two sites picked a different picture out of it.
  #
  # Still only ever taken as corroboration, never as proof: a site that has no
  # picture for a car can hand out a placeholder, and that placeholder would
  # tie together every car it was given to.
  def photo_key
    return nil if unwrapped_image_url.nil?

    unwrapped_image_url.split("?").first[%r{listing-images/([0-9a-f-]+)_}, 1]
  end

  # Long or short, out of the seller's own title, or nil when it says neither.
  #
  # German sellers write it because it sells: "langer Radstand", or LR, or LWB;
  # the short one is KR, SWB or "kurzer Radstand". Two in five titles say so,
  # which is as many as name a battery, and the two hardly ever disagree --
  # over the cars on offer, 101 long ones also said 86 kWh and not one said 77
  # or 79, while 59 short ones said 77 or 79 against a single 86.
  #
  # Worth its own column rather than reading the battery as a stand-in for it:
  # one battery per wheelbase per generation is true today and is not a fact
  # about the car, and 168 cars name a wheelbase while naming no battery at
  # all. Long first, because a title that says both means the long one.
  LONG_WHEELBASE  = /\b(lwb|lr|langer\s+radstand|lange?\s+wielbasis|long\s+wheel)/i
  SHORT_WHEELBASE = /\b(swb|kr|kurzer\s+radstand|korte?\s+wielbasis|short\s+wheel)/i

  def self.wheelbase_in(text)
    return "long"  if text.to_s.match?(LONG_WHEELBASE)
    return "short" if text.to_s.match?(SHORT_WHEELBASE)

    nil
  end

  # The battery in kWh, or nil when nothing we have seen says. Scraped into
  # the column; the version is still read for the rows that predate it.
  def battery_kwh
    kwh || self.class.usable_kwh(version.to_s[Scrapers::Base::BATTERY, 1]&.to_i)
  end

  # What makes this listing this listing, whatever url it happens to carry
  # today. 12gebrauchtwagen links through a redirect whose offer_id rotates, so
  # the same car came back as a new row on every scrape -- 491 of 3354 rows
  # were re-arrivals -- and the url is no use as identity for it.
  #
  # Mileage is part of it on purpose: without it, six different cars from one
  # seller with the same generic title collapsed into one.
  def identity
    [source, year, km, Postcode.digits(location).presence || place_key, version.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip]
  end

  # Computed rather than read from the column, so a scraper can ask a car it
  # has just built -- before saving -- whether we already have this listing.
  def identity_digest
    Digest::SHA256.hexdigest(identity.join("|"))[0, 32]
  end

  def duplicate_key
    [year&.year, km, place_key]
  end

  def place_key
    return nil if location.blank?

    Postcode.locate(country, location)&.place_key
  end

  def source
    URI.parse(url).host.to_s.delete_prefix("www.")
  rescue URI::InvalidURIError
    url.to_s
  end

  # A link that opens this car, rather than the page it was found on:
  # 12gebrauchtwagen sends you on to whichever site it came from, and gaspedaal
  # only points at its own model page with the listing id in the fragment. When
  # the price is a tie, those are the ones to drop.
  def direct_link?
    !url.to_s.include?("/c/partner") && !url.to_s.include?("#")
  end

  # Kilometres from home as the crow flies, or nil when either end is
  # unknown: no postcode on the listing, no home set, or a postcode that is
  # not in the imported tables.
  def distance_from_home
    return nil if location.blank?

    here = Home.coordinates or return nil
    there = Postcode.locate(country, location) or return nil

    there.distance_to(here).round
  end

  # The asking price plus those costs: what the car actually costs you.
  def landed_eur
    return nil if eur.nil?

    eur + import_costs
  end

  def type
    @type ||= model.type
  end

  # How long it has been in front of you: days since the first scrape that
  # found it. Not how long it has been for sale -- a car that turns up in the
  # very first scrape of a site has been on there for who knows how long -- but
  # from then on it is exactly the thing worth sorting on: what is new.
  def days_online
    (Date.current - created_at.to_date).to_i
  end

  # What to call the car in a list. The seller's own title is the useful thing,
  # but 92 listings carry none at all and one AutoScout24 advert has "." for a
  # title, so anything without a letter or a digit in it falls back to the make
  # and model.
  def title
    version.to_s.match?(/[[:alnum:]]/) ? version : type
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
    return unless km && km <= AS_NEW_KM

    self.hidden_by = "as new"
  end

  def set_wheelbase
    self.wheelbase = self.class.wheelbase_in(version)
  end

  def set_fingerprint
    self.fingerprint = identity_digest
  end

  def set_distance
    self.distance_km = distance_from_home
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
