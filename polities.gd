class_name Polities
extends RefCounted

## Who lives out there: the species, and the states they organise themselves into.
##
## These are two different things and the game had neither — an inhabited star carried the word
## "aggressive" or "peaceful" and nothing else.  A RACE is a species: one biology, one homeworld
## region, spread across however much sky it has reached.  A FACTION is a polity: a government
## holding some stars, belonging to a race.  One race commonly has several, and they need not
## agree with each other — a peaceful Thessi compact and a hostile Thessi dominion are both
## Thessi, and the player meets them separately.
##
## Everything here is derived from position and the galaxy seed, the way the star field is: a
## volume of space always produces the same race with the same name, whoever asks and whenever.
## Nothing is stored, so nothing has to be saved, migrated, or kept in step with a star list.
##
## The nesting is what makes the two layers distinct on the map:
##   RACE_CELL_LY   — a race's whole territory, so neighbours are usually kin
##   FACTION_CELL_LY — one polity inside it, so a race's space is politically divided

## Territory sizes.  A race spans several thousand light-years; a polity a few hundred, which is
## about the scale at which light-lag makes a single government implausible anyway.
const RACE_CELL_LY: float = 4000.0
const FACTION_CELL_LY: float = 800.0

## Share of polities that are hostile.  Overridden per run by the setup screen's choice, which is
## where the player sets how armed the sky is.
const DEFAULT_HOSTILE_SHARE: float = 0.5

# ── Name construction ─────────────────────────────────────────────────────────
# Syllables rather than a fixed list: a fixed list runs out, and a galaxy is large.  The pieces
# are chosen to be pronounceable in combination and to avoid reading as human place names.
const RACE_HEAD: Array = ["Thes", "Korv", "Ily", "Vash", "Zhan", "Mor", "Ael", "Tur", "Oss",
	"Kel", "Nyx", "Sar", "Dra", "Emb", "Hal", "Vor", "Ish", "Qel", "Tan", "Ura"]
const RACE_MID: Array = ["", "", "ar", "en", "ith", "or", "ai", "ul", "esh", "ov"]
const RACE_TAIL: Array = ["si", "ani", "ek", "ir", "oth", "ua", "im", "ex", "ara", "un"]

## What a polity calls itself.  Split by temperament: the hostile forms lean to command, the
## peaceful ones to agreement — the name is the first thing the player learns about a neighbour.
const HOSTILE_FORMS: Array = [
	"%s Dominion", "%s Hegemony", "%s Ascendancy", "%s War Council", "%s Supremacy",
	"Iron %s Order", "%s Conclave of Arms"]
const PEACEFUL_FORMS: Array = [
	"%s Compact", "%s Concord", "%s Assembly", "Free Worlds of %s", "%s Commonwealth",
	"%s Covenant", "%s League"]
## Distinguishes polities of the same race, so two Thessi states do not share a name.
const ORDINALS: Array = ["", "", "Second ", "Third ", "Outer ", "Inner ", "Greater ", "Lesser ",
	"Old ", "New "]


## Cell index of a position on a grid of `size` light-years.
static func _cell(pos: Vector3, size: float) -> Vector3i:
	return Vector3i(floori(pos.x / size), floori(pos.y / size), floori(pos.z / size))


## A stable seed for a cell: its index, the grid it is on, and the run's galaxy seed.
static func _seed_for(cell: Vector3i, salt: int, galaxy_seed: int) -> int:
	var h: int = (galaxy_seed ^ salt) * 0x9E3779B1
	h = (h ^ (cell.x * 0x85EBCA6B)) * 0xC2B2AE35
	h = (h ^ (cell.y * 0x27D4EB2F)) * 0x165667B1
	h = (h ^ (cell.z * 0x2545F491)) * 0x9E3779B1
	return absi(h) & 0x7FFFFFFF


## The race whose territory contains `pos`: { id, name }.
static func race_at(pos: Vector3, galaxy_seed: int) -> Dictionary:
	var cell: Vector3i = _cell(pos, RACE_CELL_LY)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_for(cell, 0x5EED_1, galaxy_seed)
	var name: String = str(RACE_HEAD[rng.randi() % RACE_HEAD.size()]) \
		+ str(RACE_MID[rng.randi() % RACE_MID.size()]) \
		+ str(RACE_TAIL[rng.randi() % RACE_TAIL.size()])
	# The seed is part of the id, not just the name: ids are saved, and two runs of different
	# galaxies must not hand the same id to different species.
	return {"id": "race_%d_%d.%d.%d" % [galaxy_seed, cell.x, cell.y, cell.z], "name": name}


