# Carscraper

A used car is worth what the market says it is worth, and the market says so a
few thousand times a day across half a dozen sites. Carscraper fetches every
listing for one model, in as many countries as you are willing to drive to, and
draws all of them on one graph: build date along the bottom, what the car would
cost you on your own driveway up the side.

![The graph](app/assets/images/example_graph.png)

A line is drawn through the lot, so a car sitting under it asks less than its
age says it should. Colour is how hard it has been driven for its age -- green
gently, red hard. Under the line and green is the find; under the line and red
is cheap for a reason.

It is one person's tool, written while looking for one van. The van has been
bought, so nothing here is being developed any more. It is kept public because
the awkward parts are all written down: what a listing page will actually tell
you, how to tell one car advertised twice from two cars advertised once, and
what to do about a seller who quotes the gross battery when the one next to
him quotes the net.

- [What you get](#what-you-get)
- [Running it yourself](#running-it-yourself)
- [Telling it what to look for](#telling-it-what-to-look-for)
- [The commands](#the-commands)
- [How it is put together](#how-it-is-put-together)
- [Scrapers](#scrapers) -- and everything below it: how each piece decides what it decides
- [On the server](#on-the-server) -- how the deployed copy is put together

## What you get

Four pages over the same cars, sharing one filter and one sort, with a menu at
the top of each:

| | |
| --- | --- |
| `/cars` | the graph |
| `/cars/table` | the same cars as a sortable table |
| `/cars/photos` | the same cars as a wall of photographs |
| `/cars/bin` | the ones you have clicked away |

The graph puts build year and price on the axes, so a car under the trend line
asks less than its year suggests. Colour is mileage per year: green is gently
used for its age, red is driven hard.

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

The filter is kept the same way. Six seats, 79 kWh, under 40,000 km is a
question you go on asking for weeks, and a bare `/cars/photos` -- which is how
you arrive, from a bookmark or the menu -- used to answer it with all eleven
hundred cars until you had filled the form in again. Now a request that brings
no `q` of its own is read with the last one, and the boxes show it. Which makes
the plain path mean "what you had", so **Clear** asks for `?clear=1`: that is
the one thing that forgets it. The cookie lasts ninety days
(`config/initializers/session_store.rb`), because a session cookie without an
expiry dies when the browser does, and shutting the laptop at night should not
count as clearing the filter. Nothing is unlocked by holding it: writing is
behind http basic auth, not the session.

`/cars/table` has the same cars as a table instead, sortable by distance,
price, mileage, build date, bargain, star, and how new it is, keeping whatever
the search form is filtering on. `New` counts the days since the scrape that
first found the car -- not how long it has been for sale, since everything in
the very first scrape of a site had been up for who knows how long, but from
then on it is exactly what you want to sort on. Newest first on the first
click. The title links to the car's own page, where you can bin it or
leave a note; the icon at the end of the row opens the listing on the site it
came from.

The star in front of a row -- and in the corner of a photo, and next to the
heading on a car's own page -- marks one worth coming back to. `Starred only`
in the filters then shows nothing else. When two listings turn out to be the
same car the cheapest still wins, but the star moves over to it: it marks the
car, not the advert. Rules about the car itself do leave a starred one alone --
a battery that is too small, a Pure -- because marking one is a decision and a
rule does not overrule a decision.

## Running it yourself

You need **Ruby 4.0.2** and **PostgreSQL**. Versions are pinned in `mise.toml`,
so with [mise](https://mise.jdx.dev) installed, `mise install` gets the right
ruby. Node and yarn are in there too, but only to rebuild the echarts file
checked into `app/assets/builds`; the app itself has no JavaScript toolchain
and needs neither to run.

```
bin/setup                     # bundle install, create the database, start the server
```

That leaves you on http://localhost:3000 with an empty database. The three
things worth doing next:

**Say where you live**, or every distance is blank. `config/home.yml` is not in
git and is read by `Home`:

```yaml
latitude: 52.379
longitude: 4.900
country: NL
```

A postcode works instead of coordinates, and either can come from the
environment (`HOME_LATITUDE`, `HOME_POSTCODE`, ...) rather than the file, which
is how the deployed copy is told. Pick a station or a town square rather than
your doorstep: every distance on these pages is a drive of hundreds of
kilometres, so a few kilometres of vagueness changes nothing and keeps your
address to yourself.

**Import the postcodes**, which is what turns "90574 Roßtal" into a distance:

```
bin/rails postcodes:import    # 20,375 rows from GeoNames; once, and slow
```

**Say what to look for**, and fetch it:

```ruby
Model.create(make: "Volkswagen", model: "ID-Buzz", min_seats: 4, min_kwh: 77)
```

```
bin/rails cars:scrape
```

The scrape asks four sites, waits three seconds between pages, and takes a few
minutes. Then http://localhost:3000/cars has a graph on it.

## Telling it what to look for

One row of `models` is one search. There is a scaffold at `/models` for it, or
the console:

| Column | What it does |
| --- | --- |
| `make`, `model` | what to search for. Spelling is loose: "ID-Buzz" finds "ID.Buzz", "ID. Buzz" and "id buzz" |
| `min_seats` | bin a listing that advertises fewer seats than this. A listing that names no seat count is kept |
| `min_kwh` | the same for the battery, in kWh, net |
| `exclude_versions` | comma separated words that mean this is not the car: `"ID.3, ID.4, Cargo"` |

`min_seats` and `min_kwh` never judge a car that says nothing -- silence is not
a small battery. Both are applied again after every scrape, so raising one puts
cars in the bin without a re-scrape.

## The commands

```
bin/rails cars:scrape         # every source for every model, then the tidying up
bin/rails cars:tidy           # the tidying up on its own, asking the sites nothing
bin/rails cars:details        # fill in seats and battery from the listing pages
bin/rails cars:photos         # fetch our own copy of any photograph we are missing
bin/rails postcodes:import    # the GeoNames tables, for distances
```

And in a console, for the things that only matter when you have changed
something:

```ruby
Car.recalculate_bargains!     # after anything that moves the trend line
Car.recalculate_distances!    # after moving house, or importing more postcodes
Car.recalculate_eur!          # after changing NOK_PER_EUR or SEK_PER_EUR
Car.renormalise_kwh!          # after changing Car::BATTERY_PACKS
```

## How it is put together

Small classes, each one a step of a round, all in `app/models`:

| | |
| --- | --- |
| `Scrape` | one round: every scraper, then the tidying up, then `Details` and `Photos` |
| `Scrapers::*` | one per site, over `Scrapers::Base`, which holds the fetching and the pacing |
| `Car` | the row, and every rule about what is a duplicate and what belongs in the bin |
| `Details` | what the search cards leave out, read off the listing's own page |
| `Photos` | our own copy of each picture, so no page of ours asks a seller's server for a file |
| `StillThere` | asks a listing we did not see this round whether it is gone |
| `PriceFit` | the plane through price, year and mileage that `bargain_eur` measures from |
| `Scatter` | the graph: points, trend line, and the colour scale |
| `Postcode`, `Home` | where a car is, where you are, and how far that is |

There are no tests. That is not a recommendation.

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
(`Car.shown`, nothing in `hidden_by`) and a scraper has seen it on a site lately (`Car.listed`, within
`Car::SEEN_WINDOW`). The two are kept apart on purpose -- one is your decision,
the other is the market's.

A listing nobody has seen for that long is sold or withdrawn, and the end of a
scrape takes it off the pages -- `hidden_by` becomes `Car::GONE`. That is worth
knowing about: the first sweep caught 1121 of 2788 rows, 599 of which were
still on the graph, because 12gebrauchtwagen's links answer 410 Gone within
days. The window is the safety margin, so a source that falls over does not
cost you its cars on a single miss, and `Scrape::MOST_OF_THEM` refuses to write
off a source this round barely saw at all.

Off the pages, not out of the database. It used to be a `destroy`, and then a
car that came back came back as a fresh row with your star, your note and your
corrections missing. Now the row keeps all of it and a scrape that sees the car
again lifts the reason (`Scrapers::Base#refresh`). Only when it has been gone
for `Car::FORGET_AFTER` -- sixty days -- and you have said nothing about it does
`Car.forget_long_gone!` actually remove it.

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
url -- keeping the one that is not binned and carrying over any note.

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
this thins the cargo vans out rather than guaranteeing none get through.

That was the whole of it while the title was the only place a seat count could
come from. Now that the listing pages are read, two cars in three have a seat
count of their own, and `Car.hide_cargo!` judges the stored number the same way
after every scrape -- so a van that says nothing in its title but three seats
on its own page is put in the bin instead of sitting between the buses. Set to
4, because the one four seater we have is a five: the seller did not count the
middle seat on the back bench.

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

## What the advert does not say

A rule never judges a car on something its advert did not mention: `min_kwh`
only looks at an ad that names a battery, `min_seats` keeps a listing that
names no seat count. The filters used to break that promise quietly -- `Seats`
and `Battery kWh` asked for a value with `=`, so picking 86 dropped every car
that says nothing without a word about it, and three in five say nothing.

So every select that reads a field the sellers only sometimes fill in ends with
`Not stated (612)`: the cars that are silent, and how many of them there are.
It is a question you can now ask instead of a set you cannot see.

Each of those three still carries its blank **Any** row, and nothing stops you
from picking that alongside 6 and 7. Read literally that says "any seat count,
and also six, and also seven"; the blank used to be dropped and the other two
kept, so ticking Any left you with exactly the filter you were trying to lift.
Any wins now, and takes the field with it -- the other filters stay where they
are.

`Seats`, `Battery kWh` and `Wheelbase` each take more than one answer at a
time, because six seats or seven is one question rather than two, and so is 79
kWh or 86. "Not stated" can be one of those answers, and it is a different
predicate -- `seats_null` rather than `seats_in` -- so the controller hands
ransack the two as a single OR group.

A group per field, and the grouping matters twice over. Ransack's plain
`m: or` would have put every other filter in the same OR, and a price limit
would have stopped meaning anything; one shared group would have done the same
across the three, so "six or seven seats" and "79 kWh or unknown" would have
meant either rather than both. Groups are ANDed with each other, so it means
both.

`Wheelbase` is the other half of that. The battery was standing in for it --
"77 and 79 are the short one, 86 is the long one" -- but that is a fact about
this year's range rather than about the car, and the title usually says it
outright, because German sellers write "langer Radstand", LR or LWB to sell it.
`Car.wheelbase_in` reads that into a column of its own: two in five titles say
so, as many as name a battery, and 168 of them name a wheelbase while naming no
battery at all, which takes the two together from 41% of the cars to 63%.

Where both are there they agree: of the cars on offer, 101 long ones also said
86 kWh and not one said 77 or 79; 59 short ones said 77 or 79 against a single
86. Six seaters are the exception worth knowing about -- six of them call
themselves short ("Pro KR AHK Klima Navi 6-Sitzer"), which is either a seller's
slip or something about the range I have not understood, so the wheelbase is
read from the title and never inferred from the seat count.

## The battery, and what is not there to find

Reading the battery out of a Dutch description sounded like the obvious next
gap: 209 AutoScout24 pages were read and only four gave one up. The 258 stored
descriptions say otherwise, and they cost nothing to check. Of the 228 with no
battery, **218 never mention kWh at all**, and eight of the remaining ten name
two capacities in the same breath -- "in Verbindung mit Hochvolt-Batterien 79
und 86 kWh", which is the WLTP disclaimer and not this car. Refusing to guess
there is right, and a Dutch phrasing would have found nothing.

What the stored pages did turn up is a rule that was too eager. `BATTERY`
refused any capacity followed by a slash, to keep consumption -- "18,5 kWh/100
km" -- out of it. But a title is often written "Pro 86 kWh / 286 PK LWB 7
persoons", or "91KWh / 6 Seats / Carplay", and those are unmistakably the pack.
The lookahead now asks for `/100` rather than any slash: three cars gained one
straight away, every future title written that way will too, and the two
descriptions that really do say kWh/100 km are still ignored.

## What the range makes certain

Two things about an ID. Buzz are true whatever the advert leaves out, and
`Car.infer_batteries!` fills them in for the cars that say nothing:

- **the long wheelbase has only ever carried the 86.** 265 cars on offer state
  a battery and all 265 say 86, from July 2024 to today.
- **before July 2024 there was only the 77.** Of 234 cars registered earlier
  that state one, 231 say 77. The three that disagree are adverts
  contradicting themselves -- a "Pro 79 kWh" registered in August 2023 and a
  "Pro 58KWh" from May 2024, neither pack existing yet.

Together that filled 307 of the 564 cars whose battery was unknown -- 143 by
age, 136 by the long wheelbase, 28 by the motor -- and not one of them
contradicts its own title.

`Car.settle_gross_batteries!` is the one place a number in an advert is
overruled, and it is worth being plain about why: the number is not wrong, it
is ambiguous. VW gives the same pack twice over -- the short car's is 86 gross
and 79 net, the long car's is 91 gross and 86 net -- so "86 kWh" in a title is
either of two packs, and a seller copying it off the spec sheet cannot say
which. `usable_kwh` turns 82 into 77 and 91 into 86, but has to leave 86 alone.

What settles it is something else the same advert says. A short wheelbase
advertised as 86 has the 79, and that second reading is the reliable one: 101
long cars say 86 and not one says 77 or 79, while 59 short ones say 77 or 79
against this single 86. So it is not that the seller is disbelieved -- he said
two things and together they are unambiguous. The mirror case never occurs: no
long car in the stock claims 77 or 79.

A correction by hand still outranks it.

One trap worth writing down, because it looked like arithmetic and was not.
Dividing a WLTP range by a WLTP consumption does **not** give the pack: that
consumption figure is measured at the wall and includes charging losses, so
the answer comes out about a tenth too high. 443 km at 19,8 kWh/100 km reads
as 87,7 kWh, which is the 86 -- and the car is a 79 on the short wheelbase,
as its photographs show plainly. Take the ten per cent off and it lands on 79
exactly. Range figures are not comparable across sites either: the same 79
pack is quoted as 443 km on mobile.de and 329 km on AutoScout24.

The motor settles what the registration date cannot, and that is the third and
fourth rule:

- **150 kW is the car before the facelift, and that had the 77.** 67 cars of
  67 whose advert states a battery.
- **a GTX is the 250 kW car.** All 56 GTX adverts that state a power say 250,
  so a GTX that mentions none still dates itself. It settles nothing about the
  pack on its own -- 117 long GTXs say 86, the short ones say 79 -- so it
  helps only through the wheelbase, like any other 250 kW car.
- **210 or 250 kW on the short wheelbase has only come with the 79.** 47 of
  48; the odd one out is an advert contradicting itself -- "210 kW Pro KR 82
  kWh", a facelift motor with the old pack -- and it names its battery, so no
  inference goes near it. Only when the wheelbase is known to be short: among
  the 210 kW cars whose wheelbase cannot be read, two say 86 and will be long
  ones.

This is what the date could not do. The facelift arrived in August 2024 but
pre-facelift stock kept being registered well into 2025 -- five cars from April
and June say 77 kWh in their own titles -- and a 150 kW badge dates the car
where its number plate does not.

An inference never sits on top of an advert: only an unknown battery is filled,
a scrape that finds a real figure writes over it, and the car's own page says
which it is -- "as the ad states it", or "the long wheelbase has only come with
the 86".

## When the advert is wrong

Car 1616 says eight seats -- not scraped out of a title, but in AutoScout24's
own structured field, so the seller typed it. An ID. Buzz is built as a five,
six or seven seater, and there are five in the photograph.

`Car#correct!` puts such a thing right and remembers that you did:

```ruby
Car.find(1616).correct!(:seats, 5)
```

The remembering is the point. Both writers ask first -- the scraper's `refresh`
and `Details#read` -- so the next round cannot read that field again and write
the eight straight back. It is the same rule as the bin: `you` outranks what a
site says.

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

## In the bin, or on the pages

A decision of yours is about the car, not about the advert it was written on.
Car 4093 was crossed off as a smoker's car, with a note saying so, and two days
later the same van arrived from another site as 4767: on the pages, unmarked,
the note nowhere. Every duplicate rule works on what is *on offer*, and a row
you have crossed off is not on offer, so nothing could carry it.

`Car.carry_decisions!` does, at tidy-up, over `Car#twins` -- the other rows for
the same car, recognised by the advert's picture folder, or failing that by
build month, odometer, town and price to the euro.

All four things travel, by `Car#adopt_decisions_from`: the crossing-off, the
note, the star and any correction. Corrections travel with their values,
because that is what a correction is -- a number that outranks the advert. Car
1616 says eight seats and has five; the copy of it that arrives tomorrow from
another site says eight as well, and would have quietly won. Yours wins over
theirs on every count: what travels is only what the receiving row does not
already have, so a correction made on this row is never replaced by one made
on another.

`hide_all_but` and `merge_retitled!` take the same route, so the row that stays
keeps what you said about the one that goes.

One column says it: `hidden_by`, which is either nil or the reason -- `you`,
`as new`, `listed on two sites`, `advertised twice`, `same photograph`,
`battery too small`, `pure model`, `a cargo van`, `no longer listed`. `Car.shown` is the ones with no reason,
`Car.binned` the rest, and `Car.hidden_by_hand` versus `Car.hidden_by_rule`
tells your decisions from the rules'.

There used to be a `visible` boolean beside it saying the same thing in
reverse, which is two columns that have to agree -- and the page had a
"Show on the pages" tick that was on by default, so you binned a car by
taking a tick away. Both are gone. Neither database had a single row where
the two disagreed, which is luck rather than design.

## Sold, or only quiet

A listing that stops turning up is usually sold, and the link usually says so
itself: 12gebrauchtwagen answers **410 Gone** the moment an offer is withdrawn.
So a round asks -- once, a second apart, about the listings it did not see this
time -- and a 410 or a 404 takes the car off the pages the same round.
`StillThere` does the asking, and only for a source that answered this round;
a timeout or a 403 says nothing about whether a car is sold and leaves it
alone.

It asks for the first answer and stops there -- `follow_redirects: false`. A
partner link that still has somewhere to send us is an offer that stands
(`302` to autohero.com), and a withdrawn one answers `410` itself, first hop.
Following the chain instead took us to mobile.de and to dealers' own sites,
spent seconds a car, and ended in `HTTParty::RedirectionTooDeep` sixty times in
one round: sixty requests, three servers bothered per car, and nothing learned. Cars 5092 and 4501 were found the other way round, by clicking
a link that opened nothing three days running.

What has not said anything either way comes off after `SEEN_WINDOW` of silence,
as before.

**Off the pages, not out of the database.** They used to be destroyed, and a
car that came back came back as a fresh row: no note, no star, no corrections,
and a "new today" date. Now it is a reason like any other -- `no longer listed`
-- so the row keeps everything you put on it, and a scrape that sees the car
again lifts the reason and puts it straight back (`Scrapers::Base#refresh`).
Nothing asks about a car already written off, so this costs one request per
listing, once.

Rows do get forgotten eventually: gone for `FORGET_AFTER` (60 days) **and**
with nothing of yours on them -- no note, no star, no correction, no crossing
off. Those four are what `Car.decided` means, and a row that has any of them is
kept however old it gets.

## The same car twice

One car can also be here several times over on **one** site, and that is a
different problem: not two adverts to choose between, but one advert that keeps
arriving as a new row.

`Car#identity` has the title in it, and 12gebrauchtwagen rewrites titles --
"Pro 150 kW (204 PS) 1-Gang-Automatik Nav" one day, "Pro KR 150 kW (204 PS)
1-Gang-Automatik" the next, sometimes merely cut a character shorter. The
aggregator can switch which advert it carries for a car, too: 4859 was a
Leverkusen bus as AutoScout24 had it, 5650 the same bus as mobile.de has it,
with another offer_id, another picture and "SHZ CARPLAY" where the old title
stopped at "SHZ CARPL". Different title, different url, so a new row -- dated
today.

That is what put a starred car back at the top of the wall as "new". The
duplicate rule hid the older row and, because a star is about the car rather
than the advert, dragged the star onto the newest one. Nothing was lost, but
the car looked like it had just arrived, every couple of days.

So `Car.same_listing_as` asks the same question with the title left out --
same site, build month, odometer, town and asking price -- and the scrapers
ask it whenever the digest misses, before storing anything. One candidate or
none: where two rows fit all five, the title is the only thing telling the
cars apart. Factory-new cars are left out altogether, because their odometers
all read the same handful of kilometres and dealers price whole trims alike:
"Pro 5S Style+ Open&Cl KomfortP+" and "Pro LR 7S Style KomfortP+ AssisP+" both
sat at 10 km and 59,840 euro in one Bavarian yard, and they are not the same
van.

One advert's photographs live in one folder, and that folder is the strongest
tie there is: 5713 and 5742 were one Berlin bus on one site, same advert, same
money, 171 km and a rewritten title apart -- which no other rule sees, since
they all want the odometer to match to the kilometre. So a row of the same site
pointing into that folder is that advert, at the scrape and at tidy-up alike.

With three guards, because a site that has no picture for a car hands out a
placeholder: at most three rows to a folder, one asking price across them, and
odometers within `RELISTED_KM` of each other. All three earn their keep --- two
factory-new vans at 10 km in one yard shared a photograph at 69,775 and 70,000
euro, and a stock picture says nothing about either car's mileage. A relisted
advert has moved a few hundred kilometres at most; 5713 and 5742 were 171
apart.

`Car.merge_retitled!` does the same for the rows already here, at tidy-up: the
oldest row stays -- it has the date you first saw the car, your star, your
note -- and takes over the title, link and picture of the freshest one. On 21
September 2026 that was 147 cars and 157 rows, one Mulheim bus having arrived
four times in six days.

And the duplicate reasons are now dropped and worked out again every round.
"Listed on two sites" is true of a pair; when the other half sells, nothing
used to lift it and the survivor sat in the bin saying it about nobody. On the
laptop's copy that freed 61 cars.

12gebrauchtwagen carries a lot of what AutoScout24 already has, so one car
turns up as two listings and counts twice, in the graph and in the trend line.
`Car.hide_duplicates!` puts all but the cheapest of a set in the bin, which
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

A third case is the same car on two sites at the same money, whose odometers
have drifted apart: 4113 reads 38000 km and 5040 reads 38600, both a 2023-04
car in Geretsried at 40800 euro. Two rules miss that for two different
reasons. `duplicate_key` holds the mileage exactly, so those two numbers never
meet; and `duplicates` asks whether a whole group of prices is one price, so
the Kiel dealer with four alike cars shields all four of them.
`Car.same_money` groups on the price to the euro instead and steps around
both, while still asking for the same build month, the same town, two
different sites and a mileage within `Car::RELISTED_KM`. Four pairs in the
stock, every one plainly one car.

A fourth case is the same listing back under a different title, which is a
harder problem than it sounds: the title is part of `Car#identity`, so when
12gebrauchtwagen rewrote its titles on 18 September -- "(+NAVI) Bluetooth"
became "(+NAVI) LED", and plenty were simply cut shorter -- 576 cars returned
as new rows instead of refreshing the ones already here, and 29 of them stood
beside their older selves on the pages. `Car.relisted` is blind to those,
because it asks for the same title to the character.

`Car.retitled` asks for everything else instead, and asks for it exactly: the
same site, the same build month, the same price to the euro, the same odometer
reading to the kilometre, the same town. Two different cars from one dealer do
not match all five. Of the 14 groups it found, not one had two titles that
agreed, and every pair was plainly one car -- "Pro LR lang | AHK | LED | NAVI |
ACC |" against "86 kWh 210 kW ENERGY LR 5 Türen", both 49370 euro at 16174 km
in Plattling. The copy that still has a picture stays.

The old rows clean themselves up: their titles are gone from the site, so
nothing stamps them again and the sweep at the end of a scrape takes them off
the pages after three days.
Leaving the title out of `identity` altogether would stop the churn at the
source, but the title is the only thing that tells two alike cars at one dealer
apart -- the price and the mileage both move -- so the row is the cheaper
price to pay.

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
but starts out binned and stays out of the graph. `Car.show_driven!` puts it
back when it stops being true: a demonstrator goes on being driven while it is
advertised, and one was sitting in the bin at 1500 km because the hiding
happens once and was never looked at again. Only what the rule put away -- a
car you crossed off yourself stays crossed off. That only happens
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

The droplet is 2 GB with no swap and it is shared with trading-bot, lidlcoupons
and ahbonus -- nine containers between them, and around 130 MB free. That is
enough to run on and thin to deploy on, because a deploy is the one moment two
copies of this app are up at once: kamal boots the new web container beside the
old one and only retires the old one when the new one answers.

Under that pressure the new one boots slowly. Three deploys in a row took 10,
17, and more than 30 seconds to answer, and the third went over kamal's default
timeout and failed -- Puma reached "Listening on 0.0.0.0:3000" a few seconds
after the proxy had stopped asking. Nothing broke: the old container kept
serving and kamal will not send traffic to one that never answered. But the
deploy fails, and it fails more often as the box fills.

`proxy.deploy_timeout` is 90 seconds for that reason. It buys room, it does not
make room: when a deploy fails again, `free -m` on the droplet is the thing to
look at, and `docker stats --no-stream` says who is holding it.

## What it needs once

**An A record** for the site's hostname pointing at the droplet -- here
`carscraper.diamondbay.nl`. The domain has a wildcard that goes somewhere else, so the
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
ssh -fN -L 5433:127.0.0.1:5433 deployer@"$DROPLET"
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
the command line. `bin/rails cars:tidy` is the tidying up on its own, for when
a duplicate has to be found again without asking the sites anything --
`bin/kamal tidy` runs it on the droplet. It removes nothing: what looks gone
can only be judged by a round that has just been past the sites. It has one guard worth knowing about: a source that is
blocked or has changed its markup returns nothing, and the listings it had
would then all look gone. So a source's cars are only removed when this round
saw at least half of what that source already had (`Scrape::MOST_OF_THEM`),
and the count is kept per source -- the sources fail one at a time, and a count
over the whole database would let a working site vouch for one nobody could
reach.

## What the sites see of us

Every request carries the headers a browser of ours carries. This code is
looking at these pages on your behalf -- the same pages you open by hand -- so
it says the same thing on the envelope: the current Chrome's `User-Agent`, its
`Accept` and `Accept-Language`, its `sec-ch-ua` client hints and its
`Sec-Fetch-*` metadata, with the image requests asking for an image and the
page requests asking for a page. Captured on 21 September 2026 from the actual
browser, by pointing it at a listener on localhost and writing down what
arrived.

Before that it was one header: a `User-Agent` claiming to be a Chrome from
November 2024 and none of the fourteen a Chrome sends with it.

Three things are deliberately not copied. **Cookies** -- those are a person's
session, not a program's. **A `Referer`** we did not actually come from.
And **`Accept-Encoding`**: Chrome offers "gzip, deflate, br, zstd", but
Net::HTTP stops decompressing for you the moment you set that header yourself,
so copying it would hand Nokogiri a bag of compressed bytes, and brotli and
zstd we could not read anyway. Left alone, Net::HTTP sends its own line and
unpacks the answer.

And one thing left out of a header rather than left off: **`image/avif`**, which
stands first in Chrome's `Accept` for images. gaspedaal and autotrack convert on
the fly and return whatever that header asks for first, so asking exactly the way
Chrome asks got avif from both -- a type `Photos::TYPES` does not know, so their
pictures were fetched and then dropped, silently, every round, while the car's
page said "no photo". Second in the list is `image/webp`, which is what
AutoScout24 serves regardless. Storing avif would have been the other repair and
the smaller file -- 37 kB against a 60 kB webp and a 90 kB jpeg -- and is still
there to be done.

None of this is about getting past a block, and it does not: the same request,
from the droplet, is still 403 at AutoScout24 and AutoTrack, and 200 from the
laptop. That difference is the IP -- see "The droplet is blocked".

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

Everything that leaves this app is paced and capped, and gives up when it is
told no:

| | between requests | at most per round | stops after |
| --- | --- | --- | --- |
| search pages | 3s | 40 pages a country | one page that is not a 200 |
| listing pages (`Details`) | 1s | 300 | 5 refusals in a row |
| photographs (`Photos`) | 0.5s | 200 | 5 refusals in a row |

So a round with a full backlog is 560 requests over ten minutes -- one a second
on average, never two at once -- and an ordinary round is a tenth of that. Two
rules keep it from turning into repetition: `Details` stamps `details_at`
whether or not the page told it anything, so a page that does not name a
battery is not asked again for `RE_READ_AFTER` (a month), and `Photos` sleeps
after a failure as well as after a success, which is exactly when slowing down
matters.

The photographs used to be the heavy part, and not from the scraping: every
view of `/cars/photos` asked their servers for six hundred pictures. `Photos`
fetches each picture once -- half a second apart, at most 200 in a round --
into `public/photos`, named after a digest of the url it came from, so a
listing that swaps its picture gets a new file and the browser cannot serve a
stale one.

Both sizes are ours. **No page of this application asks a seller's server for
anything**; the scrapers ask, once per car, for each size we do not already
have. The card on the wall is whatever the search page showed -- 250x188 and
8 kB from AutoScout24, 1280x960 and 84 kB from 12gebrauchtwagen -- and a car's
own page wants better than a thumbnail, so the 1024x768 (96 kB) is fetched too.
One extra request per car, and for the 455 that arrive at 1280x960 it is none:
what we hold is already bigger than what we would ask for.

That last part is why `large_image_url` only ever substitutes *upwards*. It
used to rewrite any size in the url to 1024x768, which for those 455 handed out
a picture smaller than the copy already on disk.

Two questions about one file, kept apart since 22 September 2026: *is this
still the picture the advert shows* (Photos asks that, and fetches again when
the answer is no) and *do we have a picture of this car at all* (a page asks
that). They were one question for a day, and the wall went blank for 94 cars
the first time a laptop scrape refreshed their `image_url`: the digest in the
file name no longer matched the new url, so a perfectly good photograph of the
same car, sitting on the disk, counted as nothing. `photo_url` now shows what
is held; `photo_stored?` still wants the name to match, which is what keeps the
queue honest.

The car page used to show the seller's url with our copy behind it as an
`onerror` fallback. Two things wrong with that: it is a page of ours fetching
from their server on every view, and the fallback had already proved necessary
-- car 1670's picture went 404 at every size AutoScout24 serves, including the
one we had fetched, while our copy of the same photograph sat here unused. Now
the copy is simply what is shown, and a car whose picture has not been fetched
yet says "no photo" rather than borrowing theirs.

**On a clock of its own, every quarter of an hour** (`PhotosJob`, see
`config/initializers/good_job.rb`). It used to be the tail of a scrape, and
that is where it kept going missing: a scrape from the laptop writes into the
droplet's database but cannot write to the droplet's disk, so it hands the
fetching over -- `mise run scrape:production` ends by telling the droplet to go
and get them -- and anything that stops before that last line leaves the newest
cars as grey boxes until the next cron round. Which is the half of the wall
anybody looks at, sorted newest first. So it no longer waits on anybody
finishing anything; it asks the database what is missing, and nearly always
that is nothing and it asks the picture servers for nothing at all.

The queue is newest first, for the same reason.

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
of the droplet -- says "no photo" rather than showing six hundred broken ones,
and the next scrape fetches what is missing. It costs one stat per car, about a
millisecond over a whole page.

## What the listing page said

`Details` keeps the page it read, in the `data` column: the seller's own text
and the whole `vehicle` block -- `bodyColor`, `powerInKw`,
`electricRangeWithFallback`, `wheelBase`, the equipment list by category,
`hadAccident`, `noOfPreviousOwners`, `hasFullServiceHistory`, `upholstery`, and
a good deal more. About 17 kB a car, so roughly 17 MB for the AutoScout24 half
of the stock.

It is kept because the request has already been made. Two numbers were all the
scraper needed, but a question asked next month -- what colour is it, has it
been in an accident, what is in it -- would otherwise mean asking the site
again for something it already told us. Left out: the fifteen kilobytes of loan
offers, the tracking parameters, and `vehicle.rawData`, which is the same facts
again in the site's own shorthand.

Only for pages read from now on, and only from a machine AutoScout24 answers,
which is not the droplet.

The seller's own text is on the car's page, folded up under "What the seller
wrote" unless it is short -- the median is 4700 characters of German equipment
names. It is worth reading: the fields have no room for "Nutzbare
Batteriekapazität: 79,0kWh", "Batteriezustand: 99%", five years of warranty
left, or what the car cost new, and all four come out of that text.

It is a stranger's html, so the view runs it through the sanitiser with a list
of tags named by hand and no attributes at all. The sanitiser's own list would
have kept `a` and `img`, and an image means our page fetching a file from a
seller's server every time you open a car.

12gebrauchtwagen has no readable page of its own -- every one of its links is
`/c/partner?offer_id=...`, a redirect to whoever actually has the car -- so
`Details` follows them. A sample of twelve suggested nine in twelve would land
on AutoScout24; all 454 of them, tried once each, say otherwise:

| | |
| --- | --- |
| suchen.mobile.de | 337 |
| AutoScout24, page read | 57 |
| failed before the destination was being recorded | 56 |
| stayed on 12gebrauchtwagen | 4 |

Three quarters go to mobile.de, which answers 403 to everyone. The sample came
off the head of the queue and was not the tail. So the honest yield is 57
pages out of 454 links -- and it cost one request each, once, because a
destination that refuses everyone is written down and never asked again.

That is worth knowing about in requests: a car behind a partner link costs
three of them rather than one, because the redirect goes through two hops. 454
such cars are waiting, against 208 direct ones, so a first pass is three rounds
at `MOST_PER_ROUND`. Each of them is asked once and stamped, including the ones
that turn out to be mobile.de or a dealer's own site -- a page we could not use
cost a request all the same.

A refusal only ends a round when it comes from a host we are actually reading.
mobile.de saying 403 is one listing we cannot have; AutoScout24 saying it five
times running is the door.

What costs time here is not the pacing. Of 110 cars read in one pass the median
was 1.3 seconds each -- a second of that our own pause -- but two took 273 and
196 seconds between them, eight of the ten minutes, both dealers' own sites at
the end of a partner link. HTTParty's timeout is per hop and starts over on
every chunk that arrives, so a server answering in a trickle holds the round
for minutes. `MAX_SECONDS` is a hard ceiling of fifteen seconds on one car,
redirects included, and a car that hits it is stamped like any other: asked
once, not again for a month.

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
against the droplet's database, from this machine. Run it by hand at
least every three days, or AutoScout24's 582 cars and AutoTrack's 30 drop off
the pages: `Car::SEEN_WINDOW` is three days. They stay in the database -- the
per-source guard sees to that -- but nobody sees them. It is the code in this
directory doing the work, so it stops first if a migration here has not been
deployed there -- otherwise the crash arrives halfway through a scrape,
"undefined method 'seats='", with a few hundred listings already written. The twice-daily round on the
droplet still does the other two, so between them nothing goes stale for longer
than you leave it.

`bin/kamal scrape` runs it on the droplet instead, which works but is asking
for a block.

The pictures are the one part of that round that does **not** happen here. A
scrape from this machine ends with `PHOTOS=elsewhere`, and then tells the
droplet to fetch its own:

```
bin/kamal app exec --roles=job --reuse "bin/rails cars:photos"
```

`Photos` decides what is missing by looking at a disk (`Car#photo_stored?`),
and writes what it fetches to that same disk. Run from here against the
droplet's database, those are two different machines: of the 1050 pictures the
droplet holds, this laptop has 148, so every round it saw nine hundred as
missing, downloaded two hundred of them (`MOST_PER_ROUND`) from the picture
servers, and filed them where no website reads them -- and then its sweep
deleted the development copies, which the droplet's database does not point at.
Two hundred pointless requests to the picture servers, twice over, every run.

So the data comes over the tunnel and the pictures are fetched at the far end.
`bin/rails cars:photos` is that step on its own: it asks the picture servers and
nothing else -- no search page, no listing page -- so it is cheap to run by hand
whenever something is missing a photograph. The droplet's own twice-daily round
still fetches its pictures inline, because there the database and the disk are
the same machine.

Which also means the droplet's database is the real one -- it is where your
clicks land when you are looking at the site -- and the one here is a
development copy. To catch this one up rather than the other way round, dump in
the other direction:

```
ssh -fN -L 5433:127.0.0.1:5433 deployer@"$DROPLET"
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

---

The first version of this lived at https://github.com/gerard76/carcrawler.
