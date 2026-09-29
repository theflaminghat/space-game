class_name SaveSchema
extends RefCounted

## The save file's field list, in one place, walked in both directions.
##
## save_game() used to write about seventy keys by hand and load_game() to read them back by hand
## three hundred lines away, with nothing connecting the two.  A field added to one and forgotten
## in the other failed silently: the value was written every save, never read, and the only
## symptom was a setting that quietly reverted.  That is not hypothetical — star_mirror_coverage
## did exactly this, and a reloaded Shkadov thruster simply stopped working.
##
## So every field is declared once here, and both directions are generated from the declaration.
## A field that is not in this table is not saved, and one that is here is necessarily read back,
## because the same row does both jobs.
##
## FIELDS that need more than a value copied — a migration, a fallback for older saves, a UI
## rebuild — are still written out by hand in Game.gd.  They are listed here anyway, with
## `custom = true`, so that the table stays a complete inventory of the file and the coverage
## test can hold Game.gd to it.

# ── Codecs ────────────────────────────────────────────────────────────────────
# JSON has no types worth the name: every number comes back as a float and every container as an
# untyped Dictionary or Array.  These say what a field is, so the value that goes back into the
# game is the type the game expects rather than whatever the parser felt like.
enum {
	INT,          ## a whole number
	FLOAT,        ## a real
	BOOL,
	STR,
	VEC3,         ## stored as [x, y, z]
	RAW_DICT,     ## a Dictionary taken as it comes
	RAW_ARRAY,    ## an Array taken as it comes
	DICT_FLOAT,   ## { key -> float }
	DICT_INT,     ## { key -> int }
	DICT_STR,     ## { key -> String }
	DICT_TRUE,    ## a set: every key present maps to true
	DICT_DICT,    ## { key -> Dictionary }, each one duplicated
	ARRAY_DICT,   ## [ Dictionary, ... ], each one duplicated
	ARRAY_STR,    ## [ String, ... ]
	NESTED_FLOAT, ## { key -> { key -> float } }, empty inner dicts dropped
}

## Where a field lives.  Anything not named here is a property of the Game node.
const ON_GAME: String = "game"
const ON_SOLAR: String = "solar"

## A default of this means "the year we have just loaded" — several clocks start from it.
const DEFAULT_YEAR: String = "@year"

## The current save format.  Nothing reads it yet: every field carries its own default, so an
## older file simply loads with those.  It exists so that the day a field has to CHANGE meaning
## rather than merely appear, there is something to branch on — which per-field defaults alone
## could never express.
const VERSION: int = 1


