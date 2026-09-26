# The scrape, on a box at home

> This is not running any more -- the search it was keeping fresh is over and
> the containers have been taken off the box. It is kept here because the
> problem it solves is the ordinary one for a scraper on a rented server, and
> the answer took some working out. Read it as a recipe, not as a description
> of something switched on.

AutoScout24 and AutoTrack answer a data centre address with 403 and a home
address with 200. Measured both ways, on the day this was written:

| from | autoscout24.nl | autotrack.nl |
| --- | --- | --- |
| the droplet | **403** | **403** |
| a home connection | 200 | 200 |

Between them those two carry half the cars, so the round that keeps them fresh
has to run from home. Until now that was `mise run scrape:production`, by hand,
from a laptop that closes. This is the same round on a box that does not.

## Why the tunnel points outward

The Odroid dials the droplet. Never the other way round.

That is the whole design, and it is there for one reason: **if someone takes
the droplet, they must not thereby get this box.** The droplet runs the public
website; it is the machine most likely to be taken. So it holds no key to here,
no address of here, and no open socket that leads here. The only connection
that exists is one this box opens, and over an established ssh session a server
cannot open a channel back to the client for a forward the client never asked
for. Agent and X11 forwarding are off as well.

Two designs were considered and dropped for failing exactly that test:

- **Tailscale.** The Odroid is already on the tailnet and already offers an
  exit node, so adding the droplet would have been two commands. But then a
  public-facing machine is a member of the network your house is on, and the
  only thing between it and the rest of the house is an ACL in a web console
  that fails silently when it is wrong.
- **A reverse tunnel with an HTTP proxy here** (`ssh -R`, tinyproxy). That
  leaves a socket *on the droplet* that ends at a container in the house.
  Filter it as hard as you like; a proxy is a thing whose job is to connect to
  what it is asked for, and `CONNECT 192.168.1.10:8123` is whatever else is
  on the network the box is standing on.
  The requirement would then rest on the filter being right rather than on
  there being nothing to filter.

## What runs here

Two containers, one internal network, nothing published to the host or the LAN:

- **`tunnel`** — alpine, `autossh`, holds `-L 5433` open to the droplet's
  Postgres. Restarts itself; `ServerAliveInterval` notices a far end that has
  died, which a port check does not.
- **`scrape`** — the app image built for arm64, waiting for the next 07:00 or
  19:00 and running `bin/rails cars:scrape` against the droplet's database
  through the tunnel.

No scheduler container: every one of them wants `/var/run/docker.sock`, and on
the box that runs the house that is root on the host.

## The pictures are not fetched here

`PHOTOS=elsewhere`. `Photos` decides what is missing by looking at a disk and
writes what it fetches to that same disk — so run from a machine that is not
the one holding the pictures, it re-downloads hundreds of files the droplet
already has and files them where no website reads them. The droplet fetches its
own, on its own schedule; the image servers answer it fine, it is only the
listing pages that are blocked. See `app/models/scrape.rb` and the
`scrape:production` task in `mise.toml`, which makes the same split.

## Setting it up

The image is built on the laptop, which is arm64 too, so it is a native build
rather than the emulated amd64 one the droplet gets. `$REGISTRY` is whatever
`config/deploy.yml` names:

```
docker buildx build --platform linux/arm64 \
  -t "$REGISTRY"/carscraper:arm64 --push .
```

The key lives here and only here — generated on this box so its private half
never crosses a wire:

```
ssh-keygen -t ed25519 -N "" -C "carscraper-odroid" -f /opt/carscraper/ssh/id_scraper
ssh-keyscan -t ed25519 "$DROPLET" > /opt/carscraper/ssh/known_hosts
```

Then the account it connects to, **on the droplet**. A system user with no
shell, and a key that may do one thing and nothing else — no pty, no agent
forwarding, and a single permitted destination:

```
sudo useradd --system --create-home --home-dir /home/scraper \
  --shell /usr/sbin/nologin scraper
sudo install -d -m 700 -o scraper -g scraper /home/scraper/.ssh
printf '%s %s\n' \
  'restrict,port-forwarding,permitopen="127.0.0.1:5433",command="/bin/false"' \
  "$(cat /opt/carscraper/ssh/id_scraper.pub)" \
  | sudo tee /home/scraper/.ssh/authorized_keys
sudo chown scraper:scraper /home/scraper/.ssh/authorized_keys
sudo chmod 600 /home/scraper/.ssh/authorized_keys
```

`permitopen` is what makes the key uninteresting if this box is ever taken:
it buys a Postgres connection and not a shell.

Secrets go in `/opt/carscraper/.env`, mode 600 — the same values
`.kamal/secrets` names, plus the address to dial, which is the one thing the
compose file will not carry in git:

```
DROPLET_HOST=
CARSCRAPER_DATABASE_PASSWORD=
SECRET_KEY_BASE=
HOME_LATITUDE=
HOME_LONGITUDE=
```

Then:

```
docker compose up -d --build
docker compose logs -f
```

## Checking it works before trusting it

Cheapest first -- this asks the sites nothing and only proves the tunnel and
the database:

```
docker compose run --rm --no-deps scrape bin/rails runner 'puts Car.count'
```

Then one round by hand, watching it:

```
docker compose run --rm scrape bin/rails cars:scrape
```

That second one works because the image's own entrypoint is left alone. An
earlier version of this file overrode it with `bash -c` to hold the waiting
loop, which quietly broke every `docker compose run`: `bash -c` takes one
argument as the script and drops the rest, so `bin/rails cars:scrape` became
`bin/rails` with `cars:scrape` as `$0`, and rails printed its help.

The key's restrictions are worth checking too, since they are what makes
losing this box survivable. Both of these must fail:

```
ssh -i ssh/id_scraper scraper@"$DROPLET" id
  -> This account is currently not available.

ssh -i ssh/id_scraper -N -L 15432:127.0.0.1:22 scraper@"$DROPLET"
  -> channel 2: open failed: administratively prohibited
```

The local port in that second one *does* open -- a client always binds its own
listener -- so the line to look for is the refused channel, not a closed port.

## When it is up

The droplet's own twice-daily round becomes the fallback rather than the main
event, and `cars:photos` needs a cron of its own there
(`config/initializers/good_job.rb`). `mise run scrape:production` stays as the
manual way in.

## If it stops

A round that fails is logged and skipped, not fatal — the container would
otherwise restart-loop on a site being down. Nothing here alerts, so the way
you notice is the site going quiet: `Car::SEEN_WINDOW` is three days, and after
that AutoScout24's and AutoTrack's cars drop off the pages. They stay in the
database — `Scrape::MOST_OF_THEM` sees to that — but nobody sees them.
