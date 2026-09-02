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
			{"name": "Alone",    "desc": "Nobody out there. The only thing that can end you is you.", "total": 0, "hostile": 0},
			{"name": "Sparse",   "desc": "A handful of neighbours, mostly peaceful.",                 "total": 4, "hostile": 1},
			{"name": "Standard", "desc": "Six civilisations within reach; three would rather you were not here.", "total": 6, "hostile": 3},
			{"name": "Crowded",  "desc": "A busy sky, and most of it armed.",                         "total": 10, "hostile": 7},
		],
	},
	{
		"id": "hostility",
		"label": "Hostility",
		"help": "How readily an aggressive civilisation decides to fire on you.",
		"choices": [
			{"name": "Wary",       "desc": "Attacks are rare. Deterrence still matters, but slowly.", "mult": 0.35},
			{"name": "Standard",   "desc": "The default balance.",                                    "mult": 1.0},
			{"name": "Relentless", "desc": "Anything that finds you will act on it.",                 "mult": 2.5},
		],
	},
	{
		"id": "climate",
		"label": "Climate",
		"help": "How much of Earth's carrying capacity a given quantity of CO2 takes away.",
		"choices": [
			{"name": "Resilient", "desc": "The biosphere absorbs a great deal before it gives.", "mult": 4.0},
			{"name": "Standard",  "desc": "The default sensitivity.",                            "mult": 1.0},
			{"name": "Fragile",   "desc": "Emissions bite early and hard.",                      "mult": 0.35},
		],
	},
	{
		"id": "doctrine",
		"label": "Opening doctrine",
		"help": "The standing rule for answering contact. Changeable later in the Automation panel.",
		"choices": [],   # filled from DoctrineData at build time — see StartMenu
	},
]

## Value of `id` for this run, or the default when the screen was skipped.
func choice(id: String) -> Dictionary:
	for opt: Dictionary in OPTIONS:
		if str(opt["id"]) != id:
			continue
		var list: Array = opt["choices"]
		if list.is_empty():
			return {}
		var idx: int = int(setup.get(id, _default_index(id)))
		return list[clampi(idx, 0, list.size() - 1)]
	return {}

## Index selected by default: the "Standard" entry where there is one, else the first.
func _default_index(id: String) -> int:
	for opt: Dictionary in OPTIONS:
		if str(opt["id"]) != id:
			continue
		var list: Array = opt["choices"]
		for i in range(list.size()):
			if str((list[i] as Dictionary).get("name", "")) == "Standard":
				return i
		return 0
	return 0
