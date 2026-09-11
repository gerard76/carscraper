New version from https://github.com/gerard76/carcrawler

It fetches the car model you are interested in and plots the result in a scatterplot
so it is easier to see which cars are bargains.

The plot puts year and price on the axis and uses color to give you information about the milage (which may vary)

# Get started

Create you first model: `Model.create(make: 'Fiat', model: 'Ducato')`

Fetch matching cars: `Scrapers::Autoscout24.new(Model.first).scrape`
See the graph on http://localhost:3000/cars

![Example graph](/app/assets/images/example_graph.png)

# Scrapers

Every scraper takes a model and fetches what that site has for it:

```ruby
model = Model.first
[Scrapers::Autoscout24, Scrapers::GebrauchtwagenDe, Scrapers::Autotrack, Scrapers::FinnNo].each do |scraper|
  scraper.new(model).scrape
end
```

| Scraper | Site | Covers |
| --- | --- | --- |
| `Scrapers::Autoscout24` | autoscout24.nl | NL, BE, DE, AT, ES, FR, LU |
| `Scrapers::GebrauchtwagenDe` | 12gebrauchtwagen.de | DE -- an aggregator over mobile.de, heycar, autohero, carwow and others |
| `Scrapers::Autotrack` | autotrack.nl | NL |
| `Scrapers::FinnNo` | finn.no | NO, prices in kroner |

Running a scraper again only adds what is new; listings already stored are
recognised by their url.

A scraper stops after `MAX_PAGES` pages as a brake, so raise that (or pass
`scrape(max_pages: 200)`) if a model has more listings than that.

Sites tend to park a different car in a model's category -- an ID. Buzz Cargo
under ID. Buzz, say. Set `exclude_versions` on the model to drop those:
`Model.first.update(exclude_versions: 'ID.3, ID.4, Cargo')`.

`min_seats` catches the ones that never say "Cargo". AutoScout24 filters on it
at the source, but 12gebrauchtwagen, AutoTrack and finn cannot -- none of them
takes a seat count in its url, and AutoTrack's seats facet drops the
make/model filter when you combine the two. So for those three the seat count
is read from the ad text ("7-s", "6-Sitzer", "3 seter", and the bare "3s"
Norwegian sellers use). A listing that names no seat count is kept, so this
thins the cargo vans out rather than guaranteeing none get through. Cars
already stored are not re-checked when you change `min_seats`.

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