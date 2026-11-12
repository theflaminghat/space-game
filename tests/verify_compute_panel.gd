extends SceneTree

## The compute panel is where the civilisation's thinking is divided: one budget per simulation
## plus the tree, and within each, the people and the machines budgeted separately.  The sliders
## have to actually drive the simulation, each row has to describe what its own budget BUYS, and
## the whole allocation has to survive a save — otherwise it is eight numbers to twiddle blindly.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _row(p, track: String) -> Dictionary:
	return (p.get("_rows") as Dictionary).get(track, {})

func _run() -> void:
	seed(20260927)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(40): await process_frame
	var g: Node = current_scene
	var rt: Node = root.get_node("ResearchTree")
	var p = g.sidebar.compute_panel
	check(p != null, "the panel exists")

	g.sidebar.hide_all()
	p.show()
	g.refresh_compute_panel()
	for _i in range(10): await process_frame

	# ── A row per track, two sliders each ──
	for t: String in g.COMPUTE_TRACKS:
		var r: Dictionary = _row(p, t)
		check(not r.is_empty(), "%s has a row" % t)
		check(r.get("human") is HSlider, "%s has a human slider" % t)
		check(r.get("ai") is HSlider, "%s has an AI slider" % t)
	check((p.get("_rows") as Dictionary).size() == g.COMPUTE_TRACKS.size(),
		"and there are no others")

	# ── Locked until the research lands ──
	check(p._locked_lbl.visible, "it says so while forecasting is unresearched")
	for t: String in g.FORECAST_TRACKS:
		check(not (_row(p, t)["human"] as HSlider).editable,
			"%s cannot be budgeted yet" % t)
		check((_row(p, t)["sight"] as Label).text.contains("locked"),
			"%s reads locked" % t)
	check((_row(p, "science")["human"] as HSlider).editable,
		"but the tree can always be budgeted")

	for n: ResearchNode in load("res://ResearchTreeData.gd").build():
		rt.force_unlock(str(n.id))
	g.refresh_compute_panel()
	for _i in range(10): await process_frame
	check(not p._locked_lbl.visible, "the notice goes once it is researched")
	for t: String in g.FORECAST_TRACKS:
		check((_row(p, t)["human"] as HSlider).editable, "%s unlocks" % t)

	# ── Each slider drives its own budget, in its own pool ──
	(_row(p, "asteroid")["human"] as HSlider).value = 50.0
	for _i in range(8): await process_frame
	check(is_equal_approx(
		float((g.compute_alloc["asteroid"] as Dictionary)["human"]), 0.5),
		"the human slider sets the human weight: %s" % str(g.compute_alloc["asteroid"]))
	check(is_equal_approx(
		float((g.compute_alloc["asteroid"] as Dictionary)["ai"]), 0.0),
		"and leaves the machine weight alone")
	(_row(p, "nuclear")["ai"] as HSlider).value = 100.0
	for _i in range(8): await process_frame
	check(is_equal_approx(float((g.compute_alloc["nuclear"] as Dictionary)["ai"]), 1.0),
		"the AI slider sets the machine weight")

	# The pools really are separate: asteroid work drawn from people, nuclear from machines.
	var sh: Dictionary = g.compute_shares()
	check(float((sh["asteroid"] as Dictionary)["human"]) > 0.0, "people are on the rocks")
	check(is_equal_approx(float((sh["asteroid"] as Dictionary)["ai"]), 0.0),
		"and no machines are")
	check(float((sh["nuclear"] as Dictionary)["ai"]) > 0.0, "machines are on the crisis")
	check(is_equal_approx(float((sh["nuclear"] as Dictionary)["human"]), 0.0),
		"and no people are")

	# ── Foresight differs per simulation, and the row says so ──
	for t: String in g.FORECAST_TRACKS:
		g.foresight_frontier[t] = float(g.year)
	for _y in range(6):
		for _d in range(365):
			g._advance_foresight(1.0)
		g.year += 1
	var h_a: float = g.forecast_horizon_years("asteroid")
	var h_n: float = g.forecast_horizon_years("nuclear")
	var h_p: float = g.forecast_horizon_years("pandemic")
	check(h_a > 0.0 and h_n > 0.0, "the two funded simulations both see something")
	check(not is_equal_approx(h_a, h_n),
		"and by different amounts: %.3f vs %.3f" % [h_a, h_n])
	check(is_equal_approx(h_p, 0.0), "the unfunded one is blind: %.3f" % h_p)

	g.refresh_compute_panel()
	for _i in range(6): await process_frame
	check((_row(p, "asteroid")["sight"] as Label).text.contains("sees"),
		"the funded row reports its sight: '%s'" % (_row(p, "asteroid")["sight"] as Label).text)
	check((_row(p, "pandemic")["sight"] as Label).text.contains("blind"),
		"the unfunded row reports none: '%s'" % (_row(p, "pandemic")["sight"] as Label).text)
	check((_row(p, "science")["sight"] as Label).text.contains("science"),
		"and the tree reports its science rate")
	check(p._human_lbl.text.contains("Human"), "the human pool total is shown")
	check(p._ai_lbl.text.contains("Machine"), "the machine pool total is shown")

	# ── The budget really is a trade ──
	g._init_compute_alloc()
	g._mark_prod_dirty()
	var science_all: float = float(g._get_total_production().get("science", 0.0))
	for pool: String in g.COMPUTE_POOLS:
		(_row(p, "asteroid")[pool] as HSlider).value = 80.0
		(_row(p, "science")[pool] as HSlider).value = 20.0
	for _i in range(8): await process_frame
	var science_most: float = float(g._get_total_production().get("science", 0.0))
	check(science_most < science_all * 0.35,
		"pointing most of it at a simulation really costs research: %s -> %s" % [
			str(science_all), str(science_most)])
	check(science_most > 0.0, "but research never stops entirely")

	# ── The whole allocation and every frontier survive a save ──
	g._init_compute_alloc()
	g._on_compute_alloc_changed("asteroid", "human", 0.37)
	g._on_compute_alloc_changed("pandemic", "ai", 0.62)
	g.foresight_frontier["nuclear"] = float(g.year) + 1234.0
	g.save_game("user://saves/computepanel.json")
	g._init_compute_alloc()
	g.load_game("user://saves/computepanel.json")
	for _i in range(6): await process_frame
	check(is_equal_approx(float((g.compute_alloc["asteroid"] as Dictionary)["human"]), 0.37),
		"the human weight is saved: %s" % str(g.compute_alloc["asteroid"]))
	check(is_equal_approx(float((g.compute_alloc["pandemic"] as Dictionary)["ai"]), 0.62),
		"and the machine weight: %s" % str(g.compute_alloc["pandemic"]))
	check(absf(g.forecast_horizon_years("nuclear") - 1234.0) < 1.0,
		"and the accumulated frontier: %.1f" % g.forecast_horizon_years("nuclear"))

	# ── An old save carrying only the single split is migrated ──
	g._init_compute_alloc()
	g.compute_forecast_share = 0.6
	g.compute_alloc = {}
	g.foresight_frontier = {}
	g._migrate_compute_alloc()
	check(g.compute_alloc.size() == g.COMPUTE_TRACKS.size(),
		"every track gets a weight")
	var sci_w: float = float((g.compute_alloc["science"] as Dictionary)["human"])
	var ast_w: float = float((g.compute_alloc["asteroid"] as Dictionary)["human"])
	check(is_equal_approx(sci_w, 0.4), "the tree keeps what it had: %s" % str(sci_w))
	check(is_equal_approx(ast_w, 0.2),
		"and the old forecast share is spread over the simulations: %s" % str(ast_w))
	check(g.foresight_frontier.size() == g.FORECAST_TRACKS.size(),
		"and every simulation gets a frontier")
	for t: String in g.FORECAST_TRACKS:
		check(float(g.foresight_frontier[t]) >= float(g.year),
			"%s resumes with the sight it had rather than blind" % t)

	print("FAILS: %d" % fails)
	quit()
