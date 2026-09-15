extends Node

var current_save_path: String = ""
var should_load_on_start: bool = false

## Choices made on the setup screen, read once by Game.start_new_game.  Kept as a plain
## dictionary with defaults filled in on read, so a run started by any other path (the sandbox,
## a direct scene load, an older build) behaves exactly as it did before this screen existed.
var setup: Dictionary = {}

## The options offered, in the order they are shown.  Each is a list of choices; every choice
## carries the multiplier or count the simulation actually uses, so nothing here is decorative.
const OPTIONS: Array = [
	{
		"id": "neighbours",
		"label": "Neighbours",
		"help": "How many other civilisations share the nearby stars, and how many of those are hostile.",
		"choices": [
			{"name": "Alone",    "desc": "Civilisations within reach: 0.",              "total": 0, "hostile": 0},
			{"name": "Sparse",   "desc": "Civilisations within reach: 4. Hostile: 1.",  "total": 4, "hostile": 1},
			{"name": "Standard", "desc": "Civilisations within reach: 6. Hostile: 3.",  "total": 6, "hostile": 3},
			{"name": "Crowded",  "desc": "Civilisations within reach: 10. Hostile: 7.", "total": 10, "hostile": 7},
		],
	},
	{
		"id": "hostility",
		"label": "Hostility",
		"help": "How readily an aggressive civilisation decides to fire on you.",
		"choices": [
			{"name": "Wary",       "desc": "Hostile strike rate: 0.35× baseline.",           "mult": 0.35},
			{"name": "Standard",   "desc": "Hostile strike rate: 1.0× baseline (default).", "mult": 1.0},
			{"name": "Relentless", "desc": "Hostile strike rate: 2.5× baseline.",            "mult": 2.5},
		],
	},
	{
		"id": "climate",
		"label": "Climate",
		"help": "How much of Earth's carrying capacity a given quantity of CO2 takes away.",
		"choices": [
			# Figures are Game.CO2_K_HALF (2.0e19 g) × mult.
			{"name": "Resilient", "desc": "Atmospheric CO₂ that halves Earth's carrying capacity: 8.0×10¹⁹ g.",           "mult": 4.0},
			{"name": "Standard",  "desc": "Atmospheric CO₂ that halves Earth's carrying capacity: 2.0×10¹⁹ g (default).", "mult": 1.0},
			{"name": "Fragile",   "desc": "Atmospheric CO₂ that halves Earth's carrying capacity: 7.0×10¹⁸ g.",           "mult": 0.35},
		],
	},
	{
		"id": "doctrine",
		"label": "Opening doctrine",
		"help": "The standing rule for answering contact. Changeable later in the Automation panel.",
		"choices": [],   # filled from DoctrineData by options()
	},
]

var _options: Array = []

## OPTIONS with the doctrine choices filled in from DoctrineData, so the two can never drift.
## Read this, not OPTIONS: a constant array is read-only in Godot, so the list can't be completed
## in place — the setup screen used to try, failed, and showed no doctrine choice at all.
func options() -> Array:
	if _options.is_empty():
		_options = OPTIONS.duplicate(true)
		for opt: Dictionary in _options:
			if str(opt["id"]) != "doctrine":
				continue
			var list: Array = []
			for d: Dictionary in DoctrineData.DOCTRINES:
				list.append({"name": str(d["name"]), "desc": str(d["desc"]),
					"doctrine": str(d["id"]),
					"default": str(d["id"]) == DoctrineData.DEFAULT_ID})
			opt["choices"] = list
	return _options

## Value of `id` for this run, or the default when the screen was skipped.
func choice(id: String) -> Dictionary:
	for opt: Dictionary in options():
		if str(opt["id"]) != id:
			continue
		var list: Array = opt["choices"]
		if list.is_empty():
			return {}
		var idx: int = int(setup.get(id, _default_index(id)))
		return list[clampi(idx, 0, list.size() - 1)]
	return {}

## Index selected by default: the entry flagged "default", else the "Standard" one, else the first.
func _default_index(id: String) -> int:
	for opt: Dictionary in options():
		if str(opt["id"]) != id:
			continue
		var list: Array = opt["choices"]
		for i in range(list.size()):
			if bool((list[i] as Dictionary).get("default", false)):
				return i
		for i in range(list.size()):
			if str((list[i] as Dictionary).get("name", "")) == "Standard":
				return i
		return 0
	return 0
