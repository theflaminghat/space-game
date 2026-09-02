class_name MissionData

# Launches now cost ROCKETS (the vehicle mass) plus FUEL (a propellant the player
# picks).  The chosen fuel's `accel` sets the transfer acceleration — and therefore
# the transit time via the brachistochrone — and that fuel is what gets consumed.
#
#   rockets  – base number of Rocket units (the launch vehicle) for a bare local
#              orbit insertion; scales up with the destination's Δv difficulty.
#   fuel     – base units of the selected propellant; scales with Δv difficulty and
#              the launch-window quality.
#
# Magnitudes mirror reality's ratios: a colony ship is a fleet of heavy-lift
# vehicles, a survey probe rides a single small rocket.
## One "Rocket" unit is a real launch vehicle, not an abstract token: ~500 t of stage hardware,
## tankage and structure — Falcon-9 through Saturn-V class.  Mission "rockets" counts VEHICLES;
## this converts the count into the grams of Rocket actually drawn from the origin's inventory.
## Grams of payload one deployable unit costs.  Without this a "satellite" cost a single gram,
## which made the largest structure a civilisation can build cheaper than a rivet.
const PAYLOAD_MASS_PER_UNIT: float = 1.0e13

const ROCKET_UNIT_MASS_G: float = 5.0e8

## Energy a launch campaign expends per gram of vehicle put on a trajectory.  Low Earth orbit
## costs ~33 MJ per kg of specific orbital energy; a real stack burns several times that once
## gravity losses, drag and staging inefficiency are counted, so ~44 kJ/g.  Interplanetary
## injections cost more again — the Δv difficulty and window factors scale this up.
const LAUNCH_ENERGY_PER_GRAM: float = 4.4e4

const MISSION_TYPES := [
	# Small interplanetary probe on a single rocket.
	{"name": "Survey",          "rockets": 1,  "fuel": 8},
	# Robotic prospecting hardware + lander — heavy-lift class.
	{"name": "Mining Ops",      "rockets": 6,  "fuel": 80},
	# Crewed habitat + life support + ISRU — by far the largest.
	{"name": "Colony Ship",     "rockets": 30, "fuel": 500},
	# Instrument-laden science probe.
	{"name": "Research Probe",  "rockets": 2,  "fuel": 16},
	# Cargo resupply to an established colony.
	{"name": "Supply Run",      "rockets": 4,  "fuel": 50},
	# Carrier that ferries one collector array to the Sun and slots it into the swarm.  Only
	# valid with the Sun as target, and one array per launch, so the swarm is built out a piece
	# at a time — 1 409 launches for a complete ring.
	#
	# What is launched is a SEED, not the finished article: PAYLOAD_MASS_PER_UNIT grams of
	# self-replicating machinery that arrives, mines the inner system, and grows itself into a
	# shell segment of ~2e10 collectors (Game.SWARM_COLLECTORS_PER_PANEL).  That is the only way
	# a megastructure is ever built, and it is why the launched mass is merely industrial while
	# the deployed area is stellar.
	{"name": "Solar Deployment", "rockets": 2, "fuel": 20,
		"payload": "SolarSatellite", "payload_per_launch": 1, "sun_only": true},
]

# Selectable propellants.  The player chooses one per launch; its `accel` (m/s²) drives
# the brachistochrone transit time, and `id` is the compound (from recipes.gd) that is
# consumed.  Higher-acceleration fuels are gated behind propulsion research and are far
# costlier to manufacture, so speed is paid for in precious fuel.
## "energy_density" is the usable energy a gram of the propellant delivers to the vehicle (J/g).
## A launch consumes exactly the mass needed to supply its energy requirement — nothing else is
## expended — so this is what makes an advanced propellant transformative rather than merely
## faster: the same trajectory that burns thousands of tonnes of chemical fuel takes grams of
## fusion fuel.  Values are real: LOX/RP-1 ≈ 10 MJ/kg, D-T fusion ≈ 340 TJ/kg, antimatter
## annihilation ≈ 90 PJ/kg after realistic capture losses.
const FUELS := [
	{"id": "Propellant", "name": "Chemical Propellant", "accel": 1.0e-2, "energy_density": 1.0e4,  "requires": "early_rocketry"},
	{"id": "He3",        "name": "Helium-3",            "accel": 1.0,    "energy_density": 3.4e11, "requires": "fusion_engineering"},
	{"id": "Antimatter", "name": "Antimatter",          "accel": 5.0e1,  "energy_density": 9.0e13, "requires": "antimatter_handling"},
]

## Usable energy per gram for a fuel id (0 when unknown).
static func fuel_energy_density(fuel_id: String) -> float:
	for f: Dictionary in FUELS:
		if str(f["id"]) == fuel_id:
			return float(f.get("energy_density", 0.0))
	return 0.0

const START_OFFSETS := [
	{"label": "Now",       "days": 0},
	{"label": "+1 Month",  "days": 30},
	{"label": "+3 Months", "days": 90},
	{"label": "+6 Months", "days": 180},
	{"label": "+1 Year",   "days": 365},
]

const DURATIONS := [
	{"label": "30 days",  "days": 30},
	{"label": "90 days",  "days": 90},
	{"label": "180 days", "days": 180},
	{"label": "1 year",   "days": 365},
	{"label": "2 years",  "days": 730},
	{"label": "5 years",  "days": 1825},
]
