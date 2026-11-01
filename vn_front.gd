class_name FrontData

## Somebody else's probes, and the rule that makes them matter.
##
## ── Why a rival replicator and not another war ──
##
## The player's swarm is EXPONENTIAL. Every fixed-size antagonist in this game — a set number of
## neighbours, an asteroid every few hundred thousand years, a salvo of relativistic missiles —
## becomes proportionally smaller as the swarm grows, and by a few thousand colonies none of
## them is a consideration. A second self-replicating civilisation is the only opponent that
## stays the same size relative to you for ever, because it is running the same process.
##
## It is also the argument the game is already about. A single replicating civilisation fills a
## galaxy in a few million years, which is nothing against the age of the disk — so either
## nobody ever started, or somebody did and we are inside the result. This is the second case.
##
## ── The rule is the feature ──
##
## The front itself is cheap: the galaxy is already a hex grid of ~900 cells that saturate and
## diffuse (see Game._update_regions), and this is that same automaton with one seed and a
## faster clock. What did not exist is DENIAL. Probe targeting asked only "have I taken this
## already", so a region could be entirely somebody else's and the swarm would still fly into
## it. Whoever reaches a volume first now holds it, both ways:
##
##   the front cannot take a cell's share the player already holds
##   the player's probes will not fly into a cell the front has taken
##
## Which turns the swarm's greedy nearest-star targeting from an invisible heuristic into a
## decision: the nearest star is no longer the right answer when the contested boundary is
## somewhere else.
##
## ── What it is not ──
##
## Not a timer. A timer would make the outcome a property of the setup screen rather than of
## anything the player did. The front advances at its own pace and the player's reach is theirs
## to push, so where the two meet is where their choices put it. And it cannot be driven back:
## you keep what you got to first, which makes the run's question "how much did you claim before
## it arrived" — a number two players can compare.

## Where it starts: rings out from the galactic centre. Zero is the centre itself, which is
## where the oldest and densest stars are and so the likeliest place for somebody to have had a
## head start on us.
const SEED_RING: int = 0

## Per-year chance a cell the front holds pushes into one neighbour, scaled by how much of its
## own cell it has taken.
##
## Set from the crossing time, not picked. Cells are 3 753 ly apart (Game.HEX_SIZE × √3), so
## one cell per 1 / 2.5e-5 = 40 000 years is a front advancing at 0.094 c — which is what a
## replicator that has to decelerate, land, mine and build the next generation actually manages.
## At 1e-3 the front moved 3.75 ly a year, nearly four times the speed of light, and a 200 000
## year head start filled the entire galaxy including Sol's own cell before the game began.
const SPREAD_RATE: float = 2.5e-5

## Years for the front to cross one cell, which is what a head start is measured in.
const YEARS_PER_CELL: float = 1.0 / SPREAD_RATE

## Per-year share of a held cell's own stars the front takes.
##
## Deliberately comparable to the crossing time: a cell passes DENIED_SHARE in about 50 000
## years, against 40 000 to reach the next one, which leaves the contested band one or two cells
## deep. That band is where the game is — much faster and the front is a wall, much slower and
## it never actually holds anything.
const CLAIM_RATE: float = 2.0e-5

## A cell is spoken for once the front holds this much of it. Below it the volume is contested
## and the player may still take stars there; above it, probes are sent elsewhere.
##
## Not 1.0, and that matters: a cell is thousands of light-years across and holds millions of
## stars, so "the front is most of the way through this volume" is the honest point at which to
## stop sending colony ships into it rather than waiting for the last star to be taken.
const DENIED_SHARE: float = 0.65


## Whether the front is close enough to have been seen yet.
##
## Its signature crosses at light speed like everybody else's, so a front that started twenty
## thousand light-years away is twenty thousand years old before Sol hears anything — by which
## time it is already much closer than where it appears to be. That gap is the whole drama of
## the reveal, and it comes free from the same rule Game applies to alien signatures.
static func detected(dist_ly: float, started_year: float, now_year: float) -> bool:
	return now_year - started_year >= dist_ly


## How much of a cell the front takes over `dt` years, given what it already holds there and
## what is left after the player's share.
##
## Saturating, and capped by `room`: the front cannot take a share of a cell somebody else got
## to first. That is the whole first-come-first-served rule, in one max and one min.
static func claimed_after(share: float, room: float, dt: float) -> float:
	var cap: float = clampf(room, 0.0, 1.0)
	var cur: float = clampf(share, 0.0, cap)
	if dt <= 0.0 or cur >= cap:
		return cur
	return minf(cap, cur + maxf(cap - cur, 0.0) * CLAIM_RATE * dt)


## Chance a held cell pushes into a neighbour over `dt` years.
static func spread_chance(share: float, dt: float) -> float:
	return clampf(SPREAD_RATE * clampf(share, 0.0, 1.0) * maxf(dt, 0.0), 0.0, 0.5)


## Whether a cell the front holds this much of is closed to the player's probes.
static func denies(share: float) -> bool:
	return share >= DENIED_SHARE
