extends SceneTree

## What the star map does when a lot of things are in flight.
##
## Two separate problems, measured before either was touched:
##
##   The map is log-radial, so a track between two stars can project tens of thousands of pixels
##   across a panel sixteen hundred wide. The dash walker stepped the WHOLE of that in 14-pixel
##   periods whether or not any of it was on screen — forty thousand pixels for one track, six
##   hundred thousand dash segments a frame for eight hundred flights at a deep zoom.
##
##   And a track is a handful of draw calls even when it IS on screen, which at about forty-five
##   microseconds each puts three thousand flights at a seventh of a second a frame. There is no
##   drawing them all; a budget is the only thing that bounds it.
##
## Both fixes are invisible when they are working, which is why they are asserted here.

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
	var sm = g.sidebar.star_map
	g.sidebar.hide_all()
	sm.show()
	for _i in range(6): await process_frame
	var w: float = sm.size.x
	var h: float = sm.size.y
	check(w > 100.0 and h > 100.0, "the panel has a size to clip against: %.0fx%.0f" % [w, h])

	# ── The clip is a real Liang–Barsky, not an approximation ──
	var sp: Array = []
	check(sm._clip_segment(Vector2(10, 10), Vector2(w - 10, h - 10), 0.0, sp),
		"a segment inside the panel survives")
	check(sp.size() == 2 and absf(float(sp[0])) < 1e-6 and absf(float(sp[1]) - 1.0) < 1e-6,
		"and is not trimmed: %s" % str(sp))
	sp = []
	check(not sm._clip_segment(Vector2(-900, -900), Vector2(-500, -500), 0.0, sp),
		"a segment entirely off the panel is dropped")
	sp = []
	check(not sm._clip_segment(Vector2(-900, h * 0.5), Vector2(-500, h * 0.5), 0.0, sp),
		"including one parallel to an edge and outside it")
	# A track running far past both edges keeps only the middle.
	sp = []
	check(sm._clip_segment(Vector2(-20000, h * 0.5), Vector2(20000, h * 0.5), 0.0, sp),
		"a track crossing the whole panel survives")
	if sp.size() == 2:
		var total: float = 40000.0
		var vis: float = (float(sp[1]) - float(sp[0])) * total
		check(absf(vis - w) < 2.0,
			"and only the on-panel stretch is kept: %.0f px of %.0f" % [vis, total])
		check(vis / total < 0.1,
			"which on this track is a twentieth of it: %.4f" % (vis / total))

	# ── Clipping does not move the dashes ──
	# The pattern has to land where it would have landed had the track been walked from one end,
	# or it crawls along the line every time the view moves and the clip starts somewhere else.
	var period: float = 14.0
	for origin: float in [-14.0, -7.3, -0.1]:
		for vis0: float in [0.0, 1.0, 13.9, 14.0, 500.0, 39999.7]:
			var s: float = sm._dash_start(origin, period, vis0)
			var steps: float = (s - origin) / period
			check(absf(steps - roundf(steps)) < 1.0e-4,
				"the walk starts a whole number of periods from the origin: %.4f" % steps)
			check(s <= vis0 + 1.0e-6,
				"at or before the first visible pixel: %.3f vs %.3f" % [s, vis0])
			check(s + period > vis0 - 1.0e-6,
				"and not a whole period early: %.3f vs %.3f" % [s, vis0])
	check(sm._dash_start(-14.0, 14.0, -100.0) == -14.0,
		"a visible stretch before the origin does not wind it backwards")

	# ── The budget bounds how many tracks are drawn ──
	var stars: Array = sm.all_stars()
	check(sm.FLIGHT_TRACK_BUDGET > 0, "there is a budget: %d" % sm.FLIGHT_TRACK_BUDGET)
	var few: Array = []
	for i in range(sm.FLIGHT_TRACK_BUDGET / 2):
		few.append({"target": str((stars[i] as Dictionary)["name"]), "progress": 0.4,
			"kind": "colony", "start_year": 1900.0, "end_year": 2400.0})
	sm.set_interstellar_state({}, few, 1.0e20, 1945.0)
	check(sm._flight_distance_cut() == INF,
		"under the budget nothing is dropped: %s" % str(sm._flight_distance_cut()))

	var many: Array = []
	for i in range(sm.FLIGHT_TRACK_BUDGET * 6):
		many.append({"target": str((stars[i % stars.size()] as Dictionary)["name"]),
			"progress": 0.4, "kind": "colony", "start_year": 1900.0, "end_year": 2400.0})
	sm.set_interstellar_state({}, many, 1.0e20, 1945.0)
	var cut: float = sm._flight_distance_cut()
	check(cut < INF, "over the budget a cut appears: %.2f ly" % cut)
	# And it is the budget-th nearest, so exactly that many survive it.
	var within: int = 0
	for m: Dictionary in many:
		var tp: Array = []
		if sm._target_pos(str(m["target"]), tp) \
				and (tp[0] as Vector3).distance_to(sm._ref_pos) <= cut:
			within += 1
	check(within >= sm.FLIGHT_TRACK_BUDGET,
		"at least the budget survives: %d of %d" % [within, many.size()])
	check(within < many.size(),
		"and the rest are dropped: %d of %d" % [within, many.size()])

	# The cut is cached, but a different number of flights re-derives it rather than reusing a
	# figure taken for a different swarm.
	var again: float = sm._flight_distance_cut()
	check(again == cut, "asking twice costs nothing and gives the same answer")
	sm.set_interstellar_state({}, many.slice(0, sm.FLIGHT_TRACK_BUDGET / 2), 1.0e20, 1945.0)
	check(sm._flight_distance_cut() == INF,
		"and dropping back under the budget lifts the cut again")

	# ── It all still draws ──
	sm.set_interstellar_state({}, many, 1.0e20, 1945.0)
	for z: float in [2.0, 8.0, 40.0]:
		sm.set("_zoom", z)
		sm.queue_redraw()
		await process_frame
	check(true, "a swarm of %d draws at every zoom without error" % many.size())

	print("FAILS: %d" % fails)
	quit()
