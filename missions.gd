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
	# Heavy-lift carrier that ferries a batch of Solar Satellites to the Sun.  Only
	# valid with the Sun as target; the satellites are an extra payload on top of the
	# rocket + fuel cost.
	{"name": "Solar Deployment", "rockets": 6, "fuel": 80,
		"payload": "SolarSatellite", "payload_per_launch": 12, "sun_only": true},
]

# Selectable propellants.  The player chooses one per launch; its `accel` (m/s²) drives
# the brachistochrone transit time, and `id` is the compound (from recipes.gd) that is
# consumed.  Higher-acceleration fuels are gated behind propulsion research and are far
# costlier to manufacture, so speed is paid for in precious fuel.
const FUELS := [
	{"id": "Propellant", "name": "Chemical Propellant", "accel": 1.0e-2, "requires": "early_rocketry"},
	{"id": "FusionFuel", "name": "Fusion Fuel",         "accel": 1.0,    "requires": "fusion_engineering"},
	{"id": "Antimatter", "name": "Antimatter",          "accel": 5.0e1,  "requires": "antimatter_handling"},
]

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
