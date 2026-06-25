class_name PoliticsData

## Display order for category sections.
const CATEGORIES: Array[String] = ["Economy", "Science", "Society", "Space"]

const CATEGORY_COLORS: Dictionary = {
	"Economy": Color(0.85, 0.70, 0.10),
	"Science": Color(0.20, 0.60, 0.90),
	"Society": Color(0.85, 0.45, 0.45),
	"Space":   Color(0.60, 0.30, 0.90),
}

## Full policy list.  Every policy is a real trade-off — there is no free lunch.
## type "toggle"  → default is bool
## type "slider"  → default/min/max/step are floats; unit is display suffix
const POLICIES: Array = [
	# ── Economy ───────────────────────────────────────────────────────────────
	{
		"id":       "tax_rate",
		"name":     "Tax Rate",
		"desc":     "State revenue funds extraction. High rates grow matter output but slow population growth and stifle compute. Neutral at 30%.",
		"category": "Economy",
		"type":     "slider", "min": 0.0, "max": 90.0, "step": 5.0, "default": 30.0, "unit": "%",
	},
	{
		"id":       "industrial_intensity",
		"name":     "Industrial Intensity",
		"desc":     "How hard heavy industry is run. Raises matter and energy output, but vents CO₂ and shortens lives through pollution.",
		"category": "Economy",
		"type":     "slider", "min": 0.0, "max": 100.0, "step": 10.0, "default": 50.0, "unit": "%",
	},
	{
		"id":       "automation",
		"name":     "Industrial Automation",
		"desc":     "Machines replace labour: +20% matter, +15% compute, −10% energy — but unemployment slows population growth and feeds AI autonomy.",
		"category": "Economy",
		"type":     "toggle", "default": false,
	},
	# ── Science ───────────────────────────────────────────────────────────────
	{
		"id":       "research_budget",
		"name":     "Research Budget",
		"desc":     "Compute directed to structured science. Up to ±40% science output, paid for by diverted matter. Neutral at 50%.",
		"category": "Science",
		"type":     "slider", "min": 0.0, "max": 100.0, "step": 5.0, "default": 50.0, "unit": "%",
	},
	{
		"id":       "ai_investment",
		"name":     "AI Investment",
		"desc":     "State-backed AI accelerates compute (up to +60%) — but every point raises AI autonomy and existential risk.",
		"category": "Science",
		"type":     "slider", "min": 0.0, "max": 100.0, "step": 10.0, "default": 20.0, "unit": "%",
	},
	{
		"id":       "open_science",
		"name":     "Open Science",
		"desc":     "Freely shared research: +15% science, +10% compute. Knowledge spreads faster — including to the machines.",
		"category": "Science",
		"type":     "toggle", "default": true,
	},
	# ── Society ───────────────────────────────────────────────────────────────
	{
		"id":       "healthcare",
		"name":     "Public Healthcare",
		"desc":     "Investment in medicine and sanitation. Adds up to +25 years of life expectancy, paid for with matter.",
		"category": "Society",
		"type":     "slider", "min": 0.0, "max": 60.0, "step": 5.0, "default": 10.0, "unit": "%",
	},
	{
		"id":       "natalism",
		"name":     "Population Policy",
		"desc":     "From antinatalist (−) to pronatalist (+). Pronatalism speeds population growth and raises capacity but lowers per-capita compute; antinatalism reverses it.",
		"category": "Society",
		"type":     "slider", "min": -50.0, "max": 50.0, "step": 10.0, "default": 0.0, "unit": "%",
	},
	{
		"id":       "welfare",
		"name":     "Social Welfare",
		"desc":     "A safety net: faster population growth and a few years of life expectancy, funded by matter.",
		"category": "Society",
		"type":     "slider", "min": 0.0, "max": 50.0, "step": 5.0, "default": 15.0, "unit": "%",
	},
	{
		"id":       "civil_liberties",
		"name":     "Civil Liberties",
		"desc":     "An open society: +10% science and +10% compute through innovation, at the cost of −8% central economic efficiency.",
		"category": "Society",
		"type":     "toggle", "default": true,
	},
	{
		"id":       "military_spending",
		"name":     "Military Spending",
		"desc":     "The arms race drives technology: up to +30% science, at a matter cost. But while humanity is confined to one world it stokes geopolitical tension and the risk of nuclear war — a risk that fades as you spread to other worlds.",
		"category": "Society",
		"type":     "slider", "min": 0.0, "max": 50.0, "step": 5.0, "default": 10.0, "unit": "%",
	},
	# ── Space ─────────────────────────────────────────────────────────────────
	{
		"id":       "space_budget",
		"name":     "Space Programme",
		"desc":     "Exploration spending: up to +15% science, paid for with matter.",
		"category": "Space",
		"type":     "slider", "min": 0.0, "max": 50.0, "step": 5.0, "default": 10.0, "unit": "%",
	},
	{
		"id":       "planetary_defense",
		"name":     "Planetary Defence",
		"desc":     "Detection and deflection of incoming bodies. At full funding, asteroid impacts are ~5× rarer — but it drains matter and energy.",
		"category": "Space",
		"type":     "slider", "min": 0.0, "max": 100.0, "step": 10.0, "default": 0.0, "unit": "%",
	},
	{
		"id":       "asteroid_mining",
		"name":     "Asteroid Mining Rights",
		"desc":     "Extraction treaties for the belt: +30% matter output.",
		"category": "Space",
		"type":     "toggle", "default": false,
	},
	{
		"id":       "nuclear_propulsion",
		"name":     "Nuclear Propulsion Programme",
		"desc":     "High-thrust nuclear drives cut transit times 25%, at a −8% energy cost.",
		"category": "Space",
		"type":     "toggle", "default": false,
	},
]

