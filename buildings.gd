class_name BuildingData

## Real-world calibration basis (all numbers scaled to game units):
##   Game unit: minerals = grams (g), energy cost = Joules (J), power = Watts (W),
##              compute = FLOP/s (c/s in shorthand below)
##
## Building costs are *bills of materials*: instead of a generic "minerals" lump,
## each structure consumes the specific crafted goods it is really made of
## (produced by the manufacturing recipes in recipes.gd) plus an energy cost.
##
## Power-plant balance: every plant's total material cost is proportional to its
## energy output at a constant ~2.0e-6 g/W, built from abundant crust-derived
## materials (Concrete, Steel, Ceramic) — copper is avoided in power plants because
## at 0.02 % of the crust it would bottleneck construction.  Mine output (below) is
## sized so a few mines can feed that bill of materials in reasonable game-time.
##
## Gating note: try_build only requires that you *hold* a material, so a building
## whose material's recipe you haven't unlocked is never impossible — it simply
## prompts you to research that recipe and craft it.  The one exception is the
## basic Mine, which must stay buildable from the very start: it uses only
## Concrete (abundant, coal-free, craftable with no research) so mine expansion
## can never dead-lock the economy.

# ── Building levels ───────────────────────────────────────────────────────────
## Most infrastructure comes in tiers: the same structure built bigger.  Each level costs
## LEVEL_COST_MULT× more and yields LEVEL_OUTPUT_MULT× more, so a higher tier is the efficient
## choice once you can afford the capital outlay — while level 1 stays buildable forever, and
## stays the only thing a young colony can actually pay for.
##
## Tiers are GENERATED rather than authored (see all()), so every building gains them
## automatically and there is no duplicated data to keep in step.  A building opts out with
## "levels": 1 — used for the Biomass Burner (its min_count floor under the grid belongs to a
## single fixed size) and the Space Elevator (its value is launch multipliers, which don't
## scale).  Coal and oil DO tier: their fuel draw scales with output, so grams-per-watt — and
## therefore the whole fuel/climate balance — is identical at every level.
const LEVEL_COUNT:       int   = 3
const LEVEL_COST_MULT:   float = 3.0
const LEVEL_OUTPUT_MULT: float = 3.5
const LEVEL_SUFFIX:      Array = ["", " II", " III", " IV", " V"]
## One research node per tier, shared by every building — a single breakthrough scales the
## whole industrial base rather than gating each structure separately.
const LEVEL_RESEARCH: Array = ["", "precision_manufacturing", "autonomous_factories"]
## Dictionary blocks scaled by output.  "consumption" is included deliberately: a bigger plant
## burns proportionally more fuel, so tiers don't quietly become free energy.
const LEVEL_OUTPUT_KEYS: Array = ["production", "storage", "consumption"]
## Bare numeric keys scaled the same way.
const LEVEL_SCALAR_KEYS: Array = ["mc_capacity", "farm_capacity", "ranch_capacity",
	"atmo_rate", "radiator_capacity", "detection", "shelter",
	"beam_send", "beam_recv"]

# ── Single buildings, not complexes ───────────────────────────────────────────
## Entries were originally authored at REGIONAL FLEET scale — one "Coal Plant" meant 132 GW of
## national generating capacity, not a power station.  "units" is how many real buildings an
## authored entry lumped together; all() divides its cost AND every output by that number, so
## each catalogue entry is one actual structure with a plausible real-world rating.
##
## Dividing output and cost by the same factor leaves the economy mathematically identical —
## K buildings at 1/K the size and 1/K the price is exactly the old entry.  Game.start_new_game
## multiplies the 1945 fleet counts by the same factor, so a fresh game has the same grid it
## always had, now expressed as thousands of real stations instead of dozens of abstractions.
## Blocks divided by "units" and lifted by Units.MASS_SCALE.  "consumption" is deliberately
## absent: fuel burn is authored directly in real grams per day per building (see the plants
## below), so it must skip both transforms.  It still rides the LEVEL scaling, because a plant
## with 3.5× the output really does burn 3.5× the fuel.
const UNIT_KEYS: Array = ["cost", "production", "storage"]

## base name → how many real buildings the authored entry represented.
const UNITS: Dictionary = {
	"Biomass Burner":   200,     # 132 GW fleet → 660 MW station
	"Coal Plant":       200,     # 132 GW fleet → 660 MW unit
	"Oil Plant":        300,     # 132 GW fleet → 440 MW unit
	"Natural Gas Burner": 264,   # 132 GW fleet → 500 MW combined-cycle unit
	"Solar Farm":       1000,    # 50 GW fleet  → 50 MW utility farm
	"Nuclear Plant":    300,     # 300 GW fleet → 1 GW reactor
	"Fusion Reactor":   1000,    # 1.5 TW fleet → 1.5 GW plant
	"Thermal Radiator": 1000,    # 4 TW fleet   → 4 GW radiator array
	"Bunker":           1000,    # 200 M sheltered → 200 k per shelter
	"Ground Rectenna":  1000,    # 5 TW fleet    -> 5 GW station
	"Microwave Uplink": 1000,    # 5 TW fleet    -> 5 GW station
	"Orbital Rectenna": 1000,    # 20 TW fleet   -> 20 GW platform
	"Power Relay Satellite": 1000,  # 25 TW fleet -> 25 GW relay
}