## One row per key in the save file.
##
##   key     the name in the JSON
##   prop    the property it lives in, when that differs from the key
##   on      ON_SOLAR for the star's own state; Game otherwise
##   kind    the codec above
##   default what an older save without the key gets
##   custom  true when Game.gd handles it by hand; listed here for the inventory only
const FIELDS: Array[Dictionary] = [
	# ── The clock.  First, because several defaults below are "the loaded year". ──
	{"key": "year",  "kind": INT, "default": 2026},
	{"key": "month", "kind": INT, "default": 0},
	{"key": "day",   "kind": INT, "default": 0},

	# ── The star ──
	# Mass and the lifted running total are custom: mass goes through set_star_mass(), and the
	# total is merged with maxf() because it carries slivers the mass is too coarse to hold.
	{"key": "star_mass_msun",     "custom": true},
	{"key": "star_lifted_msun",   "custom": true},
	{"key": "star_age_offset",    "on": ON_SOLAR, "prop": "star_age_offset_years",
		"kind": FLOAT, "default": 0.0},
	{"key": "star_drift_ly",      "on": ON_SOLAR, "kind": VEC3, "default": null},
	{"key": "star_velocity_ms",   "on": ON_SOLAR, "kind": FLOAT, "default": 0.0},
	{"key": "star_thrust_dir",    "on": ON_SOLAR, "kind": VEC3, "default": null},
	{"key": "star_thrust_target", "on": ON_SOLAR, "kind": STR, "default": ""},

	# ── The galaxy and the run's setup ──
	# The seed is custom: every position, name and territory is derived from it, so it has to be
	# pushed into StarMapPanel before anything asks for a star.
	{"key": "galaxy_seed",      "custom": true},
	{"key": "setup_hostility",  "kind": FLOAT, "default": 1.0},
	{"key": "setup_climate",    "kind": FLOAT, "default": 1.0},
	{"key": "contact_doctrine", "custom": true},   # also pushed to the automation panel

	# ── Research, resources, industry ──
	{"key": "research",           "custom": true},   # ResearchTree owns its own format
	{"key": "resources",          "custom": true},   # merged into the live pool, not replaced
	{"key": "planet_buildings",   "custom": true},   # renames, retired buildings, soft-lock guard
	{"key": "build_queue",        "kind": RAW_DICT, "default": null},
	{"key": "active_buildings",   "kind": RAW_DICT, "default": null},
	{"key": "extraction_focus",   "kind": RAW_DICT, "default": null},
	{"key": "keep_limits",        "kind": NESTED_FLOAT, "default": null},
	{"key": "compound_inventory", "custom": true},   # flat -> per-world format migration
	{"key": "production_jobs",    "custom": true},   # lives in the production panel
	{"key": "automation_rules",   "custom": true},   # lives in the automation panel
	{"key": "policies",           "custom": true},   # retired policies are dropped
	{"key": "entropy_exported",   "kind": FLOAT, "default": 0.0},
	{"key": "atmospheric_co2",    "kind": DICT_FLOAT, "default": null},
	{"key": "solar_satellites_deployed", "custom": true},  # migrated arrays add to it

	# ── People ──
	{"key": "population",         "custom": true},   # lives in stats, and world_pop supersedes it
	{"key": "people_ever_lived",  "prop": "_people_ever_lived", "custom": true},
	{"key": "world_pop",          "custom": true},   # older saves have none; derived from colonies
	{"key": "colonized_planets",  "kind": RAW_ARRAY, "default": null},
	{"key": "colonized_stars",    "custom": true},   # followed by a resync
	{"key": "colonized_year",     "prop": "_colonized_year", "custom": true},   # back-filled
	{"key": "split_thresholds",   "prop": "_split_thresholds", "custom": true}, # back-filled
	{"key": "colony_parent",      "prop": "_colony_parent", "kind": DICT_STR, "default": null},
	{"key": "colony_year",        "prop": "_colony_year", "kind": DICT_INT, "default": null},
	{"key": "variant_parent",     "custom": true},   # replays the evolution tree into the UI
	{"key": "engulfed_planets",   "prop": "_engulfed_planets", "kind": DICT_TRUE, "default": null},

	# ── Launches and flights ──
	{"key": "active_launches",      "custom": true},  # reserved swarm slots are recounted
	{"key": "next_launch_id",       "prop": "_next_launch_id", "custom": true},
	{"key": "interstellar_missions", "kind": ARRAY_DICT, "default": null},
	{"key": "probe_missions",        "kind": ARRAY_DICT, "default": null},
	{"key": "outgoing_messages",     "kind": ARRAY_DICT, "default": null},
	{"key": "interstellar_attacks",  "kind": ARRAY_DICT, "default": null},
	{"key": "incoming_attacks",      "kind": ARRAY_DICT, "default": null},
	{"key": "comm_relays",           "kind": DICT_TRUE, "default": null},
	{"key": "vn_orders",             "prop": "_vn_orders", "kind": DICT_DICT, "default": null},
	{"key": "vn_seeds",              "custom": true},  # stored as keys; older saves fall back
	{"key": "vn_milestone_idx",      "prop": "_vn_milestone_idx", "kind": INT, "default": 0},

	# ── The frontier ──
	{"key": "regions",           "prop": "_regions", "custom": true},   # fixed record shape
	{"key": "region_last_year",  "prop": "_region_last_year", "kind": FLOAT,
		"default": DEFAULT_YEAR},
	{"key": "cluster_last_year", "prop": "_cluster_last_year", "kind": FLOAT,
		"default": DEFAULT_YEAR},
	{"key": "cluster_colonized", "kind": DICT_FLOAT, "default": null},
	{"key": "infra_probed",      "prop": "_infra_probed", "kind": DICT_TRUE, "default": null},

	# ── Neighbours ──
	{"key": "star_factions",    "custom": true},   # absent in old saves: seeded fresh
	{"key": "star_polity",      "kind": DICT_STR, "default": null},
	{"key": "factions",         "prop": "_factions", "kind": RAW_DICT, "default": null},
	{"key": "races",            "prop": "_races", "kind": RAW_DICT, "default": null},
	{"key": "known_alignments", "prop": "_known_alignments", "kind": DICT_TRUE, "default": null},
	{"key": "alien_since",      "prop": "_alien_since", "custom": true},   # derived when absent
	{"key": "detected_aliens",  "prop": "_detected_aliens", "kind": DICT_TRUE, "default": null},
	{"key": "alien_fired",      "prop": "_alien_fired", "custom": true},   # fixed record shape
	{"key": "alien_last_year",  "prop": "_alien_last_year", "kind": FLOAT,
		"default": DEFAULT_YEAR},
	{"key": "deterrent_active", "prop": "_deterrent_active", "kind": BOOL, "default": false},
	{"key": "diplo_status",     "prop": "_diplo_status", "kind": DICT_STR, "default": null},
	{"key": "grudges",          "prop": "_grudges", "kind": DICT_INT, "default": null},

	# ── Catastrophe schedule ──
	# The three "next" years are custom: an older save with no schedule gets a fresh one rolled
	# from the year it is being loaded at, which a constant default cannot express.
	{"key": "next_impact_year",   "prop": "_next_impact_year", "custom": true},
	{"key": "next_pandemic_year", "prop": "_next_pandemic_year", "custom": true},
	{"key": "next_nuclear_year",  "prop": "_next_nuclear_year", "custom": true},
	{"key": "arms_strain",        "prop": "_arms_strain", "kind": FLOAT, "default": 0.0},

	# ── Panels that keep their own state ──
	{"key": "stats_history", "custom": true},
]


