class_name BuildingData

## Real-world calibration basis (all numbers scaled to game units):
##   Game unit: minerals = grams (g), energy cost = Joules (J), power = Watts (W),
##              compute = FLOP/s (c/s in shorthand below)
##
## Reference anchor — Solar Farm:
##   Real-world utility PV ≈ $1 000/kW installed → 200 W per module at this scale.
##   Silicon panel mass ≈ 5 kg for 200 W → 5 000 g.
##   Fabrication energy ≈ 5 MJ/kW → 1 000 J for 200 W → 5 000 J stored cost.
##   → 25 g/W  and  25 J/W  (reference ratios used for all power plants below)
##
## Power plant mineral cost per watt vs solar reference:
##   Solar   25 g/W  (1×)     Oil    22 g/W  (0.88×)   Coal   78 g/W  (3.1×)
##   Nuclear 250 g/W (10×)    Fusion 625 g/W (25×)     Orbital 2500 g/W (100×)
##
## Power plant energy cost per watt vs solar reference:
##   Solar   25 J/W  (1×)     Oil    18 J/W  (0.72×)   Coal   42 J/W  (1.7×)
##   Nuclear 125 J/W (5×)     Fusion 313 J/W (12.5×)   Orbital 1667 J/W (66.7×)

const BUILDINGS := [
	# ── Always available ──────────────────────────────────────────────────────
	# Solar Farm — utility PV array, 200 W per module.
	# Real: ~$1 000/kW, panel mass ~5 kg/kW, fab energy ~5 MJ/kW.
	{"name": "Solar Farm",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"minerals": 5_000, "energy": 5_000},
		"production": {"energy": 200.0}},

	# Mine — small surface excavator (~12 kg of steel structure).
	# Extracts ~50 g/s of raw ore at low power draw.
	{"name": "Mine",
		"allowed_types": ["rocky"],
		"cost": {"minerals": 12_000, "energy": 1_500},
		"production": {"minerals": 50.0}},

	# Coal Plant — fire-tube boiler + condensing steam turbine.
	# Real: ~$2 800/kW capital cost → 3.1× solar per watt.  1 800 W output.
	{"name": "Coal Plant",
		"allowed_types": ["rocky"],
		"cost": {"minerals": 140_000, "energy": 75_000},
		"production": {"energy": 1_800.0}},

	# Oil Plant — gas-turbine combined-cycle.
	# Real: ~$900/kW capital cost → 0.88× solar per watt (cheapest per W).  2 500 W output.
	{"name": "Oil Plant",
		"allowed_types": ["rocky"],
		"cost": {"minerals": 55_000, "energy": 45_000},
		"production": {"energy": 2_500.0}},

	# ── Tier 1 (research-gated) ───────────────────────────────────────────────
	# Nuclear Plant — PWR + concrete containment + steam turbines.
	# Real: ~$10 000/kW capital cost → 10× solar per watt.  8 000 W output.
	{"name": "Nuclear Plant",
		"allowed_types": ["rocky"],
		"cost": {"minerals": 2_000_000, "energy": 1_000_000},
		"production": {"energy": 8_000.0}},

	# Research Lab — precision instruments + clean-room optics.
	# Energy cost dominated by electron-beam and vacuum equipment.
	{"name": "Research Lab",
		"allowed_types": ["rocky"],
		"cost": {"minerals": 8_000, "energy": 20_000},
		"production": {"compute": 10.0}},

	# ── Tier 2 ────────────────────────────────────────────────────────────────
	# Automated Mine — robotic excavators + conveyor systems (10× basic mine).
	# 500 g/s extraction at much higher capital cost.
	{"name": "Automated Mine",
		"allowed_types": ["rocky"],
		"cost": {"minerals": 60_000, "energy": 25_000},
		"production": {"minerals": 500.0}},

	# Compute Core — GPU server rack + liquid cooling.
	# Silicon chip fab ≈ 1 GJ/kg → energy cost dominates.  20 c/s.
	{"name": "Compute Core",
		"allowed_types": ["rocky"],
		"cost": {"minerals": 10_000, "energy": 50_000},
		"production": {"compute": 20.0}},

	# Colony Dome — titanium pressure hull + life support + ISRU systems.
	# No direct resource production; enables colonist housing.
	{"name": "Colony Dome",
		"allowed_types": ["rocky"],
		"cost": {"minerals": 50_000, "energy": 80_000},
		"production": {}},

	# ── Tier 3 ────────────────────────────────────────────────────────────────
	# Fusion Reactor — superconducting tokamak + tritium blanket.
	# Real projected DEMO-class: ~$25 000/kW → 25× solar per watt.  80 000 W output.
	{"name": "Fusion Reactor",
		"allowed_types": ["rocky"],
		"cost": {"minerals": 50_000_000, "energy": 25_000_000},
		"production": {"energy": 80_000.0}},

	# AI Research Hub — warehouse-scale GPU cluster + immersion cooling.
	# Semiconductor fab dominates energy cost.  80 c/s.
	{"name": "AI Research Hub",
		"allowed_types": ["rocky"],
		"cost": {"minerals": 50_000, "energy": 250_000},
		"production": {"compute": 80.0}},

	# ── Tier 4 — orbital / any solid body ────────────────────────────────────
	# Orbital Array — space solar power constellation.
	# Launch cost ~30 MJ/kg to LEO dominates; panel mass is modest.
	# ~100× solar mineral cost per watt.  1 200 W output.
	{"name": "Orbital Array",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"minerals": 3_000_000, "energy": 2_000_000},
		"production": {"energy": 1_200.0}},

	# ── Storage ───────────────────────────────────────────────────────────────
	# Storage Depot — pressurised mineral silos + battery banks.
	# No production; raises this planet's mineral and energy cap by 1 000 000 each.
	# Affordable early — intended as the first response to a full stockpile.
	{"name": "Storage Depot",
		"allowed_types": ["rocky"],
		"cost": {"minerals": 25_000, "energy": 15_000},
		"production": {},
		"storage": {"minerals": 1_000_000.0, "energy": 1_000_000.0}},

	# Orbital Cache — sealed vault domes + supercapacitor ring; 10× the depot.
	# Requires Automated Logistics to coordinate high-throughput orbital transfer.
	{"name": "Orbital Cache",
		"allowed_types": ["rocky", "gas_giant"],
		"cost": {"minerals": 200_000, "energy": 100_000},
		"production": {},
		"storage": {"minerals": 10_000_000.0, "energy": 10_000_000.0}},
]
