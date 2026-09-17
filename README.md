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

`/cars/photos` is the same cars as a wall of photographs: the first picture
from each listing, kept here rather than hot-linked -- see `Photos`. A grid has
no column headers to click, so the same sorts sit above it as links.

Both open cheapest first, and then on whatever you last sorted on: the choice
is kept in the session and shared between the two pages, so the table and the
photos agree without being told twice.

`/cars/table` has the same cars as a table instead, sortable by distance,
price, mileage, build date, bargain, star, and how new it is, keeping whatever
the search form is filtering on. `New` counts the days since the scrape that
first found the car -- not how long it has been for sale, since everything in
the very first scrape of a site had been up for who knows how long, but from
then on it is exactly what you want to sort on. Newest first on the first
click. The title links to the car's own page, where you can hide it or
leave a note; the icon at the end of the row opens the listing on the site it
came from.

The star in front of a row -- and in the corner of a photo, and next to the
heading on a car's own page -- marks one worth coming back to. `Starred only`
in the filters then shows nothing else. When two listings turn out to be the
same car the cheapest still wins, but the star moves over to it: it marks the
car, not the advert. Rules about the car itself do leave a starred one alone --
a battery that is too small, a Pure -- because marking one is a decision and a
rule does not overrule a decision.

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

The four pages -- graph, table, photos, bin -- sit in one menu at the top of
every page, with the current one marked, and the links carry whatever the
search form is filtering on from one view to the next. The filters themselves
sit in a card above it, a label over each field, wrapping into as many rows as
the window needs, with a Clear link once something is filled in.

Every photo has a cross in its corner: one click and the car is off all three
pages. `/cars/bin` has those back, with a button each, and nothing else in it.

That is what `hidden_by` is for. A car can be off the pages because you put it
there (`Car::BY_HAND`) or because a rule did -- listed on two sites, advertised
twice, as new, battery too small -- and the two must not be mixed up. The bin
would be a heap of duplicates rather than a list of decisions, and worse, a
rule would overwrite a decision. So the rules skip a car you hid yourself, and
hiding one of a pair by hand leaves its twin on the pages, since there is no
longer a duplicate to hide. What a rule hid needs the console to bring back,
on purpose.

A car is on the pages when two things hold: you have not clicked it away
(`visible`) and a scraper has seen it on a site lately (`Car.listed`, within
`Car::SEEN_WINDOW`). The two are kept apart on purpose -- one is your decision,
the other is the market's.

A listing nobody has seen for that long is sold or withdrawn, and
`Car.remove_vanished!` takes the row out at the end of a scrape. That is worth
knowing about: the first sweep removed 1121 of 2788 rows, 599 of which were
still on the graph -- 12gebrauchtwagen's links answer 410 Gone within days. The
window is the safety margin, so a source that falls over does not cost you its
cars on a single miss. A car that comes back comes back as a new row, and any
note on it is gone with it.

Running a scraper again only adds what is new. A listing is recognised by its
fingerprint -- `Car#identity`: the site it came from, its build month, its
mileage, its place and its title -- and not by its url, because a url is not
always the same thing twice. 12gebrauchtwagen links through a redirect whose
offer_id rotates, so the same car used to come back as a new row on every
round: 491 of 3354 rows were re-arrivals, hidden again as duplicates the moment
they landed. Now they are recognised and refreshed instead, url and all.

Mileage is part of the fingerprint on purpose. Without it, six different cars
from one seller sharing a generic title collapsed into one. `Car.merge_relisted!`
sweeps up rows that share a fingerprint exactly -- the same listing under a new
url -- keeping the visible one and carrying over any note.

A scraper stops after `MAX_PAGES` pages as a brake, so raise that (or pass
`scrape(max_pages: 200)`) if a model has more listings than that.

Sites tend to park a different car in a model's category -- an ID. Buzz Cargo
under ID. Buzz, say. Set `exclude_versions` on the model to drop those:
`Model.first.update(exclude_versions: 'ID.3, ID.4, Cargo')`.

