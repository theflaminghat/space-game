extends SceneTree

## Above SolarSystem.ORBIT_BLUR_ABOVE_MULT the bodies stop being drawn individually and each
## orbit shows a blurred ring instead.
##
## The cutoff used to be a YEAR (ORBIT_FREEZE_YEAR, 1 000 000), from when the timescale was a
## fixed super-linear function of the date so "late" and "fast" meant the same thing. They do not
## any more — the player picks the speed — and the old trigger was one-way: once a run passed the
## year, the bodies never came back however far it slowed down.

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
	var ss: Node = root.get_node("SolarSystem")
	var earth: Node3D = g.get_node("WorldRoot/Planets/earth")
	var torus: Node3D = g.get_node_or_null("WorldRoot/Planets/earth_blur_torus")
	check(torus != null, "the blur ring exists")

	check(is_equal_approx(ss.ORBIT_BLUR_ABOVE_MULT, 100.0),
		"the cutoff is 100x: %s" % str(ss.ORBIT_BLUR_ABOVE_MULT))
	check(is_equal_approx(ss.TIMESCALE_BASE, g.TIMESCALE_BASE),
		"Game and the clock agree on the base rate")

	# ── Every rung of the ladder ──
	g.year = 99_000_000            # so every speed is unlocked
	g._sync_speed_unlocks()
	for i in range(g.SPEED_TIERS.size()):
		g.set_speed_tier(i)
		ss.paused = false
		ss.ui_paused = false
		for _i in range(3): await process_frame
		ss.paused = false
		ss.ui_paused = false
		for _i in range(3): await process_frame
		var mult: float = float(g.SPEED_TIERS[i]["mult"])
		var want_bodies: bool = mult <= ss.ORBIT_BLUR_ABOVE_MULT
		check(ss.orbits_resolvable() == want_bodies,
			"%sx resolvable=%s" % [str(mult), str(ss.orbits_resolvable())])
		check(is_equal_approx(ss.speed_multiplier(), mult),
			"%sx reports its own multiplier: %s" % [str(mult), str(ss.speed_multiplier())])
		# Skip the visual assertions when an event card has paused the run: a pause is
		# SUPPOSED to bring the bodies back so the player can look at them.
		if ss.paused or ss.ui_paused:
			continue
		check(earth.visible == want_bodies,
			"%sx body visible=%s (wanted %s)" % [str(mult), str(earth.visible), str(want_bodies)])
		check(torus.visible == (not want_bodies),
			"%sx blur ring visible=%s (wanted %s)" % [str(mult), str(torus.visible), str(not want_bodies)])

	# ── It goes BOTH ways ──
	# The old year trigger never restored anything; this is the half that was missing.
	g.set_speed_tier(9)
	ss.paused = false
	ss.ui_paused = false
	for _i in range(5): await process_frame
	var blurred_at_top: bool = not ss.solar_system_active
	g.set_speed_tier(0)
	ss.paused = false
	ss.ui_paused = false
	for _i in range(5): await process_frame
	check(blurred_at_top, "the fastest rung blurs")
	check(ss.solar_system_active, "and slowing back to 1x restores the bodies")
	check(earth.visible and not torus.visible, "with the ring gone again")

	# ── Pausing shows them whatever the speed ──
	g.set_speed_tier(9)
	for _i in range(5): await process_frame
	ss.paused = true
	for _i in range(5): await process_frame
	check(earth.visible, "pausing at the fastest speed shows the bodies for inspection")
	ss.paused = false

	# ── The year alone no longer decides anything ──
	# A run past the old million-year cutoff, at 1x, draws its planets like any other.
	g.year = 5_000_000
	g.set_speed_tier(0)
	ss.paused = false
	ss.ui_paused = false
	for _i in range(6): await process_frame
	check(ss.solar_system_active,
		"year 5 000 000 at 1x still draws the system (the old cutoff was 1 000 000)")
	check(earth.visible, "and the bodies are there")

	print("FAILS: %d" % fails)
	quit()
