extends SceneTree

## The automation panel: forms on the left, what is actually running on the right, split by kind.
##
## The rules used to sit underneath the forms — and the forms are long, a launch rule alone being
## six fields and a manifest — so the list of standing orders fell off the bottom of the panel
## exactly when there was most to see. And it was one list: a build rule and a launch rule have
## nothing to do with each other, mixed in whatever order they happened to be added.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var ap = g.sidebar.automation_panel
	g.sidebar.hide_all()
	# SHOWN: a hidden Control is never laid out, so every rect below would be whatever it was
	# last given and the containment checks would compare two meaningless numbers.
	ap.show()
	for _i in range(6): await process_frame

	check(ap._build_rules != null, "there is a list for build rules")
	check(ap._launch_rules != null, "and a separate one for launches")
	check(ap._build_rules != ap._launch_rules, "they are not the same list")

	# ── Empty, each says so for itself ──
	# "No rules yet" under Building while six launches are running is the useful message, and a
	# single shared one could not give it.
	ap.load_rules([])
	for _i in range(2): await process_frame
	check(ap._build_rules.get_child_count() == 1, "the build list shows a note when empty")
	check(ap._launch_rules.get_child_count() == 1, "and so does the launch list")
	var b_note: String = (ap._build_rules.get_child(0) as Label).text
	var l_note: String = (ap._launch_rules.get_child(0) as Label).text
	check(b_note != l_note, "and they say different things: %s / %s" % [b_note, l_note])

	# ── Rules land in the list for their kind ──
	var fuel := str((MissionData.FUELS[0] as Dictionary)["id"])
	ap.load_rules([
		{"id": 1, "type": "build", "planet": "earth", "building": "Mine", "target": 12,
			"enabled": true},
		{"id": 2, "type": "launch", "mission": "Supply Run", "origin": "earth", "target": "mars",
			"fuel": fuel, "arrival": "orbit", "keep": 2, "cargo": {"Steel": 5.0e8},
			"enabled": true},
		{"id": 3, "type": "build", "planet": "mars", "building": "Solar Farm", "target": 40,
			"enabled": true},
		{"id": 4, "type": "launch", "mission": "Research Probe", "origin": "earth",
			"target": "venus", "fuel": fuel, "arrival": "orbit", "keep": 1, "enabled": false},
	])
	for _i in range(4): await process_frame
	check(ap._build_rules.get_child_count() == 2,
		"both build rules are in the build list: %d" % ap._build_rules.get_child_count())
	check(ap._launch_rules.get_child_count() == 2,
		"and both launch rules in the launch list: %d" % ap._launch_rules.get_child_count())
	# No note where there are rules.
	for row in ap._build_rules.get_children():
		check(row is HBoxContainer, "a build entry is a rule row, not a note")
	for row2 in ap._launch_rules.get_children():
		check(row2 is HBoxContainer, "and so is a launch entry")

	# ── The rules are to the RIGHT of the forms ──
	var forms: Control = ap._l_mission            # a control from the left-hand form column
	check(forms != null, "the launch form is built")
	var forms_r: Rect2 = forms.get_global_rect()
	var rules_r: Rect2 = (ap._build_rules as Control).get_global_rect()
	check(rules_r.position.x >= forms_r.end.x - 1.0,
		"the rules column starts past the forms: %.0f vs %.0f" % [
			rules_r.position.x, forms_r.end.x])
	var lr: Rect2 = (ap._launch_rules as Control).get_global_rect()
	check(lr.position.x >= forms_r.end.x - 1.0, "both lists are over there")
	check(lr.position.y > rules_r.position.y, "launches below building, not beside it")

	# ── And nothing spills out of the panel ──
	# Measured, not eyeballed: a rule description is a Label, whose minimum width is its whole
	# line, so an unwrapped one does not merely overflow — it pushes the column open from the
	# inside and carries the checkbox and the remove button off the edge with it.
	var panel_r: Rect2 = (ap as Control).get_global_rect()
	var over: Array = []
	for box: Control in [ap._build_rules, ap._launch_rules]:
		for row3 in box.get_children():
			var rr: Rect2 = (row3 as Control).get_global_rect()
			if rr.end.x > panel_r.end.x + 0.5:
				over.append("%.0f > %.0f" % [rr.end.x, panel_r.end.x])
	check(over.is_empty(), "every rule row stays inside the panel: %s" % str(over))

	print("FAILS: %d" % fails)
	quit()
