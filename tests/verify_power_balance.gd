extends SceneTree

## Power plants trade what they cost to build against what they burn.
##
## ── What was wrong ──
##
## Every plant cost the same ~2.0e-6 g per watt to build.  The Solar Farm needed no research,
## burned nothing, emitted nothing and could stand on rock, a gas giant or the belt, and it
## collected as much over Jupiter as over Earth — so at the same build cost it was strictly
## better than coal, oil, gas, nuclear and fusion while the Sun shone, and the Biomass Burner,
## fuel-free at a coal plant's price, was strictly better than coal and oil.  A plant that loses
## on every axis is not a choice.
##
## And the Battery Bank was steel and copper, and stored less per tonne than the Flywheel Array
## unlocked beside it.
##
## ── What is asserted ──
##
## BUILD COST. Per watt of a level-1 bill (energy left out: it is not a material), every plant
## that burns fuel is at least twice as cheap to build as the Solar Farm; among them nuclear,
## which burns almost nothing, is the dearest and fusion, whose fuel is the hard part, the
## cheapest; and the Biomass Burner, which can never be lost, is the dearest of all, so it is a
## floor and not a cheap way round coal.
##
## DISTANCE. A Solar Farm collects by the inverse square of its world's distance from the Sun,
## measured off the grid rather than the formula: the same ten farms on Mercury, Mars, in the
## belt and over Jupiter against Earth.  A moon is lit as its planet.  Earth's farms make what
## they always did, so a 1945 grid is untouched.
##
## THE BATTERY BANK. Built from sodium-ion cells, and opened by the research that makes them.
## (Where it stands among the other stores is verify_building_ladders.)

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

const PLANTS: Array = ["Biomass Burner", "Solar Farm", "Nuclear Plant", "Coal Plant", "Oil Plant",
	"Natural Gas Burner", "Fusion Reactor"]
const FUELLED: Array = ["Nuclear Plant", "Coal Plant", "Oil Plant", "Natural Gas Burner", "Fusion Reactor"]
## Sunlight against Earth's, from the semi-major axes: (1 / a)².
const LIGHT: Dictionary = {
	"mercury": 6.674, "mars": 0.4307, "asteroid_belt": 0.1306, "jupiter": 0.03694,
}
const FARMS: int = 10

func _watts_per_gram(BD, name: String) -> float:
	var b: Dictionary = BD.find(name)
	check(not b.is_empty(), "%s is in the catalogue" % name)
	var g: float = 0.0
	var cost: Dictionary = b.get("cost", {})
	for k: String in cost:
		if k != "energy":
			g += float(cost[k])
	return float((b.get("production", {}) as Dictionary).get("energy", 0.0)) / maxf(g, 1.0)

func _run() -> void:
	seed(20261114)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(40): await process_frame
	var g: Node = current_scene
	var BD = load("res://buildings.gd")

	# ── Build cost against fuel ──
	var wpg: Dictionary = {}
	for p: String in PLANTS:
		wpg[p] = _watts_per_gram(BD, p)
	for p: String in FUELLED:
		check(not (BD.find(p).get("consumption", {}) as Dictionary).is_empty(), "%s burns something" % p)
		# (Nuclear is exactly twice, so the bound allows for rounding.)
		check(float(wpg[p]) >= 2.0 * float(wpg["Solar Farm"]) * (1.0 - 1e-9),
			"%s builds at least twice the Solar Farm's watts per gram: %.2f vs %.2f W/g"
				% [p, float(wpg[p]), float(wpg["Solar Farm"])])
	for p: String in ["Coal Plant", "Oil Plant", "Natural Gas Burner"]:
		check(float(wpg["Nuclear Plant"]) < float(wpg[p]),
			"nuclear, which burns almost nothing, costs more to build per watt than %s" % p)
	for p: String in PLANTS:
		if p != "Fusion Reactor":
			check(float(wpg["Fusion Reactor"]) > float(wpg[p]),
				"fusion is the cheapest per watt to build, cheaper than %s" % p)
		if p != "Biomass Burner":
			check(float(wpg["Biomass Burner"]) < float(wpg[p]),
				"the Biomass Burner is the dearest per watt to build, dearer than %s" % p)

	# ── Sunlight falls with distance ──
	check(is_equal_approx(g._insolation_at("earth"), 1.0), "Earth is lit as it always was: %s" % g._insolation_at("earth"))
	check(is_equal_approx(g._insolation_at("earth_moon_0"), 1.0), "and so is its moon")
	check(is_equal_approx(g._insolation_at("jupiter_moon_0"), g._insolation_at("jupiter")),
		"a moon is lit as its planet")
	var worlds: Array = ["earth", "jupiter_moon_0"] + LIGHT.keys()
	for w: String in worlds:
		var roster: Array = []
		for _k in range(FARMS):
			roster.append("Solar Farm")
		g.planet_buildings[w] = roster
	g.active_buildings.clear()
	g._prod_planet.clear()
	g._mark_prod_dirty()
	g._recompute_production_cache()
	var rated: float = float((BD.find("Solar Farm")["production"] as Dictionary)["energy"])
	var ss: Node = root.get_node("SolarSystem")
	var sun: float = ss.sun_luminosity_lsun(float(g.year)) * ss.insolation_mult()
	var at_earth: float = g._planet_power("earth")
	check(is_equal_approx(at_earth, FARMS * rated * sun),
		"ten farms on Earth make ten farms' rating times the Sun: %s vs %s"
			% [Units.format_si(at_earth, "W"), Units.format_si(FARMS * rated * sun, "W")])
	for w: String in LIGHT:
		var r: float = g._planet_power(w) / maxf(at_earth, 1.0)
		check(absf(r - float(LIGHT[w])) <= 0.01 * float(LIGHT[w]),
			"ten farms on %s make %.4f of Earth's: %.4f" % [w, float(LIGHT[w]), r])
	var moon_r: float = g._planet_power("jupiter_moon_0") / maxf(at_earth, 1.0)
	check(absf(moon_r - float(LIGHT["jupiter"])) <= 0.01 * float(LIGHT["jupiter"]),
		"and on a moon of Jupiter what they make over Jupiter: %.4f" % moon_r)

	# ── The Battery Bank ──
	var bank: Dictionary = BD.find("Battery Bank")
	check((bank.get("cost", {}) as Dictionary).has("Battery"), "the Battery Bank is built from cells: %s" % str(bank.get("cost")))
	var node: String = str(load("res://unlocks.gd").BUILDING_UNLOCK_REQUIREMENTS.get("Battery Bank", ""))
	var cells: String = ""
	for r: Dictionary in load("res://recipes.gd").RECIPES:
		if (r.get("outputs", {}) as Dictionary).has("Battery"):
			cells = str(r.get("requires", ""))
	check(cells != "" and node == cells,
		"and opens with the research that makes them: %s vs %s" % [node, cells])

	print("FAILS: %d" % fails)
	quit()