## The polity holding `pos`: { id, name, alignment, race_id, race_name }.
##
## `hostile_share` comes from the run's setup choice, so a sky the player asked to be half armed
## stays half armed wherever they travel.
## `force_aggressive` overrides the temperament the volume would otherwise get: -1 derives it,
## 0 forces peaceful, 1 forces hostile.  The setup screen fixes how many of the FIRST neighbours
## are armed, and a polity's name follows its temperament — so forcing one has to rebuild the
## name as well, or the sky fills with peaceful-sounding Covenants that shoot at you.
static func faction_at(pos: Vector3, galaxy_seed: int,
		hostile_share: float = DEFAULT_HOSTILE_SHARE, force_aggressive: int = -1) -> Dictionary:
	var race: Dictionary = race_at(pos, galaxy_seed)
	var cell: Vector3i = _cell(pos, FACTION_CELL_LY)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_for(cell, 0x5EED_2, galaxy_seed)
	var rolled: bool = rng.randf() < clampf(hostile_share, 0.0, 1.0)
	var aggressive: bool = rolled if force_aggressive < 0 else force_aggressive == 1
	var forms: Array = HOSTILE_FORMS if aggressive else PEACEFUL_FORMS
	var form: String = str(forms[rng.randi() % forms.size()])
	var ordinal: String = str(ORDINALS[rng.randi() % ORDINALS.size()])
	return {
		"id": "pol_%d_%d.%d.%d" % [galaxy_seed, cell.x, cell.y, cell.z],
		"name": ordinal + (form % str(race["name"])),
		# The word the rest of the game already speaks: star_factions holds this.
		"alignment": "aggressive" if aggressive else "peaceful",
		"race_id": str(race["id"]),
		"race_name": str(race["name"]),
	}


## A breakaway state: the same species, a government of its own.
##
## A polity that has grown past what light-lag lets one government administer does not keep
## growing — its far colonies stop taking orders.  The splinter keeps the race (biology does not
## secede) and gets its own name, its own id and its own politics, which is how a species ends up
## with a dozen mutually disagreeing states over deep time.
static func splinter_of(parent: Dictionary, pos: Vector3, galaxy_seed: int, serial: int,
		hostile_share: float = DEFAULT_HOSTILE_SHARE) -> Dictionary:
	var cell: Vector3i = _cell(pos, FACTION_CELL_LY)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_for(cell, 0x5EED_3 ^ (serial * 0x9E3779B1), galaxy_seed)
	var race_name: String = str(parent.get("race_name", "?"))
	var aggressive: bool = rng.randf() < clampf(hostile_share, 0.0, 1.0)
	var forms: Array = HOSTILE_FORMS if aggressive else PEACEFUL_FORMS
	var form: String = str(forms[rng.randi() % forms.size()])
	var ordinal: String = str(ORDINALS[rng.randi() % ORDINALS.size()])
	return {
		"id": "pol_%d_%d.%d.%d_s%d" % [galaxy_seed, cell.x, cell.y, cell.z, serial],
		"name": ordinal + (form % race_name),
		"alignment": "aggressive" if aggressive else "peaceful",
		"race_id": str(parent.get("race_id", "")),
		"race_name": race_name,
		"splinter": true,
	}


## Whether a polity's name reads as what it is.  The ordinals are prefixes, so a name always
## ENDS with one of the forms filled in with its race's name — which makes this exact rather
## than a guess at keywords.  Worth being able to assert: the name is the first thing the player
## learns about a neighbour, and it should not mislead.
static func name_matches_alignment(faction: Dictionary) -> bool:
	var name: String = str(faction.get("name", ""))
	var race: String = str(faction.get("race_name", ""))
	var aggressive: bool = str(faction.get("alignment", "")) == "aggressive"
	for form: String in (HOSTILE_FORMS if aggressive else PEACEFUL_FORMS):
		if name.ends_with(form % race):
			return true
	return false


## How a neighbour is introduced in one line: the polity and the species behind it.
static func describe(faction: Dictionary) -> String:
	if faction.is_empty():
		return ""
	return "%s (%s)" % [str(faction.get("name", "?")), str(faction.get("race_name", "?"))]
