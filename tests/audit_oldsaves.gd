extends SceneTree

## Real save files written before the field table existed, loaded by the code that has it.
##
## Forward compatibility here rests entirely on per-field defaults: an older file simply has no
## entry for a field that did not exist when it was written, and gets the default.  These four
## fixtures are genuine saves from earlier in development — 29, 63 and 64 keys against today's 72,
## none of them carrying a save_version — so they exercise that for real rather than by construction.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(20260927)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(25): await process_frame
	var g: Node = current_scene
	var ss: Node = root.get_node("SolarSystem")

	for fixture: String in ["old_sandbox_1945", "old_lifttest", "old_startest", "old_phase3"]:
		var path: String = "res://tests/fixtures/%s.json" % fixture
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		check(raw is Dictionary, "%s parses" % fixture)
		if not (raw is Dictionary):
			continue
		var saved: Dictionary = raw
		check(not saved.has("save_version"), "%s predates the version stamp" % fixture)

		g.load_game(path)

		# The clock, which every other restored value is measured against.
		check(g.year == int(saved.get("year", -1)),
			"%s: the year is restored (%d vs %d)" % [fixture, g.year, int(saved.get("year", -1))])

		# Nothing came back as a broken type: these are the fields the table re-floats and
		# re-ints, and a wrong type here is a crash on the first tick rather than a bad number.
		check(g.planet_buildings is Dictionary and not g.planet_buildings.is_empty(),
			"%s: it has a building roster" % fixture)
		check(g.world_pop is Dictionary and g.world_pop.has("earth"),
			"%s: somebody lives on Earth" % fixture)
		check(g._total_population() > 0.0, "%s: the population is positive" % fixture)
		check(g.stats is Dictionary and float(g.stats.get("current_population", 0.0)) > 0.0,
			"%s: the stats agree" % fixture)

		# Fields these files are too old to contain take their defaults rather than erroring.
		check(ss.star_drift_ly is Vector3, "%s: the drift vector is a vector" % fixture)
		check(g._arms_strain >= 0.0, "%s: arms strain has a sane default" % fixture)
		check(g._region_last_year <= float(g.year) + 1.0,
			"%s: the region clock is not in the future" % fixture)
		check(g._cluster_last_year <= float(g.year) + 1.0,
			"%s: the cluster clock is not in the future" % fixture)

		# A save too old to carry any faction data gets a freshly seeded neighbourhood — and the
		# POLITIES behind it, not just the alignment words.  The old loader seeded all four and
		# then blanked three of them on the next lines, so those neighbours came back armed or
		# peaceful with no government and no species behind them.
		if not saved.has("star_factions") and not g.star_factions.is_empty():
			check(not g.star_polity.is_empty(),
				"%s: seeded neighbours have governments" % fixture)
			check(not g._factions.is_empty() and not g._races.is_empty(),
				"%s: and those governments and species are registered" % fixture)
			var unheld: Array = []
			for star: String in g.star_factions:
				if str(g.faction_of(star).get("name", "")).is_empty():
					unheld.append(star)
			check(unheld.is_empty(),
				"%s: every seeded neighbour is a named polity (%d without)" % [
					fixture, unheld.size()])

		# And the loaded state survives being run.
		ss.paused = false
		ss.ui_paused = false
		g.get_tree().paused = false
		for _i in range(20):
			ss.ui_paused = false
			await process_frame
		check(not g.game_over, "%s: it survives twenty frames of play" % fixture)
		print("%-20s %d keys, year %d, pop %s — ok" % [
			fixture, saved.size(), g.year, str(g._total_population())])
		ss.paused = true

	print("FAILS: %d" % fails)
	quit()
