extends SceneTree
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
	for _i in range(20): await process_frame
	var g: Node = current_scene
	var ss: Node = root.get_node("SolarSystem")
	var row: HBoxContainer = g.get_node("main_ui/VBoxContainer3/HBoxContainer/HBoxContainer")
	var buttons: Array = row.get_children()
	print("buttons: ", buttons.map(func(b): return "%s%s" % [b.text, "" if not b.disabled else "(locked)"]))
	check(buttons.size() == g.SPEED_TIERS.size(), "one button per tier")
	# At 1945 only the first two rungs are open.
	print("year ", g.year, " unlocked ", g.unlocked_speed_tiers(), " spd ", ss.seconds_per_day)
	check(g.unlocked_speed_tiers() == 2, "two tiers at 1945")
	check(is_equal_approx(ss.seconds_per_day, g.TIMESCALE_BASE), "base rate at 1x")
	check(not buttons[1].disabled and buttons[2].disabled, "2x open, 5x locked")
	check(buttons[0].button_pressed, "1x selected")
	# Pressing a locked button is impossible; asking for it clamps.
	g.set_speed_tier(9)
	check(g._speed_tier == 1, "asking for a locked tier clamps to the fastest unlocked: %d" % g._speed_tier)
	buttons[1].emit_signal("pressed")
	check(is_equal_approx(ss.seconds_per_day, g.TIMESCALE_BASE / 2.0), "2x halves seconds per day: %s" % ss.seconds_per_day)
	check(buttons[1].button_pressed and not buttons[0].button_pressed, "selection follows the press")
	# The base rate never changes with the year (the old curve did).
	var before: float = ss.seconds_per_day
	g.year = 5000
	g._update_timescale()
	check(is_equal_approx(ss.seconds_per_day, before), "rate unchanged by the year at a fixed tier")
	check(g.unlocked_speed_tiers() == 7, "seven tiers by year 5000: %d" % g.unlocked_speed_tiers())
	check(not buttons[6].disabled and buttons[7].disabled, "10k open, 100k locked at year 5000")
	var notes: Array = g._pending_event_notifications.filter(func(n): return str(n["id"]).begins_with("speed_tier_"))
	print("unlock announcements: ", notes.map(func(n): return n["title"]))
	check(notes.size() >= 1, "an unlock is announced")
	# Every rung, once unlocked, gives its multiplier.
	g.year = 100000000
	g._update_timescale()
	check(g.unlocked_speed_tiers() == g.SPEED_TIERS.size(), "all tiers unlocked in deep time")
	for i in range(g.SPEED_TIERS.size()):
		g.set_speed_tier(i)
		var want: float = g.TIMESCALE_BASE / float(g.SPEED_TIERS[i]["mult"])
		check(is_equal_approx(ss.seconds_per_day, want), "tier %d gives %s" % [i, want])
	check(g.SPEED_TIERS[g.SPEED_TIERS.size() - 1]["mult"] >= 1.0e9, "top tier is at least 1e9")
	print("FAILS: ", fails)
	quit()
