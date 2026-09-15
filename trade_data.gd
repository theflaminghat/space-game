class_name TradeData

## Interstellar trade: how another civilisation values goods, and when it accepts a proposal.
##
## Value is EMBODIED ENERGY — what it would cost to produce one unit, in the energy reserve's own
## unit (watt-days, displayed as J).  Energy is worth itself.  Science is worth what computing it
## costs.  A raw material is worth the energy of digging it out, raised by how scarce it is even
## where it is most accessible.  Anything manufactured is worth its inputs plus the energy its
## cheapest recipe spends, per gram of output.  It is the one price two strangers can agree on
## while sharing nothing but physics — and it is derived from the same recipe and planet tables
## the economy runs on, so it moves whenever they do.
##
## A proposal is judged when it ARRIVES: by the partner's true alignment, the standing between
## the two civilisations, and what the partner can actually supply at that moment.

## Energy to perform one FLOP on 2020s hardware (~1e-11 J), in watt-days — the unit the energy
## reserve counts in (see units.gd).  What a partner would spend to compute the science itself.
const SCIENCE_VALUE_PER_FLOP: float = 1.0e-11 / 86400.0
## Extraction energy of an ore that makes up the whole of a deposit, per gram (watt-days).
const RAW_VALUE_PER_G: float = 0.01
## Scarcity: a raw material is worth RAW_VALUE_PER_G × abundance^-RAW_SCARCITY_POW, where abundance
## is its mass fraction in the richest mineable layer anywhere in the system.
const RAW_SCARCITY_POW: float = 0.5
const MIN_ABUNDANCE: float = 1.0e-12

## Offer value ÷ request value a partner requires before it accepts, by standing.  "" is a
## civilisation that has never exchanged a message with this one.
const ACCEPT_RATIO: Dictionary = {"allied": 0.9, "trading": 1.0, "contact": 1.1, "": 1.25}

## Supply capacity.  A partner can supply, in one proposal, at most a year of its own output.
## Output runs from a pre-swarm civilisation's grid to its whole star's luminosity as its Dyson
## swarm completes, interpolated logarithmically with the swarm's completion (0..1).
const PRE_SWARM_POWER_W: float = 3.0e12      # 1945 Earth
const FULL_SWARM_POWER_W: float = 3.8e26     # one solar luminosity
const CAPACITY_DAYS: float = 365.25

const GLOBAL_KEYS: Array = ["energy", "science"]

static var _values: Dictionary = {}


## Value per unit of every tradeable good: key → watt-days per gram (per J for energy, per FLOP
## for science).  Computed once; the tables it reads are constant.
static func values(game: Node) -> Dictionary:
	if not _values.is_empty():
		return _values
	var v: Dictionary = {"energy": 1.0, "science": SCIENCE_VALUE_PER_FLOP}
	# Raw materials: the richest mineable layer anywhere decides how scarce each one is.
	var best: Dictionary = {}
	var layers: Array = []
	for p: String in PlanetData.PLANETS:
		var comp: Dictionary = PlanetData.PLANETS[p].get("composition_g", {})
		for layer: String in ["crust", "atmosphere"]:
			if comp.has(layer):
				layers.append(comp[layer])
	if game:
		layers.append((game.MOON_COMPOSITION as Dictionary).get("crust", {}))
	for l: Dictionary in layers:
		var total: float = 0.0
		for c: String in l:
			total += float(l[c])
		if total <= 0.0:
			continue
		for c: String in l:
			best[c] = maxf(float(best.get(c, 0.0)), float(l[c]) / total)
	for c: String in best:
		v[c] = RAW_VALUE_PER_G * pow(maxf(float(best[c]), MIN_ABUNDANCE), -RAW_SCARCITY_POW)
	# Manufactured goods: relax over the recipe graph until every price is its cheapest route.
	for _pass in range(16):
		var changed: bool = false
		for r: Dictionary in RecipeData.RECIPES:
			var cost: float = 0.0
			var ok: bool = true
			var ins: Dictionary = r.get("inputs", {})
			for k: String in ins:
				if not v.has(k):
					ok = false
					break
				cost += float(ins[k]) * float(v[k])
			if not ok:
				continue
			var outs: Dictionary = r.get("outputs", {})
			var mass: float = 0.0
			for k: String in outs:
				if not (k in GLOBAL_KEYS or k == "minerals"):
					mass += float(outs[k])
			if mass <= 0.0:
				continue
			var per_g: float = cost / mass
			for k: String in outs:
				if k in GLOBAL_KEYS or k == "minerals":
					continue
				if not v.has(k) or per_g < float(v[k]) * 0.999999:
					v[k] = per_g
					changed = true
		if not changed:
			break
	_values = v
	return v


