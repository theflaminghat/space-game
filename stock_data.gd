class_name StockData

## Founding stock: which population is sent to settle a world, and what has been written into it.
##
## Every lineage in the game used to be identical. EvolutionTreeData.planet_variant() handed each
## diverged world the same COMPUTE_PER_INDIVIDUAL, so "H. sapiens martian" and "H. sapiens
## terran" differed by an epithet and a tree node and nothing else — the genealogy was recorded
## carefully and then carried no consequence. A civilisation of ten thousand colonies was one
## population in ten thousand places, which means one survival number: whatever kills a colony
## kills all of them.
##
## A stock is two things: HOW MANY WENT, and WHAT HAS BEEN SPLICED INTO THEM.
##
## HOW MANY GO is a shipping cost against genetic variation. A founder group is a sample of the
## population it leaves, and a small sample loses the long tail of rare alleles — not inbreeding
## depression (a hundred thousand people are far past the threshold for that) but a thinner set
## of genetic backgrounds, and a smaller effective population, which drifts faster. So a light
## seed is cheap and becomes its own lineage sooner, and gets less out of whatever was written
## into it; a broad one is expensive, stays recognisably its parent for longer, and expresses an
## edit fully.
##
## WHAT HAS BEEN WRITTEN is a set of TRAITS, each an engineered change to the germ line. This is
## gene splicing and not a breeding programme, and the distinction is the whole timing of the
## thing: selection moves a population over hundreds of thousands of years, and a sequence that
## is already written moves through one in a couple of generations. SPLICE_YEARS is decades. The
## slow part is no longer distributing a trait — it is HAVING one, which still means a colony
## somewhere worked the sequence out, or Synthetic Biology wrote it from first principles.
##
## Every trait costs something. A longer childhood buys a trained mind and fewer children; a
## body that needs less buys more people per world and less of everything else. MAX_TRAITS caps
## how much of a genome can be rewritten before it stops being viable, which is what stops the
## answer being "all of them" — with a cap of three the player is choosing between minds, bodies
## and numbers rather than accumulating.
##
## ── Traits are keyed by STRING ID, deliberately ──
## An index into this table would have been smaller and faster and would have made the trade
## impossible. Trading genetic information with a colony four hundred light-years out means
## naming what is delivered across a save file, a light-delayed message and a version boundary.
## A string does that; a row number does not.

## The founder-group sizes a colony ship can carry.
##
##   pop        people delivered — what world_pop starts at
##   mass_mult  launch cost, against the standard group: people, life support and rations
##   diversity  share of the parent population's variation that survives the sampling
const FOUNDERS: Array[Dictionary] = [
	{"id": "minimal", "label": "Minimal", "pop": 1.0e5, "mass_mult": 0.35, "diversity": 0.45,
		"blurb": "A hundred thousand. Cheap to lift, quick to become something else, and working from a thin sample of what it left."},
	{"id": "standard", "label": "Standard", "pop": 1.0e6, "mass_mult": 1.0, "diversity": 0.75,
		"blurb": "A million — the group every colony used to get."},
	{"id": "broad", "label": "Broad", "pop": 1.0e7, "mass_mult": 4.0, "diversity": 1.0,
		"blurb": "Ten million. Four times the launch for a population that carries its parent's whole range and expresses an edit for everything it is worth."},
]

