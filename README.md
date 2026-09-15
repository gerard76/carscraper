New version from https://github.com/gerard76/carcrawler

It fetches the car model you are interested in and plots the result in a scatterplot
so it is easier to see which cars are bargains.

The plot puts build year and price on the axes, so a car under the trend line
asks less than its year suggests. Colour is mileage per year: green is gently
used for its age, red is driven hard. Under the line and green is the find;
under the line and red is cheap for a reason.

Mileage itself is deliberately not what is coloured. Over 2000 ID. Buzz
listings it correlates -0.68 with the build year, so it would mostly repeat
what the position along the x axis already shows, while mileage per year
correlates 0.10 with it and 0.10 with the distance to the line -- it is the one
thing the graph cannot show twice. The scale runs over the 5th to 95th
percentile of what is on screen, so a single absurd listing cannot flatten it.
A car whose seller left the odometer empty cannot be placed on that scale and
is drawn as a grey ring.

`/cars/table` has the same cars as a table instead, sortable by distance,
price, mileage, build date, title or place, keeping whatever the search form is
filtering on. The title links to the car's own page, where you can hide it or
leave a note; the icon at the end of the row opens the listing on the site it
came from.

# Get started

Create you first model: `Model.create(make: 'Fiat', model: 'Ducato')`

Fetch matching cars: `Scrapers::Autoscout24.new(Model.first).scrape`
See the graph on http://localhost:3000/cars

![Example graph](/app/assets/images/example_graph.png)

# Scrapers

One command does the lot -- every source for every model, and the tidying up
that a scrape leaves behind:

```
bin/rails cars:scrape
```

That last part matters and cannot be skipped: listings turn up that are already
here under another url, and one car arriving moves the bargain of every other
car. The task hides the duplicates and the batteries that are too small, then
works the bargains out again.

Every scraper also takes a model on its own and fetches what that site has:

```ruby
model = Model.first
[Scrapers::Autoscout24, Scrapers::GebrauchtwagenDe, Scrapers::Autotrack, Scrapers::Gaspedaal, Scrapers::FinnNo].each do |scraper|
  scraper.new(model).scrape
end
```

| Scraper | Site | Covers |
| --- | --- | --- |
| `Scrapers::Autoscout24` | autoscout24.nl | NL, BE, DE, LU -- see `COUNTRIES` |
| `Scrapers::GebrauchtwagenDe` | 12gebrauchtwagen.de | DE -- an aggregator over mobile.de, heycar, autohero, carwow and others |
| `Scrapers::Autotrack` | autotrack.nl | NL |
| `Scrapers::Gaspedaal` | gaspedaal.nl | NL -- an aggregator over Marktplaats, the ANWB, dealer sites and a few dozen more |
| `Scrapers::FinnNo` | finn.no | NO, prices in kroner |

Running a scraper again only adds what is new; listings already stored are
recognised by their url.

A scraper stops after `MAX_PAGES` pages as a brake, so raise that (or pass
`scrape(max_pages: 200)`) if a model has more listings than that.

Sites tend to park a different car in a model's category -- an ID. Buzz Cargo
under ID. Buzz, say. Set `exclude_versions` on the model to drop those:
`Model.first.update(exclude_versions: 'ID.3, ID.4, Cargo')`.

`min_kwh` throws out a battery smaller than you want. It only judges an ad
that names one -- 149 of 1366 do -- so a Pure that keeps quiet about its 59 kWh
stays. Set to 77 it caught eight, one of them titled "Pro 58KWh", which no
amount of filtering on trim names would have found.

`min_seats` catches the ones that never say "Cargo". None of the sites takes a
seat count in its url that we can use: AutoScout24 has one, but it also drops
every listing whose seller left the seats empty -- 35 of the 80 it removed on
an ID. Buzz, genuine passenger versions among them -- and AutoTrack's seats
facet drops the make/model filter when you combine the two. So the seat count
is read from the ad text instead ("7-s", "6-Sitzer", "3 seter", and the bare
"3s" Norwegian sellers use). A listing that names no seat count is kept, so
this thins the cargo vans out rather than guaranteeing none get through. Cars
already stored are not re-checked when you change `min_seats`.

## Is it a good price

`Car#bargain_eur` says how much less a car asks than comparable cars of its
age and mileage: the distance from a least squares plane through price, build
year and mileage, in euro. Positive is cheap, negative is dear.

It is worked out for every car at once, because the plane is drawn from all of
them -- one car arriving moves it, and with it everybody's number. So
`Car.recalculate_bargains!` belongs after a scrape, next to
`hide_duplicates!`; cars scraped since sit on nil until it runs.

Read it within a trim, not across trims. The fit knows nothing about trim
level, and a Pure is not a cheap GTX but a cheaper car: over these listings a
GTX averages 7168 under the plane and a Pure 14514 over it, and 18 of the top
20 "bargains" are Pures. Neither fix is clean -- trim words in ad titles are
unreliable ("Pure GTX 86 kWh" exists) and only a third of titles name a kW or
kWh figure -- so the search form has `Title contains` and `Title excludes`
boxes instead: narrow to one trim, or knock one out, then sort on the column.

What the trims are, going by what the ads themselves say:

