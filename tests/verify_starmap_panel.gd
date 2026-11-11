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
	sm.size = Vector2(1700, 700)
	for _i in range(15): await process_frame


	# ── One column, one width ──
	# The diplomacy buttons were a row of four inside the stack, so they were the only controls
	# on the panel whose width came from their own text — "Contact" narrow, "Declare war" wide —
	# under six buttons that each spanned it. Nothing in here may be a row of its own again.
	var box: Node = ui.get_child(0).get_child(0)
	check(box is VBoxContainer, "the action panel is a single column")
	var widths: Dictionary = {}
	var pressable: int = 0
	for c in box.get_children():
		check(not (c is HBoxContainer), "nothing in the column is a row: %s" % str(c))
		if (c is Button or c is OptionButton) and (c as Control).visible:
			pressable += 1
			widths[snappedf((c as Control).size.x, 0.5)] = true
	check(pressable >= 8, "the stack has its buttons: %d" % pressable)
	check(widths.size() == 1, "and every one of them is one width: %s" % str(widths.keys()))

	# ── What is there is not in the panel for what can be done ──
	# The star's name, its distance, a detected civilisation's infrastructure and our own
	# colony's used to be four labels stacked on top of these buttons, which put the reading and
	# the acting in one column and repeated the name and distance the bottom-left readout was
	# already showing. One Label is left here, and it is about the buttons.
	var stray: Array = []
	for c in box.get_children():
		if c is Label and c != sm._action_hint:
			stray.append((c as Label).text)
	check(stray.is_empty(), "the action panel carries no readout text: %s" % str(stray))
	check(sm._action_hint != null and str(sm._action_hint.text) != "",
		"only what the buttons do: %s" % str(sm._action_hint.text if sm._action_hint else ""))

	# And the readout is the one that has it. The selected star is a detected civilisation, so
	# its infrastructure block is known text, and it is held for the readout to draw.
	check(str(sm._intel_text) != "", "the readout carries the system's intel block")
	check(str(sm._intel_text).to_lower().find("infrastructure") >= 0,
		"naming what is known to be there: %s" % str(sm._intel_text).substr(0, 60))

	# ── The readout grows to what it carries ──
	# It was a fixed 320 px, which was enough for a star's physics and clips a block naming a
	# civilisation's buildings. The floor is still the floor, and the map is still the ceiling.
	var plain_w: float = sm.info_box_width(["Proxima Centauri", "4.25 light-years"])
	check(is_equal_approx(plain_w, sm.INFO_BOX_MIN_W),
		"short lines leave it at the floor: %.0f vs %.0f" % [plain_w, sm.INFO_BOX_MIN_W])
	var long_line: String = "  \u2022 Orbital telescopes: a line far longer than three hundred and twenty pixels"
	var wide_w: float = sm.info_box_width(["Proxima Centauri", long_line])
	check(wide_w > plain_w, "a long one widens it: %.0f -> %.0f" % [plain_w, wide_w])
	sm.size = Vector2(420, 700)
	for _i in range(5): await process_frame
	check(sm.info_box_width(["Proxima Centauri", long_line]) <= sm.size.x,
		"and it never grows past the map it sits in: %.0f in %.0f" % [
			sm.info_box_width(["Proxima Centauri", long_line]), sm.size.x])
	sm.size = Vector2(1700, 700)
	for _i in range(10): await process_frame

	print("FAILS: %d" % fails)
	quit()