## Returns a fresh Dictionary of {policy_id: default_value} for all policies.
static func default_state() -> Dictionary:
	var d: Dictionary = {}
	for p: Dictionary in POLICIES:
		d[p["id"]] = p["default"]
	return d

# ── Policy effect formulas ──────────────────────────────────────────────────
# Single source of truth for how policies modify the economy and world state.
# Game.gd applies these to the live simulation; the politics screen displays them
# so the player always sees the actual current effect.

## Science-output multiplier (applied to science accumulation rate).
static func science_mult(s: Dictionary) -> float:
	var m := 1.0
	if bool(s.get("open_science", true)):     m += 0.15
	if bool(s.get("civil_liberties", true)):  m += 0.10
	m += (float(s.get("research_budget", 50.0)) - 50.0) / 50.0 * 0.40   # ±40%
	m += float(s.get("space_budget", 10.0)) / 50.0 * 0.15               # +15% at max
	m += float(s.get("military_spending", 10.0)) / 50.0 * 0.30          # arms race → tech, +30% at max
	return maxf(0.1, m)

## Compute multiplier (applied to total compute, which feeds science).
static func compute_mult(s: Dictionary) -> float:
	var m := 1.0
	m += float(s.get("ai_investment", 20.0)) / 100.0 * 0.60             # +60% at max
	if bool(s.get("automation", false)):      m += 0.15
	if bool(s.get("open_science", true)):     m += 0.10
	if bool(s.get("civil_liberties", true)):  m += 0.10
	m -= float(s.get("natalism", 0.0)) / 50.0 * 0.15                    # more dependents ↓ per-capita
	return maxf(0.1, m)