## Engineered traits, as multipliers on the civilisation's own figures.
##
##   growth    on POP_GROWTH_PER_YEAR — how fast a world fills its capacity, and refills it
##   life      on the life expectancy a world's people reach
##   compute   on useful thinking per person. This is the FRACTION OF A LIFE spent trained and
##             productive, and how much of a mind is given to the work — not the 1e17 FLOP/s
##             neocortex floor, which is hardware and does not move.
##   capacity  on how many of them a world holds: calories, air, water and tolerance per head
##
## Every row trades. Nothing here is free, and nothing here is strictly better than the stock it
## replaces — that is what makes the choice a choice.
const TRAITS: Array[Dictionary] = [
	{"id": "high_intelligence", "label": "High Intelligence",
		"growth": 0.80, "life": 1.00, "compute": 1.70, "capacity": 0.95,
		"blurb": "A larger, hungrier neocortex and a childhood half again as long. Each mind is worth far more and there are fewer of them, later."},
	{"id": "longevity", "label": "Extended Lifespan",
		"growth": 0.65, "life": 1.55, "compute": 1.15, "capacity": 1.00,
		"blurb": "Senescence pushed back. A life spends far more of itself trained and working, and a population that lives this long replaces itself slowly."},
	{"id": "rapid_maturation", "label": "Rapid Maturation",
		"growth": 2.30, "life": 0.85, "compute": 0.70, "capacity": 1.00,
		"blurb": "Adult in a few years. Fills an empty world in a fraction of the time and comes back from a strike that would finish anybody else, and almost none of a life is spent thinking."},
	{"id": "low_metabolism", "label": "Low Metabolism",
		"growth": 0.90, "life": 1.10, "compute": 0.95, "capacity": 1.45,
		"blurb": "Runs cold and eats little. The same world feeds half again as many, and none of them are quick."},
	{"id": "rad_hardened", "label": "Radiation Hardening",
		"growth": 0.95, "life": 1.30, "compute": 0.90, "capacity": 1.10,
		"blurb": "Redundant repair pathways and a genome that tolerates being hit. Deep space and a thin magnetosphere stop being lethal; the same machinery runs the rest of the body conservatively."},
	{"id": "vacuum_adapted", "label": "Vacuum Tolerance",
		"growth": 0.80, "life": 0.95, "compute": 0.90, "capacity": 1.70,
		"blurb": "Sealed skin, collapsible lungs, hours of consciousness on nothing. Most of a dead world becomes liveable, and very little else goes right."},
]

## What Earth is in 1945, and what anything unrecorded is taken to be: an unedited population.
const BASELINE_FOUNDERS: String = "standard"

## How much of a genome can be rewritten before it stops holding together. The cap is what makes
## the trait list a choice: the multipliers below all trade, but a population that could hold
## every one of them would still come out ahead by taking every one of them.
const MAX_TRAITS: int = 3

## Years for a written sequence to reach a whole population — germ-line edits, a couple of
## generations of them. THIS IS THE POINT OF THE TRAIT SYSTEM BEING SPLICING: the same change by
## selection was two million years, and a run that is measured in millions could do it perhaps
## twice. At decades it is something the player does and then sees.
const SPLICE_YEARS: float = 40.0

## How much of a trait's effect a founder group actually realises, at zero variation. A sequence
## spliced into a thin population expresses unevenly: fewer genetic backgrounds for an edit to
## land cleanly against, and a floor of it that always lands.
const DIVERSITY_FLOOR: float = 0.25

## Divergence timing against variation: a small effective population drifts faster, so it becomes
## a distinct lineage sooner. At full diversity the threshold is what it always was.
const DRIFT_MIN_MULT: float = 0.45

## Years for an isolated population to recover its variation toward a native one's, by mutation.
## A thin founder group is not thin forever; it just spends a geological age being so.
const DIVERSITY_RECOVERY_YEARS: float = 3.0e6

## Years of isolation before a distinct colony works out a sequence of its own.
##
## This is the slow clock the trade runs on, and it is deliberately the only slow one left. A
## colony four hundred light-years out has its own laboratories, its own world pushing on it and
## nobody to share with, and given long enough it writes something the home archive does not
## have. Splicing that into your own people takes decades; being the one who worked it out takes
## this.
const DISCOVER_YEARS: float = 3.0e5


## Years still owed before `stock` finishes the splice it is running.
static func splice_years_needed(stock: Variant) -> float:
	# A varied population takes an edit more evenly, so the rollout finishes sooner — the same
	# standing variation that makes a broad founder group worth its launch cost.
	var spread: float = 0.6 + 0.4 * diversity_of(stock)
	return SPLICE_YEARS / maxf(spread, 0.01)


## Variation after `dt` years of mutation in an isolated population: an exponential approach to
## the full range a native population carries.
static func recovered_diversity(diversity: float, dt: float) -> float:
	if dt <= 0.0:
		return clampf(diversity, 0.0, 1.0)
	var k: float = exp(-dt / DIVERSITY_RECOVERY_YEARS)
	return clampf(1.0 - (1.0 - clampf(diversity, 0.0, 1.0)) * k, 0.0, 1.0)