`min_kwh` throws out a battery smaller than you want. It only judges a car we
have a battery for, so a Pure that keeps quiet about its 59 kWh stays. It used
to read the title and nothing else -- 149 of 1366 named one -- and now it reads
the `kwh` column below, which the listing pages fill in as well, so it judges
a good deal more of them. Set to 77 it caught eight, one of them titled
"Pro 58KWh", which no amount of filtering on trim names would have found.

`min_seats` catches the ones that never say "Cargo". None of the sites takes a
seat count in its url that we can use: AutoScout24 has one, but it also drops
every listing whose seller left the seats empty -- 35 of the 80 it removed on
an ID. Buzz, genuine passenger versions among them -- and AutoTrack's seats
facet drops the make/model filter when you combine the two. So the seat count
is read from the ad text instead ("7-s", "6-Sitzer", "3 seter", and the bare
"3s" Norwegian sellers use). A listing that names no seat count is kept, so
this thins the cargo vans out rather than guaranteeing none get through. Cars
already stored are not re-checked when you change `min_seats`.

## Seats and battery

Both are columns now -- `cars.seats` and `cars.kwh` -- and both are filters on
the search form. Blank on a car means the advert never said, never that it has
none.

They matter more than they look. On an ID. Buzz the battery *is* the wheelbase:
one pack per generation, so 77 and 79 are the short one and 86 is the long one.
And the short one comes as a five seater (2/3) or a six seater (2/2/2), where
the long one adds a seven seater (2/3/2). Wanting a six seater on a short
wheelbase is a perfectly ordinary thing to want and nothing on a search page
lets you ask for it.

Reading it out of the title is not enough. Of 647 listings, 67 said anything
about seats -- one in ten. So `Details` opens the listing's own page, where
AutoScout24 carries `numberOfSeats` as a real field, and fills in what the
card could not say: 526 of its 541 cars, and 544 of the 647 altogether. That
took short six seaters from 4 to 20. It runs at the end of a scrape next to
`Photos`, one page per car and once per car, and on its own with
`bin/rails cars:details`. Only AutoScout24: four fifths of the cars come from
there and it is the only one of the four whose detail page we know how to read.

Which means it only works from a machine AutoScout24 answers. From the droplet
every listing page is a 403 (see "The droplet is blocked" below), so the
twice-daily round there fills in nothing; what fills these in is
`mise run scrape:production` from this machine, the same round that keeps
AutoScout24 and AutoTrack fresh at all. `REFUSALS_BEFORE_GIVING_UP` stops the
droplet working through three hundred refusals to find that out -- five in a
row and it leaves the rest, because one 403 among answers is a listing taken
down and five in a row is the door.

The battery is not a field anywhere, so it is read off three things in turn:
the seller's title, then a *labelled* capacity in the description
("Hochvolt-Batterie 91 kWh (brutto)", "Nutzbare Batteriekapazität: 79,0kWh"),
and failing both, every capacity the text mentions -- but only when they all
come to the same pack.

That last condition is the whole trick. A few lines above the specification
sits the disclaimer on bidirectional charging, "nur in Verbindung mit
Hochvolt-Batterien 79 kWh und 86 kWh", which names two packs the car may not
have; simply taking the first kWh in the description filed seven long
wheelbase cars as short ones, four of them seven seaters, which cannot be
short at all. Two different capacities means it is the disclaimer talking.

`Car::BATTERY_PACKS` then writes every gross figure down as its net one --
82 to 77, 84 to 79, 91 to 86 -- because sellers quote both and do not say
which, and one car reading as 84 in one advert and 79 in the next makes the
filter useless. Add a model with another battery and its gross figures belong
in that table; change the table and `Car.renormalise_kwh!` works the stored
cars out again, the way `Car.recalculate_eur!` does for a new exchange rate.
`Car::PLAUSIBLE_KWH` throws out what was never a battery: the energy label's
"0,00 kWh/100 km" arrived as a pack of nought until the pattern learned to
refuse a slash after the unit.

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
20 "bargains" are Pures. The search form has `Title contains` and `Title
excludes` boxes for that: narrow to one trim, or knock one out, then sort on
the column.

