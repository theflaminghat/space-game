extends SceneTree

## Whether a colony is still yours, and when you find out that it is not.
##
## A colony four hundred light-years out cannot be governed: every order describes a
## four-hundred-year-old situation and every answer is four hundred years old on arrival. So
## loyalty drifts with DISTANCE, faster when its people have been spliced into something Earth
## is not, and a consignment arriving is the one thing that pushes back.
##
## And the same light-lag applies to the news. The map goes on showing a colony that stopped
## being yours centuries ago, because that is still the last thing anybody heard.
##
## What has to hold:
##   distance sets the rate, and an in-system world does not drift at all
##   divergence multiplies it
##   supply reverses it
##   secession is immediate in the simulation and LATE in the readout
##   a seceded colony is a foreign state, and its lineage goes with it
##   the post survives a save

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(20261025)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var AD = load("res://allegiance.gd")
	var SD = load("res://stock_data.gd")


	# ── The rules, before any colony exists ──
	check(AD.drift_per_year(0.0, 0.0) == 0.0,
		"an in-system world is not governed by radio and does not drift")
	var near: float = AD.drift_per_year(10.0, 0.0)
	var far: float = AD.drift_per_year(500.0, 0.0)
	check(far > near, "distance sets the rate: %s vs %s" % [str(far), str(near)])
	check(absf(far / near - 50.0) < 1.0e-6, "in exact proportion to it")
	check(AD.drift_per_year(100.0, 1.0) > AD.drift_per_year(100.0, 0.0),
		"and divergence multiplies it")
	check(absf(AD.drift_per_year(100.0, 1.0)
			/ AD.drift_per_year(100.0, 0.0) - (1.0 + AD.DIVERGENCE_WEIGHT)) < 1.0e-6,
		"by exactly DIVERGENCE_WEIGHT at full divergence")
	# A nearby colony is effectively permanent; a distant one is not.
	var yrs_10: float = 1.0 / AD.drift_per_year(10.0, 0.0)
	var yrs_1000: float = 1.0 / AD.drift_per_year(1000.0, 0.0)
	check(yrs_10 > 100000.0, "ten light-years holds for ages: %.0f yr" % yrs_10)
	check(yrs_1000 < 5000.0, "a thousand does not: %.0f yr" % yrs_1000)
	# Supply pushes back, and nothing goes past the ends.
	check(AD.supplied(0.5) > 0.5, "a consignment restores loyalty")
	check(AD.supplied(1.0) == 1.0, "and never past loyal")
	check(AD.drifted(0.0, 1000.0, 1.0, 1.0e9) == 0.0, "nor below open secession")

	# Divergence is the symmetric difference over the union.
	check(AD.divergence([], []) == 0.0, "two unedited populations are the same people")
	check(AD.divergence(["longevity"], ["longevity"]) == 0.0, "so are two identical ones")
	check(AD.divergence(["longevity"], []) == 1.0, "one edit against none is total")
	check(absf(AD.divergence(["a", "longevity"], ["longevity"]) - 0.5) < 1.0e-6,
		"and one shared out of two is a half: %s"
			% str(AD.divergence(["a", "longevity"], ["longevity"])))


	# ── A colony drifts, and a supplied one does not ──
	var w: String = "Alpha Centauri A"
	g.colonized_stars.append(w)
	g._col_star_set[w] = true
	g._colony_year[w] = g.year
	g.world_pop[w] = 1.0e6
	g._world_stock[w] = SD.found("standard", [], SD.baseline())
	g._advance_allegiance(1.0)
	check(g.colony_loyalty.has(w), "a colony gets a loyalty figure on its first visit")
	check(float(g.colony_loyalty[w]) > 0.99, "and starts loyal: %s" % str(g.colony_loyalty[w]))
	var dist: float = g._star_distance_ly(w)
	check(dist > 1.0, "it is a real distance away: %.2f ly" % dist)
	g._advance_allegiance(50000.0)
	var after_drift: float = float(g.colony_loyalty[w])
	check(after_drift < 1.0, "fifty thousand years of silence costs it: %s" % str(after_drift))
	g._supply_allegiance(w)
	check(float(g.colony_loyalty[w]) > after_drift,
		"and a consignment wins some back: %s" % str(g.colony_loyalty[w]))
	# A diverged colony drifts faster than an identical one at the same distance.
	var w2: String = "Barnard's Star"
	g.colonized_stars.append(w2)
	g._col_star_set[w2] = true
	g._colony_year[w2] = g.year
	g.world_pop[w2] = 1.0e6
	g._world_stock[w2] = SD.found("standard", ["longevity", "high_intelligence"], SD.baseline())
	g.colony_loyalty[w] = 1.0
	g.colony_loyalty[w2] = 1.0
	check(g._colony_divergence(w2) > g._colony_divergence(w),
		"the spliced colony is the diverged one: %s vs %s" % [
			str(g._colony_divergence(w2)), str(g._colony_divergence(w))])


	# ── Secession: immediate in the simulation, late in the readout ──
	# This is the whole point of the pair. The colony is gone the moment it goes; the map does
	# not find out until the light gets here.
	var far_star: String = ""
	for s in g.colonized_stars:
		if g._star_distance_ly(str(s)) > 2.0:
			far_star = str(s)
	check(far_star != "", "there is a colony at a distance to test with")
	var fd: float = g._star_distance_ly(far_star)
	# Let its post settle into a steady state first, so the report in hand is a real one.
	for _i in range(40):
		g._advance_allegiance(fd * 0.5)
	var held_before: int = g.colonized_stars.size()
	var believed_before: int = g.believed_colonies().size()
	check(believed_before == held_before,
		"nothing is believed that is not also true yet: %d vs %d" % [
			believed_before, held_before])

	g.colony_loyalty[far_star] = 0.0
	g._advance_allegiance(1.0)
	check(not g.colonized_stars.has(far_star), "at zero it declares, and stops being ours")
	check(g._seceded.has(far_star), "which the simulation records")
	check(not g.world_pop.has(far_star), "its people are not our people")
	check(not g._world_stock.has(far_star),
		"and its lineage goes with it — traits and all")
	# The player does not know.
	check(g.believed_colonies().has(far_star),
		"but the map still shows it as ours: %s" % str(g.believed_colonies().has(far_star)))
	var rep: Dictionary = g.colony_report(far_star)
	check(not bool(rep.get("gone", false)),
		"the report in hand does not say it is gone: %s" % str(rep))
	check(g._player_colony_intel().has(far_star),
		"and the readout still lists it")
	# It is a foreign state now, whether or not we have heard.
	check(g.star_factions.has(far_star), "it is a civilisation in its own right")
	var who: Dictionary = g.faction_of(far_star)
	check(str(who.get("race_name", "")) == AD.HUMAN_RACE,
		"of our own species: %s" % str(who.get("race_name", "")))
	check(str(who.get("name", "")) != "", "with a name of its own: %s" % str(who.get("name", "")))

	# The news crosses at light speed, and then the map agrees with the world.
	g.year += int(ceil(fd)) + 1
	g._tick_colony_news(far_star, fd, 0.0, true)
	var rep2: Dictionary = g.colony_report(far_star)
	check(bool(rep2.get("gone", false)),
		"when the light arrives the report says it is gone: %s" % str(rep2))
	check(not g.believed_colonies().has(far_star),
		"and the map stops showing it")
	check(g.believed_colonies().size() < believed_before,
		"the civilisation is smaller than it thought: %d vs %d" % [
			g.believed_colonies().size(), believed_before])


	# ── What is reported is dated, and the date is shown ──
	var live: String = ""
	for s in g.colonized_stars:
		if g._star_distance_ly(str(s)) > 2.0:
			live = str(s)
	if live != "":
		var ld: float = g._star_distance_ly(live)
		for _i in range(30):
			g._advance_allegiance(ld * 0.5)
		var lr: Dictionary = g.colony_report(live)
		check(float(lr.get("age", 0.0)) > 0.0,
			"a report has an age: %s yr" % str(lr.get("age")))
		check(float(lr.get("age", 0.0)) >= ld * 0.9,
			"of at least the light crossing: %s vs %s ly" % [str(lr.get("age")), str(ld)])
		check(str(lr.get("text", "")).find("ago") >= 0,
			"and says so in words: %s" % str(lr.get("text")))
		# Infrastructure is observed as it WAS, not as it is.
		var now_infra: Dictionary = g._colony_infra_at(live)
		var seen_infra: Dictionary = g._colony_infra_at(live, float(g.year) - ld)
		check(float(seen_infra["dyson"]) <= float(now_infra["dyson"]),
			"a colony is seen less built than it is: %s vs %s" % [
				str(seen_infra["dyson"]), str(now_infra["dyson"])])


	# ── It survives a save ──
	g.save_game("user://saves/allegiance.json")
	var want_loy: Dictionary = g.colony_loyalty.duplicate(true)
	var want_sec: Array = g._seceded.keys()
	g.colony_loyalty = {}
	g._seceded = {}
	g._colony_news = {}
	g.load_game("user://saves/allegiance.json")
	for k: String in want_loy:
		check(g.colony_loyalty.has(k), "loyalty survives for %s" % k)
		if g.colony_loyalty.has(k):
			check(absf(float(g.colony_loyalty[k]) - float(want_loy[k])) < 1.0e-6,
				"to the figure: %s vs %s" % [str(g.colony_loyalty[k]), str(want_loy[k])])
	for k: String in want_sec:
		check(g._seceded.has(k), "and so does a declaration: %s" % k)
	check(not g._colony_news.is_empty(), "the post comes back too")
	# A mangled record is dropped, and silence is read as "nothing is believed" rather than
	# as "still ours" — a broken file must not invent a colony.
	var f := FileAccess.open("user://saves/allegiance.json", FileAccess.READ)
	var raw: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	raw["colony_news"] = {"Nowhere": "not a record"}
	var f2 := FileAccess.open("user://saves/allegiance_bad.json", FileAccess.WRITE)
	f2.store_string(JSON.stringify(raw))
	f2.close()
	g.load_game("user://saves/allegiance_bad.json")
	check(not g._colony_news.has("Nowhere"), "a record that does not parse is dropped")
	check(not g.believed_colonies().has("Nowhere"), "and no ghost is invented from it")

	print("FAILS: %d" % fails)
	quit()
