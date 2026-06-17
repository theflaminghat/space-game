class_name GameEvents

## Category palette — used for notification card borders.
const CATEGORY_COLORS: Dictionary = {
	"civilization": Color(0.85, 0.55, 0.10),
	"science":      Color(0.20, 0.60, 0.90),
	"technology":   Color(0.20, 0.80, 0.40),
	"space":        Color(0.65, 0.30, 0.90),
	"warning":      Color(0.90, 0.20, 0.20),
}

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
		"title":         "Cold War Tension",
		"desc":          "Two superpowers emerge from the ashes of World War II. The race for dominance — military, scientific, and ideological — will shape the next century.",
		"category":      "civilization",
		"trigger_type":  "year",
		"trigger_value": 1947,
	},
	{
		"id":            "television_age",
		"title":         "Television Age",
		"desc":          "Mass broadcast media connects hundreds of millions for the first time. Information — and propaganda — now spread faster than any army.",
		"category":      "technology",
		"trigger_type":  "year",
		"trigger_value": 1955,
	},
	{
		"id":            "nuclear_energy",
		"title":         "Atoms for Peace",
		"desc":          "The first commercial nuclear power plants come online, promising cheap and abundant energy alongside the spectre of meltdown and waste.",
		"category":      "technology",
		"trigger_type":  "year",
		"trigger_value": 1960,
	},
	{
		"id":            "new_millennium",
		"title":         "New Millennium",
		"desc":          "Humanity crosses into the 21st century. Digital networks weave the planet together; billions live longer, healthier lives than any generation before.",
		"category":      "civilization",
		"trigger_type":  "year",
		"trigger_value": 2000,
	},
	{
		"id":            "first_orbit",
		"title":         "First Steps Beyond Earth",
		"desc":          "A spacecraft breaks free of Earth's gravity and enters orbit. Humanity has taken its first step into the cosmos.",
		"category":      "space",
		"trigger_type":  "orbit_mission",
		"trigger_value": 0,
	},
	{
		"id":            "mars_reached",
		"title":         "Red Planet Reached",
		"desc":          "A mission arrives at Mars. The fourth planet has been touched by human ingenuity for the first time.",
		"category":      "space",
		"trigger_type":  "mission_mars",
		"trigger_value": 0,
	},
	{
		"id":            "outer_system",
		"title":         "Outer System Reached",
		"desc":          "A mission crosses the asteroid belt and reaches one of the gas giants. The outer solar system is no longer beyond reach.",
		"category":      "space",
		"trigger_type":  "mission_outer",
		"trigger_value": 0,
	},
	{
		"id":            "first_colony",
		"title":         "Second Cradle",
		"desc":          "A permanent off-world colony has been established. For the first time in history, humanity's survival is no longer tied to a single world.",
		"category":      "civilization",
		"trigger_type":  "colony_count",
		"trigger_value": 1,
	},
	{
		"id":            "three_colonies",
		"title":         "Multi-Planet Species",
		"desc":          "Three worlds now sustain human populations. Extinction by any single planetary catastrophe is no longer inevitable.",
		"category":      "civilization",
		"trigger_type":  "colony_count",
		"trigger_value": 3,
	},
	{
		"id":            "ten_billion",
		"title":         "Ten Billion",
		"desc":          "Earth's population crosses ten billion souls. Resources are stretched to their limits; new solutions — or new worlds — are desperately needed.",
		"category":      "civilization",
		"trigger_type":  "population",
		"trigger_value": 10_000_000_000.0,
	},
	{
		"id":            "trillion_souls",
		"title":         "Trillion Souls",
		"desc":          "The total human population surpasses one trillion across all inhabited worlds. An unimaginable wealth of minds alive in this expanding civilization.",
		"category":      "civilization",
		"trigger_type":  "population",
		"trigger_value": 1_000_000_000_000.0,
	},
	{
		"id":            "cognitive_horizon",
		"title":         "Cognitive Horizon",
		"desc":          "Combined human and machine computation crosses a critical threshold. Discovery now outpaces what any single mind can fully comprehend.",
		"category":      "science",
		"trigger_type":  "compute",
		"trigger_value": 1.0e22,
	},
	{
		"id":            "solar_warning",
		"title":         "The Dying Sun",
		"desc":          "Astronomers confirm the Sun has entered its red giant phase. Within a million years the inner planets will be consumed. Humanity must look to the stars.",
		"category":      "warning",
		"trigger_type":  "year",
		"trigger_value": 7_589_000_000,
	},
]
