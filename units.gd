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
	# Sub-kilo: integer if whole, one decimal otherwise
	if v == floorf(v):
		return "%d %s" % [int(value), unit]
	return "%.1f %s" % [value, unit]

## Like format_si but spells out the full magnitude prefix (kilo, Mega, Giga…).
## Intended for the HUD top bar where readability matters more than compactness.
##   format_si_verbose(1500.0,  "grams")  → "1.5 kilograms"
##   format_si_verbose(8.3e9,   "Watts")  → "8.3 GigaWatts"
##   format_si_verbose(50.0,    "grams")  → "50 grams"
static func format_si_verbose(value: float, unit: String) -> String:
	var v := absf(value)
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
	# Sub-kilo: integer if whole, one decimal otherwise
	if v == floorf(v):
		return "%d %s" % [int(value), unit]
	return "%.1f %s" % [value, unit]

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
