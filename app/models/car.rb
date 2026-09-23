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
  # A reason from last round is not a reason. "Listed on two sites" is true of
  # a pair, and when the other half is sold the survivor stays in the bin
  # saying it about nobody -- nothing ever lifted one of these, and after
  # merge_retitled! there are rows whose twin has not merely gone but never
  # existed as a separate car. So the duplicate reasons are dropped and worked
  # out again, every round, on what is actually here.
  #
  # Only the duplicate ones, and never a decision of yours: "as new" has its
  # own way back (show_driven!), and "you" is not ours to lift.
  def self.forget_duplicate_reasons!
    where(hidden_by: DUPLICATE_REASONS).update_all(hidden_by: nil)
  end

  def self.hide_duplicates!
    hidden = 0

    forget_duplicate_reasons!

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

    same_money.each do |group|
      keep = group.min_by { |car| [car.eur, car.direct_link? ? 0 : 1] }

      hidden += hide_all_but(keep, group, "listed on two sites")
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
    others = group - [keep]
    gone   = others.reject(&:hidden_by_hand?)

    # The cheapest listing is the one that stays, and everything you have said
    # about the car moves to it -- from every other row in the group, including
    # the crossed-off ones, which are not in `gone` at all.
    keep.adopt_decisions_from(others)

    gone.each { |car| car.update_columns(hidden_by: reason) }.size
  end

  # A row you have said something about: crossed off, starred, written on, or
  # put right by hand.
  def self.decided
    where(hidden_by: BY_HAND)
      .or(where(favourite: true))
      .or(where.not(comments: [nil, ""]))
      .or(where("corrections::text not in ('{}', 'null', '')"))
  end

  # What you decided about a car holds for the car, on whatever site it turns
  # up next, and however many rows it turns up as.
  #
  # Every duplicate rule works on what is on offer, and a row you crossed off
  # is not on offer, so nothing carried it: car 4093 was crossed off as a
  # smoker's car, with a note saying so, and two days later the same van
  # arrived from another site as 4767 -- on the pages, unmarked, the note
  # nowhere. A correction can go the same way: the seat count you fixed by hand
  # on one row says nothing about the copy that arrives tomorrow, and that copy
  # carries the seller's number.
  #
  # Runs at tidy-up, before the duplicate rules, so a row it crosses off is out
  # of their way.
  def self.carry_decisions!
    carried = 0

    decided.each do |car|
      car.twins.each { |twin| carried += twin.adopt_decisions_from(car) }
    end

    carried
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

  # The same car on two sites at the same money, whose odometers have drifted
  # apart: one site's copy of the reading is older than the other's.
  #
  # Two rules miss it for two different reasons. duplicate_key holds the
  # mileage exactly, so 38000 and 38600 never meet; and `duplicates` asks
  # whether a whole group of prices is one price, so a dealer with four alike
  # cars in Kiel shields every one of them. Grouping on the price to the euro
  # steps around both.
  #
  # Everything else still has to agree: the same build month, the same town,
  # two different sites, a mileage within RELISTED_KM. Over the stock that is
  # four pairs and every one is plainly one car -- "Bus 210 kW LR Pro" at 8700
  # and 8755 km in Bahretal, 55489 euro both times.
  def self.same_money
    on_offer.where.not(km: nil).where.not(location: nil)
            .group_by { |car| [car.year, car.place_key, car.eur] }
            .filter_map do |key, group|
      next if key.any?(&:nil?) || group.size < 2
      next if group.map(&:source).uniq.size < 2

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
            .group_by { |car| [car.source, car.year, car.km, car.locality, car.eur] }
            .filter_map do |key, group|
      next if key.any?(&:nil?) || group.size < 2

      group
    end
  end

  # The five things retitled asks for, asked of one listing before it is
  # stored: is this car already here under another title?
  #
  # Hiding the second row was only half a fix. The row is still a row, with
  # today's date on it and none of what you did to the first one, and the
  # duplicate rule then keeps the *freshest* advert -- so a car starred on the
  # 17th came back to the top of the wall on the 21st marked "new today", with
  # the star dragged along behind it. Car 4859 and car 5650 were one bus in
  # Leverkusen: 12gebrauchtwagen carried the AutoScout24 advert for it, then
  # switched to the mobile.de one, which meant another offer_id, another
  # picture and "SHZ CARPLAY" where the old title said "SHZ CARPL".
  #
  # So the scrapers ask this when the digest misses, and refresh what is here
  # instead of adding to it.
  #
  # One candidate or none. Where two rows fit all five, the title is the only
  # thing telling those cars apart -- a Bavarian dealer has thirteen at 10 km
  # in one postcode -- and glueing two of them together loses a car.
  #
  # Which is also why factory-new cars are left out of this altogether. Their
  # odometers all read the same handful of kilometres and dealers price whole
  # trims alike, so all five can agree on two plainly different cars: "Pro 5S
  # Style+ Open&Cl KomfortP+" and "Pro LR 7S Style KomfortP+ AssisP+" both sat
  # at 10 km and 59840 euro in one yard, a short five seater and a long seven
  # seater. A used car's odometer is its own: 8378 km at 45980 euro from one
  # dealer in Leverkusen is one bus, however the advert is worded this week.
  def self.same_listing_as(fresh)
    return nil if fresh.km.nil? || fresh.year.nil? || fresh.price.nil? || fresh.location.blank?
    return nil if fresh.km <= AS_NEW_KM

    candidates = where(km: fresh.km, year: fresh.year, price: fresh.price, currency: fresh.currency)
                 .reject { |car| car.id == fresh.id }
                 .select { |car| car.source == fresh.source && car.locality == fresh.locality }

    candidates.first if candidates.one?
  end

  # What the rows already here need, since they were made before the scrapers
  # knew to ask. One car, several rows, one per title it has worn: four of them
  # for a Mulheim bus, on four different days.
  #
  # The row that stays is the oldest -- that is the one carrying the date you
  # first saw the car, your star and your note -- and it takes over the live
  # advert from the freshest row, so the link still opens something. The rest
  # go. A car you binned by hand is not touched.
  #
  # The reason a rule gave for hiding it goes too: it was about a row that no
  # longer exists, and nothing ever lifts one of those. The rules run again
  # directly after this, on what is left.
  DUPLICATE_REASONS = ["listed on two sites", "advertised twice", "same photograph"].freeze

  # Rounds, because merging changes what is grouped: a row that stays takes
  # over the freshest advert, and that can bring it alongside a third row that
  # was in nobody's group before. Two passes settled production; the cap is
  # there so a bug cannot spin here.
  MERGE_PASSES = 5

  def self.merge_retitled!
    merged = 0

    MERGE_PASSES.times do
      gone = merge_retitled_once!
      merged += gone
      break if gone.zero?
    end

    merged
  end

  def self.merge_retitled_once!
    merged = 0

    listed.where.not(hidden_by: BY_HAND).where.not(km: nil).where.not(location: nil)
          .group_by { |car| [car.source, car.year, car.km, car.locality, car.eur] }
          .each do |key, group|
      next if key.any?(&:nil?) || group.size < 2

      # Delivery mileage tells two cars apart from nobody -- see
      # same_listing_as -- and this one destroys rows, so it stays away from
      # them. The duplicate rules still hide what they hide.
      next if key[2] <= AS_NEW_KM

      keep  = group.min_by(&:id)
      fresh = group.max_by { |car| [car.seen_at || Time.at(0), car.id] }

      # Before they go: the star, the note, the crossing-off, the corrections.
      keep.adopt_decisions_from(group - [keep])

      (group - [keep]).each do |car|
        car.destroy
        merged += 1
      end

      changes = { seen_at: fresh.seen_at }
      changes[:hidden_by] = nil if DUPLICATE_REASONS.include?(keep.reload.hidden_by)

      # The advert as it stands today, from whichever row saw it last. The
      # picture comes with its own file, which we already have.
      if fresh != keep
        changes.merge!(url: fresh.url, version: fresh.version, image_url: fresh.image_url,
                       photo: fresh.photo, large_photo: fresh.large_photo)
      end

      # Only ever filled in: what Details read off a page it has been to is
      # worth more than a blank on an older row.
      %i[seats kwh details_at data].each do |field|
        value = fresh.public_send(field)
        changes[field] = value if keep.public_send(field).blank? && value.present?
      end

      keep.update_columns(changes)
    end

    merged
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

  # The one place a number in an advert is overruled, and worth being plain
  # about why: the number is not wrong, it is ambiguous.
  #
  # VW gives the same pack twice over. The short car's is 86 gross and 79 net;
  # the long car's is 91 gross and 86 net. So "86 kWh" in a title is either of
  # two packs, and a seller copying it off the spec sheet cannot tell you which
  # -- usable_kwh turns 82 into 77 and 91 into 86, but has to leave 86 alone.
  #
  # What settles it is another thing the same advert says. A short wheelbase
  # advertised as 86 has the 79, and that second reading is the reliable one:
  # 101 long cars say 86 and not one says 77 or 79, while 59 short ones say 77
  # or 79 against this single 86.
  #
  # A correction by hand still wins over both.
  def self.settle_gross_batteries!
    settled = 0

    where(kwh: 86, wheelbase: "short").find_each do |car|
      next if car.corrected?(:kwh)

      car.update_columns(
        kwh: 79,
        data: car.data.to_h.merge("kwh_from" => "the advert says 86, which on a short wheelbase is the 79 measured gross")
      )
      settled += 1
    end

    settled
  end

  # A demonstrator that has been driven since it arrived is not new any more.
  # The hiding happens once, when the car is first saved, so without this a car
  # that came in on delivery mileage stays out of sight at 1500 km. Only what
  # the rule put away: a car you crossed off yourself stays crossed off.
  def self.show_driven!
    binned.where(hidden_by: "as new").where("km > ?", AS_NEW_KM).update_all(hidden_by: nil)
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

  # Hides the delivery van. The Cargo is the same car with panels where the
  # side windows go and nothing behind the front seats, and it does not always
  # say so: "L1H1 204pk 77kWh RWD / Demonstratieauto" reads like any other
  # advert unless you know that L1H1 is a body shape. The seat count gives it
  # away -- the Cargo seats two or three, the Bus five, six or seven -- and now
  # that the listing pages are read, two cars in three have one.
  #
  # It judges the same number the scraper judges titles by, so a van that says
  # "3-ZITS" in its title never arrives at all and one that only says it on its
  # own page is put in the bin here. And like hide_small_batteries!, a car that
  # states no seat count is left alone.
  #
  # Four seats is deliberately not too few: the one four seater we have is a
  # five whose seller did not count the middle seat on the back bench.
  def self.hide_cargo!
    hidden = 0

    on_offer.includes(:model).each do |car|
      next if car.favourite

      minimum = car.model.min_seats.to_i
      next if minimum.zero?
      next if car.seats.nil? || car.seats >= minimum

      car.update_columns(hidden_by: "a cargo van")
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

  # The photo at a size worth looking at, which is only ever asked of the site
  # by Photos and never by a page of ours.
  #
  # What the scrapers store is whatever the search page showed, and that
  # differs by site: AutoScout24 hands out a 250x188 thumbnail (8 kB), and
  # 12gebrauchtwagen a 1280x960 one (84 kB). Both name the size in the url, so
  # asking for another one is a substitution -- upwards only. Rewriting every
  # size to 1024x768 was handing out a smaller picture than the one already in
  # hand for the 455 cars that arrive at 1280.
  BIGGEST = "1024x768".freeze
  SIZE_IN_URL = %r{/(\d+)x(\d+)\.(webp|jpg|jpeg|png)\z}

  def large_image_url
    return nil if unwrapped_image_url.nil?
    return unwrapped_image_url if unwrapped_image_url[SIZE_IN_URL, 1].to_i >= 1024

    unwrapped_image_url.sub(SIZE_IN_URL, "/#{BIGGEST}.\\3")
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
  # What the range itself makes certain, for the adverts that do not say.
  #
  # Two rules, because these are the only two the stock bears out without a
  # single exception:
  #
  #   the long wheelbase has only ever carried the 86 -- 265 cars on offer
  #   state a battery and all 265 say 86, from July 2024 to today;
  #
  #   before July 2024 there was only the 77 -- of 234 cars registered earlier
  #   that state one, 231 say 77, and the three that disagree are adverts
  #   contradicting themselves: a "Pro 79 kWh" registered August 2023 and a
  #   "Pro 58KWh" from May 2024, neither pack existing yet.
  #
  # What it deliberately will not do is guess after July 2024. The facelift
  # arrived that August, but pre-facelift stock kept being registered well
  # into 2025 -- five cars from April and June 2025 say 77 kWh in their own
  # titles. A date cannot settle that and the advert can.
  #
  # Never over an advert: only a car whose battery is unknown is filled in,
  # and a later scrape that finds a real figure writes over the inference.
  FACELIFT = Date.new(2024, 7, 1)

  # The motor dates the car better than its registration does, which is the
  # whole trouble with the date rule: the old 150 kW car kept being sold new
  # into 2025. Over the cars whose advert states a battery: 150 kW comes with
  # the 77 in 67 out of 67, and a short 250 kW with the 79 in 26 out of 26.
  # A short 210 kW is 79 in 21 of 22, the odd one out being an advert that
  # contradicts itself -- "210 kW Pro KR 82 kWh", a facelift motor with the
  # old pack -- and it states its battery, so no inference touches it.
  #
  # Only when the wheelbase is known to be short: among the 210 kW cars whose
  # wheelbase we cannot read, two say 86, and those will be long ones.
  POWER = /\b(1[0-9]{2}|2[0-9]{2})\s*kW\b/i

  # A GTX is the 250 kW car and nothing else: of the GTX adverts that state a
  # power, all 56 say 250. So a title that says GTX and no kW still dates
  # itself. What GTX does not settle on its own is the pack -- 117 long ones
  # all say 86, while the short ones say 79 -- so it only helps through the
  # wheelbase, like any other 250 kW car.
  GTX = /\bgtx\b/i

  def self.infer_batteries!
    filled = 0

    on_offer.where(kwh: nil).find_each do |car|
      power = car.version.to_s[POWER, 1]&.to_i
      power ||= 250 if car.version.to_s.match?(GTX)

      inferred, because =
        if car.wheelbase == "long"
          [86, "the long wheelbase has only come with the 86"]
        elsif power == 150
          [77, "150 kW is the car before the facelift, and that had the 77"]
        elsif car.wheelbase == "short" && [210, 250].include?(power)
          [79, "#{power} kW on the short wheelbase has only come with the 79"]

        elsif car.year && car.year < FACELIFT && !car.version.to_s.match?(PURE)
          [77, "before July 2024 there was only the 77"]
        end
      next if inferred.nil?

      car.update_columns(kwh: inferred, data: car.data.to_h.merge("kwh_from" => because))
      filled += 1
    end

    filled
  end

  # Worked out rather than read off the advert, and said so on the car's page.
  def inferred_kwh
    data.to_h["kwh_from"] if kwh
  end

  # What the seller wrote, for the cars whose own advert page we have been to.
  # Details keeps it because the request has already been paid for, and it is
  # where the things no field holds are said: that the battery is 79 kWh and
  # measures 99% of new, that there are five years of warranty left, what the
  # car cost new. Half of it is a bulleted equipment list and the other half is
  # the dealer's sales pitch.
  #
  # Kept exactly as the site served it, which means html, so whatever displays
  # it has to run it through a sanitiser -- it is a stranger's markup.
  def description
    data.to_h["description"].presence
  end

  # What you have put right by hand.
  #
  # The advert is not always the truth: car 1616 says eight seats in
  # AutoScout24's own structured field, and there are five in its photograph.
  # An ID. Buzz is built as a five, six or seven seater, so the seller simply
  # typed the wrong thing -- and without this the next scrape would read that
  # field again and write the eight straight back.
  #
  # Same idea as hidden_by: "you" outranks what a site says.
  def correct!(field, value)
    update_columns(field => value, corrections: corrections.merge(field.to_s => value))
  end

  def corrected?(field)
    corrections.is_a?(Hash) && corrections.key?(field.to_s)
  end

  # The other rows that are this same car, wherever they came from.
  #
  # The photograph is the strongest tie: one advert's pictures live in one
  # folder, and the sites that syndicate each other hand out the same folder --
  # which is what made 4093 and 4767 recognisable as one van. Failing that, the
  # same build month, odometer, town and asking price to the euro, which is the
  # test Car.retitled makes and is wrong about nobody.
  def twins
    others = self.class.where.not(id: id)

    return others.where("image_url like ?", "%#{photo_key}%").to_a if photo_key.present?
    return [] if km.nil? || year.nil? || eur.nil? || locality.blank?

    others.where(km: km, year: year, eur: eur).select { |car| car.locality == locality }
  end

  # Everything you have said about this car, taken over from another row of it.
  # A star, a note, a crossing-off and a correction are about the van; which
  # row they were written on is an accident of which advert we saw first.
  #
  # Yours wins over theirs, on every count: a note here is not replaced by a
  # note there, and a correction here outranks the same correction there. What
  # travels is what this row does not have.
  #
  # Corrections travel with their values, because that is what a correction is
  # -- a number that outranks the advert. Car 1616 says eight seats and has
  # five; the copy of it that arrives tomorrow from another site says eight as
  # well.
  #
  # Returns 1 when it took something over, 0 when it had nothing to take, so a
  # round can count what it did.
  def adopt_decisions_from(others)
    others  = Array(others)
    changes = {}

    changes[:favourite] = true if !favourite && others.any?(&:favourite)

    note = others.filter_map { |car| car.comments.presence }.first
    changes[:comments] = note if comments.blank? && note

    changes[:hidden_by] = BY_HAND if !hidden_by_hand? && others.any?(&:hidden_by_hand?)

    theirs = others.reduce({}) { |all, car| car.corrections.to_h.merge(all) }
    ours   = corrections.to_h
    unless (theirs.keys - ours.keys).empty?
      changes[:corrections] = theirs.merge(ours)
      changes[:corrections].each { |field, value| changes[field.to_sym] = value }
    end

    return 0 if changes.empty?

    update_columns(changes)
    1
  end

  # In the bin, or on the pages. hidden_by says which, and why.
  def binned?
    hidden_by.present?
  end

  def shown?
    hidden_by.nil?
  end

  # The card picture on the wall and in the bin: our own copy, or nothing.
  #
  # Our copy of *a* picture of this car, note, not of the picture the advert
  # happens to show this morning. Those are different questions and they were
  # one question for a day: a scrape from the laptop refreshed image_url on 94
  # AutoScout24 cars, the digest in the file name stopped matching the new url,
  # and the wall went blank for all of them -- with the old photographs sitting
  # on the disk, of the same cars, perfectly good. photo_stored? is the
  # question Photos asks (is this still the advert's picture, should it be
  # fetched again); this is the question a page asks.
  #
  # It used to fall back to the site's own url so that a car scraped a minute
  # ago still showed something. That is one page of ours asking a seller's
  # server for a file, which is the thing we do not do -- and it bought little:
  # Photos runs at the end of the same round that finds the car, so the wait it
  # covered is minutes.
  def photo_url
    "#{Photos::PATH}/#{photo}" if held?(photo)
  end

  # The one on a car's own page: our big copy, with our card copy behind it for
  # the cars whose big one has not been fetched yet.
  def large_photo_url
    return "#{Photos::PATH}/#{large_photo}" if held?(large_photo)

    photo_url
  end

  # Named after the url it came from, so a listing that swaps its picture gets
  # a new file rather than a stale one. The big one hangs off a url of its own,
  # so the same rule names it and the two cannot collide.
  def photo_digest
    return nil if unwrapped_image_url.nil?

    Digest::SHA256.hexdigest(unwrapped_image_url)[0, 16]
  end

  def large_photo_digest
    return nil if large_image_url.nil?

    Digest::SHA256.hexdigest(large_image_url)[0, 16]
  end

  # The name in the column is only half of it: the file has to be there too.
  # A database restored onto a machine without the pictures -- this laptop,
  # carrying a dump of the droplet -- would otherwise show six hundred broken
  # images and never fetch them, because the column says they are already
  # here. Checking costs one stat per car, and it means a wiped volume heals
  # itself on the next scrape.
  # What Photos asks: is the file here, and is it still the picture the advert
  # shows? A listing that swaps its photograph fails the second half and is
  # fetched again -- the name is a digest of the url it came from, so a new url
  # means a new file rather than a stale one under the old name.
  def photo_stored?
    held?(photo) && named_after?(photo, photo_digest)
  end

  def large_photo_stored?
    held?(large_photo) && named_after?(large_photo, large_photo_digest)
  end

  # On the disk, under that name. The name in the column is only half of it: a
  # database restored onto a machine without the pictures -- this laptop,
  # carrying a dump of the droplet -- would otherwise show six hundred broken
  # images and never fetch them, because the column says they are already here.
  # One stat per car, about a millisecond over a page.
  def held?(name)
    name.present? && File.exist?(Photos::DIRECTORY.join(name))
  end

  def named_after?(name, digest)
    digest.present? && name.to_s.start_with?(digest)
  end

  # Worth a request only when the site has something bigger than the picture
  # the card already gave us. For 12gebrauchtwagen it has not: its 1280x960 is
  # above the size we ask for, so its stored file is the big one.
  def wants_large_photo?
    image_url.present? && large_image_url != unwrapped_image_url && !large_photo_stored?
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
    [source, year, km, locality, version.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip]
  end

  # Where the car stands, for the rules that have to agree with each other
  # about it. The postcode as written comes first and needs no lookup; only a
  # listing that gives a bare town name asks the table, and that answer can
  # come back nil (a town the tables do not carry). A key that is sometimes nil
  # for the same row is worse than a coarse one: merge_retitled! skipped car
  # 5650 on its first pass and merged it on the second, which is how this was
  # found.
  def locality
    Postcode.digits(location).presence || place_key
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
    # Read out of the title on every save, so a correction by hand would be
    # thrown away by the next scrape without this.
    return if corrected?(:wheelbase)

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