## How many real buildings the authored entry for `base_name` represented (1 when unlisted).
static func units(base_name: String) -> int:
	return maxi(1, int(UNITS.get(base_name, 1)))

## Divide an authored entry down to one real building.
static func _to_single_unit(b: Dictionary) -> Dictionary:
	var k: int = units(str(b["name"]))
	if k <= 1:
		return b
	var f: float = 1.0 / float(k)
	for key: String in UNIT_KEYS:
		var blk: Dictionary = b.get(key, {})
		for res: String in blk:
			blk[res] = float(blk[res]) * f
	for key: String in LEVEL_SCALAR_KEYS:
		if b.has(key):
			b[key] = float(b[key]) * f
	return b

## Lift every MASS in an entry onto realistic footing (see Units.MASS_SCALE).  Energy, science,
## compute, shelter, capacity and detection figures are left alone — they are not masses.
static func _to_real_mass(b: Dictionary) -> Dictionary:
	var m: float = Units.MASS_SCALE
	for key: String in UNIT_KEYS:   # cost, production, storage
		var blk: Dictionary = b.get(key, {})
		for res: String in blk:
			if res not in Units.NON_MASS_KEYS:
				blk[res] = float(blk[res]) * m
	if b.has("atmo_rate"):          # grams pulled from the atmosphere per day
		b["atmo_rate"] = float(b["atmo_rate"]) * m
	# Work units are material throughput — a mass-like quantity — for factory floor space
	# and for arable land alike.
	for wk: String in ["mc_capacity", "farm_capacity", "ranch_capacity"]:
		if b.has(wk):
			b[wk] = float(b[wk]) * m
	# Stored energy is not a mass, but it was authored at a token scale — lift it to the real
	# capacity of the installation (see Units.ENERGY_STORAGE_SCALE).
	var stor: Dictionary = b.get("storage", {})
	if stor.has("energy"):
		stor["energy"] = float(stor["energy"]) * Units.ENERGY_STORAGE_SCALE
	return b

static var _expanded: Array = []

## The full catalogue: every authored building plus its generated higher tiers.  Use this
## everywhere instead of BUILDINGS, which holds level 1 only.
static func all() -> Array:
	if _expanded.is_empty():
		for authored: Dictionary in BUILDINGS:
			# Reduce the authored fleet entry to ONE building, put its masses in real units,
			# then tier the result.
			var b: Dictionary = _to_real_mass(_to_single_unit(authored.duplicate(true)))
			var lv1: Dictionary = b.duplicate(true)
			lv1["level"] = 1
			lv1["base_name"] = str(b["name"])
			lv1["level_research"] = ""
			lv1.erase("levels")
			_expanded.append(lv1)
			for lv in range(2, _levels_for(b) + 1):
				_expanded.append(_scaled(b, lv))
	return _expanded

## How many tiers a building has: its explicit "levels", or LEVEL_COUNT when it has any scalar
## output worth scaling.  A structure that only carries special effects gets no tiers.
static func _levels_for(b: Dictionary) -> int:
	if b.has("levels"):
		return maxi(1, int(b["levels"]))
	if not (b.get("production", {}) as Dictionary).is_empty():
		return LEVEL_COUNT
	for k: String in LEVEL_OUTPUT_KEYS + LEVEL_SCALAR_KEYS:
		if b.has(k):
			return LEVEL_COUNT
	return 1

## One generated tier: the authored building with its costs and outputs scaled.
static func _scaled(base: Dictionary, level: int) -> Dictionary:
	var d: Dictionary = base.duplicate(true)
	var cost_f: float = pow(LEVEL_COST_MULT,   float(level - 1))
	var out_f:  float = pow(LEVEL_OUTPUT_MULT, float(level - 1))
	d["name"] = str(base["name"]) + str(LEVEL_SUFFIX[mini(level - 1, LEVEL_SUFFIX.size() - 1)])
	d["base_name"] = str(base["name"])
	d["level"] = level
	d["level_research"] = str(LEVEL_RESEARCH[mini(level - 1, LEVEL_RESEARCH.size() - 1)])
	d.erase("levels")
	d.erase("min_count")   # the "always keep one running" floor belongs to the base tier only
	var costs: Dictionary = d.get("cost", {})
	for k: String in costs:
		costs[k] = float(costs[k]) * cost_f
	for key: String in LEVEL_OUTPUT_KEYS:
		var blk: Dictionary = d.get(key, {})
		for k: String in blk:
			blk[k] = float(blk[k]) * out_f
	for k: String in LEVEL_SCALAR_KEYS:
		if d.has(k):
			d[k] = float(d[k]) * out_f
	return d