## The stock of a world that has no record — 1945 Earth, a colony from a save written before
## stocks existed, a statistical region.
##
## FULL variation, and the distinction matters. The diversity of a founder GROUP is how much of
## its parent population it sampled, and the standard group's 0.75 describes a million people
## picked out of Earth. Earth is not a founder group: it is a whole planet of unedited humanity,
## and it carries all of its own variation by definition. So the baseline founders id says what a
## colony ship defaults to, and the diversity here says what a native population is — they are
## different questions and only found() puts them together.
static func baseline() -> Dictionary:
	# Complete, not minimal: every record carries the splice fields and the cached trait key, so
	# that normalise's fast path recognises it and hands it straight back. A record built short
	# is one that gets rebuilt on every read.
	return {"founders": BASELINE_FOUNDERS, "traits": [], "tkey": "", "diversity": 1.0,
		"splice": "", "splice_done": 0.0, "discover": 0.0}


# Indexed by id rather than scanned.
#
# Every one of these is on the per-world path that Game._update_population walks each day, and a
# linear scan of a six-row table is six string comparisons where a hash lookup is one. At twenty
# thousand colonies that difference is the difference between a tick nobody notices and one that
# shows.
static var _by_founders: Dictionary = {}
static var _by_trait: Dictionary = {}

## Combined multipliers, keyed by the joined trait key — see tkey_for.
##
## A set of traits has one answer and there are only 42 sets a stock can legally hold, so the
## product is worked out once per set and read from here afterwards. This is what keeps the
## population loop at one hash lookup per world per day now that a stock is a SET rather than a
## single row: without it, a trait system with a cap of three would have tripled the cost of the
## hottest loop in the game.
static var _by_tkey: Dictionary = {}

static func _index() -> void:
	if not _by_founders.is_empty():
		return
	for f: Dictionary in FOUNDERS:
		_by_founders[str(f["id"])] = f
	for t: Dictionary in TRAITS:
		_by_trait[str(t["id"])] = t
	_by_tkey[""] = {"growth": 1.0, "life": 1.0, "compute": 1.0, "capacity": 1.0}


## A founder row by id, or the standard group if the id is not one.
static func founders_row(id: String) -> Dictionary:
	_index()
	return _by_founders.get(id, FOUNDERS[1])


## A trait row by id, or an empty dictionary if the id is not one.
static func trait_row(id: String) -> Dictionary:
	_index()
	return _by_trait.get(id, {})


## A trait's display name, falling back to the raw id so an unknown one is still legible.
static func trait_label(id: String) -> String:
	return str(trait_row(id).get("label", id))


static func is_founders(id: String) -> bool:
	_index()
	return _by_founders.has(id)


static func is_trait(id: String) -> bool:
	_index()
	return _by_trait.has(id)


## Every id, for a console listing or a dropdown.
static func founders_ids() -> Array:
	var out: Array = []
	for f: Dictionary in FOUNDERS:
		out.append(str(f["id"]))
	return out


static func trait_ids() -> Array:
	var out: Array = []
	for t: Dictionary in TRAITS:
		out.append(str(t["id"]))
	return out


## A list of trait ids reduced to the canonical set a stock can hold: known ids only, no
## duplicates, in TRAITS order, no more than MAX_TRAITS of them.
##
## TRAITS order rather than sorted order, so that the key a set hashes to does not depend on
## which order the player happened to tick the boxes in — two populations holding the same three
## traits are the same stock and must share one cache entry.
static func canon_traits(ids: Variant) -> Array:
	_index()
	if not (ids is Array):
		return []
	var want: Dictionary = {}
	for v in (ids as Array):
		var id: String = str(v)
		if _by_trait.has(id):
			want[id] = true
	var out: Array = []
	for t: Dictionary in TRAITS:
		if out.size() >= MAX_TRAITS:
			break
		var id: String = str(t["id"])
		if want.has(id):
			out.append(id)
	return out


## The cache key for a canonical trait list. Empty string for an unedited population.
static func tkey_for(traits: Array) -> String:
	return "|".join(traits)


## The combined multipliers for a trait key, worked out once per distinct set.
## Treat the returned dictionary as read-only — it is the cached one, not a copy.
static func mults_for(tkey: String) -> Dictionary:
	_index()
	var hit: Variant = _by_tkey.get(tkey)
	if hit is Dictionary:
		return hit
	var m: Dictionary = {"growth": 1.0, "life": 1.0, "compute": 1.0, "capacity": 1.0}
	for id: String in tkey.split("|", false):
		var row: Dictionary = _by_trait.get(id, {})
		for f: String in m:
			m[f] = float(m[f]) * float(row.get(f, 1.0))
	_by_tkey[tkey] = m
	return m


