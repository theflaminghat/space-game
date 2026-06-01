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
