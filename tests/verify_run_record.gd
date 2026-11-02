extends SceneTree

## The run, as a record two players can compare.
##
## ── Why peaks and not the last moment ──
##
## game_over_screen's old stats block had already worked this out and said so in a comment: the
## final population and colony count are "deliberately absent", because at the end they are both
## zero. A run that held six thousand stars for a billion years and a run that never left Earth
## finish identically, so the last moment cannot tell them apart and a summary built from it
## reports nothing.
##
## So the high-water marks are kept AS THEY HAPPEN. They cannot be recovered afterwards: the
## stats graph is downsampled, and the year a record was set is not in it.
##
## stars_at_front is the figure the whole rival-front feature exists to produce — how much of
## the galaxy was yours when somebody else's probes turned up — and it is captured when the
## front's light ARRIVES, because what you had when you found out is what you can be held to.
##
## ── Why rows are omitted ──
##
## A run that never met the front and a run that lost everything to it are different runs. A
## table of blanks reads as a form; a row appears when the thing it reports happened.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

## The record as { label -> value }, for asking about one row.
func _as_map(rows: Array) -> Dictionary:
	var out: Dictionary = {}
	for r: Array in rows:
		out[str(r[0])] = str(r[1])
	return out

func _run() -> void:
	seed(20261101)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var ss: Node = root.get_node("SolarSystem")


	# ── A fresh run reports what has happened, which is almost nothing ──
	var fresh: Dictionary = _as_map(g.run_summary())
	check(fresh.has("Span"), "a span is always reported")
	check(fresh.has("Humans who ever lived"), "and the headcount that does not reset")
	check(fresh.has("Achievements"), "and the achievement count")
	for absent: String in ["Stars held, peak", "Stars lost to secession",
			"Worlds disassembled", "Rival front seen", "Sol displaced"]:
		check(not fresh.has(absent),
			"nothing that has not happened is listed: %s" % absent)


	# ── The peaks are high-water marks, not current values ──
	g.world_pop["earth"] = 9.0e9
	g.stats["current_population"] = 9.0e9
	g._update_peaks()
	var top: float = g.peak_population
	check(top >= 9.0e9, "a peak is recorded: %s" % str(top))
	var top_year: int = g.peak_population_year
	# Now lose almost everybody. The peak must not follow it down — that is the entire point.
	g.year += 1000
	g.world_pop["earth"] = 1.0e3
	g.stats["current_population"] = 1.0e3
	g._update_peaks()
	check(absf(g.peak_population - top) < 1.0,
		"and does not fall back with the population: %s vs %s" % [str(g.peak_population), str(top)])
	check(g.peak_population_year == top_year,
		"nor does the year it was set: %d vs %d" % [g.peak_population_year, top_year])
	var m: Dictionary = _as_map(g.run_summary())
	check(m.has("Peak population"), "and it reaches the record")
	check(str(m["Peak population"]).find("(year") >= 0,
		"with the year it happened: %s" % str(m["Peak population"]))

	# Same for stars and worlds held.
	g.colonized_stars = ["A", "B", "C", "D"]
	g.colonized_planets = ["mars", "venus"]
	g._update_peaks()
	g.colonized_stars = []
	g.colonized_planets = []
	g._update_peaks()
	check(g.peak_stars == 4, "stars held is a peak too: %d" % g.peak_stars)
	check(g.peak_worlds == 2, "and worlds settled: %d" % g.peak_worlds)
	var m2: Dictionary = _as_map(g.run_summary())
	check(m2.get("Stars held, peak", "") == "4",
		"reported from the peak, not the empty present: %s" % str(m2.get("Stars held, peak")))


	# ── The front figure is captured once, when the news arrives ──
	check(g.stars_at_front == -1, "nothing is captured before the front is seen")
	g.colonized_stars = ["A", "B", "C"]
	g.front_seen = true
	g.front_year = 90000.0
	g._update_peaks()
	check(g.stars_at_front == 3, "the holding at that moment is captured: %d" % g.stars_at_front)
	# Everything after is somebody else's problem: the figure must not move again.
	g.colonized_stars = ["A", "B", "C", "D", "E", "F", "G"]
	g._update_peaks()
	check(g.stars_at_front == 3,
		"and never moves again: %d" % g.stars_at_front)
	var m3: Dictionary = _as_map(g.run_summary())
	check(m3.has("Rival front seen"), "the front is reported once seen")
	check(m3.get("Stars held when it arrived", "") == "3",
		"with what was held then: %s" % str(m3.get("Stars held when it arrived")))


	# ── It survives a save, or the record is only ever about this session ──
	# Read the peaks as they stand rather than reusing the figures from earlier: the front check
	# above raised the star peak to seven, and asserting the older four would be asserting that
	# _update_peaks had stopped working.
	var want_stars: int = g.peak_stars
	var want_front: int = g.stars_at_front
	g.save_game("user://saves/record_verify.json")
	g.peak_population = 0.0
	g.peak_population_year = 0
	g.peak_stars = 0
	g.stars_at_front = -1
	g.load_game("user://saves/record_verify.json")
	check(absf(g.peak_population - top) < 1.0,
		"the peak comes back: %s vs %s" % [str(g.peak_population), str(top)])
	check(g.peak_population_year == top_year, "with its year")
	check(g.peak_stars == want_stars,
		"and the star peak: %d vs %d" % [g.peak_stars, want_stars])
	check(g.stars_at_front == want_front,
		"and the front figure: %d vs %d" % [g.stars_at_front, want_front])
	DirAccess.remove_absolute("user://saves/record_verify.json")


	# ── The voice ──
	# VOICE.md: the game reports, it does not narrate. A summary that told the player what their
	# run amounted to would be making the conclusion for them.
	var text: String = g.run_summary_text()
	check(text.find("Span") >= 0, "the text form carries the record")
	for banned: String in ["doomed", "fragile", "inevitable", "cradle", "ashes", "nothing remains",
			"you ", "your "]:
		check(text.to_lower().find(banned) < 0,
			"and no editorial or second person: found '%s'" % banned)
	# Units, not bare magnitudes.
	g.year = 4210000000
	var t2: String = g.run_summary_text()
	check(t2.find("Gyr") >= 0 or t2.find("Myr") >= 0,
		"a deep-time year carries its unit: %s" % t2.split("\n")[1])
	g.year = 2001


	# ── Both views render it ──
	var page = g.sidebar.achievements_page
	check(page != null, "the records page exists")
	page.show()
	g._push_achievements()
	for _i in range(3): await process_frame
	check(page._record != null and page._record.get_child_count() > 0,
		"and shows the record during the run, not only after losing it")
	check(page._record_text.find("Span") >= 0, "with a copyable form")
	# Two cells per row.
	check(page._record.get_child_count() == g.run_summary().size() * 2,
		"one label and one value per row: %d cells for %d rows" % [
			page._record.get_child_count(), g.run_summary().size()])

	var over = g.game_over_screen
	check(over != null, "the ending screen exists")
	over.show_game_over("Test", "A test ending.", g.year, g.stats, 1.0e11,
		g.run_summary(), g.run_summary_text())
	for _i in range(2): await process_frame
	check(over._record_grid != null and over._record_grid.get_child_count() > 0,
		"the ending renders the same record")
	check(over._summary_text.find("Span") >= 0, "and can copy it")

	print("FAILS: %d" % fails)
	quit()
