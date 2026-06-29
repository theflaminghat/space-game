class_name SandboxSave

## Generates a "sandbox" save: everything researched, massive stockpiles of every
## material and energy, and every world colonised in 1945.  Built through the same
## save schema Game.save_game writes (see Game.load_game), so loading it is identical
## to loading any normal save — no special-case code anywhere else.
##
## The node list comes from ResearchTreeData.build() (the authoritative source) rather
## than the live ResearchTree, so this works even from the start menu before any game
## has populated the tree.

const SAVE_PATH: String = "user://saves/sandbox_1945.json"
const SLOT_NAME: String = "sandbox_1945"

## Every world colonised at game start.  Earth is home (not in colonized_planets) but
## still gets a 1945 lineage epoch like the rest.
const WORLDS: Array = [
	"earth", "mercury", "venus", "mars", "jupiter", "saturn", "uranus", "neptune",
]

const HUGE_MATTER:   float = 1.0e12   # per-planet stock of every compound (uncapped)
const HUGE_SCIENCE:  float = 1.0e15   # science is uncapped
const HUGE_ENERGY:   float = 5.0e9    # kept under the storage cap the loadout provides
const HUGE_MINERALS: float = 1.0e9    # ditto

## Buildings placed on every world.  The storage counts are sized so the energy/mineral
## caps comfortably exceed HUGE_ENERGY/HUGE_MINERALS (else the load clamp would shave
## them back); the rest give big production + manufacturing capacity to play with.
## (allowed_types isn't enforced on load, so the same loadout works on gas giants too.)
const PLANET_LOADOUT: Dictionary = {
	"Superconducting Storage Ring": 100,   # 100 × 5e7 = 5e9 energy cap per world
	"Orbital Vault":                100,   # 100 × 1e7 = 1e9 matter cap per world
	"Automated Factory":             40,   # manufacturing capacity
	"Fusion Reactor":                20,   # power
	"Automated Mine":                40,   # raw extraction
	"AI Research Hub":               10,   # compute / science
	"Colony Dome":                    1,
	"Space Elevator":                 1,
	"Biomass Burner":                 1,   # min_count soft-lock guard
}

## Write the sandbox save to disk (creating user://saves/ if needed).
static func write(path: String = SAVE_PATH) -> void:
	var dir := DirAccess.open("user://")
	if dir != null and not dir.dir_exists("saves"):
		dir.make_dir("saves")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("SandboxSave: could not open %s for writing" % path)
		return
	file.store_string(JSON.stringify(build(), "\t"))
	file.close()

## Build the full save dictionary (same schema as Game.save_game).
static func build() -> Dictionary:
	return {
		"research":           _research_state(),
		"year":               1945,
		"month":              0,
		"day":                0,
		"population":         2_300_000_000.0,
		"people_ever_lived":  8.5e10,
		"production_jobs":    [],
		"automation_rules":   [],
		"planet_buildings":   _buildings(),
		"resources":          _global_resources(),
		"active_launches":    [],
		"next_launch_id":     1,
		"solar_satellites_deployed": 0,
		"colonized_planets":  _colonized_planets(),
		"colonized_year":     _per_world_int(1945),
		"split_thresholds":   _per_world_int(750_000),
		"colony_parent":      _colony_parents(),
		"variant_parent":     {},
		"surveyed_planets":   WORLDS.duplicate(),
		"policies":           PoliticsData.default_state(),
		"stats_history":      {},
		"compound_inventory": _inventory(),
		"atmospheric_co2":    {},
		"fired_events":       [],
		"fired_event_years":  {},
		"next_impact_year":   1995,
		"next_pandemic_year": 1995,
		"next_nuclear_year":  1995,
		"arms_strain":        0.0,
	}

# ── Section builders ──────────────────────────────────────────────────────────

## Every research node UNLOCKED + complete, with the huge resource pools folded in
## (Game.load_game then overrides resources from the top-level "resources" entry).
static func _research_state() -> Dictionary:
	var node_states: Dictionary = {}
	for n: ResearchNode in ResearchTreeData.build():
		node_states[n.id] = {"state": ResearchNode.State.UNLOCKED, "progress": 1.0}
	return {
		"nodes":           node_states,
		"resources":       _global_resources(),
		"active_research": "",
		"research_queue":  [],
	}

static func _global_resources() -> Dictionary:
	return {"science": HUGE_SCIENCE, "energy": HUGE_ENERGY, "minerals": HUGE_MINERALS}

## { world → [building names…] } with the full loadout on every world.
static func _buildings() -> Dictionary:
	var out: Dictionary = {}
	for w: String in WORLDS:
		var list: Array = []
		for bname: String in PLANET_LOADOUT:
			for _i in range(int(PLANET_LOADOUT[bname])):
				list.append(bname)
		out[w] = list
	return out

## Massive amounts of every known compound on every world.
static func _inventory() -> Dictionary:
	var compounds: Array = _all_compounds()
	var out: Dictionary = {}
	for w: String in WORLDS:
		var inv: Dictionary = {}
		for c: String in compounds:
			inv[c] = HUGE_MATTER
		out[w] = inv
	return out

## Every compound that can appear: recipe inputs/outputs plus crust/atmosphere ores,
## minus the global pools (energy/science/minerals) which live in "resources".
static func _all_compounds() -> Array:
	var set: Dictionary = {}
	for r: Dictionary in RecipeData.RECIPES:
		for k: String in (r.get("inputs", {}) as Dictionary):
			set[k] = true
		for k: String in (r.get("outputs", {}) as Dictionary):
			set[k] = true
	for pname: String in PlanetData.PLANETS:
		var comp: Dictionary = (PlanetData.PLANETS[pname] as Dictionary).get("composition_g", {})
		for layer: String in comp:
			for c: String in (comp[layer] as Dictionary):
				set[c] = true
	for skip: String in ["energy", "science", "minerals"]:
		set.erase(skip)
	return set.keys()

## Colonised worlds = everything except Earth (home).
static func _colonized_planets() -> Array:
	var out: Array = []
	for w: String in WORLDS:
		if w != "earth":
			out.append(w)
	return out

static func _colony_parents() -> Dictionary:
	var out: Dictionary = {}
	for w: String in WORLDS:
		if w != "earth":
			out[w] = "earth"
	return out

static func _per_world_int(value: int) -> Dictionary:
	var out: Dictionary = {}
	for w: String in WORLDS:
		out[w] = value
	return out
