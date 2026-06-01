class_name TimelineEvents

## Category palette – used by TimelineCanvas for card borders and connector dots.
const CATEGORY_COLORS: Dictionary = {
	"civilization": Color(0.85, 0.55, 0.10),
	"science":      Color(0.20, 0.60, 0.90),
	"technology":   Color(0.20, 0.80, 0.40),
	"space":        Color(0.65, 0.30, 0.90),
}

## Chronological list of landmark events shown on the timeline.
const EVENTS: Array = [
	{
		"year":     1945,
		"title":    "First Atomic Bomb",
		"desc":     "Trinity test detonates the first nuclear device. The Atomic Age begins — and with it, humanity's first true civilisational crossroads.",
		"category": "technology",
	},
	{
		"year":     1957,
		"title":    "Sputnik 1",
		"desc":     "USSR launches Earth's first artificial satellite, opening the Space Age.",
		"category": "space",
	},
	{
		"year":     1961,
		"title":    "First Human in Space",
		"desc":     "Yuri Gagarin completes one orbit aboard Vostok 1 on 12 April.",
		"category": "space",
	},
	{
		"year":     1969,
		"title":    "Moon Landing",
		"desc":     "Apollo 11 lands on the Moon; Armstrong and Aldrin walk its surface.",
		"category": "space",
	},
	{
		"year":     1975,
		"title":    "Microprocessor Era",
		"desc":     "Intel 8080 enables personal computing; the digital revolution begins.",
		"category": "technology",
	},
	{
		"year":     1991,
		"title":    "World Wide Web",
		"desc":     "Tim Berners-Lee opens the Web publicly, connecting humanity globally.",
		"category": "technology",
	},
	{
		"year":     1997,
		"title":    "Mars Pathfinder",
		"desc":     "Sojourner becomes the first successful Mars rover, proving robotic exploration.",
		"category": "space",
	},
	{
		"year":     2003,
		"title":    "Human Genome",
		"desc":     "Human Genome Project completes the full sequence of human DNA.",
		"category": "science",
	},
	{
		"year":     2012,
		"title":    "Higgs Boson",
		"desc":     "CERN confirms the Higgs boson at the LHC, completing the Standard Model.",
		"category": "science",
	},
	{
		"year":     2016,
		"title":    "Gravitational Waves",
		"desc":     "LIGO detects gravitational waves from merging black holes for the first time.",
		"category": "science",
	},
	{
		"year":     2021,
		"title":    "James Webb Launch",
		"desc":     "JWST launched on Christmas Day, offering unprecedented views of the early universe.",
		"category": "space",
	},
]