## The property a row refers to.
static func prop_of(f: Dictionary) -> String:
	return str(f.get("prop", f["key"]))


## True when Game.gd writes and reads this field by hand.
static func is_custom(f: Dictionary) -> bool:
	return bool(f.get("custom", false))


## Every key the save file is expected to contain, custom ones included.
static func all_keys() -> Array[String]:
	var out: Array[String] = []
	for f: Dictionary in FIELDS:
		out.append(str(f["key"]))
	return out


## The rows this module handles itself.
static func plain_fields() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f: Dictionary in FIELDS:
		if not is_custom(f):
			out.append(f)
	return out


## Read every plain field out of the game and into a Dictionary ready for JSON.
static func encode(game: Node, solar: Node) -> Dictionary:
	var out: Dictionary = {}
	for f: Dictionary in plain_fields():
		var src: Node = solar if str(f.get("on", ON_GAME)) == ON_SOLAR else game
		var v: Variant = src.get(prop_of(f))
		out[str(f["key"])] = _to_json(v, int(f["kind"]))
	return out


## Put every plain field back.  Rows are applied in table order, so the clock is restored before
## the clocks that default to it.
static func decode(data: Dictionary, game: Node, solar: Node) -> void:
	for f: Dictionary in plain_fields():
		var dst: Node = solar if str(f.get("on", ON_GAME)) == ON_SOLAR else game
		var key: String = str(f["key"])
		var kind: int = int(f["kind"])
		var fallback: Variant = f.get("default", null)
		if typeof(fallback) == TYPE_STRING and str(fallback) == DEFAULT_YEAR:
			fallback = float(game.year)
		dst.set(prop_of(f), _from_json(data.get(key, null), kind, fallback))


## A value on its way out to JSON.  Only the container kinds need anything doing: a Vector3 has
## no JSON form, and the rest are already numbers, strings or plain collections.
static func _to_json(v: Variant, kind: int) -> Variant:
	match kind:
		VEC3:
			var p: Vector3 = v
			return [p.x, p.y, p.z]
		_:
			return v


## A value on its way back in, forced to the type the game expects.  `fallback` is used whenever
## the key is missing or holds the wrong sort of thing — which is what lets an older save load.
static func _from_json(v: Variant, kind: int, fallback: Variant) -> Variant:
	match kind:
		INT:
			return int(v) if v != null else int(fallback)
		FLOAT:
			return float(v) if v != null else float(fallback)
		BOOL:
			return bool(v) if v != null else bool(fallback)
		STR:
			return str(v) if v != null else str(fallback)
		VEC3:
			# Three numbers or nothing: a half-written vector is no vector.
			if v is Array and (v as Array).size() == 3:
				return Vector3(float(v[0]), float(v[1]), float(v[2]))
			return Vector3.ZERO
		RAW_DICT:
			return v if v is Dictionary else {}
		RAW_ARRAY:
			return v if v is Array else []
		DICT_FLOAT:
			var df: Dictionary = {}
			if v is Dictionary:
				for k: String in v:
					df[k] = float(v[k])
			return df
		DICT_INT:
			var di: Dictionary = {}
			if v is Dictionary:
				for k: String in v:
					di[k] = int(v[k])
			return di
		DICT_STR:
			var ds: Dictionary = {}
			if v is Dictionary:
				for k: String in v:
					ds[k] = str(v[k])
			return ds
		DICT_TRUE:
			var dt: Dictionary = {}
			if v is Dictionary:
				for k: String in v:
					dt[k] = true
			return dt
		DICT_DICT:
			var dd: Dictionary = {}
			if v is Dictionary:
				for k: String in v:
					if v[k] is Dictionary:
						dd[k] = (v[k] as Dictionary).duplicate()
			return dd
		ARRAY_DICT:
			var ad: Array = []
			if v is Array:
				for e in v:
					if e is Dictionary:
						ad.append((e as Dictionary).duplicate())
			return ad
		ARRAY_STR:
			var as_: Array = []
			if v is Array:
				for e in v:
					as_.append(str(e))
			return as_
		NESTED_FLOAT:
			var nf: Dictionary = {}
			if v is Dictionary:
				for outer: String in v:
					if not (v[outer] is Dictionary):
						continue
					var inner: Dictionary = {}
					for k: String in v[outer]:
						inner[k] = float(v[outer][k])
					if not inner.is_empty():
						nf[outer] = inner
			return nf
	return fallback
