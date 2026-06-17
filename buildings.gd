class_name BuildingData

## Real-world calibration basis (all numbers scaled to game units):
##   Game unit: minerals = grams (g), energy cost = Joules (J), power = Watts (W),
##              compute = FLOP/s (c/s in shorthand below)
##
## Building costs are *bills of materials*: instead of a generic "minerals" lump,
## each structure consumes the specific crafted goods it is really made of
## (produced by the manufacturing recipes in recipes.gd) plus an energy cost.
## Material masses are grams; they sum to roughly the old mineral cost so the
## overall economy stays balanced.
##
## Gating note: try_build only requires that you *hold* a material, so a building
## whose material's recipe you haven't unlocked is never impossible — it simply
## prompts you to research that recipe and craft it.  The one exception is the
## basic Mine, which must stay buildable from the very start: it uses only
## Concrete (abundant, coal-free, craftable with no research) so mine expansion
## can never dead-lock the economy.

const BUILDINGS := [
	# ── Inherited 1945 power infrastructure (given to the player at game start) ─
	# The 1945 global energy supply (~100 EJ/yr ≈ 3.169e12 W) is delivered as a
	# FLEET of regional power stations (≈126.75 GW each) rather than one giant
	# plant.  Game.start_new_game() grants 10 biomass + 10 coal + 5 oil = 25
	# stations → 1.2675e12 + 1.2675e12 + 6.3375e11 ≈ 3.169e12 W (a 40/40/20 split).
	# "buildable": false → they can't be *constructed* (no new 1945-era stations),
	# but they CAN be demolished as the player modernises — except the Biomass
	# Burner, whose "min_count": 1 keeps at least one running so energy production
	# never collapses (which would soft-lock the economy, since building anything
	# costs energy).  Fuelled by the starting mines + production jobs.
	# "co2_per_energy" = grams of CO₂ vented to the atmosphere per unit of energy
	# generated (per game-day of running).  Combustion intensities differ by fuel:
	# coal is dirtiest, oil cleanest, biomass in between.  Solar/nuclear/fusion omit
	# the field, so they emit nothing.
	{"name": "Biomass Burner",
		"buildable": false,
		"min_count": 1,
		"allowed_types": ["rocky"],
		"cost": {},
		"production": {"energy": 1.2675e11},
		"co2_per_energy": 38.0},
	{"name": "Coal Plant",
		"buildable": false,
		"allowed_types": ["rocky"],
		"cost": {},
		"production": {"energy": 1.2675e11},
		"co2_per_energy": 45.0},
	{"name": "Oil Plant",
		"buildable": false,
		"allowed_types": ["rocky"],
		"cost": {},
		"production": {"energy": 1.2675e11},
		"co2_per_energy": 32.0},

	# ── Always available ──────────────────────────────────────────────────────
	# Matter Depot — steel silos + concrete bunkers.  Raises the matter cap only.
	{"name": "Matter Depot",
		"allowed_types": ["rocky"],
		"cost": {"Steel": 16_000, "Concrete": 8_000, "energy": 15_000},
		"production": {},
		"storage": {"minerals": 1_000_000.0}},

	# Battery Bank — grid-scale capacitor + battery banks.  Raises the energy cap only.
	{"name": "Battery Bank",
		"allowed_types": ["rocky"],
		"cost": {"Steel": 10_000, "Cu": 8_000, "energy": 15_000},
		"production": {},
		"storage": {"energy": 1_000_000.0}},

	# Solar Farm — utility PV array, 200 W per module.
	# One assembled photovoltaic module (Solar Panel Assembly recipe).
	{"name": "Solar Farm",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"SolarPanel": 5_000, "energy": 5_000},
		"production": {"energy": 200.0}},

	# Mine — surface excavator on a concrete pad.  Concrete is coal-free and needs
	# no research, so the first mines are always buildable (no bootstrap lock).
	{"name": "Mine",
		"allowed_types": ["rocky"],
		"cost": {"Concrete": 10_000, "energy": 1_500},
		"production": {"minerals": 50.0}},

	# ── Tier 1 (research-gated) ───────────────────────────────────────────────
	# Nuclear Plant — PWR + containment + steam turbines.  Real reactor ≈ 1 GW.
	# Massive containment concrete, steel pressure vessel, ceramic fuel cladding.
	{"name": "Nuclear Plant",
		"allowed_types": ["rocky"],
		"cost": {"Concrete": 900_000, "Steel": 700_000, "Cu": 80_000, "Ceramic": 20_000, "energy": 1_000_000},
		"production": {"energy": 1.0e9}},

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
		"production": {"minerals": 500.0}},

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
	# Fusion Reactor — superconducting tokamak + ceramic blanket.  ≈ 2 GW electrical.
	{"name": "Fusion Reactor",
		"allowed_types": ["rocky"],
		"cost": {"Steel": 28_000_000, "Ceramic": 5_000_000, "Cu": 2_000_000, "Superconductor": 60_000, "energy": 25_000_000},
		"production": {"energy": 2.0e9}},

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
		"production": {"energy": 2.0e8},
		# Multipliers applied to launches originating from a body that has one.
		"launch_cost_mult":     0.35,   # −65% mineral & energy cost to orbit
		"launch_duration_mult": 0.80},  # −20% transit/insertion time

	# ── Tier 4 — orbital / any solid body ────────────────────────────────────
	# Orbital Array — space solar power constellation.  1 200 W output.
	# Photovoltaic panels, aluminium frame, control microchips.
	{"name": "Orbital Array",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"SolarPanel": 2_000_000, "Al": 800_000, "Microchip": 50_000, "energy": 2_000_000},
		"production": {"energy": 1_200.0}},

	# ── Storage ───────────────────────────────────────────────────────────────
	# Orbital Vault — sealed aluminium vault domes; 10× the Matter Depot (matter only).
	{"name": "Orbital Vault",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Steel": 100_000, "Al": 50_000, "energy": 100_000},
		"production": {},
		"storage": {"minerals": 10_000_000.0}},

	# Orbital Battery — superconducting storage ring; 10× the Battery Bank (energy only).
	{"name": "Orbital Battery",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"Steel": 80_000, "Al": 40_000, "Battery": 30_000, "energy": 100_000},
		"production": {},
		"storage": {"energy": 10_000_000.0}},
]
