extends SceneTree

## Saving a game under a name the player chose.
##
## Saving already worked and had nothing to say: the pause menu's Save button wrote
## user://saves/default.json without asking, so every run that had not been loaded from a named
## slot overwrote the same file. There was no way to keep two games, and no way to tell which
## one you were in.
##
## What has to hold:
##   a name becomes a file the START MENU can find again — the two sanitisers must agree
##   saving NAMES the run, so the next save goes to the same slot
##   the dialog reports what actually happened to the file, and a failure stays open
##   a saved game loads back as itself

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(20261030)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var gs: Node = root.get_node("GameSession")
	var SDlg = load("res://save_dialog.gd")


	# ── A name becomes a path, and an unusable one becomes nothing ──
	check(SDlg.slot_path("Second Age") == "user://saves/Second Age.json",
		"a plain name is a plain file: %s" % SDlg.slot_path("Second Age"))
	check(SDlg.sanitise("  spaced  ") == "spaced", "the name is trimmed")
	check(SDlg.slot_path("") == "", "an empty name is not a path")
	check(SDlg.slot_path("   ") == "", "nor is whitespace")
	# The three characters that would otherwise escape the saves directory or break a path.
	var nasty: String = SDlg.sanitise("a/b\\c:d")
	check(nasty.find("/") < 0 and nasty.find("\\") < 0 and nasty.find(":") < 0,
		"separators are stripped out of a name: %s" % nasty)
	# And it must agree with the menu that has to find the file again. StartMenu builds its path
	# the same way; if the two ever drift, a save made in game cannot be loaded from the menu.
	var slot: String = "Odd/Name:Here"
	var menu_path: String = "user://saves/" \
		+ slot.strip_edges().replace("/", "_").replace("\\", "_").replace(":", "_") + ".json"
	check(SDlg.slot_path(slot) == menu_path,
		"and the dialog agrees with the start menu: %s vs %s" % [
			SDlg.slot_path(slot), menu_path])


	# ── The Save button opens a dialog rather than writing silently ──
	gs.current_save_path = ""
	g.year = 2187
	check(g._default_save_name() == "Humanity 2187",
		"an unnamed run is offered its year: %s" % g._default_save_name())
	g._on_save_pressed()
	for _i in range(2): await process_frame
	var dlg = g._save_dialog
	check(dlg != null, "the dialog exists")
	check(dlg != null and dlg.visible, "and is showing")
	check(dlg != null and dlg._name_edit.text == "Humanity 2187",
		"with the name filled in ready to type over")
	check(dlg != null and dlg.process_mode == Node.PROCESS_MODE_ALWAYS,
		"and it works while the tree is paused, which is when it is reachable")


	# ── Naming one writes it, and names the run ──
	var target: String = "Verify Slot"
	var path: String = SDlg.slot_path(target)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	dlg._name_edit.text = target
	dlg._on_save()
	for _i in range(2): await process_frame
	check(FileAccess.file_exists(path), "the file is on disk: %s" % path)
	check(str(gs.current_save_path) == path,
		"and the run is now that slot: %s" % str(gs.current_save_path))
	check(not dlg.visible, "the dialog closes on success")
	check(g._default_save_name() == target,
		"so saving again offers the same name: %s" % g._default_save_name())
	# It is listed for next time.
	check(SDlg.existing_slots().has(target),
		"and it shows up in the list of saves: %s" % str(SDlg.existing_slots().slice(0, 6)))

	# A second save with no path goes to the SAME slot rather than back to default.json.
	var before_m: int = FileAccess.get_modified_time(path)
	g.year = 2200
	check(g.save_game(), "an unargumented save still works")
	check(str(gs.current_save_path) == path, "and still points at the named slot")


	# ── The dialog warns before replacing, and reports the result ──
	g._on_save_pressed()
	for _i in range(2): await process_frame
	dlg._name_edit.text = target
	dlg._refresh_state()
	check(dlg._status.text.find("replaces") >= 0,
		"an existing name says it will be replaced: %s" % dlg._status.text)
	dlg._name_edit.text = "Brand New Slot Name"
	dlg._refresh_state()
	check(dlg._status.text.find("replaces") < 0,
		"a fresh one does not: %s" % dlg._status.text)
	check(not dlg._save_btn.disabled, "and Save is available")
	dlg._name_edit.text = "   "
	dlg._refresh_state()
	check(dlg._save_btn.disabled, "an empty name cannot be saved")
	dlg._on_save()
	check(dlg.visible, "and pressing Save anyway leaves the dialog open")
	# A failure is reported and the dialog STAYS OPEN, so the player can try another name.
	dlg.set_result(false, "Could not write that file.")
	check(dlg.visible, "a failed save keeps the dialog up")
	dlg.set_result(true, "Saved.")
	check(not dlg.visible, "and a good one closes it")


	# ── What was saved loads back ──
	var want_year: int = g.year
	g.year = 1
	g.load_game(path)
	check(g.year == want_year,
		"the named save loads back as itself: %d vs %d" % [g.year, want_year])

	DirAccess.remove_absolute(path)
	var extra: String = SDlg.slot_path("Brand New Slot Name")
	if FileAccess.file_exists(extra):
		DirAccess.remove_absolute(extra)

	print("FAILS: %d" % fails)
	quit()
