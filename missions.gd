class_name MissionData

const MISSION_TYPES := [
	{"name": "Survey",         "cost": {"minerals": 50,  "energy": 20}},
	{"name": "Mining Ops",     "cost": {"minerals": 100, "energy": 40}},
	{"name": "Colony Ship",    "cost": {"minerals": 500, "energy": 200}},
	{"name": "Research Probe", "cost": {"minerals": 80,  "energy": 30}},
	{"name": "Supply Run",     "cost": {"minerals": 30,  "energy": 15}},
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
