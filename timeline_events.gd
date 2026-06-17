class_name TimelineEvents

## Category palette – used by TimelineCanvas for card borders and connector dots.
const CATEGORY_COLORS: Dictionary = {
	"civilization": Color(0.85, 0.55, 0.10),
	"science":      Color(0.20, 0.60, 0.90),
	"technology":   Color(0.20, 0.80, 0.40),
	"space":        Color(0.65, 0.30, 0.90),
}

## Landmark events shown on the historical timeline.
## Only pre-1946 history is shown here; in-game achievements appear as
## live notifications via GameEvents (events.gd).
const EVENTS: Array = [
	{
		"year":     1945,
		"title":    "First Atomic Bomb",
		"desc":     "Trinity test detonates the first nuclear device. The Atomic Age begins — and with it, humanity's first true civilisational crossroads.",
		"category": "technology",
	},
]