`Car.hide_pures!` takes the Pures out altogether, and it is that same lopsided
number it goes by. A Pure has 59 kWh where a Pro has 79 and 125 kW where a Pro
has 150, but its ad seldom states either, so `min_kwh` never sees it. What the
graph sees is a car priced against Pros, sitting far under the line. Neither
half of the rule would do alone -- "Pure" turns up in paint names, and a car
can honestly be `Car::PURE_BARGAIN` (8000) under the going rate -- but
together they are as certain as this gets without the seller saying anything.
All 23 on offer were caught, the closest call at 8679 where the whole fleet's
ninth decile was 9365, and none was a mislabelled Pro: the four whose titles
name a power all said 125 kW, and one spelled out "Motor: 125 kW (170 PS) 59
kW". A "Pure GTX 86 kWh" is safe from it, because a GTX does not sit 8000 under
the line.

The rule runs between two passes of `recalculate_bargains!`: it needs the
numbers to spot them, and taking two dozen cars out from under the line moves
the line for everyone left. Over these listings it lifted the fit from 6608 to
6910 euro a year of age.

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

A seller advertising one car twice is a second case, and the url and the
fingerprint both miss it: the two ads have their own ids, their own
photographs, and an odometer that has moved on between them. `Car.relisted`
catches those on the same site, the same year, the same town, the same title
to the character, the same money, and a mileage within `Car::RELISTED_KM` of
each other -- the taxi that turned this up read 10800 on one ad and 11500 on
the other.

That last condition is what makes it safe. Dealers do keep several alike cars:
one in Kiel has three under the one title, 12500 km apart, and one in
Gelsenkirchen two that are 42000 km apart. An identical title on its own would
have thrown those away. The newest reading survives -- the ad seen most
recently, and of those the one with the most on the clock.

One exception to the price having to match: when two listings are exactly
`Car::VAT` apart, that difference is the VAT. The Dutch trade quotes a
commercial vehicle -- a three seater on grey plates, say -- without it and
everybody else with it, and the sites each pick up one of the two. The listing
that includes it stays, because privately that is what you pay. Three such
pairs were in here, and the cheapest car on the graph was one of them: 27900 at
gaspedaal against 33759 at AutoScout24, to the euro the same car.

The photographs are the other way past the price. A Reutlingen car was on
12gebrauchtwagen for 38830 and on AutoScout24 for 37460 -- 3.7% apart, too far
for `Car::PRICE_SPREAD` -- but both listings show the same picture. That is
visible because 12gebrauchtwagen serves AutoScout24's pictures through a proxy,
and `Car#unwrapped_image_url` takes them back out of it.

The picture's path is worth more than the picture. AutoScout24 files it as
`listing-images/<advert>_<picture>`, so the first half is the advert's own id,
and `Car#photo_key` keeps only that: two listings whose pictures come out of one
folder are one advert, even where the two sites picked a different picture out
of it. A Berlin car was 67989 on one site and 68985 on the other, both from
advert deae2207.

It is still only corroboration, never proof. A site with no picture for a car
can hand out a placeholder, and a placeholder would tie together every car it
was given to. So the photo replaces the price and nothing else: the build month,
the town, a mileage within `Car::RELISTED_KM` and two different sites all still
have to agree, and the group has to be no bigger than
`Car::MOST_SITES_WITH_ONE_CAR`, which a placeholder would blow past at once. In
this data there is no placeholder to worry about: all 667 adverts that appear
twice appear exactly twice, never twice on one site, every pair agrees on build
month and town, 658 of them read the same mileage to the kilometre, and 662
carry the same title to the character. The rule collapsed 27 pairs the price had
let through, as much as 6900 euro apart.

Those pairs are also what the price rule alone keeps missing, because it asks
that a whole group of cars be one price rather than pairing them up. A Rosstal
dealer had three GTXs on the same day at the same mileage, each cross-listed:
59190, 60490 and 60990, which the group test reads as 3% and throws out whole.
The adverts sort them into the three pairs they are.

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
# On the server

Deployed with kamal to the same droplet as the other projects, at
https://carscraper.diamondbay.nl. Anyone with the link can look; every click
that changes something -- crossing a car away, putting one back, a note, the
models scaffold -- asks for one shared password.

```
bin/kamal setup     first time: installs docker, boots postgres, deploys
bin/kamal deploy    every time after that
bin/kamal rollback  back to the previous version
bin/kamal logs      follow them
bin/kamal console   a rails console in the running container
bin/kamal psql      a psql in the accessory
```

