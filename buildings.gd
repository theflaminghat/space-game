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
	# Energy costs stay under the base energy storage cap (1e5) so these are
	# buildable from the start without first raising the cap with Battery Banks; the
	# real investment is the (uncapped) Concrete/Steel/Cu bill of materials.
	# Material cost is balanced to energy output across ALL power plants at a constant
	# ~2.0e-6 g per watt, and uses only abundant crust-derived materials (Concrete,
	# Steel) — no copper, which at 0.02% of the crust would bottleneck construction.
	# 132 GW × 2.0e-6 = 264 000 g total.
	{"name": "Biomass Burner",
		"min_count": 1,
		"allowed_types": ["rocky"],
		"cost": {"Concrete": 160_000, "Steel": 104_000, "energy": 40_000},
		"production": {"energy": 1.32e11},   # 132 GW
		"co2_per_energy": 38.0},
	{"name": "Coal Plant",
		"allowed_types": ["rocky"],
		"cost": {"Concrete": 160_000, "Steel": 104_000, "energy": 50_000},
		"production": {"energy": 1.32e11},   # 132 GW
		"co2_per_energy": 45.0},
	{"name": "Oil Plant",
		"allowed_types": ["rocky"],
		"cost": {"Concrete": 160_000, "Steel": 104_000, "energy": 50_000},
		"production": {"energy": 1.32e11},   # 132 GW
		"co2_per_energy": 32.0},

	# ── Always available ──────────────────────────────────────────────────────
	# Matter Depot — steel silos + concrete bunkers.  Raises the matter cap only.
	{"name": "Matter Depot",
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
		"allowed_types": ["rocky"],
		"cost": {"Steel": 10_000, "Cu": 8_000, "energy": 15_000},
		"production": {},
		"storage": {"energy": 1_000_000.0}},

	# Flywheel Array — kinetic storage in vacuum-spun rotors.  Cheap, copper-light,
	# works anywhere; modest capacity.
	{"name": "Flywheel Array",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Steel": 30_000, "Cu": 6_000, "energy": 25_000},
		"production": {},
		"storage": {"energy": 3_000_000.0}},

	# Pumped Hydro Storage — water pumped uphill behind a dam.  Bulk storage from
	# abundant materials (concrete + steel), but needs a gravity well + terrain, so
	# rocky worlds only.  The cheapest energy per unit stored early on.
	{"name": "Pumped Hydro Storage",
		"allowed_types": ["rocky"],
		"cost": {"Concrete": 50_000, "Steel": 15_000, "energy": 40_000},
		"production": {},
		"storage": {"energy": 5_000_000.0}},

	# Solar Farm — utility-scale photovoltaic plant, 50 GW.  The early, clean,
	# fuel-free option: weaker than a fossil station but emits nothing, so several
	# farms replace one 132 GW burner.  Cost scales with the new output (a real
	# multi-GW array) so it stays a genuine investment rather than free power.
	{"name": "Solar Farm",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"SolarPanel": 80_000, "Steel": 20_000, "energy": 50_000},
		"production": {"energy": 5.0e10}},   # 50 GW (50e9 × 2.0e-6 = 100 000 g)

	# Mine — surface excavator on a concrete pad.  Concrete is coal-free and needs
	# no research, so the first mines are always buildable (no bootstrap lock).
	# Output is sized so a handful of mines can actually feed power-plant construction:
	# extracted mass is split across the crust by composition, then refined, so at
	# 8 000 g/day the abundant ores (Fe₂O₃ for steel, CaO/SiO₂ for concrete) supply a
	# 132 GW fossil station in roughly two months of game-time with the 6 starting mines.
	{"name": "Mine",
		"allowed_types": ["rocky"],
		"cost": {"Concrete": 10_000, "energy": 1_500},
		"production": {"minerals": 8_000.0}},

	# Workshop — light assembly halls + machine tools.  Raises a world's Manufacturing
	# Capacity: how much it can run in the recipe panel at once.  "mc_capacity" is in
	# work-units/day, on top of the manual base every inhabited world has (Game.BASE_MC).
	# Buildable from the start so a young economy can scale industry before research lands.
	{"name": "Workshop",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Steel": 8_000, "Concrete": 6_000, "energy": 10_000},
		"production": {},
		"mc_capacity": 15_000.0},

	# ── Tier 1 (research-gated) ───────────────────────────────────────────────
	# Nuclear Plant — multi-unit PWR complex, 300 GW.  The first power source that
	# beats a fossil station: denser and cleaner, the workhorse upgrade once
	# nuclear_power is researched.
	{"name": "Nuclear Plant",
		"allowed_types": ["rocky"],
		"cost": {"Concrete": 400_000, "Steel": 180_000, "Ceramic": 20_000, "energy": 80_000},
		"production": {"energy": 3.0e11}},   # 300 GW (300e9 × 2.0e-6 = 600 000 g)

	# Research Lab — precision instruments + clean-room optics.
	# Steel frame, glass optics, copper wiring.
	{"name": "Research Lab",
		"allowed_types": ["rocky"],
		"cost": {"Concrete": 3_000, "Glass": 3_000, "Cu": 1_500, "energy": 20_000},
		"production": {"compute": 10.0}},

	# ── Tier 2 ────────────────────────────────────────────────────────────────
	# Automated Mine — robotic excavators + conveyors (10× basic mine).
	# Steel chassis, control microchips, plastic conveyor components.
	{"name": "Automated Mine",
		"allowed_types": ["rocky"],
		"cost": {"Steel": 40_000, "Plastic": 4_000, "Microchip": 300, "energy": 25_000},
		"production": {"minerals": 80_000.0}},   # 10× the basic mine

	# Factory — full production lines + automated tooling.  ~5× a Workshop's output;
	# the mainstay of an industrialised world's Manufacturing Capacity.
	{"name": "Factory",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Steel": 40_000, "Concrete": 30_000, "Microchip": 2_000, "energy": 60_000},
		"production": {},
		"mc_capacity": 80_000.0},

	# Data Center — GPU server racks + liquid cooling.  20 c/s.
	# Dominated by microchips; steel racks, copper interconnect, plastic housings.
	{"name": "Data Center",
		"allowed_types": ["rocky"],
		"cost": {"Microchip": 3_000, "Steel": 3_000, "Cu": 2_000, "Plastic": 1_000, "energy": 50_000},
		"production": {"compute": 20.0}},

	# Colony Dome — titanium pressure hull + life support + ISRU systems.
	{"name": "Colony Dome",
		"allowed_types": ["rocky"],
		"cost": {"Ti": 18_000, "Glass": 15_000, "Steel": 12_000, "energy": 80_000},
		"production": {}},

	# ── Tier 3 ────────────────────────────────────────────────────────────────
	# Fusion Reactor — superconducting tokamak farm + ceramic blanket.  1.5 TW —
	# the endgame power source, an order of magnitude past any fossil or fission plant.
	{"name": "Fusion Reactor",
		"allowed_types": ["rocky"],
		"cost": {"Steel": 2_300_000, "Ceramic": 650_000, "Superconductor": 50_000, "energy": 200_000},
		"production": {"energy": 1.5e12}},   # 1.5 TW (1.5e12 × 2.0e-6 = 3.0e6 g)

	# Automated Factory — lights-out robotic plant.  ~8× a Factory; the densest source
	# of Manufacturing Capacity, and where the automation research lane really pays off
	# (it lifts the labour ceiling that otherwise caps how much industry a population runs).
	{"name": "Automated Factory",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Steel": 200_000, "Microchip": 30_000, "Plastic": 10_000, "energy": 300_000},
		"production": {},
		"mc_capacity": 600_000.0},

	# Orbital Laser — a star-scale directed-energy weapon ringing the world it's built on.
	# It can discharge the whole energy reserve in a single shot; firing it at another
	# planet devastates the target — but channelling that much power through the array
	# back-stresses the home star, ageing Sol toward its death (see Game.fire_orbital_laser).
	{"name": "Orbital Laser",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Superconductor": 200_000, "Steel": 300_000, "Microchip": 50_000, "energy": 500_000},
		"production": {}},

	# AI Research Hub — warehouse-scale GPU cluster + immersion cooling.  80 c/s.
	{"name": "AI Research Hub",
		"allowed_types": ["rocky"],
		"cost": {"Microchip": 20_000, "Steel": 12_000, "Cu": 10_000, "Plastic": 5_000, "energy": 250_000},
		"production": {"compute": 80.0}},

	# ── Megastructure infrastructure ──────────────────────────────────────────
	# Space Elevator — a tether from the surface to beyond geostationary altitude.
	# The tether is a carbon-nanotube composite; superconducting climbers; steel anchor.
	{"name": "Space Elevator",
		"allowed_types": ["rocky"],
		"cost": {"CarbonComposite": 40_000_000, "Steel": 15_000_000, "Superconductor": 1_000_000, "energy": 30_000_000},
		"production": {"energy": 2.0e10},   # 20 GW (a side benefit; its real value is launch discounts)
		# Multipliers applied to launches originating from a body that has one.
		"launch_cost_mult":     0.35,   # −65% mineral & energy cost to orbit
		"launch_duration_mult": 0.80},  # −20% transit/insertion time

	# ── Storage ───────────────────────────────────────────────────────────────
	# Orbital Vault — sealed aluminium vault domes; 10× the Matter Depot (matter only).
	{"name": "Orbital Vault",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Steel": 100_000, "Al": 50_000, "energy": 100_000},
		"production": {},
		"storage": {"minerals": 10_000_000.0}},

	# Orbital Battery — orbital battery farm; 10× the Battery Bank (energy only).
	{"name": "Orbital Battery",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Steel": 80_000, "Al": 40_000, "Battery": 30_000, "energy": 100_000},
		"production": {},
		"storage": {"energy": 10_000_000.0}},

	# Superconducting Storage Ring (SMES) — current circulating forever in a chilled
	# superconducting loop.  The densest energy store: 50× a Battery Bank, but gated by
	# superconducting research and built from costly superconductor.
	{"name": "Superconducting Storage Ring",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Superconductor": 40_000, "Steel": 60_000, "energy": 150_000},
		"production": {},
		"storage": {"energy": 50_000_000.0}},
]
