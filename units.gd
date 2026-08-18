class_name Units

# ─────────────────────────────────────────────────────────────────────────────
# Physical unit definitions for every tracked in-game resource.
#
# Stored quantities and their SI base units:
#   science   – accumulated floating-point operations          (FLOP)
#   minerals  – raw mass in metric tonnes                      (t)
#   energy    – stored energy in Joules                        (J)
#   compute   – instantaneous processing rate                  (FLOP/s)
#
# All values are stored at the base unit magnitude (1 unit = 1 t, 1 J, 1 FLOP…).
# The SI prefix formatter below makes any magnitude readable in the HUD.
# ─────────────────────────────────────────────────────────────────────────────

# ── Mass scale ────────────────────────────────────────────────────────────────
## The industrial economy was authored at a "toy" mass scale: a Mine yielded 8 kg/day and a
## building cost tens of kilograms.  Internally consistent, but nowhere near real tonnage —
## an actual mine moves ~10 000 t/day.  MASS_SCALE lifts every mass in the game onto realistic
## footing at once: mine output, building bills of materials, fuel burn, storage, and stockpiles.
##
## Applied programmatically (BuildingData.all(), and the constants below) rather than by editing
## hundreds of literals, so there is a single number to tune and no chance of two tables drifting
## apart.  Because EVERY mass moves together, the economy is unchanged — only the units are real:
## a Mine now yields 10 000 t/day and its bill of materials is ~12 500 t of concrete.
##
## Deliberately NOT scaled: energy (Joules), science (FLOP), compute (FLOP/s), shelter capacity
## (people), manufacturing capacity (work), radiator capacity (Watts), detection, and the crust
## and atmosphere compositions in planet_data.gd — those are already in real units.
const MASS_SCALE: float = 1.25e6

## Resource keys inside a cost/production/storage block that are NOT masses, so MASS_SCALE
## must skip them.
const NON_MASS_KEYS: Array = ["energy", "science", "compute"]

# ── Energy storage scale ──────────────────────────────────────────────────────
## Energy STORAGE was authored at a token scale — a "Battery Bank" held 1 MJ, against a grid
## producing 3.3e12 J a day.  Fine while nothing expensive was ever bought with energy, but a
## launch campaign costs 1e13–1e15 J, so the pool's ceiling made launches unaffordable no matter
## how long you saved.  This lifts stored energy onto real installation capacities:
##   Battery Bank  1 MJ → 10 TJ  (2.8 GWh — Moss-Landing class grid battery)
##   Pumped Hydro  5 MJ → 50 TJ  (13.9 GWh — Bath-County class facility)
## Applied only to the "energy" entry of a storage block (and the per-world base cap); energy
## COSTS are untouched, since those were always in real Joules.
const ENERGY_STORAGE_SCALE: float = 1.0e7

const RESOURCE_DEFS: Dictionary = {
	# key       label        stored unit   rate unit
	"science":  {"label": "Science",  "unit": "FLOP",    "rate_unit": "FLOP/s"},
	"minerals": {"label": "Matter",   "unit": "Grams",   "rate_unit": "Grams/s"},
	"energy":   {"label": "Energy",   "unit": "Joules",  "rate_unit": "Watts"},
	"compute":  {"label": "Compute",  "unit": "FLOP/s",  "rate_unit": "FLOP/s"},
}

# ── Core formatter ────────────────────────────────────────────────────────────