## Minerals (matter) production multiplier.
static func minerals_mult(s: Dictionary) -> float:
	var m := 1.0
	m += float(s.get("industrial_intensity", 50.0)) / 100.0 * 0.50      # +50% at max
	if bool(s.get("automation", false)):      m += 0.20
	if bool(s.get("asteroid_mining", false)): m += 0.30
	m += (float(s.get("tax_rate", 30.0)) - 30.0) / 10.0 * 0.04          # state-funded extraction
	# Social and research spending divert matter.
	m -= float(s.get("research_budget", 50.0)) / 100.0 * 0.15
	m -= float(s.get("healthcare", 10.0)) / 60.0 * 0.15
	m -= float(s.get("welfare", 15.0)) / 50.0 * 0.12
	m -= float(s.get("space_budget", 10.0)) / 50.0 * 0.10
	m -= float(s.get("planetary_defense", 0.0)) / 100.0 * 0.15
	m -= float(s.get("military_spending", 10.0)) / 50.0 * 0.12
	if bool(s.get("civil_liberties", true)):  m -= 0.08
	return maxf(0.05, m)

## Energy production multiplier.
static func energy_mult(s: Dictionary) -> float:
	var m := 1.0
	m += (float(s.get("industrial_intensity", 50.0)) - 50.0) / 50.0 * 0.30   # ±30%, neutral at 50%
	if bool(s.get("automation", false)):         m -= 0.10
	if bool(s.get("nuclear_propulsion", false)): m -= 0.08
	m -= float(s.get("planetary_defense", 0.0)) / 100.0 * 0.10
	return maxf(0.05, m)

## Mission-duration multiplier (lower is faster).
static func mission_dur_mult(s: Dictionary) -> float:
	var m := 1.0
	if bool(s.get("nuclear_propulsion", false)): m *= 0.75
	return m

## Population logistic-growth-rate multiplier.
static func pop_growth_mult(s: Dictionary) -> float:
	var m := 1.0
	m += float(s.get("natalism", 0.0)) / 50.0 * 0.40                    # ±40%
	m += float(s.get("welfare", 15.0)) / 50.0 * 0.20
	m -= (float(s.get("tax_rate", 30.0)) - 30.0) / 10.0 * 0.03
	if bool(s.get("automation", false)): m -= 0.10                     # unemployment
	return maxf(0.1, m)

## Population carrying-capacity multiplier.
static func pop_capacity_mult(s: Dictionary) -> float:
	var m := 1.0
	m += float(s.get("natalism", 0.0)) / 50.0 * 0.20
	m += float(s.get("welfare", 15.0)) / 50.0 * 0.10
	m -= float(s.get("industrial_intensity", 50.0)) / 100.0 * 0.10     # pollution lowers capacity
	return maxf(0.2, m)

## Life-expectancy bonus in YEARS (added to the medical-research baseline).
static func life_expectancy_bonus(s: Dictionary) -> float:
	var b := 0.0
	b += float(s.get("healthcare", 10.0)) / 60.0 * 25.0                # up to +25 years
	b += float(s.get("welfare", 15.0)) / 50.0 * 8.0
	b -= float(s.get("industrial_intensity", 50.0)) / 100.0 * 10.0     # pollution
	return b

## CO₂-emissions multiplier (applied to every plant's venting rate).
static func co2_mult(s: Dictionary) -> float:
	var m := 0.5 + float(s.get("industrial_intensity", 50.0)) / 100.0  # 0.5×…1.5×
	if bool(s.get("automation", false)): m -= 0.10                     # efficiency
	return maxf(0.1, m)

## Asteroid-impact interval multiplier (higher = impacts are rarer).
static func asteroid_gap_mult(s: Dictionary) -> float:
	return 1.0 + float(s.get("planetary_defense", 0.0)) / 100.0 * 4.0  # up to 5× rarer

## Live AI-autonomy level [0,1] — a visible existential-risk indicator driven by AI policy.
static func ai_autonomy(s: Dictionary) -> float:
	var a := 0.10
	a += float(s.get("ai_investment", 20.0)) / 100.0 * 0.60
	if bool(s.get("automation", false)):  a += 0.12
	if bool(s.get("open_science", true)): a += 0.08
	return clampf(a, 0.0, 1.0)

## Live existential-risk level [0,1] — rises with unchecked AI autonomy.
static func existential_risk(s: Dictionary) -> float:
	return clampf(ai_autonomy(s) * 0.6, 0.0, 1.0)