## What it needs once

**An A record** for `carscraper.diamondbay.nl` pointing at the droplet
(146.185.130.81). The domain has a wildcard that goes somewhere else, so the
name resolves today and resolves *wrong*: `pre-connect` refuses to deploy until
it points at the right machine, because kamal-proxy would otherwise ask Let's
Encrypt for a certificate it cannot be given and the site would sit on 502.

**The secrets**, all of which live in the credentials and nowhere else:

```
bin/rails credentials:edit     # or: mise run edcred
```

```yaml
secret_key_base: ...          # signs the cookies
kamal:
  registry_user: ...          # a DigitalOcean registry token with read+write;
  registry_password: ...      # for a personal token, the same value twice
database:
  password: ...               # postgres is created with it, the app connects with it
auth:
  password: ...               # what you and Mila type before a click that changes something
home:
  latitude: ...               # where the distances are measured from
  longitude: ...
```

`secret_key_base`, the database password, the click password and the
coordinates are filled in already; the two registry values are not.
`pre-connect` names anything still empty before the deploy touches the server.

`.kamal/secrets` holds no values -- this repository is public -- only the names,
each one read out of those credentials by `.kamal/read-secret` at deploy time
and handed to the container as an environment variable. So the app on the
server reads none of that file itself and is never given the key.

The key is `config/master.key`, sitting next to them and not in git. Without it
the credentials cannot be opened and nothing can be deployed, so it wants to be
in a backup somewhere -- and `pre-build` refuses to build if it ever turns up
in git, because this repository is public.

**The data**, because the database starts empty and the graph needs cars:

```
bin/kamal accessory boot postgres
# 5433 at both ends: the accessory publishes 5433 on the droplet, because
# 5432 there is trading-bot's database and would take the password badly.
ssh -fN -L 5433:127.0.0.1:5433 deployer@146.185.130.81
pg_dump --no-owner --no-privileges carscrape | psql -h localhost -p 5433 -U carscraper carscraper_production
```

That carries the postcodes over too, which is the slow part of a fresh start
(`Postcode.import!` downloads 20375 rows and only needs doing once).

## Scraping on its own

A `job` container next to the web one runs GoodJob, and GoodJob runs the
scrape at **07:00 and 19:00**, Amsterdam time. `Car::SEEN_WINDOW` is three
days, so once a day would keep the pages full; twice means a listing is in the
graph within twelve hours of appearing, and one failed round leaves nothing
stale. Asking four sites more often than that buys nothing.

The schedule is in `config/initializers/good_job.rb`, and only the process
started with `GOOD_JOB_ENABLE_CRON=1` acts on it -- the job role, and nothing
else -- so the web container cannot enqueue a scrape of its own.

`Scrape` is the whole of it, and `bin/rails cars:scrape` is the same class from
the command line. It has one guard worth knowing about: a source that is
blocked or has changed its markup returns nothing, and the listings it had
would then all look gone. So a source's cars are only removed when this round
saw at least half of what that source already had (`Scrape::MOST_OF_THEM`),
and the count is kept per source -- the sources fail one at a time, and a count
over the whole database would let a working site vouch for one nobody could
reach.

## What the sites see of us

Only result pages -- there are no detail pages to fetch, the cards carry
everything -- one request at a time, three seconds apart
(`Scrapers::Base::DELAY`). A round is roughly 15 pages of AutoScout24 (100
listings a page, but four countries and a page each to find the end), 36 of
12gebrauchtwagen at around 20 a page, 3 of AutoTrack, and 2 of gaspedaal, whose
whole result set sits on one page behind a lookup of the model's slug. Call it
60 requests, twice a day, in two three-minute bursts. One person opening the
same searches in a browser pulls more than that in scripts and adverts alone.

The ceiling is higher than the average, worth knowing: if a site changes its
markup and the "no more results" check stops working, each scraper runs to
`MAX_PAGES` -- 40 a country for AutoScout24, 80 for 12gebrauchtwagen -- so
about 560 requests in a day rather than 120.