## Total value of a bundle {key → amount}; goods with no price count for nothing.
static func bundle_value(bundle: Dictionary, vals: Dictionary) -> float:
	var t: float = 0.0
	for k: String in bundle:
		t += float(bundle[k]) * float(vals.get(k, 0.0))
	return t


## What a partner with this much of a Dyson swarm (0..1) can supply in one proposal.
static func capacity(dyson: float) -> float:
	var f: float = clampf(dyson, 0.0, 1.0)
	var power: float = exp(lerpf(log(PRE_SWARM_POWER_W), log(FULL_SWARM_POWER_W), f))
	return power * CAPACITY_DAYS


## A partner's verdict on a proposal: {accept, reason, ratio, need}.
##   reason: "hostile" | "war" | "capacity" | "gift" | "terms"
static func assess(offer_value: float, request_value: float, status: String,
		alignment: String, cap: float) -> Dictionary:
	var need: float = float(ACCEPT_RATIO.get(status, ACCEPT_RATIO[""]))
	var ratio: float = offer_value / request_value if request_value > 0.0 else INF
	if alignment == "aggressive":
		return {"accept": false, "reason": "hostile", "ratio": ratio, "need": need}
	if status == "war":
		return {"accept": false, "reason": "war", "ratio": ratio, "need": need}
	if request_value > cap:
		return {"accept": false, "reason": "capacity", "ratio": ratio, "need": need}
	if request_value <= 0.0:
		return {"accept": true, "reason": "gift", "ratio": ratio, "need": need}
	return {"accept": ratio >= need, "reason": "terms", "ratio": ratio, "need": need}


static func display_name(key: String) -> String:
	match key:
		"energy":  return "Energy"
		"science": return "Science"
	return str(CompoundData.NAMES.get(key, key))


static func format_amount(key: String, amount: float) -> String:
	match key:
		"energy":  return Units.format_si(amount, "J")
		"science": return Units.format_si(amount, "FLOP")
	return Units.format_si(amount, "g")


## "3.0 Tg Steel, 5.0 PJ Energy" — a bundle in one line, for notices.
static func bundle_text(bundle: Dictionary) -> String:
	var parts: Array = []
	for k: String in bundle:
		parts.append("%s %s" % [format_amount(k, float(bundle[k])), display_name(k)])
	return ", ".join(parts) if not parts.is_empty() else "nothing"


## Parse an amount typed by the player: plain or scientific notation, with thousands separators,
## an optional SI prefix (k M G T P E Z Y) and an optional unit ("g", "J", "FLOP").  -1 if invalid.
static func parse_amount(text: String) -> float:
	var t: String = text.strip_edges().replace(",", "").replace(" ", "").replace("_", "")
	for unit: String in ["FLOP", "g", "J"]:
		if t.ends_with(unit) and t.length() > unit.length():
			t = t.left(t.length() - unit.length())
			break
	var mult: float = 1.0
	const PREFIX: Dictionary = {"k": 1.0e3, "M": 1.0e6, "G": 1.0e9, "T": 1.0e12, "P": 1.0e15,
		"E": 1.0e18, "Z": 1.0e21, "Y": 1.0e24}
	if t.length() > 1 and PREFIX.has(t.right(1)):
		mult = float(PREFIX[t.right(1)])
		t = t.left(t.length() - 1)
	if not t.is_valid_float():
		return -1.0
	var v: float = t.to_float() * mult
	return v if v >= 0.0 else -1.0
