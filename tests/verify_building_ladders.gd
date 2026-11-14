extends SceneTree

## A later building is worth more per tonne than the one it follows.
##
## ── What was wrong ──
##
## Compute, detection, energy storage and radiating capacity are civilisation-wide pools, and
## no world limits how much stands on it, so where a building may stand almost never matters.
## What is left to choose on is output per tonne of the bill, and on that several buildings had
## nothing going for them: the Orbital Compute Core computed less per tonne than the Data Center
## a tier before it, the Radio Telescope Array less than the Observatory unlocked with it, the
## Space Telescope less than both, the Orbital Battery less than a starting Flywheel Array, the
## Factory no more than the Workshop it needs chips to beat, the Orbital Construction Station
## half the Automated Factory, and the Orbital Habitat a hundredth of a Colony Dome.  A
## dominated building is worse than none: it spends a row of the build list on a decision that
## has already been made elsewhere.
##
## ── What is asserted ──
##
## LADDERS. Each entry is a building, the one it follows, the output they share and the factor
## the later one must beat the earlier by, per gram of its level-1 bill (energy left out: it is
## not a material).  Where a ladder has a rung above, the building also stays under it.
##
## The Orbital Habitat is the exception that is meant to be one: it may lose to the Colony Dome,
## which needs ground, but by no more than twenty to one, because over a gas giant and in solar
## orbit it is the only housing there is.
##
## The compute anchor in buildings.gd is checked against the numbers it describes.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

var BD = load("res://buildings.gd")

## [later, earlier, output, at least this many times the earlier per gram]
const LADDERS: Array = [
	["Orbital Compute Core",   "Data Center",           "compute",        2.0],
	["Radio Telescope Array",  "Observatory",           "detection",      1.5],
	["Space Telescope",        "Radio Telescope Array", "detection",      1.5],
	["Orbital Battery",        "Flywheel Array",        "storage_energy", 2.0],
	["Factory",                "Workshop",              "mc_capacity",    1.5],
	["Orbital Construction Station", "Automated Factory", "mc_capacity",  1.5],
]
## [building, the rung above it, output]
const CEILINGS: Array = [
	["Orbital Battery", "Superconducting Storage Ring", "storage_energy"],
]

func _bill_grams(b: Dictionary) -> float:
	var g: float = 0.0
	var cost: Dictionary = b.get("cost", {})
	for k: String in cost:
		if k != "energy":
			g += float(cost[k])
	return g

func _output(b: Dictionary, what: String) -> float:
	match what:
		"compute":        return float((b.get("production", {}) as Dictionary).get("compute", 0.0))
		"storage_energy": return float((b.get("storage", {}) as Dictionary).get("energy", 0.0))
		_:                return float(b.get(what, 0.0))

func _per_gram(name: String, what: String) -> float:
	var b: Dictionary = BD.find(name)
	check(not b.is_empty(), "%s is in the catalogue" % name)
	if b.is_empty():
		return 0.0
	var g: float = _bill_grams(b)
	var out: float = _output(b, what)
	check(out > 0.0, "%s has some %s" % [name, what])
	return out / maxf(g, 1.0)

func _run() -> void:
	for l: Array in LADDERS:
		var hi: float = _per_gram(str(l[0]), str(l[2]))
		var lo: float = _per_gram(str(l[1]), str(l[2]))
		var r: float = hi / maxf(lo, 1e-300)
		check(r >= float(l[3]), "%s beats %s per gram on %s by at least %.1fx: %.2fx"
			% [l[0], l[1], l[2], float(l[3]), r])
	for c: Array in CEILINGS:
		var below: float = _per_gram(str(c[0]), str(c[2]))
		var above: float = _per_gram(str(c[1]), str(c[2]))
		check(below < above, "%s stays under %s per gram on %s: %.3g vs %.3g"
			% [c[0], c[1], c[2], below, above])

	# The habitat may lose to the dome on ground, but not by a hundred to one.
	var hab: float = _per_gram("Orbital Habitat", "habitat")
	var dome: float = _per_gram("Colony Dome", "habitat")
	check(hab < dome, "the Colony Dome still houses more per gram where there is ground")
	check(hab * 20.0 >= dome, "the Orbital Habitat is within twenty to one of the dome: 1 to %.0f"
		% (dome / maxf(hab, 1e-300)))

	# The anchor in buildings.gd: twenty-two cores against ten billion people is about 0.9x.
	var core: float = _output(BD.find("Orbital Compute Core"), "compute")
	var people: float = 1.0e10 * float(load("res://EvolutionTreeData.gd").COMPUTE_PER_INDIVIDUAL)
	var ratio: float = 22.0 * core / people
	check(ratio > 0.8 and ratio < 1.0, "twenty-two cores think about 0.9x what ten billion people do: %.2fx" % ratio)

	print("FAILS: %d" % fails)
	quit()