The photographs used to be the heavy part, and not from the scraping: every
view of `/cars/photos` asked their servers for six hundred pictures. `Photos`
fetches each card picture once -- a fifth of a second apart, at most 500 in a
round -- into `public/photos`, named after a digest of the url it came from, so
a listing that swaps its picture gets a new file and the browser cannot serve a
stale one. Six hundred cards come to about 4 MB, which Thruster serves without
troubling Rails. What is still theirs is the big picture on a car's own page:
that is one request for one car, and not worth keeping a second copy of every
photograph for.

`Photos` also sweeps: a file no car points at any more is deleted, so the
directory follows the cars rather than growing forever.

On the server the directory is a named docker volume (`config/deploy.yml`), so
it outlives a deploy: a deploy replaces containers, and the volume is not one.
Docker fills a new volume from the directory in the image, which is why
`public/photos/.keep` ships -- that is where the owner comes from, and without
it the rails user could not write. Both roles mount the same volume: the job
container writes, the web container serves.

Nothing about the name in the database is trusted on its own, either. A car
counts as having its own copy only when the file is actually there, so a
database that has been restored somewhere else -- this laptop, holding a dump
of the droplet -- shows the sites' own pictures rather than six hundred broken
ones, and the next scrape fetches what is missing. It costs one stat per car,
about a millisecond over a whole page.

## The droplet is blocked, and this is what that looks like

Measured on the first scheduled round, 17 September 2026:

| | requests | |
| --- | --- | --- |
| 12gebrauchtwagen | 50 | fifty pages, right to the last one |
| AutoScout24 | 4 | **HTTP 403**, one per country, inside 150 ms |
| gaspedaal | 2 | fine |
| AutoTrack | 1 | **HTTP 403** |

So two of the four turn a data centre address away at the door, and between
them they carry half the cars. The guard held -- "left 792 autoscout24.nl
listings that look gone alone" -- and the pictures still came down fine, which
says the block is on the listing pages and not on their image servers.

What keeps those two fresh is a round from this machine, which is not blocked:

```
mise run scrape:production
```

```
mise run scrape:production
```

Whether it is open already is decided by asking postgres, not by asking the
socket: an ssh whose far end has died still holds port 5433 here, and `nc -z`
is satisfied by that. A round once sailed past the check on a tunnel like
that and fell over on "connection refused" a moment later, looking for all the
world like the database was down. If the tunnel cannot be opened because an
older one still has the port, `pkill -f 'ssh -fN -L 5433'` and go again.

That opens the tunnel if it is not open already and runs the same scrape
against the droplet's database, from this machine. It is the code in this
directory doing the work, so it stops first if a migration here has not been
deployed there -- otherwise the crash arrives halfway through a scrape,
"undefined method 'seats='", with a few hundred listings already written. The twice-daily round on the
droplet still does the other two, so between them nothing goes stale for longer
than you leave it.

`bin/kamal scrape` runs it on the droplet instead, which works but is asking
for a block.

Which also means the droplet's database is the real one -- it is where your
clicks land when you are looking at the site -- and the one here is a
development copy. To catch this one up rather than the other way round, dump in
the other direction:

```
ssh -fN -L 5433:127.0.0.1:5433 deployer@146.185.130.81
PGPASSWORD=$(.kamal/read-secret database.password) \
  pg_dump --clean --if-exists --no-owner --no-privileges \
  -h localhost -p 5433 -U carscraper carscraper_production | psql carscrape
```

## The hooks

All nine of kamal's hooks are in `.kamal/hooks`, and each one says at the top
what it is for. Three of them only announce what is happening; the rest check
something that has actually gone wrong somewhere: an empty secret (docker
answers "flag needs an argument: 'p' in -p"), a DNS record pointing at the
wrong server, a dirty checkout shipping code that matches no commit, the
credentials key creeping into a public repository, a migration running against the image
the server already had rather than the one being deployed, a deploy that exits
0 having changed nothing, and a proxy reboot taking every other site on the
droplet down with it.

Two of them can be argued with:

```
ALLOW_DIRTY_TREE=1 bin/kamal deploy           ship uncommitted changes anyway
CONFIRM_PROXY_REBOOT=1 bin/kamal proxy reboot  yes, take the whole droplet down
```