## The whole multiplier cache, for a caller about to look up thousands of rows that would rather
## not pay a static call for each one. Treat it as read-only, and go through mults_for for any
## key that might not be in it yet.
static var _warmed: bool = false

static func mult_table() -> Dictionary:
	_index()
	# Warmed for every legal set, so the hot loop's .get() never misses and never has to fall
	# back to the building path.  42 sets at a cap of three; the walk below is over all of them.
	#
	# Against a FLAG and not against the table's size: mults_for() fills entries in as they are
	# asked for, so a table with a few lazy entries in it is not a warmed one, and a size test
	# would leave the hot loop silently reading baseline multipliers for every set nobody had
	# happened to ask about yet.
	if not _warmed:
		_warmed = true
		_warm([], 0)
	return _by_tkey


static func _warm(prefix: Array, from: int) -> void:
	mults_for(tkey_for(prefix))
	if prefix.size() >= MAX_TRAITS:
		return
	for i in range(from, TRAITS.size()):
		var next: Array = prefix.duplicate()
		next.append(str(TRAITS[i]["id"]))
		_warm(next, i + 1)


## Anything shaped roughly like a stock, turned into one that every accessor below can read.
## Loaded saves, console input and older files all come through here.
##
## A record written before traits existed named a life history — "fecund", "balanced",
## "enduring" — and those are not traits and have no equivalent, so they are dropped and the
## world comes back unedited. That is the honest reading: those populations were selected, not
## written, and the game no longer models selection into a life history.
static func normalise(stock: Variant) -> Dictionary:
	if not (stock is Dictionary):
		return baseline()
	var d: Dictionary = stock
	# A record that is already well formed is handed back AS IT IS, with nothing allocated.
	#
	# This is the hot path and it was not obvious: Game._update_population walks every inhabited
	# world every day, and the accessors below each normalise again internally — so one world
	# cost several dictionary allocations and a pile of linear id scans. At twenty thousand
	# colonies that was most of two thirds of a second per tick.
	#
	# Returning the same dictionary rather than a copy is also the semantics the callers want:
	# _advance_lineages and splice_trait both mutate what they are given and write it back,
	# which is a no-op once they are the same object.
	if d.has("diversity") and d.has("tkey") and (d.get("traits") is Array) \
			and is_founders(str(d.get("founders", ""))):
		return d
	var f: String = str(d.get("founders", BASELINE_FOUNDERS))
	if not is_founders(f):
		f = BASELINE_FOUNDERS
	var traits: Array = canon_traits(d.get("traits", []))
	# Diversity is a property of the FOUNDING EVENT — how large the group was — so it is stored
	# rather than derived. A record without one is taken to be a native population carrying all
	# of its own variation, which is what every world of a save written before stocks existed was.
	var div: float = clampf(float(d.get("diversity", 1.0)), 0.0, 1.0)
	# A splice in progress is carried through, because this is the gate every stock passes on its
	# way off disk — dropped here, a world two thirds of the way through a rollout would start
	# again every time the game was loaded.
	var sp: String = str(d.get("splice", ""))
	if not is_trait(sp) or traits.has(sp):
		sp = ""
	return {"founders": f, "traits": traits, "tkey": tkey_for(traits),
		"diversity": div, "splice": sp,
		"splice_done": maxf(float(d.get("splice_done", 0.0)), 0.0),
		"discover": maxf(float(d.get("discover", 0.0)), 0.0)}


## Put `traits` into a record and keep the cached key with it. Every write to a stock's trait
## list goes through here — the key and the list cannot be allowed to disagree, because the
## population loop reads the key and nothing else.
static func set_traits(stock: Dictionary, ids: Array) -> Dictionary:
	var traits: Array = canon_traits(ids)
	stock["traits"] = traits
	stock["tkey"] = tkey_for(traits)
	return stock


## Variation an unedited founder group of this size carries.
static func diversity_for(founders_id: String) -> float:
	return clampf(float(founders_row(founders_id).get("diversity", 1.0)), 0.0, 1.0)


