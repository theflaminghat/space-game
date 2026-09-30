extends SceneTree

## The compute panel is where the civilisation's thinking is divided between finding things out
## and seeing what is coming.  The slider has to actually drive the split, and the readouts have
## to describe what the split BUYS, or it is a number with no meaning attached.

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
	for _i in range(40): await process_frame
	var g: Node = current_scene
	var rt: Node = root.get_node("ResearchTree")
	var p = g.sidebar.compute_panel
	check(p != null, "the panel exists")

	# ── Locked until the research lands ──
	g.sidebar.hide_all()
	p.show()
	g.refresh_compute_panel()
	for _i in range(10): await process_frame
	check(p._locked_lbl.visible, "it says so while forecasting is unresearched")
	check(not p._slider.editable, "and the slider cannot be moved")
	check(p._horizon_lbl.text.contains("none"), "foresight reads none: '%s'" % p._horizon_lbl.text)

	for n: ResearchNode in load("res://ResearchTreeData.gd").build():
		rt.force_unlock(str(n.id))
	g.refresh_compute_panel()
	for _i in range(10): await process_frame
	check(not p._locked_lbl.visible, "the notice goes once it is researched")
	check(p._slider.editable, "and the slider unlocks")

	# ── The slider drives the game ──
	p._slider.value = 40.0
	for _i in range(10): await process_frame
	check(is_equal_approx(g.compute_forecast_share, 0.4),
		"moving it sets the split: %s" % str(g.compute_forecast_share))
	check(g.forecast_horizon_years() > 0.0, "which opens a horizon")
	check(p._pct_lbl.text == "40%", "and the readout agrees: '%s'" % p._pct_lbl.text)

	# ── The readouts describe what it buys ──
	var science: float = float(g._get_total_production().get("science", 0.0))
	g.refresh_compute_panel()
	for _i in range(6): await process_frame
	check(p._total_lbl.text.contains("Total thinking"), "total is shown")
	check(p._horizon_lbl.text.contains("ahead"),
		"the horizon is shown in years: '%s'" % p._horizon_lbl.text)
	check(science > 0.0, "research still produces at a 40% split: %s" % str(science))

	# ── The split really is a trade ──
	p._slider.value = 0.0
	for _i in range(8): await process_frame
	var science_none: float = float(g._get_total_production().get("science", 0.0))
	p._slider.value = 80.0
	for _i in range(8): await process_frame
	var science_most: float = float(g._get_total_production().get("science", 0.0))
	check(science_most < science_none * 0.3,
		"assigning most of it to foresight really costs research: %s -> %s" % [
			str(science_none), str(science_most)])
	check(g.forecast_horizon_years() > 0.0, "and buys sight with it")

	# ── It survives a save ──
	g.compute_forecast_share = 0.37
	g.save_game("user://saves/computepanel.json")
	g.compute_forecast_share = 0.0
	g.load_game("user://saves/computepanel.json")
	for _i in range(6): await process_frame
	check(is_equal_approx(g.compute_forecast_share, 0.37),
		"the split is saved: %s" % str(g.compute_forecast_share))

	print("FAILS: %d" % fails)
	quit()
