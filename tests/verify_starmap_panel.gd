extends SceneTree

## The star map's action panel is bound to the RIGHT edge and grows leftward.
##
## It used to pin both horizontal offsets, which fixed it at exactly LAUNCH_UI_WIDTH however long
## its buttons were — so a button carrying a stock count ran off the edge instead of widening the
## panel. LAUNCH_UI_WIDTH is now a floor; the right edge is the only fixed horizontal position.

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
	for _i in range(30): await process_frame
	var g: Node = current_scene
	var rt: Node = root.get_node("ResearchTree")
	for n: ResearchNode in load("res://ResearchTreeData.gd").build():
		rt.force_unlock(str(n.id))
	rt.resources["energy"] = 1.0e40
	var star := ""
	for s in g.star_factions:
		star = str(s); break
	g._detected_aliens[star] = true
	g.sidebar.show_star_map()
	var sm = g.sidebar.star_map
	sm.focus_star(star)
	for _i in range(20): await process_frame
	var ui: Control = sm._launch_ui
	check(ui.visible, "the action panel is up")

	# ── Bound to the right, ten pixels in ──
	var gap := func() -> float: return sm.size.x - (ui.position.x + ui.size.x)
	check(is_equal_approx(gap.call(), sm.LAUNCH_UI_GAP),
		"right gap is LAUNCH_UI_GAP: %.2f vs %.2f" % [gap.call(), sm.LAUNCH_UI_GAP])
	check(is_equal_approx(sm.LAUNCH_UI_GAP, 10.0),
		"which is ten pixels: %s" % str(sm.LAUNCH_UI_GAP))
	# The same inset along the bottom, so the corner is even.
	var bottom_gap: float = sm.size.y - (ui.position.y + ui.size.y)
	check(is_equal_approx(bottom_gap, sm.LAUNCH_UI_GAP),
		"bottom gap matches the side gap: %.2f vs %.2f" % [bottom_gap, sm.LAUNCH_UI_GAP])
	check(ui.grow_horizontal == Control.GROW_DIRECTION_BEGIN,
		"and it grows toward the left")

	# ── It stays bound when the map changes size ──
	for w: float in [1100.0, 1700.0, 900.0]:
		sm.size = Vector2(w, 700.0)
		for _i in range(10): await process_frame
		check(is_equal_approx(gap.call(), sm.LAUNCH_UI_GAP),
			"still %.0f px in at map width %.0f: %.2f" % [sm.LAUNCH_UI_GAP, w, gap.call()])
		check(ui.position.x + ui.size.x <= sm.size.x,
			"and never hangs off the edge at width %.0f" % w)

	# ── Content wider than the floor pushes the LEFT edge out, not the right ──
	sm.size = Vector2(1700, 700)
	for _i in range(10): await process_frame
	var narrow_w: float = ui.size.x
	var narrow_left: float = ui.position.x
	check(narrow_w >= sm.LAUNCH_UI_WIDTH,
		"the floor width holds: %.0f >= %.0f" % [narrow_w, sm.LAUNCH_UI_WIDTH])
	var was: String = sm._missile_btn.text
	sm._missile_btn.text = "Fire missiles...  (a label far longer than the panel's own width)"
	for _i in range(15): await process_frame
	check(ui.size.x > narrow_w,
		"wide content widens the panel: %.0f -> %.0f" % [narrow_w, ui.size.x])
	check(ui.position.x < narrow_left,
		"by moving the LEFT edge out: %.0f -> %.0f" % [narrow_left, ui.position.x])
	check(is_equal_approx(gap.call(), sm.LAUNCH_UI_GAP),
		"while the right edge does not move: %.2f" % gap.call())
	print("narrow %.0f wide at x=%.0f; grown %.0f wide at x=%.0f; right gap %.1f both times" % [
		narrow_w, narrow_left, ui.size.x, ui.position.x, gap.call()])
	sm._missile_btn.text = was

	print("FAILS: %d" % fails)
	quit()
