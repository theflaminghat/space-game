class_name MissionData

# Costs are the *baseline* for a bare surface-to-orbit launch (difficulty factor
# 1.0); LaunchPanel multiplies them by the destination's Hohmann Δv difficulty, so
# an interplanetary transfer to Mars or Neptune costs proportionally more.
#
#   minerals (g)  ≈ launch-vehicle wet mass — propellant + structure expended.
#   energy   (J)  ≈ the energy that mass-to-orbit demands (capacitor/grid draw).
#
# Magnitudes are scaled to the game economy but the *ratios* mirror reality: a
# colony ship is a Starship-class vehicle (~thousands of tonnes), a survey probe
# rides a small launcher, and a research probe / supply run sit in between.
const MISSION_TYPES := [
	# Small interplanetary probe on a medium launcher.
	{"name": "Survey",         "cost": {"minerals":    20_000, "energy":    30_000}},
	# Robotic prospecting hardware + lander — heavy-lift class.
	{"name": "Mining Ops",     "cost": {"minerals":   200_000, "energy":   250_000}},
	# Crewed habitat + life support + ISRU — super-heavy, by far the largest.
	{"name": "Colony Ship",    "cost": {"minerals": 1_500_000, "energy": 2_500_000}},
	# Instrument-laden science probe.
	{"name": "Research Probe", "cost": {"minerals":    25_000, "energy":    45_000}},
	# Cargo resupply to an established colony.
	{"name": "Supply Run",     "cost": {"minerals":    80_000, "energy":    90_000}},
	# Heavy-lift carrier that ferries a batch of manufactured Solar Satellites to the
	# Sun and releases them into the Dyson swarm.  Only valid with the Sun as target;
	# the cost here is the carrier vehicle — the satellites themselves are consumed
	# from the origin planet's stockpile (payload_per_launch per flight).
	{"name": "Solar Deployment", "cost": {"minerals": 150_000, "energy": 200_000},
		"payload": "SolarSatellite", "payload_per_launch": 12, "sun_only": true},
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
