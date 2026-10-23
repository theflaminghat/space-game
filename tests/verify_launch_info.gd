extends SceneTree

## The launch panel's info line describes the TARGET.  The energy reserve is a property of the
## civilisation, not of the star being looked at, so it does not belong on an uncolonised system
## — it used to sit there climbing on its own (a battery charging toward the grid's storage cap)
## and read as a fact about that star.  Cost and affordability live in the action dialog, where
## the speed and count that determine them are chosen; this test pins both halves of that.

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
	var p = g.sidebar.star_map
	g.sidebar.hide_all()
	p.show()
	for _i in range(4): await process_frame

	# Pick an uncolonised, uninhabited star and select it.
	var target := ""
	for s: Dictionary in p.all_stars():
		var nm: String = str(s["name"])
		if not g._col_star_set.has(nm) and not g.star_factions.has(nm):
			target = nm
			break
	check(target != "", "found an uncolonised star to select")
	var idx: int = p._star_index(target)
	check(idx >= 0, "the star is in the catalogue")
	p.set("_selected", idx)
	p._update_launch_ui()
	for _i in range(2): await process_frame

	var line: String = p.get("_launch_info").text
	check(not line.to_lower().contains("energy"),
		"an uncolonised star's info line says nothing about energy: " + line)
	check(line.contains("Pick an action"), "it still tells the player what to do: " + line)

	# A large reserve must not put the figure back.
	rt.resources["energy"] = 1.0e20
	p.set_interstellar_state({}, [], 1.0e20)
	for _i in range(2): await process_frame
	check(not (p.get("_launch_info").text as String).to_lower().contains("energy"),
		"and still says nothing with the reserve full")

	# But the panel still HOLDS the reserve, because the dialog needs it to judge affordability.
	check(is_equal_approx(float(p.get("_avail_energy")), 1.0e20),
		"the reserve is still pushed to the panel for the dialog")

	# ── The dialog is where cost and affordability are stated ──
	p._open_action_dialog("colonize")
	for _i in range(4): await process_frame
	var dlg: String = p.get("_dlg_info").text if p.get("_dlg_info") != null else ""
	check(dlg.length() > 0, "the dialog produced a cost line")
	check(dlg.contains("J"), "the dialog states the energy cost: " + dlg)
	p._close_action_dialog()
	for _i in range(2): await process_frame

	# With nothing in the reserve the dialog is the thing that refuses.
	rt.resources["energy"] = 0.0
	p.set_interstellar_state({}, [], 0.0)
	p._open_action_dialog("colonize")
	for _i in range(4): await process_frame
	var poor: String = p.get("_dlg_info").text
	check(poor.contains("insufficient") or p.get("_dlg_confirm").disabled,
		"an unaffordable launch is refused in the dialog: " + poor)
	p._close_action_dialog()

	print("FAILS: %d" % fails)
	quit()