## Build-panel grouping.  Every entry carries a "category"; these give the section order and
## their display names, so the list reads as an organised catalogue rather than one long roll.
const CATEGORY_ORDER: Array = [
	"power", "storage", "extraction", "industry",
	"science", "observation", "habitation", "support", "defense",
]
const CATEGORY_LABELS: Dictionary = {
	"power":       "Power",
	"storage":     "Storage",
	"extraction":  "Extraction",
	"industry":    "Industry",
	"science":     "Science",
	"observation": "Observation",
	"habitation":  "Habitation",
	"support":     "Support",
	"defense":     "Defence",
}
const CATEGORY_COLORS: Dictionary = {
	"power":       Color(1.00, 0.82, 0.40),
	"storage":     Color(0.55, 0.90, 0.65),
	"extraction":  Color(0.80, 0.68, 0.50),
	"industry":    Color(0.70, 0.78, 0.92),
	"science":     Color(0.60, 0.80, 1.00),
	"observation": Color(0.75, 0.70, 1.00),
	"habitation":  Color(0.95, 0.72, 0.80),
	"support":     Color(0.60, 0.85, 0.88),
	"defense":     Color(0.95, 0.55, 0.50),
}

const BUILDINGS := [
	# ── 1945 fossil power infrastructure (a starting fleet AND buildable) ──────
	# The 1945 global energy supply is a FLEET of regional power stations rated
	# 132 GW each.  Game.start_new_game() grants 10 biomass + 10 coal + 5 oil = 25
	# stations → 1.32e12 + 1.32e12 + 6.6e11 = 3.3e12 W (a 40/40/20 split, ≈ the real
	# 1945 supply of ~100 EJ/yr).  At default policy this is exactly the 3.3 TW the
	# grid shows on a fresh game.
	# These are the cheap, dirty workhorse of the early grid: buildable from the
	# start (no research gate) with a modest bill of materials — but every one vents
	# CO₂ while it runs, so leaning on them warms the planet.  The Biomass Burner's
	# "min_count": 1 keeps at least one running so energy production can never
	# collapse (which would soft-lock the economy, since building anything costs
	# energy).  Solar/nuclear/fusion cost more (or are gated) but emit nothing.
	# "co2_per_energy" = grams of CO₂ vented to the atmosphere per unit of energy
	# generated (per game-day of running).  Combustion intensities differ by fuel:
	# coal is dirtiest, oil cleanest, biomass in between.
	# "consumption" = grams of fuel drawn from THIS WORLD's inventory per game-day, per
	# building (same time base as mine output and recipe inputs).  A plant that can't be
	# fed throttles in proportion to the fuel it does get — producing less power and
	# venting proportionally less CO₂ — so fossil power is finite and competes with
	# manufacturing for the same coal.  The Biomass Burner deliberately has NO fuel line:
	# it regrows its own feedstock, which keeps it a fuel-free floor under the grid so
	# its "min_count": 1 can still guarantee power never collapses.
	# Energy costs stay under the base energy storage cap (1e5) so these are
	# buildable from the start without first raising the cap with Battery Banks; the
	# real investment is the (uncapped) Concrete/Steel/Cu bill of materials.
	# Material cost is balanced to energy output across ALL power plants at a constant
	# ~2.0e-6 g per watt, and uses only abundant crust-derived materials (Concrete,
	# Steel) — no copper, which at 0.02% of the crust would bottleneck construction.
	# 132 GW × 2.0e-6 = 264 000 g total.
	{"name": "Biomass Burner",
		"levels": 1,
		"category": "power",
		"min_count": 1,
		"allowed_types": ["rocky"],
		"cost": {"Concrete": 160_000, "Steel": 104_000, "energy": 40_000},
		"production": {"energy": 1.32e11},   # 132 GW
		"co2_per_energy": 38.0},
	# Coal is ~0.05 % of Earth's crust, so a handful of mines can just about feed the
	# starting coal fleet — but every gram burned is a gram the smelters don't get.
	{"name": "Coal Plant",
		"category": "power",
		"allowed_types": ["rocky"],
		"cost": {"Concrete": 160_000, "Steel": 104_000, "energy": 50_000},
		"production": {"energy": 1.32e11},   # 132 GW fleet → 660 MW unit
		# 660 MW at ~38 % thermal efficiency on 24 MJ/kg coal = 72 kg/s = 6.25e9 g/day.
		# Authored per BUILDING in real grams/day (skips the units + MASS_SCALE transforms).
		"consumption": {"Coal": 6.25e9},
		"co2_per_energy": 45.0},
	# Burns FUEL OIL, not crude — the barrel goes through the Oil Refining still first.
	# Natural Gas Burner — combined-cycle gas turbine.  The cleanest thing that burns: ~50 g of
	# CO2 per MJ against coal's ~95, so it emits a little over half what a coal station does for
	# the same power.  500 MW at ~60 % efficiency on 55 MJ/kg methane = 15 kg/s = 1.31e9 g/day,
	# authored per BUILDING in real grams/day like the other fuelled plants.
	{"name": "Natural Gas Burner",
		"category": "power",
		"allowed_types": ["rocky"],
		"cost": {"Concrete": 120_000, "Steel": 88_000, "energy": 45_000},
		"production": {"energy": 1.32e11},   # 132 GW fleet → 500 MW unit
		"consumption": {"CH4": 1.31e9},
		"co2_per_energy": 24.0},

	# Oil is ~5000× rarer than coal in the crust, so oil plants can never be sustained by
	# mining alone: they burn down the inherited reserve and then starve.  Peak oil, modelled.
	{"name": "Oil Plant",
		"category": "power",
		"allowed_types": ["rocky"],
		"cost": {"Concrete": 160_000, "Steel": 104_000, "energy": 50_000},
		"production": {"energy": 1.32e11},   # 132 GW fleet → 440 MW unit
		# 440 MW at ~40 % efficiency on 42 MJ/kg fuel oil = 26 kg/s = 2.26e9 g/day.
		"consumption": {"FuelOil": 2.26e9},
		"co2_per_energy": 32.0},

	# ── Always available ──────────────────────────────────────────────────────
	# Matter Depot — steel silos + concrete bunkers.  Raises the matter cap only.
	{"name": "Matter Depot",
		"category": "storage",
		"allowed_types": ["rocky"],
		"cost": {"Steel": 16_000, "Concrete": 8_000, "energy": 15_000},
		"production": {},
		"storage": {"minerals": 1_000_000.0}},

	# ── Energy storage ─────────────────────────────────────────────────────────
	# Several distinct kinds, each raising the energy cap only.  They trade off the
	# same way real grid storage does: cheap-but-bulky mechanical stores (pumped hydro,
	# flywheels) using abundant materials, vs. dense tech-gated stores (superconducting
	# rings) that hold far more per build but need advanced materials/research.  Build
	# costs stay under the base energy cap (1e5) where they're meant to be reachable
	# from the start; later ones assume you've already raised the cap with earlier ones.

	# Battery Bank — grid-scale electrochemical battery banks.  The baseline store.
	{"name": "Battery Bank",
		"category": "storage",
		"allowed_types": ["rocky"],
		"cost": {"Steel": 10_000, "Cu": 8_000, "energy": 15_000},
		"production": {},
		"storage": {"energy": 1_000_000.0}},

	# Flywheel Array — kinetic storage in vacuum-spun rotors.  Cheap, copper-light,
	# works anywhere; modest capacity.
	{"name": "Flywheel Array",
		"category": "storage",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Steel": 30_000, "Cu": 6_000, "energy": 25_000},
		"production": {},
		"storage": {"energy": 3_000_000.0}},

	# Pumped Hydro Storage — water pumped uphill behind a dam.  Bulk storage from
	# abundant materials (concrete + steel), but needs a gravity well + terrain, so
	# rocky worlds only.  The cheapest energy per unit stored early on.
	{"name": "Pumped Hydro Storage",
		"category": "storage",
		"allowed_types": ["rocky"],
		"cost": {"Concrete": 50_000, "Steel": 15_000, "energy": 40_000},
		"production": {},
		"storage": {"energy": 5_000_000.0}},

	# Solar Farm — utility-scale photovoltaic plant, 50 GW.  The early, clean,
	# fuel-free option: weaker than a fossil station but emits nothing, so several
	# farms replace one 132 GW burner.  Cost scales with the new output (a real
	# multi-GW array) so it stays a genuine investment rather than free power.
	{"name": "Solar Farm",
		"category": "power",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"SolarPanel": 80_000, "Steel": 20_000, "energy": 50_000},
		"production": {"energy": 5.0e10},   # 50 GW (50e9 × 2.0e-6 = 100 000 g)
		# Output follows the Sun.  A panel is not a generator, it is a collector, so its yield
		# rises with the ageing main sequence, spikes absurdly on the red-giant branch, and goes
		# effectively dark once nothing is left but a white dwarf.  Everything that makes power
		# in this game runs out eventually; this is how the solar fleet does it.
		"solar": true},

	# Mine — surface excavator on a concrete pad.  Concrete is coal-free and needs
	# no research, so the first mines are always buildable (no bootstrap lock).
	# Output is sized so a handful of mines can actually feed power-plant construction:
	# extracted mass is split across the crust by composition, then refined, so at
	# 8 000 g/day the abundant ores (Fe₂O₃ for steel, CaO/SiO₂ for concrete) supply a
	# 132 GW fossil station in roughly two months of game-time with the 6 starting mines.
	{"name": "Mine",
		"category": "extraction",
		"allowed_types": ["rocky"],
		"cost": {"Concrete": 10_000, "energy": 1_500},
		"production": {"minerals": 8_000.0}},

	# Atmospheric Condenser — refrigerated intake towers that liquefy the air and fractionate
	# it.  The companion to the Mine: where a mine splits its yield across the CRUST, this
	# splits across the ATMOSPHERE ("atmo_rate", grams/game-day), so it is the only way to reach
	# volatiles the ground doesn't hold — N₂, O₂, and water on Earth; CO₂ on Venus and Mars.
	# Yield therefore depends entirely on where it stands, and a body with no atmosphere gives
	# nothing.  Costlier than a mine (refrigeration plant, not an excavator), but like a mine it
	# has no running cost once built.
	{"name": "Atmospheric Condenser",
		"category": "extraction",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Steel": 24_000, "Cu": 6_000, "Concrete": 12_000, "energy": 20_000},
		"production": {},
		"atmo_rate": 6_000.0},

	# Workshop — light assembly halls + machine tools.  Raises a world's Manufacturing
	# Capacity: how much it can run in the recipe panel at once.  "mc_capacity" is in
	# work-units/day, on top of the manual base every inhabited world has (Game.BASE_MC).
	# Buildable from the start so a young economy can scale industry before research lands.
	{"name": "Workshop",
		"category": "industry",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Steel": 8_000, "Concrete": 6_000, "energy": 10_000},
		"production": {},
		"mc_capacity": 15_000.0},

	# ── Tier 1 (research-gated) ───────────────────────────────────────────────
	# Nuclear Plant — multi-unit PWR complex, 300 GW.  The first power source that
	# beats a fossil station: denser and cleaner, the workhorse upgrade once
	# nuclear_power is researched.
	# Burns ENRICHED uranium, not ore — the Uranium Enrichment cascade has to run first.
	# A 1 GW PWR loads ~27 t of fresh fuel a year, so ~75 kg/day per reactor.  Authored per
	# BUILDING in real grams/day, like the other fuelled plants.
	{"name": "Nuclear Plant",
		"category": "power",
		"allowed_types": ["rocky"],
		"cost": {"Concrete": 400_000, "Steel": 180_000, "Ceramic": 20_000, "energy": 80_000},
		"production": {"energy": 3.0e11},   # 300 GW fleet → 1 GW reactor
		"consumption": {"EnrichedU": 7.5e4}},

	# Research Lab — precision instruments + clean-room optics.
	# Steel frame, glass optics, copper wiring.
	{"name": "Research Lab",
		"category": "science",
		"allowed_types": ["rocky"],
		"cost": {"Concrete": 3_000, "Glass": 3_000, "Cu": 1_500, "energy": 20_000},
		"production": {"compute": 10.0}},

	# ── Signature detection (finding alien civilisations) ─────────────────────
	# "detection" raises the per-year chance of resolving an alien system's signature
	# once its light has reached Sol.  A ground Observatory is buildable from the start;
	# the space telescope (above the atmosphere) and the deep-space array see far more.
	{"name": "Observatory",
		"category": "observation",
		"allowed_types": ["rocky"],
		"cost": {"Concrete": 6_000, "Glass": 4_000, "Cu": 2_000, "energy": 15_000},
		"production": {},
		"detection": 4.0},
	# Radio Telescope Array — dishes + correlator electronics; picks up faint transmissions.
	{"name": "Radio Telescope Array",
		"category": "observation",
		"allowed_types": ["rocky"],
		"cost": {"Steel": 40_000, "Cu": 20_000, "Microchip": 4_000, "energy": 60_000},
		"production": {},
		"detection": 16.0},
	# Space Telescope — an orbiting observatory above the atmosphere's blur and noise.
	{"name": "Space Telescope",
		"category": "observation",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Steel": 120_000, "Glass": 60_000, "Superconductor": 8_000, "Microchip": 20_000, "energy": 300_000},
		"production": {},
		"detection": 60.0},

	# ── Tier 2 ────────────────────────────────────────────────────────────────
	# Automated Mine — robotic excavators + conveyors (10× basic mine).
	# Steel chassis, control microchips, plastic conveyor components.
	{"name": "Automated Mine",
		"category": "extraction",
		"allowed_types": ["rocky"],
		"cost": {"Steel": 40_000, "Plastic": 4_000, "Microchip": 300, "energy": 25_000},
		"production": {"minerals": 80_000.0}},   # 10× the basic mine

	# Factory — full production lines + automated tooling.  ~5× a Workshop's output;
	# the mainstay of an industrialised world's Manufacturing Capacity.
	{"name": "Factory",
		"category": "industry",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Steel": 40_000, "Concrete": 30_000, "Microchip": 2_000, "energy": 60_000},
		"production": {},
		"mc_capacity": 80_000.0},

	# Data Center — GPU server racks + liquid cooling.  20 c/s.
	# Dominated by microchips; steel racks, copper interconnect, plastic housings.
	{"name": "Data Center",
		"category": "science",
		"allowed_types": ["rocky"],
		"cost": {"Microchip": 3_000, "Steel": 3_000, "Cu": 2_000, "Plastic": 1_000, "energy": 50_000},
		"production": {"compute": 20.0}},

	# Colony Dome — titanium pressure hull + life support + ISRU systems.
	{"name": "Colony Dome",
		"category": "habitation",
		"allowed_types": ["rocky"],
		"cost": {"Ti": 18_000, "Glass": 15_000, "Steel": 12_000, "energy": 80_000},
		"production": {}},

	# Bunker — a continent-spanning network of deep hardened shelters, stocked and sealed.
	# "shelter" is how many people ride out a catastrophe inside: when a nuclear exchange or an
	# asteroid strike would otherwise kill a share of the population, that many are guaranteed
	# to walk back out.  Bunkers are built to outlast the surface, so — alone among structures —
	# they survive the event that levels everything else standing on the world.
	# Sized at civil-defence scale to match the rest of the catalogue (a "Coal Plant" is a
	# 132 GW regional fleet, not one station), and priced to match: sheltering a nation is the
	# work of decades.  Higher levels shelter 3.5× as many, as with any other output.
	{"name": "Bunker",
		"category": "habitation",
		"allowed_types": ["rocky"],
		"cost": {"Concrete": 2_000_000, "Steel": 1_000_000, "energy": 200_000},
		"production": {},
		"shelter": 2.0e8},

	# ── Tier 3 ────────────────────────────────────────────────────────────────
	# Fusion Reactor — superconducting tokamak farm + ceramic blanket.  1.5 TW —
	# the endgame power source, an order of magnitude past any fossil or fission plant.
	{"name": "Fusion Reactor",
		"category": "power",
		"allowed_types": ["rocky"],
		"cost": {"Steel": 2_300_000, "Ceramic": 650_000, "Superconductor": 50_000, "energy": 200_000},
		"production": {"energy": 1.5e12},   # 1.5 TW fleet -> 1.5 GW plant
		# D-He3 releases ~3.4e11 J per gram; at ~40 % conversion a 1.5 GW plant burns
		# 1.1e-2 g/s = ~950 g/day.  Fusion is astonishingly fuel-light -- but the fuel only
		# exists in lunar regolith and gas-giant envelopes, so it still has to be gone and got.
		"consumption": {"He3": 950.0}},

	# Automated Factory — lights-out robotic plant.  ~8× a Factory; the densest source
	# of Manufacturing Capacity, and where the automation research lane really pays off
	# (it lifts the labour ceiling that otherwise caps how much industry a population runs).
	{"name": "Automated Factory",
		"category": "industry",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Steel": 200_000, "Microchip": 30_000, "Plastic": 10_000, "energy": 300_000},
		"production": {},
		"mc_capacity": 600_000.0},

	# Orbital Laser — a star-scale directed-energy weapon ringing the world it's built on.
	# It can discharge the whole energy reserve in a single shot; firing it at another
	# planet devastates the target — but channelling that much power through the array
	# back-stresses the home star, ageing Sol toward its death (see Game.fire_orbital_laser).
	{"name": "Orbital Laser",
		"category": "defense",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Superconductor": 200_000, "Steel": 300_000, "Microchip": 50_000, "energy": 500_000},
		"production": {}},

	# AI Research Hub — warehouse-scale GPU cluster + immersion cooling.  80 c/s.
	{"name": "AI Research Hub",
		"category": "science",
		"allowed_types": ["rocky"],
		"cost": {"Microchip": 20_000, "Steel": 12_000, "Cu": 10_000, "Plastic": 5_000, "energy": 250_000},
		"production": {"compute": 80.0}},

	# Thermal Radiator — a field of high-emissivity panels that dumps the civilisation's
	# waste heat to space.  "radiator_capacity" (W) adds to how much power the grid can draw
	# before it runs radiating-limited and its output is curtailed — essential once a Dyson
	# swarm's tens of terawatts arrive.  Steel structure, ceramic-coated emitter surface.
	{"name": "Thermal Radiator",
		"category": "support",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Steel": 1_200_000, "Ceramic": 400_000, "Cu": 100_000, "energy": 200_000},
		"production": {},
		"radiator_capacity": 4.0e12},   # +4 TW of heat-shedding capacity

	# ── Agriculture ──────────────────────────────────────────────────
	# Two buildings, not seven.  A Farm is arable capacity and a Ranch is pens and pasture;
	# WHAT they grow is a recipe chosen in the Production panel, exactly like a smelter.  That
	# is what agriculture actually is — the same field grows wheat or rice depending on what
	# was sown, and the same pens hold cattle or hogs.
	#
	# "farm_capacity" / "ranch_capacity" are work-units per day, the agricultural twins of
	# mc_capacity: recipes in the "agriculture" and "livestock" categories draw on them
	# instead of on factory floor space (see Game._process_production).

	# Farm — open ground under an open sky.  Cheap, enormous, and only possible on a world
	# that already has weather; on anything else the crop freezes, boils or suffocates.
	{"name": "Farm",
		"category": "agriculture",
		"allowed_types": ["rocky"],
		"cost": {"Steel": 3_000, "Concrete": 2_500, "energy": 2_000},
		"production": {},
		"farm_capacity": 1_800.0},

	# Ranch — pens, pasture, water and handling.  Which animal stands in it is a recipe.
	{"name": "Ranch",
		"category": "agriculture",
		"allowed_types": ["rocky"],
		"cost": {"Steel": 3_500, "Concrete": 2_000, "energy": 1_800},
		"production": {},
		"ranch_capacity": 1_800.0},

	# Hydroponics Bay — sealed racks under lamps.  Arable capacity where there is no soil and
	# no sky, which is what makes a colony possible at all; it buys that with power and with
	# water it cannot get from weather.  A fraction of open ground's capacity per building.
	{"name": "Hydroponics Bay",
		"category": "agriculture",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Steel": 12_000, "Glass": 5_000, "Plastic": 4_000, "Microchip": 500, "energy": 15_000},
		"production": {},
		"farm_capacity": 600.0,
		"consumption": {"energy": 2.0e8}},

	# Climate-Controlled Farm — a sealed, pressurised, temperature-regulated field under glass.
	# Where a Hydroponics Bay grows racks, this grows ground: it holds a whole artificial
	# climate steady against whatever is outside, and so returns nearly open-field capacity on
	# a world that has no business supporting a field.
	#
	# Aerogel is what makes the envelope possible at all — the only insulator light enough to
	# roof a field with and still hold a Martian night out.
	{"name": "Climate-Controlled Farm",
		"category": "agriculture",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Steel": 20_000, "Glass": 12_000, "Aerogel": 6_000, "Microchip": 1_500,
			"Superconductor": 800, "energy": 40_000},
		"production": {},
		"farm_capacity": 1_500.0,
		"ranch_capacity": 400.0,
		"consumption": {"energy": 5.0e8, "CO2": 8.0e7, "NH3": 2.0e7}},


	# ── Power transmission ────────────────────────────────────────────────────
	# Energy made where nobody lives has to be moved.  A Dyson swarm hangs inside Mercury's
	# orbit and a colony's reactors sit on another world entirely, so their output reaches the
	# grid only as a beam -- and a beam needs an aperture at both ends.  "beam_send" (W) is how
	# much power a structure can put into the network; "beam_recv" (W) is how much can be caught
	# and rectified.  Transmitted power is capped by whichever side is narrower, so the two have
	# to be built out together (see Game._link_capacity).

	# Ground Rectenna -- a rectifying antenna farm, kilometres of dipole mesh over farmland.
	# The NASA reference design lands ~5 GW per site.  Air and weather eat part of the beam;
	# that loss is already reflected in the figure below, which is DELIVERED power.
	{"name": "Ground Rectenna",
		"category": "support",
		"allowed_types": ["rocky"],
		"cost": {"Steel": 800_000, "Cu": 600_000, "Plastic": 200_000, "Microchip": 50_000, "energy": 300_000},
		"production": {},
		"beam_recv": 5.0e12},

	# Microwave Uplink -- the other end of the same technology: a phased array that puts a
	# world's surplus generation into the network.  Metamaterial lensing is what lets an
	# aperture this size hold a beam together across astronomical distances.
	{"name": "Microwave Uplink",
		"category": "support",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Steel": 600_000, "Cu": 800_000, "Metamaterial": 40_000, "Microchip": 150_000, "energy": 500_000},
		"production": {},
		"beam_send": 5.0e12},

	# Orbital Rectenna -- the same collector in free fall, where there is no atmosphere to
	# scatter the beam and no structural limit on aperture.  Four times a ground station's
	# throughput, at the price of putting it up there.
	{"name": "Orbital Rectenna",
		"category": "support",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Al": 500_000, "Cu": 400_000, "Ceramic": 300_000, "Microchip": 200_000, "energy": 800_000},
		"production": {},
		"beam_recv": 2.0e13},

	# Power Relay Satellite -- a mirror-and-array platform that catches the swarm's output and
	# throws it inward.  Superconducting busbars carry the current between aperture and emitter
	# without dissipating it as the waste heat that limits every terrestrial design.
	{"name": "Power Relay Satellite",
		"category": "support",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Al": 600_000, "Superconductor": 250_000, "Metamaterial": 60_000, "Microchip": 200_000, "energy": 1_000_000},
		"production": {},
		"beam_send": 2.5e13},

	# ── Orbital-scale infrastructure ──────────────────────────────────
	# The rung between a planet and a star.  A mature fusion grid runs ~1e15 W, which needs
	# 37 000 Thermal Radiators to shed and has no receiver to match at all — while the swarm-
	# class structures below start at 2e21 and are absurd until a swarm actually exists.  These
	# two fill a gap of eleven orders of magnitude that the player would otherwise cross one
	# gigawatt at a time.

	# Orbital Radiator Array — free-flying panels in high orbit, shedding a fusion economy's
	# waste heat where there is no atmosphere to carry it and no night to wait for.
	{"name": "Orbital Radiator Array",
		"category": "support",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Steel": 900_000, "Ceramic": 400_000, "Graphene": 120_000,
			"Superconductor": 60_000, "energy": 900_000},
		"production": {},
		"radiator_capacity": 4.0e14},

	# Orbital Power Grid — a receiving and relaying constellation around one world, the step
	# between a rectenna farm and an aperture that can catch a fraction of a star.
	{"name": "Orbital Power Grid",
		"category": "support",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Al": 800_000, "Superconductor": 500_000, "Metamaterial": 90_000,
			"Microchip": 300_000, "energy": 1_200_000},
		"production": {},
		"beam_recv": 2.0e15,
		"beam_send": 2.0e15},


	# ── Stellar-scale infrastructure ──────────────────────────────────
	# A finished swarm delivers ~9.5e23 W.  Nothing built a gigawatt at a time can radiate,
	# catch or hold that: it would take 2e14 Thermal Radiators, which is not a build order but
	# a wall.  These four are the swarm's counterparts — structures of the same class as the
	# collectors themselves, sized so a complete ring needs a few hundred of each rather than
	# a few hundred trillion.  They are the reason a Dyson swarm is a PROJECT and not a button.
	#
	# All four are built from the exotic materials the late tree unlocks; that is what those
	# recipes were always for.

	# Radiator Swarm — films co-orbiting the collectors, dumping the waste heat of everything
	# the civilisation does.  Thermodynamics, not collection, is what caps a Dyson economy:
	# every joule you use has to leave again as heat or you cook.
	{"name": "Radiator Swarm",
		"category": "support",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Graphene": 12_000_000, "CarbonNanotube": 8_000_000, "Aerogel": 5_000_000,
			"Steel": 20_000_000, "energy": 40_000_000},
		"production": {},
		"radiator_capacity": 2.0e21},

	# Stellar Rectenna Grid — receiving aperture at planetary-orbit scale.  A ground station
	# measured in kilometres cannot land a fraction of a percent of a star.
	{"name": "Stellar Rectenna Grid",
		"category": "support",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Metamaterial": 10_000_000, "Superconductor": 9_000_000,
			"CarbonNanotube": 6_000_000, "Al": 18_000_000, "energy": 50_000_000},
		"production": {},
		"beam_recv": 2.0e21},

	# Swarm Relay Network — the transmitting half: phased apertures strung between the
	# collectors and everywhere the power is actually spent.
	{"name": "Swarm Relay Network",
		"category": "support",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Metamaterial": 12_000_000, "Superconductor": 11_000_000,
			"QuantumProcessor": 900_000, "Al": 15_000_000, "energy": 60_000_000},
		"production": {},
		"beam_send": 2.5e21},

	# Orbital Ring Store — a superconducting loop the diameter of a planet's orbit, holding
	# current indefinitely.  A swarm's output is only useful if it can be banked between the
	# moments a civilisation needs all of it at once.
	{"name": "Orbital Ring Store",
		"category": "storage",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Superconductor": 15_000_000, "SelfHealingComposite": 7_000_000,
			"CarbonNanotube": 5_000_000, "Steel": 25_000_000, "energy": 45_000_000},
		"production": {},
		"storage": {"energy": 5.0e17}},


	# ── Megastructure infrastructure ──────────────────────────────────────────
	# Space Elevator — a tether from the surface to beyond geostationary altitude.
	# The tether is a carbon-nanotube composite; superconducting climbers; steel anchor.
	{"name": "Space Elevator",
		"levels": 1,
		"category": "support",
		"allowed_types": ["rocky"],
		"cost": {"CarbonComposite": 40_000_000, "Steel": 15_000_000, "Superconductor": 1_000_000, "energy": 30_000_000},
		"production": {"energy": 2.0e10},   # 20 GW (a side benefit; its real value is launch discounts)
		# Multipliers applied to launches originating from a body that has one.
		"launch_cost_mult":     0.35,   # −65% mineral & energy cost to orbit
		"launch_duration_mult": 0.80},  # −20% transit/insertion time

	# ── Storage ───────────────────────────────────────────────────────────────
	# Orbital Vault — sealed aluminium vault domes; 10× the Matter Depot (matter only).
	{"name": "Orbital Vault",
		"category": "storage",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Steel": 100_000, "Al": 50_000, "energy": 100_000},
		"production": {},
		"storage": {"minerals": 10_000_000.0}},

	# Orbital Battery — orbital battery farm; 10× the Battery Bank (energy only).
	{"name": "Orbital Battery",
		"category": "storage",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Steel": 80_000, "Al": 40_000, "Battery": 30_000, "energy": 100_000},
		"production": {},
		"storage": {"energy": 10_000_000.0}},

	# Superconducting Storage Ring (SMES) — current circulating forever in a chilled
	# superconducting loop.  The densest energy store: 50× a Battery Bank, but gated by
	# superconducting research and built from costly superconductor.
	{"name": "Superconducting Storage Ring",
		"category": "storage",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Superconductor": 40_000, "Steel": 60_000, "energy": 150_000},
		"production": {},
		"storage": {"energy": 50_000_000.0}},
]
