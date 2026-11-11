class_name PoliticsData

## Display order for category sections.
const CATEGORIES: Array[String] = ["Economy", "Science", "Society"]

const CATEGORY_COLORS: Dictionary = {
	"Economy": Color(0.85, 0.70, 0.10),
	"Science": Color(0.20, 0.60, 0.90),
	"Society": Color(0.85, 0.45, 0.45),
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
		"desc":     "State-backed AI accelerates compute (up to +60%) — and every point raises how capable the machines are. Capability that outruns Alignment Research is what the existential-risk figure counts.",
		"category": "Science",
		"type":     "slider", "min": 0.0, "max": 100.0, "step": 10.0, "default": 20.0, "unit": "%",
	},
	{
		"id":       "ai_alignment",
		"name":     "Alignment Research",
		"desc":     "Work on understanding what the machines are doing before they do it. Closes the gap between how capable they are and how well they are understood — but it runs on the same compute as everything else, so the understanding is paid for in thinking.",
		"category": "Science",
		"type":     "slider", "min": 0.0, "max": 100.0, "step": 10.0, "default": 0.0, "unit": "%",
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
	# Social Welfare was here, and it was the two Society policies either side of it at a
	# smaller size: population growth and capacity in natalism's 2:1 ratio, life expectancy on
	# healthcare's matter-funded terms, and no cost of its own that those two did not already
	# charge. Nothing could be asked of it that could not be asked elsewhere, so it was a
	# second copy of two decisions rather than a third decision. The reachable envelope went
	# with it — growth 1.69× → 1.49×, life +33 → +25 years, capacity 1.30× → 1.20× — and the
	# default run is leaner on people and richer on matter by the 15% it used to be set to.
	# Saves that carry it load fine: retired keys are dropped (see Game.load path).
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
	m += float(s.get("military_spending", 10.0)) / 50.0 * 0.30          # arms race → tech, +30% at max
	return maxf(0.1, m)

## Compute multiplier (applied to total compute, which feeds science).
static func compute_mult(s: Dictionary) -> float:
	var m := 1.0
	m += float(s.get("ai_investment", 20.0)) / 100.0 * 0.60             # +60% at max
	# Safety work is work. It runs on the same machines as the tree and the forecasts, so the
	# only way to buy understanding is with thinking that was going to go somewhere else.
	m -= float(s.get("ai_alignment", 0.0)) / 100.0 * 0.30               # -30% at max
	if bool(s.get("automation", false)):      m += 0.15
	if bool(s.get("open_science", true)):     m += 0.10
	if bool(s.get("civil_liberties", true)):  m += 0.10
	m -= float(s.get("natalism", 0.0)) / 50.0 * 0.15                    # more dependents ↓ per-capita
	# Revenue taken is investment not made, and the machines are bought with the same money as
	# the mine. The policy has SAID this since it was written — "high rates ... stifle compute"
	# — while nothing in here read tax_rate, so the page promised an effect the simulation did
	# not have. Neutral at 30% like its other two terms, so a default run is unchanged and what
	# the fix adds is reach: a command economy digs hard and thinks slowly, and the reverse.
	m -= (float(s.get("tax_rate", 30.0)) - 30.0) / 10.0 * 0.03
	return maxf(0.1, m)

## Minerals (matter) production multiplier.
static func minerals_mult(s: Dictionary) -> float:
	var m := 1.0
	m += float(s.get("industrial_intensity", 50.0)) / 100.0 * 0.50      # +50% at max
	if bool(s.get("automation", false)):      m += 0.20
	m += (float(s.get("tax_rate", 30.0)) - 30.0) / 10.0 * 0.04          # state-funded extraction
	# Social and research spending divert matter.
	m -= float(s.get("research_budget", 50.0)) / 100.0 * 0.15
	m -= float(s.get("healthcare", 10.0)) / 60.0 * 0.15
	m -= float(s.get("military_spending", 10.0)) / 50.0 * 0.12
	if bool(s.get("civil_liberties", true)):  m -= 0.08
	return maxf(0.05, m)

## Energy production multiplier.
static func energy_mult(s: Dictionary) -> float:
	var m := 1.0
	m += (float(s.get("industrial_intensity", 50.0)) - 50.0) / 50.0 * 0.30   # ±30%, neutral at 50%
	if bool(s.get("automation", false)):         m -= 0.10
	return maxf(0.05, m)

## Population logistic-growth-rate multiplier.
static func pop_growth_mult(s: Dictionary) -> float:
	var m := 1.0
	m += float(s.get("natalism", 0.0)) / 50.0 * 0.40                    # ±40%
	m -= (float(s.get("tax_rate", 30.0)) - 30.0) / 10.0 * 0.03
	if bool(s.get("automation", false)): m -= 0.10                     # unemployment
	return maxf(0.1, m)

## Population carrying-capacity multiplier.
static func pop_capacity_mult(s: Dictionary) -> float:
	var m := 1.0
	m += float(s.get("natalism", 0.0)) / 50.0 * 0.20
	m -= float(s.get("industrial_intensity", 50.0)) / 100.0 * 0.10     # pollution lowers capacity
	return maxf(0.2, m)

## Life-expectancy bonus in YEARS (added to the medical-research baseline).
static func life_expectancy_bonus(s: Dictionary) -> float:
	var b := 0.0
	b += float(s.get("healthcare", 10.0)) / 60.0 * 25.0                # up to +25 years
	b -= float(s.get("industrial_intensity", 50.0)) / 100.0 * 10.0     # pollution
	return b

## CO₂-emissions multiplier (applied to every plant's venting rate).
static func co2_mult(s: Dictionary) -> float:
	var m := 0.5 + float(s.get("industrial_intensity", 50.0)) / 100.0  # 0.5×…1.5×
	if bool(s.get("automation", false)): m -= 0.10                     # efficiency
	return maxf(0.1, m)

## How far the machines are being pushed [0,1].
##
## Alignment is deliberately NOT subtracted here: safety research does not make a system less
## capable, it makes it better understood. The two are separate quantities and the gap between
## them is the thing that matters — see existential_risk below.
static func ai_autonomy(s: Dictionary) -> float:
	var a := 0.10
	a += float(s.get("ai_investment", 20.0)) / 100.0 * 0.60
	if bool(s.get("automation", false)):  a += 0.12
	if bool(s.get("open_science", true)): a += 0.08
	return clampf(a, 0.0, 1.0)

## How much of that capability is understood [0,1], at these settings, once the work has landed.
static func ai_alignment_level(s: Dictionary) -> float:
	return clampf(float(s.get("ai_alignment", 0.0)) / 100.0, 0.0, 1.0)

## Capability nobody understands [0,1] — what the run is actually exposed to.
##
## This used to be `autonomy x 0.6`: a number that rose with AI investment, had no counter-move,
## and could not be driven to zero. It fed nothing but a happiness penalty and the pandemic odds,
## so the strongest compute lever in the game was a one-way ratchet with no failure mode of its
## own. It is the GAP now — capability minus understanding — which is a quantity the player can
## close, and the only reading on this page that can be taken to a true zero and kept there.
##
## This is where the settings SETTLE. The live figure is Game.ai_exposure(), which walks towards
## it: capability and understanding are both stocks and neither moves the year a slider does.
static func existential_risk(s: Dictionary) -> float:
	return clampf(ai_autonomy(s) - ai_alignment_level(s), 0.0, 1.0)
