class_name AllegianceData

## Whether a colony is still yours, and when you find out that it is not.
##
## ── Why distance is the whole mechanic ──
##
## A colony four hundred light-years out cannot be governed. Not because it is ungovernable in
## principle, but because every instruction you send describes a situation four hundred years
## stale, and every answer you get back is four hundred years old when it arrives. An exchange
## is eight hundred years. Nobody administers anything on those terms; what a distant colony has
## instead of a government is a memory of one.
##
## So loyalty drifts at a rate PROPORTIONAL TO DISTANCE, and GOVERNABLE_LY_YEARS sets the scale:
## a colony stays yours for roughly `GOVERNABLE_LY_YEARS / dist_ly` years without attention.
##
##   10 ly    ~200 000 years    effectively permanent
##   100 ly    ~20 000 years    a long imperial span
##   500 ly     ~4 000 years    needs looking after
##   1 000 ly   ~2 000 years    barely held at all
##
## ── And why divergence multiplies it ──
##
## A population that has been spliced into something Earth is not has less and less reason to
## take Earth's word for anything. The trait system already makes colonies genuinely different
## people over deep time (see stock_data.gd); this is where that difference stops being an
## economic curiosity and becomes a political fact.
##
## ── What the player can do about it ──
##
## Send things. A consignment arriving is the one unambiguous signal that the far end still
## matters to somebody, and it restores CONSIGNMENT_GAIN of loyalty — which is what gives the
## colony economy a reason to exist beyond the materials it moves. A civilisation that trades
## with its own frontier keeps it; one that founds colonies and forgets them does not.
##
## Nothing here is a hard timer. A colony you supply never falls, and one you ignore always
## does, and the distance decides how much attention "not ignored" means.

## Years × light-years of administrative reach. Divided by a colony's distance, this is roughly
## how long it stays loyal with nothing sent to it.
const GOVERNABLE_LY_YEARS: float = 2.0e6

## How much faster a population that is no longer the same people drifts. At full divergence the
## rate is multiplied by 1 + this.
const DIVERGENCE_WEIGHT: float = 2.0

## Loyalty restored by one consignment arriving.
const CONSIGNMENT_GAIN: float = 0.20

## Below this a colony is restless: the readout says so, and it is the last warning before the
## declaration. Above it, nothing is visibly wrong.
const RESTLESS_AT: float = 0.5

## At or below this a colony declares for itself.
const SECESSION_AT: float = 0.0

## What a freshly settled colony starts as.
const FOUNDED_AT: float = 1.0

## The race name a human splinter state is generated against — see Polities.splinter_of, whose
## name forms are filled with it ("Free Worlds of Humanity", "Second Humanity Compact").
const HUMAN_RACE: String = "Humanity"


## How different two populations are, 0 (identical) to 1 (nothing in common).
##
## The symmetric difference over the union — Jaccard distance — on the spliced traits each
## carries. Two unedited populations are identical by definition, which is the right answer: in
## 1945 every colony is the same people as home.
static func divergence(colony_traits: Array, home_traits: Array) -> float:
	var seen: Dictionary = {}
	for t in colony_traits:
		seen[str(t)] = 1
	var shared: int = 0
	for t in home_traits:
		var k: String = str(t)
		if seen.has(k) and int(seen[k]) == 1:
			seen[k] = 2          # in both
			shared += 1
		elif not seen.has(k):
			seen[k] = 3          # home only
	var union: int = seen.size()
	if union <= 0:
		return 0.0
	return clampf(float(union - shared) / float(union), 0.0, 1.0)


## Loyalty lost per year by a colony `dist_ly` away whose people have diverged this far.
static func drift_per_year(dist_ly: float, diverged: float) -> float:
	if dist_ly <= 0.0:
		return 0.0               # an in-system world is not administered by radio
	var base: float = dist_ly / GOVERNABLE_LY_YEARS
	return base * (1.0 + DIVERGENCE_WEIGHT * clampf(diverged, 0.0, 1.0))


## Loyalty after `years` of no contact.
static func drifted(loyalty: float, dist_ly: float, diverged: float, years: float) -> float:
	if years <= 0.0:
		return clampf(loyalty, 0.0, 1.0)
	return clampf(loyalty - drift_per_year(dist_ly, diverged) * years, 0.0, 1.0)


## Loyalty after a consignment lands.
static func supplied(loyalty: float) -> float:
	return clampf(loyalty + CONSIGNMENT_GAIN, 0.0, 1.0)


static func is_restless(loyalty: float) -> bool:
	return loyalty <= RESTLESS_AT and loyalty > SECESSION_AT


static func has_seceded(loyalty: float) -> bool:
	return loyalty <= SECESSION_AT


## One line for the readout: what the last report said, and how old it is.
static func describe(loyalty: float, report_age: float) -> String:
	var mood: String = "loyal"
	if loyalty <= SECESSION_AT:
		mood = "in open secession"
	elif loyalty <= RESTLESS_AT:
		mood = "restless"
	elif loyalty < 0.85:
		mood = "drifting"
	return "%s (%d%%)" % [mood, int(round(clampf(loyalty, 0.0, 1.0) * 100.0))] \
		if report_age <= 0.0 else "%s (%d%%) as of %d yr ago" % [
			mood, int(round(clampf(loyalty, 0.0, 1.0) * 100.0)), int(round(report_age))]