## Format a numeric value with an SI magnitude prefix followed by unit.
## The SI prefix is attached directly to the unit with no extra space.
##   format_si(8.3e9,  "FLOP/s") → "8.3 GFLOP/s"
##   format_si(1500.0, "J")      → "1.5 kJ"
##   format_si(50.0,   "t")      → "50 t"
##   format_si(0.0,    "W")      → "0 W"
static func format_si(value: float, unit: String) -> String:
	var v := absf(value)
	# Quetta (10^30) is the largest SI prefix; past 1000 Q, keep it and switch the
	# mantissa to base-10 (scientific) notation, e.g. "1.50×10^7 QFLOP".
	if v >= 1.0e33:
		var q := value * 1.0e-30                        # amount in Quetta
		var e := int(floor(log(absf(q)) / log(10.0)))   # base-10 exponent
		var m := q / pow(10.0, e)                        # mantissa
		if absf(m) >= 10.0:                              # log10 rounding guard
			m *= 0.1
			e += 1
		return "%.2f×10^%d %s" % [m, e, "Q" + unit]
	if v >= 1.0e30: return "%.2f %s" % [value * 1.0e-30, "Q" + unit]   # Quetta
	if v >= 1.0e27: return "%.2f %s" % [value * 1.0e-27, "R" + unit]   # Ronna
	if v >= 1.0e24: return "%.2f %s" % [value * 1.0e-24, "Y" + unit]   # Yotta
	if v >= 1.0e21: return "%.2f %s" % [value * 1.0e-21, "Z" + unit]   # Zetta
	if v >= 1.0e18: return "%.2f %s" % [value * 1.0e-18, "E" + unit]   # Exa
	if v >= 1.0e15: return "%.1f %s" % [value * 1.0e-15, "P" + unit]
	if v >= 1.0e12: return "%.1f %s" % [value * 1.0e-12, "T" + unit]
	if v >= 1.0e9:  return "%.1f %s" % [value * 1.0e-9,  "G" + unit]
	if v >= 1.0e6:  return "%.1f %s" % [value * 1.0e-6,  "M" + unit]
	if v >= 1.0e3:  return "%.1f %s" % [value * 1.0e-3,  "k" + unit]
	# Unit scale: integer if whole, one decimal otherwise.
	if v >= 1.0:
		if v == floorf(v):
			return "%d %s" % [int(value), unit]
		return "%.1f %s" % [value, unit]
	if v == 0.0:
		return "0 %s" % unit
	# Sub-unit: the negative SI prefixes, so small flows read as "5 mg" rather than "0.0 g".
	if v >= 1.0e-3:  return "%.1f %s" % [value * 1.0e3,  "m" + unit]   # milli
	if v >= 1.0e-6:  return "%.1f %s" % [value * 1.0e6,  "µ" + unit]   # micro
	if v >= 1.0e-9:  return "%.1f %s" % [value * 1.0e9,  "n" + unit]   # nano
	if v >= 1.0e-12: return "%.1f %s" % [value * 1.0e12, "p" + unit]   # pico
	if v >= 1.0e-15: return "%.1f %s" % [value * 1.0e15, "f" + unit]   # femto
	if v >= 1.0e-18: return "%.1f %s" % [value * 1.0e18, "a" + unit]   # atto
	if v >= 1.0e-21: return "%.1f %s" % [value * 1.0e21, "z" + unit]   # zepto
	if v >= 1.0e-24: return "%.1f %s" % [value * 1.0e24, "y" + unit]   # yocto
	if v >= 1.0e-27: return "%.1f %s" % [value * 1.0e27, "r" + unit]   # ronto
	if v >= 1.0e-30: return "%.1f %s" % [value * 1.0e30, "q" + unit]   # quecto
	return "0 %s" % unit   # below quecto — indistinguishable from nothing

