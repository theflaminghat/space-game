class_name GameEvents

## Category palette — used for notification card borders.
const CATEGORY_COLORS: Dictionary = {
	"civilization": Color(0.85, 0.55, 0.10),
	"science":      Color(0.20, 0.60, 0.90),
	"technology":   Color(0.20, 0.80, 0.40),
	"space":        Color(0.65, 0.30, 0.90),
	"warning":      Color(0.90, 0.20, 0.20),
}

## Copy is written in the instrument voice (see VOICE.md): factual, neutral, no
## editorialising.  The text states what happened and the measured result; the player
## supplies any meaning.  Do not add adjectives of dread or grandeur here.

## trigger_type values:
##   "year"          – fires once when game year >= trigger_value (int)
##   "population"    – fires once when population >= trigger_value (float)
##   "colony_count"  – fires once when colony_count >= trigger_value (int)
##   "compute"       – fires once when compute_rate >= trigger_value (float)
##   "orbit_mission" – fires when any orbit mission completes
##   "mission_mars"  – fires when a mission to Mars completes
##   "mission_outer" – fires when a mission to an outer planet completes

const EVENTS: Array = [
	{
		"id":            "cold_war",
		"title":         "Cold War",
		"desc":          "Two states emerge from the Second World War as dominant powers. Their military, scientific, and ideological competition defines the period.",
		"category":      "civilization",
		"trigger_type":  "year",
		"trigger_value": 1947,
	},
	{
		"id":            "television_age",
		"title":         "Mass Broadcast Media",
		"desc":          "Television reaches hundreds of millions of households. Information now propagates faster than physical transport.",
		"category":      "technology",
		"trigger_type":  "year",
		"trigger_value": 1955,
	},
	{
		"id":            "nuclear_energy",
		"title":         "Commercial Fission Power",
		"desc":          "The first commercial nuclear reactors enter service. Grid-scale fission power is available, with containment and long-term waste requirements.",
		"category":      "technology",
		"trigger_type":  "year",
		"trigger_value": 1960,
	},
	{
		"id":            "new_millennium",
		"title":         "21st Century",
		"desc":          "The calendar enters the 21st century. Global digital networks are operational; population and life expectancy are at record highs.",
		"category":      "civilization",
		"trigger_type":  "year",
		"trigger_value": 2000,
	},
	{
		"id":            "first_orbit",
		"title":         "Orbital Spaceflight",
		"desc":          "A spacecraft has reached orbit. A human-made object is sustained beyond the atmosphere for the first time.",
		"category":      "space",
		"trigger_type":  "orbit_mission",
		"trigger_value": 0,
	},
	{
		"id":            "mars_reached",
		"title":         "Mars Arrival",
		"desc":          "A mission has reached Mars. The fourth planet is within operational range.",
		"category":      "space",
		"trigger_type":  "mission_mars",
		"trigger_value": 0,
	},
	{
		"id":            "outer_system",
		"title":         "Outer System Arrival",
		"desc":          "A mission has crossed the asteroid belt and reached a gas giant.",
		"category":      "space",
		"trigger_type":  "mission_outer",
		"trigger_value": 0,
	},
	{
		"id":            "first_colony",
		"title":         "Off-World Settlement",
		"desc":          "A permanent settlement is established beyond Earth. Inhabited worlds: 2.",
		"category":      "civilization",
		"trigger_type":  "colony_count",
		"trigger_value": 1,
	},
	{
		"id":            "three_colonies",
		"title":         "Three Worlds Settled",
		"desc":          "Three worlds now sustain independent populations.",
		"category":      "civilization",
		"trigger_type":  "colony_count",
		"trigger_value": 3,
	},
	{
		"id":            "ten_billion",
		"title":         "Ten Billion",
		"desc":          "Earth's population reaches 1.0×10^10.",
		"category":      "civilization",
		"trigger_type":  "population",
		"trigger_value": 10_000_000_000.0,
	},
	{
		"id":            "trillion_souls",
		"title":         "One Trillion",
		"desc":          "Total population across all settled worlds reaches 1.0×10^12.",
		"category":      "civilization",
		"trigger_type":  "population",
		"trigger_value": 1_000_000_000_000.0,
	},
	{
		"id":            "cognitive_horizon",
		"title":         "Compute Threshold",
		"desc":          "Combined biological and machine computation reaches 1.0×10^22 operations per second.",
		"category":      "science",
		"trigger_type":  "compute",
		"trigger_value": 1.0e22,
	},
	{
		"id":            "solar_warning",
		"title":         "Main-Sequence Departure",
		"desc":          "Spectroscopy confirms Sol has left the main sequence. Projected envelope expansion reaches 1.0 AU in approximately 1,000,000 years.",
		"category":      "warning",
		"trigger_type":  "year",
		"trigger_value": 7_589_000_000,
	},
]