| | cars | average | battery | power | 4MOTION |
| --- | --- | --- | --- | --- | --- |
| Pure | 53 | 47525 | 59-63 kWh | 125 kW | none |
| 1st | 6 | 43758 | 77 kWh | | none |
| Pro | 821 | 51994 | 77-86 kWh | 150 or 210 kW | none |
| GTX | 319 | 68044 | mostly 86 kWh | 250 kW only | 70% |

## What a car costs you

The graph plots the asking price plus an estimate of what it takes to get the
car onto Dutch plates, per country, from `Car::IMPORT_COSTS`. The `Eur max`
filter goes by that same total, and the car page breaks it out.

It is one figure for every country worth driving to: 1700, which is what Das
Import quotes all-in for fetching a car from Germany -- their service,
transport, the RDW fees and the registration. Nothing is added for tax, because
a fully electric car owes no BPM, and that is what makes a single number
enough. Change the constant and the graph follows.

A Cargo on grey plates is a bestelauto, which is taxed by its own tariff, so
this figure would not hold for one. They are filtered out well before the
graph.

Norway is the odd one out. It sits outside the EU, so duty and VAT are owed on
the value of the car itself, which no fixed amount covers. It is set to a third
of the asking price plus 1500, and that is the first figure to check if the
Norwegian cars look off.

## How far away it is

`Car#distance_km` is the straight line distance from home, worked out from the
postcode the listing comes with. It is a fifth or so short of the road
distance, which is close enough to tell a errand from a trip.

Two things have to be in place. First the postcode tables, which are free from
GeoNames and imported once:

```
bin/rails postcodes:import
```

Then where you live, in `config/home.yml`, which is not in git because a
postcode says roughly where you are and this remote is public:

```yaml
postcode: "1234"
country: NL
```

Without either of those there are simply no distances, and the graph and the
car page leave them out. After moving house, or after importing another
country, run `Car.recalculate_distances!` to work the cars already stored out
again.

A listing only has a distance if its site says where the car is, and they do
not agree on how. AutoScout24 and 12gebrauchtwagen name a postcode ("8606 JS",
"40233 Düsseldorf"); AutoTrack and gaspedaal name the seller's town
("Harderwijk", "Den Bosch") and no postcode at all. Towns are matched on their
name, falling back to an everyday alias and then to the name without the
province a seller tacked on, so "Den Haag" finds 's-Gravenhage and "Hengelo Ov"
finds Hengelo. `Car#location` holds whichever came with the listing and
`Postcode.locate` takes both: digits are looked up as a postcode, anything else
as a town, whose postcodes are averaged into its middle. finn.no is left out --
Norway is too far to drive to anyway.

## The same car twice

12gebrauchtwagen carries a lot of what AutoScout24 already has, so one car
turns up as two listings and counts twice, in the graph and in the trend line.
`Car.hide_duplicates!` sets all but the cheapest of a set to not visible, which
is where they stay: a later scrape leaves listings it already has alone. Worth
running after a scrape.

Two listings are one car when they agree on build year, odometer reading and
place, and their prices are within `Car::PRICE_SPREAD` of each other. They also
have to come from different sites -- there are dealers with several similar
cars on one site, whose listings match on all of that without being the same
car.

One exception to the price having to match: when two listings are exactly
`Car::VAT` apart, that difference is the VAT. The Dutch trade quotes a
commercial vehicle -- a three seater on grey plates, say -- without it and
everybody else with it, and the sites each pick up one of the two. The listing
that includes it stays, because privately that is what you pay. Three such
pairs were in here, and the cheapest car on the graph was one of them: 27900 at
gaspedaal against 33759 at AutoScout24, to the euro the same car.

Year rather than build month, and place rather than the location as written,
because the sites do not say those the same way: gaspedaal knows only a year
where AutoScout24 knows the month, and one names a postcode where the other
names a town. Both are resolved through the postcode tables first, so "6546 AS"
and "Nijmegen" meet. Matching on odometer alone is tempting and wrong: two
different cars can share a reading, and one Leverkusen dealer has seven sets
that do.

## New cars, and other currencies

A car at or below `Car::AS_NEW_KM` (100) has delivery mileage, so it is stored
but starts with `visible` off and stays out of the graph. That only happens
when it is first scraped -- switch one back on by hand and it stays on.

Prices in kroner are converted with `Car::NOK_PER_EUR` and `Car::SEK_PER_EUR`.
Those are fixed numbers and go stale; after changing them run
`Car.recalculate_eur!` to work out the cars already stored again.

## Adding one

Inherit from `Scrapers::Base`, which handles fetching, pacing, cleaning up
text and saving a Car, and implement `#scrape`. Two things are worth copying
from the existing ones:

- Check every listing against `matches_model?` before saving it. All three of
  these sites hand back their entire stock when a filter in the url stops
  being understood, and without that check you import the lot.
- Watch out for leasing offers. Their price is a monthly rate, and neither
  12gebrauchtwagen nor finn marks them as such in its structured data.

## Sites that are gone

`bilnorge.no` is a news site now, `cargurus.de` is a placeholder pointing at
cargurus.com and `broommarked.no` redirects to tv2.no/broom. `autotrader.nl`
still works but resells AutoScout24's stock, so it returns listings we
already have. `bilweb.se` (Sweden, prices in kroner, mileage in *mil* of
10 km) is scrapeable but had no ID. Buzz at all.