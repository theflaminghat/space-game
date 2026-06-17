extends RefCounted
class_name EvolutionTreeData

## Dynamic, planet-lineage evolution tree.
##
## The tree always starts at a single root — 20th-century baseline humans.  As the
## game runs, each populated world (Earth plus every colony) that has sustained a
## population long enough diverges into its own lineage, "Homo sapiens <epithet>".
## A world's variant descends from whichever population it split off from: Earth's
## from the baseline, a colony's from the world it was settled from (or the baseline
## if that world had not yet diverged).  Nodes are therefore generated at runtime by
## EvolutionTreeUI rather than declared up front — see planet_variant() / baseline().
##
## compute (FLOP/s per individual): every lineage retains the ~1e17 FLOP/s neocortex
## floor; Game.gd reads the best unlocked value to convert population into a
## civilisation-wide compute rate.

const COMPUTE_PER_INDIVIDUAL: float = 1.0e17

## Species epithet for each world's long-isolated population.
const PLANET_EPITHET: Dictionary = {
	"earth":   "terran",
	"mercury": "hermian",
	"venus":   "cytherean",
	"mars":    "martian",
	"jupiter": "jovian",
	"saturn":  "kronian",
	"uranus":  "uranian",
	"neptune": "neptunian",
	"moon":    "selenian",
}

## The single baseline node every run starts with.
static func baseline() -> Dictionary:
	return {
		"name": "Homo sapiens",
		"subtitle": "Baseline humans",
		"description": "Unmodified 20th-century humans — the common ancestor from which every planetary lineage later diverges.",
		"parents": [],
		"pos": Vector2(60, 60),
		"planet": "",
		"compute": COMPUTE_PER_INDIVIDUAL,
	}

## Node id used for a world's variant.
static func variant_id(planet: String) -> String:
	return "homo_sapiens_" + planet

## Human-readable epithet for a world (falls back to the raw name).
static func epithet_for(planet: String) -> String:
	return str(PLANET_EPITHET.get(planet, planet))

## Build a planet-variant node descending from `parent_id`, placed at `pos`.
static func planet_variant(planet: String, parent_id: String, pos: Vector2) -> Dictionary:
	var epithet: String = epithet_for(planet)
	var world: String = planet.capitalize()
	return {
		"name": "H. sapiens %s" % epithet,
		"subtitle": "%s population" % world,
		"description": "The population of %s, isolated long enough to diverge into a distinct human lineage." % world,
		"parents": [parent_id],
		"pos": pos,
		"planet": planet,
		"compute": COMPUTE_PER_INDIVIDUAL,
	}