## Like format_si but spells out the full magnitude prefix (kilo, Mega, Giga…).
## Intended for the HUD top bar where readability matters more than compactness.
##   format_si_verbose(1500.0,  "grams")  → "1.5 kilograms"
##   format_si_verbose(8.3e9,   "Watts")  → "8.3 GigaWatts"
##   format_si_verbose(50.0,    "grams")  → "50 grams"
static func format_si_verbose(value: float, unit: String) -> String:
	var v := absf(value)
	# Past 1000 Quetta, keep the Quetta prefix and write the mantissa in base-10
	# (scientific) notation, e.g. "1.50×10^7 QuettaFLOP".
	if v >= 1.0e33:
		var q := value * 1.0e-30
		var e := int(floor(log(absf(q)) / log(10.0)))
		var m := q / pow(10.0, e)
		if absf(m) >= 10.0:
			m *= 0.1
			e += 1
		return "%.2f×10^%d %s" % [m, e, "Quetta" + unit]
	if v >= 1.0e30: return "%.2f %s" % [value * 1.0e-30, "Quetta" + unit]
	if v >= 1.0e27: return "%.2f %s" % [value * 1.0e-27, "Ronna"  + unit]
	if v >= 1.0e24: return "%.2f %s" % [value * 1.0e-24, "Yotta"  + unit]
	if v >= 1.0e21: return "%.2f %s" % [value * 1.0e-21, "Zetta"  + unit]
	if v >= 1.0e18: return "%.2f %s" % [value * 1.0e-18, "Exa"    + unit]
	if v >= 1.0e15: return "%.1f %s" % [value * 1.0e-15, "Peta"   + unit]
	if v >= 1.0e12: return "%.1f %s" % [value * 1.0e-12, "Tera"   + unit]
	if v >= 1.0e9:  return "%.1f %s" % [value * 1.0e-9,  "Giga"   + unit]
	if v >= 1.0e6:  return "%.1f %s" % [value * 1.0e-6,  "Mega"   + unit]
	if v >= 1.0e3:  return "%.1f %s" % [value * 1.0e-3,  "Kilo"   + unit]
	# Unit scale: integer if whole, one decimal otherwise.
	if v >= 1.0:
		if v == floorf(v):
			return "%d %s" % [int(value), unit]
		return "%.1f %s" % [value, unit]
	if v == 0.0:
		return "0 %s" % unit
	# Sub-unit magnitudes, spelled out to match the rest of this formatter.
	if v >= 1.0e-3:  return "%.1f %s" % [value * 1.0e3,  "milli" + unit]
	if v >= 1.0e-6:  return "%.1f %s" % [value * 1.0e6,  "micro" + unit]
	if v >= 1.0e-9:  return "%.1f %s" % [value * 1.0e9,  "nano"  + unit]
	if v >= 1.0e-12: return "%.1f %s" % [value * 1.0e12, "pico"  + unit]
	if v >= 1.0e-15: return "%.1f %s" % [value * 1.0e15, "femto" + unit]
	if v >= 1.0e-18: return "%.1f %s" % [value * 1.0e18, "atto"  + unit]
	if v >= 1.0e-21: return "%.1f %s" % [value * 1.0e21, "zepto" + unit]
	if v >= 1.0e-24: return "%.1f %s" % [value * 1.0e24, "yocto" + unit]
	if v >= 1.0e-27: return "%.1f %s" % [value * 1.0e27, "ronto" + unit]
	if v >= 1.0e-30: return "%.1f %s" % [value * 1.0e30, "quecto" + unit]
	return "0 %s" % unit

# ── Resource-aware helpers ────────────────────────────────────────────────────

## Format a stored resource amount with its natural physical unit.
##   format_resource("minerals", 5300.0) → "5.3 KiloGrams"
##   format_resource("energy",   2.0e10) → "20.0 GigaJoules"
static func format_resource(key: String, value: float) -> String:
	var unit: String = (RESOURCE_DEFS.get(key, {}) as Dictionary).get("unit", key)
	return format_si_verbose(value, unit)

## Format a resource production or consumption rate.
##   format_rate("energy",   2.0)   → "2 Watts"
##   format_rate("minerals", 1.5e6) → "1.5 MegaGrams/s"
static func format_rate(key: String, rate: float) -> String:
	var unit: String = (RESOURCE_DEFS.get(key, {}) as Dictionary).get("rate_unit", key + "/s")
	return format_si_verbose(rate, unit)

## Format a cost or production dictionary into a compact single-line string.
##   format_cost({"minerals": 50, "energy": 20})      → "50 Grams  20 Joules"
##   format_cost({"SolarPanel": 5000, "energy": 5000}) → "5.0 kg SolarPanel  5.0 kJoules"
##   format_cost({})                                   → "Free"
static func format_cost(cost: Dictionary) -> String:
	var parts: Array = []
	for key: String in cost:
		var v := float(cost[key])
		if v > 0.0:
			parts.append(format_cost_component(key, v))
	return "  ".join(parts) if not parts.is_empty() else "Free"

## Format a single cost line item (one resource or compound).
##   format_cost_component("minerals", 50)      → "50 Grams"
##   format_cost_component("SolarPanel", 5000)  → "5.0 kg SolarPanel"
static func format_cost_component(key: String, v: float) -> String:
	if RESOURCE_DEFS.has(key):
		return format_resource(key, v)
	# Compound inventory item — display mass in grams + compound name.
	return "%s %s" % [format_si(v, "g"), key]
