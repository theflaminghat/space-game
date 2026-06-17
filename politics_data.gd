class_name PoliticsData

## Display order for category sections.
const CATEGORIES: Array[String] = ["Economy", "Science", "Society", "Space"]

const CATEGORY_COLORS: Dictionary = {
	"Economy": Color(0.85, 0.70, 0.10),
	"Science": Color(0.20, 0.60, 0.90),
	"Society": Color(0.85, 0.45, 0.45),
	"Space":   Color(0.60, 0.30, 0.90),
}

## Full policy list.
## type "toggle"  → default is bool
## type "slider"  → default/min/max/step are floats; unit is display suffix
const POLICIES: Array = [
	# ── Economy ───────────────────────────────────────────────────────────────
	{
		"id":       "tax_rate",
		"name":     "Tax Rate",
		"desc":     "Higher rates raise mineral revenues. Rates below 35% stimulate private research.",
		"category": "Economy",
		"type":     "slider",
		"min":      0.0,
		"max":      80.0,
		"step":     5.0,
		"default":  35.0,
		"unit":     "%",
	},
	{
		"id":       "automation",
		"name":     "Industrial Automation",
		"desc":     "Replaces human labour with machines. +15% minerals, −10% energy.",
		"category": "Economy",
		"type":     "toggle",
		"default":  false,
	},
	{
		"id":       "carbon_tax",
		"name":     "Carbon Tax",
		"desc":     "Levies on fossil fuels fund clean research. −15% energy rate, +8% science.",
		"category": "Economy",
		"type":     "toggle",
		"default":  false,
	},
	# ── Science ───────────────────────────────────────────────────────────────
	{
		"id":       "research_budget",
		"name":     "Research Budget",
		"desc":     "Fraction of compute directed to structured science programmes. Neutral at 50%.",
		"category": "Science",
		"type":     "slider",
		"min":      0.0,
		"max":      100.0,
		"step":     5.0,
		"default":  50.0,
		"unit":     "%",
	},
	{
		"id":       "open_source",
		"name":     "Open Source Mandate",
		"desc":     "All publicly funded research is freely accessible. +20% science rate.",
		"category": "Science",
		"type":     "toggle",
		"default":  false,
	},
	{
		"id":       "ai_research",
		"name":     "AI Research Initiative",
		"desc":     "State-backed AI investment accelerates compute growth. +20% compute rate.",
		"category": "Science",
		"type":     "toggle",
		"default":  false,
	},
	# ── Society ───────────────────────────────────────────────────────────────
	{
		"id":       "free_press",
		"name":     "Free Press",
		"desc":     "Independent media improves scientific literacy across the population. +5% science.",
		"category": "Society",
		"type":     "toggle",
		"default":  true,
	},
	{
		"id":       "ubi",
		"name":     "Universal Basic Income",
		"desc":     "Guaranteed income reduces poverty and frees citizens for innovation. +10% compute, −5% minerals.",
		"category": "Society",
		"type":     "toggle",
		"default":  false,
	},
	{
		"id":       "military_spending",
		"name":     "Military Spending",
		"desc":     "Protects infrastructure and supply lines. Costs minerals proportionally.",
		"category": "Society",
		"type":     "slider",
		"min":      0.0,
		"max":      50.0,
		"step":     2.0,
		"default":  10.0,
		"unit":     "%",
	},
	# ── Space ─────────────────────────────────────────────────────────────────
	{
		"id":       "space_budget",
		"name":     "Space Programme Budget",
		"desc":     "Proportion of GDP directed to exploration. Each 10% adds 1% to science output.",
		"category": "Space",
		"type":     "slider",
		"min":      0.0,
		"max":      40.0,
		"step":     2.0,
		"default":  10.0,
		"unit":     "%",
	},
	{
		"id":       "asteroid_mining",
		"name":     "Asteroid Mining Rights",
		"desc":     "International treaty grants extraction rights in the belt. +25% minerals.",
		"category": "Space",
		"type":     "toggle",
		"default":  false,
	},
	{
		"id":       "nuclear_propulsion",
		"name":     "Nuclear Propulsion Programme",
		"desc":     "High-thrust nuclear drives cut transit times. All missions 20% shorter.",
		"category": "Space",
		"type":     "toggle",
		"default":  false,
	},
]

## Returns a fresh Dictionary of {policy_id: default_value} for all policies.
static func default_state() -> Dictionary:
	var d: Dictionary = {}
	for p: Dictionary in POLICIES:
		d[p["id"]] = p["default"]
	return d

# ── Policy effect formulas ──────────────────────────────────────────────────
# Single source of truth for how policies modify production.  Game.gd applies
# these to the live economy; the politics screen displays them so the player
# always sees the actual current multipliers.  Keep these in sync with the
# per-policy descriptions above.

## Science-output multiplier (applied to science accumulation rate).
static func science_mult(s: Dictionary) -> float:
	var m := 1.0
	if bool(s.get("open_source", false)): m += 0.20
	if bool(s.get("carbon_tax",  false)): m += 0.08
	if bool(s.get("free_press",   true)): m += 0.05
	# research_budget: 50% neutral, ±20% across the range.
	m += (float(s.get("research_budget", 50.0)) - 50.0) / 50.0 * 0.20
	# space_budget: +1% per 10% spent.
	m += float(s.get("space_budget", 10.0)) / 10.0 * 0.01
	return maxf(0.1, m)

## Compute multiplier (applied to total compute, which feeds science).
static func compute_mult(s: Dictionary) -> float:
	var m := 1.0
	if bool(s.get("ai_research", false)): m += 0.20
	if bool(s.get("ubi",         false)): m += 0.10
	return m

## Minerals (matter) production multiplier.
static func minerals_mult(s: Dictionary) -> float:
	var m := 1.0
	if bool(s.get("automation",      false)): m += 0.15
	if bool(s.get("asteroid_mining", false)): m += 0.25
	if bool(s.get("ubi",             false)): m -= 0.05
	# tax_rate: 35% neutral; each 5% above/below shifts minerals ±2%.
	m += (float(s.get("tax_rate", 35.0)) - 35.0) / 5.0 * 0.02
	# military_spending drains minerals (−10% at the 50% maximum).
	m -= float(s.get("military_spending", 10.0)) / 50.0 * 0.10
	return maxf(0.05, m)

## Energy production multiplier.
static func energy_mult(s: Dictionary) -> float:
	var m := 1.0
	if bool(s.get("automation", false)): m -= 0.10
	if bool(s.get("carbon_tax", false)): m -= 0.15
	return maxf(0.05, m)

## Mission-duration multiplier (lower is faster).
static func mission_dur_mult(s: Dictionary) -> float:
	if bool(s.get("nuclear_propulsion", false)):
		return 0.80
	return 1.0