## The stock a colony is founded with: the group the player chose to ship, carrying the traits
## the order calls for, out of the population at `parent`.
##
## Splicing is why this is simple now. A colony ship's founders are edited before they leave, so
## asking for a trait the origin world does not have costs nothing beyond holding the sequence —
## which Game checks before the order is accepted. What the founder group cannot escape is being
## a SAMPLE: ten million people carry more of their parent's range than a hundred thousand, and
## no edit puts back variation that was never loaded.
static func found(founders_id: String, traits: Variant, parent: Dictionary) -> Dictionary:
	var f: String = founders_id if is_founders(founders_id) else BASELINE_FOUNDERS
	var from: Dictionary = normalise(parent)
	# Variation cannot be recovered by sampling an already-narrow parent: the group is taken from
	# what the parent has, not from what its own parent had.
	var div: float = minf(diversity_for(f), float(from["diversity"]))
	var st: Dictionary = {"founders": f, "diversity": clampf(div, 0.0, 1.0),
		"splice": "", "splice_done": 0.0, "discover": 0.0}
	return set_traits(st, canon_traits(traits))


## People a colony founded on this stock starts with.
static func pop_of(stock: Variant) -> float:
	return float(founders_row(str(normalise(stock)["founders"])).get("pop", 1.0e6))


## Launch cost of shipping this founder group, against the standard one.
static func mass_mult_of(stock: Variant) -> float:
	return maxf(float(founders_row(str(normalise(stock)["founders"])).get("mass_mult", 1.0)), 0.01)


static func diversity_of(stock: Variant) -> float:
	return float(normalise(stock)["diversity"])


static func traits_of(stock: Variant) -> Array:
	return normalise(stock)["traits"] as Array


## How much of a trait's effect this stock realises. A multiplier of m at full variation becomes
## 1 + (m − 1) × realisation, so an unedited population is unaffected whatever its diversity —
## nothing was written into it to express unevenly.
static func realisation_of(stock: Variant) -> float:
	return DIVERSITY_FLOOR + (1.0 - DIVERSITY_FLOOR) * diversity_of(stock)


## One combined multiplier, scaled by how much of it this stock actually expresses.
static func _realised(stock: Variant, field: String) -> float:
	var st: Dictionary = normalise(stock)
	var m: float = float(mults_for(str(st["tkey"])).get(field, 1.0))
	return 1.0 + (m - 1.0) * realisation_of(st)


static func growth_mult_of(stock: Variant) -> float:
	return maxf(_realised(stock, "growth"), 0.01)


static func life_mult_of(stock: Variant) -> float:
	return maxf(_realised(stock, "life"), 0.01)


static func compute_mult_of(stock: Variant) -> float:
	return maxf(_realised(stock, "compute"), 0.01)


static func capacity_mult_of(stock: Variant) -> float:
	return maxf(_realised(stock, "capacity"), 0.01)


## Scale on a world's divergence threshold: a thin founder group drifts into its own lineage
## sooner, because drift goes as the inverse of effective population.
static func drift_mult_of(stock: Variant) -> float:
	return DRIFT_MIN_MULT + (1.0 - DRIFT_MIN_MULT) * diversity_of(stock)


## "High Intelligence + Extended Lifespan", or "unedited".
static func traits_text(stock: Variant) -> String:
	var ids: Array = traits_of(stock)
	if ids.is_empty():
		return "unedited"
	var parts: Array = []
	for id: String in ids:
		parts.append(trait_label(id))
	return " + ".join(parts)


## "Broad / High Intelligence (variation 100%)" — for the launch readout, the console and the
## colony panel.
static func describe(stock: Variant) -> String:
	var st: Dictionary = normalise(stock)
	return "%s / %s (variation %d%%)" % [
		str(founders_row(str(st["founders"])).get("label", "?")),
		traits_text(st), int(round(diversity_of(st) * 100.0))]


## The same stock as a line of effects, which is what the player is actually choosing between.
static func effects_text(stock: Variant) -> String:
	var st: Dictionary = normalise(stock)
	return "%s founders · growth x%.2f · life x%.2f · thinking x%.2f · room x%.2f · diverges x%.2f" % [
		_si(pop_of(st)), growth_mult_of(st), life_mult_of(st), compute_mult_of(st),
		capacity_mult_of(st), drift_mult_of(st)]


## Short population figure, without pulling Units in for one call.
static func _si(v: float) -> String:
	if v >= 1.0e9:
		return "%.0fbn" % (v / 1.0e9)
	if v >= 1.0e6:
		return "%.0fm" % (v / 1.0e6)
	if v >= 1.0e3:
		return "%.0fk" % (v / 1.0e3)
	return "%.0f" % v
