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
	"earth", "mercury", "venus", "mars", "asteroid_belt", "jupiter", "saturn", "uranus", "neptune",
]

## Per-planet stock of every compound (uncapped).  Raised from 1e12 once the swarm became a
## stellar-scale project: one collector array alone costs 1e13 g of SolarSatellite, so the old
## "huge" figure could not buy a single piece of the thing this save exists to test.
const HUGE_MATTER:   float = 1.0e18
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
	# 40 of these asked for ~350 billion workers even fully automated, pinning STAFFING at 6 %
	# for the whole save.  That was survivable when low staffing only slowed manufacturing; now
	# that food runs on the same workforce it starved every world.  Eight is what this
	# population can actually run.
	"Automated Factory":              8,   # manufacturing capacity
	# Power.  20 of these ran the industry fine but could not light a tenth of the food: a world
	# of ten billion spends ~1e12 units/day growing what it eats, which dwarfs everything else
	# on this list put together.
	"Fusion Reactor":             1_900,   # power
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
		"population":         EARTH_POP,
		"world_pop":          _world_pop(),
		"people_ever_lived":  8.5e10,
		"production_jobs":    _food_jobs(),
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
## The roster is saved as COUNTS, matching Game._buildings_to_counts() -- the loadout is already
## a name->count map, so there is no reason to expand it into thousands of repeated strings just
## to have the loader tally them straight back up.
## Population per world.  Earth sits at its carrying capacity; the colonies stay small, because
## feeding people under lamps costs ~12 GW per million (see the Algae Culture recipe) and no
## amount of sandbox generosity changes that arithmetic.
const EARTH_POP:  float = 1.0e10
const COLONY_POP: float = 1.0e6

static func _buildings() -> Dictionary:
	var out: Dictionary = {}
	for w: String in WORLDS:
		var r: Dictionary = PLANET_LOADOUT.duplicate()
		# Agriculture is sized per world rather than issued uniformly: a world of ten billion
		# needs an Earth's worth of ground, and one of a million needs a few sealed bays.
		if w == "earth":
			r["Farm"] = 12_500
			r["Ranch"] = 1_300
		else:
			r["Hydroponics Bay"] = 20
		# The belt gets only what can stand there (no Space Elevator, no Biomass Burner): unlike the
		# planets' loadout, the build panel hides everything else on it, so it could never be
		# managed or demolished.
		if w == "asteroid_belt":
			for bname: String in r.keys():
				if not _allowed_in_belt(bname):
					r.erase(bname)
		out[w] = r
	return out

static func _allowed_in_belt(bname: String) -> bool:
	for b: Dictionary in BuildingData.BUILDINGS:
		if str(b["name"]) == bname:
			return (b.get("allowed_types", []) as Array).has("belt")
	return false

## Every world runs a food slate sized to feed it with room to spare.  Earth grows the full
## diet on open ground; everywhere else runs algae under lamps, which is what a world with no
## sky can actually do.
static func _world_pop() -> Dictionary:
	var out: Dictionary = {}
	for w: String in WORLDS:
		out[w] = EARTH_POP if w == "earth" else COLONY_POP
	return out

static func _food_jobs() -> Array:
	var jobs: Array = []
	var id: int = 1
	for w: String in WORLDS:
		var pop: float = EARTH_POP if w == "earth" else COLONY_POP
		var need: float = pop * 2000.0 * 1.35        # 35 % headroom
		if w == "earth":
			for spec: Array in [["Wheat Cultivation", 0.58], ["Rice Cultivation", 0.29],
					["Vegetable Cultivation", 0.19], ["Poultry Farming", 0.016],
					["Aquaculture", 0.013], ["Swine Husbandry", 0.008],
					["Cattle Raising", 0.002]]:
				jobs.append({"id": id, "recipe": str(spec[0]), "planet": w,
					"rate": need * float(spec[1])})
				id += 1
		else:
			jobs.append({"id": id, "recipe": "Algae Culture", "planet": w, "rate": need})
			id += 1
	return jobs

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
