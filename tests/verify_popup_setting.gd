extends SceneTree

## Timeline event popups are the transient cards in the top-right corner.  A player who turns
## them off should get silence from them and nothing else: the timeline still records every
## event, and turning them back on must not then dump the backlog that accumulated meanwhile.

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
	var sm = g.settings_menu
	check(sm != null, "the settings menu exists")

	# ── The control is under Gameplay, and defaults to on ──
	# This test writes settings.cfg, so it must not read the default off the player's (or its
	# own last run's) file: the key is cleared, the menu reloaded, and the original restored at
	# the end.  Without this the suite fails on the second run and passes standalone.
	var cfg_path := "user://settings.cfg"
	var cfg0 := ConfigFile.new()
	cfg0.load(cfg_path)
	var had_key: bool = cfg0.has_section_key("gameplay", "timeline_popups")
	var was: bool = bool(cfg0.get_value("gameplay", "timeline_popups", true))
	if had_key:
		cfg0.erase_section_key("gameplay", "timeline_popups")
		cfg0.save(cfg_path)
	sm._load_and_apply()
	for _i in range(4): await process_frame

	var btn: CheckButton = sm.get("_timeline_popup_btn")
	check(btn != null, "the checkbox was built")
	var under_gameplay := false
	for tabs in sm.find_children("*", "TabContainer", true, false):
		for page in tabs.get_children():
			if page.name == "Gameplay" and btn != null and sm.is_ancestor_of(btn) \
					and page.is_ancestor_of(btn):
				under_gameplay = true
	check(under_gameplay, "the checkbox sits on the Gameplay tab")
	check(sm.timeline_popups_enabled(), "popups default to on")

	var vbox: VBoxContainer = g.get("_event_notif_vbox")
	check(vbox != null, "the card container exists")

	# ── On: an announcement becomes a card, and reaches the timeline ──
	var canvas: Node = g.timeline_panel.get("_canvas")
	check(canvas != null, "the timeline canvas exists")
	var before: int = (canvas.get("_live_events") as Array).size()
	for c in vbox.get_children():
		c.queue_free()
	for _i in range(4): await process_frame
	g._announce("Test A", "card expected", "test_popup_a")
	for _i in range(6): await process_frame
	check(vbox.get_child_count() > 0, "a card appeared while popups were on")

	# ── Off: no card, and the queue does not hold the event for later ──
	btn.button_pressed = false
	check(not sm.timeline_popups_enabled(), "the getter follows the checkbox")
	for c in vbox.get_children():
		c.queue_free()
	for _i in range(4): await process_frame
	g._announce("Test B", "no card expected", "test_popup_b")
	g._announce("Test C", "no card expected", "test_popup_c")
	for _i in range(8): await process_frame
	check(vbox.get_child_count() == 0, "no card appeared while popups were off")
	check((g.get("_pending_event_notifications") as Array).is_empty(),
		"the queue was discarded rather than held")

	# Re-enabling must not replay what happened while they were off.
	btn.button_pressed = true
	for _i in range(8): await process_frame
	check(vbox.get_child_count() == 0, "turning popups back on did not dump the backlog")

	# ── The timeline itself kept recording throughout ──
	check((canvas.get("_live_events") as Array).size() == before + 3,
		"all three events still reached the timeline")

	# ── Persistence round-trip ──
	btn.button_pressed = false
	sm.save_settings()
	var cfg := ConfigFile.new()
	check(cfg.load("user://settings.cfg") == OK, "settings.cfg was written")
	check(bool(cfg.get_value("gameplay", "timeline_popups", true)) == false,
		"the setting was persisted")

	# Leave the file as it was found.
	if had_key:
		cfg.set_value("gameplay", "timeline_popups", was)
	else:
		cfg.erase_section_key("gameplay", "timeline_popups")
	cfg.save(cfg_path)

	print("FAILS: %d" % fails)
	quit()
