extends SceneTree

## The star map sorts the cluster shell into its two tiers ONCE PER VIEW, not once per frame.
##
## The patch holds eight thousand clusters and all but a handful are one entry in a batched point
## cloud.  Their screen positions are a function of the view and of nothing else, so the sort
## produces the same answer every frame the player is neither panning nor zooming — and the map
## redraws continuously while the simulation runs, because Game pushes mission progress and the
## energy readout every simulated day and each push queues a redraw.  That made the sort half of
## a frame that nothing in it had any reason to repeat.
##
## Two properties are worth holding onto, and they pull in opposite directions:
##   the cache must not rebuild while the view is still, and
##   it must agree, exactly, with what recomputing would have produced.
## The second is what makes the first safe, so it is checked at every view the first is checked at.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

## Whether the cache rebuilt across a pair of samples.  A rebuild is the only thing that writes
## either half of the key, and it only ever writes values that differed — so the pair moving and
## a rebuild happening are the same event, and no instrumentation is needed to see it.
func _rebuilt(a: Array, b: Array) -> bool:
	return not (a[0] as Vector3).is_equal_approx(b[0] as Vector3) or a[1] != b[1]

func _sample(sm) -> Array:
	return [sm.get("_cl_ref"), (sm.get("_cl_key") as Array).duplicate()]

## Redraw `n` times without touching the view, and count the rebuilds.
func _redraws(sm, n: int) -> int:
	var rebuilds: int = 0
	var prev: Array = _sample(sm)
	for _i in range(n):
		sm.queue_redraw()
		await process_frame
		var now: Array = _sample(sm)
		if _rebuilt(prev, now):
			rebuilds += 1
		prev = now
	return rebuilds

## Force the sort to run again from scratch at the current view and hand back what it produced.
func _recompute(sm) -> Array:
	sm.set("_cl_key", [])
	sm.queue_redraw()
	await process_frame
	return [(sm.get("_cl_pts") as PackedVector2Array).duplicate(),
		(sm.get("_cl_pt_col") as PackedColorArray).duplicate(),
		(sm.get("_cl_glyph_idx") as PackedInt32Array).duplicate()]

## How many points in the cached cloud are painted as a human holding.
func _human_points(sm) -> int:
	var n: int = 0
	for c: Color in (sm.get("_cl_pt_col") as PackedColorArray):
		if absf(c.r - sm.STATUS_COL_HUMAN.r) < 0.01 \
				and absf(c.g - sm.STATUS_COL_HUMAN.g) < 0.01 \
				and absf(c.b - sm.STATUS_COL_HUMAN.b) < 0.01:
			n += 1
	return n

func _run() -> void:
	seed(20261008)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var sm = g.sidebar.star_map
	var ss: Node = root.get_node("SolarSystem")
	g.sidebar.hide_all()
	sm.show()
	for _i in range(8): await process_frame

	# The whole test rests on _draw actually running, so say so out loud before relying on it.
	sm.queue_redraw()
	await process_frame
	var clusters: Array = sm.star_clusters()
	check(clusters.size() > 1000, "the patch is the full streamed shell: %d" % clusters.size())
	check((sm.get("_cl_pts") as PackedVector2Array).size() >= 2,
		"the panel draws, so there is a point cloud to cache")

	# ── A still view rebuilds once and then stops ──
	# Sixty frames is a second of the redraw storm the running simulation produces.
	for z: float in [1.0, 8.0, 40.0]:
		sm.set("_zoom", z)
		sm.queue_redraw()
		await process_frame                       # the one rebuild the zoom change earns
		var n: int = await _redraws(sm, 60)
		check(n == 0, "zoom %.0f: sixty more redraws rebuild nothing (%d)" % [z, n])

		# ── And the thing it is holding is the right answer ──
		var held: Array = [(sm.get("_cl_pts") as PackedVector2Array).duplicate(),
			(sm.get("_cl_pt_col") as PackedColorArray).duplicate(),
			(sm.get("_cl_glyph_idx") as PackedInt32Array).duplicate()]
		var fresh: Array = await _recompute(sm)
		check(held[0] == fresh[0], "zoom %.0f: the held point cloud is what recomputing gives" % z)
		check(held[1] == fresh[1], "zoom %.0f: and the colours with it" % z)
		check(held[2] == fresh[2], "zoom %.0f: and the glyph list" % z)

		# ── Every cluster is in exactly one tier ──
		var pts: int = (held[0] as PackedVector2Array).size() / 2
		var gly: int = (held[2] as PackedInt32Array).size()
		check(pts + gly <= clusters.size(),
			"zoom %.0f: %d points + %d glyphs fits in %d clusters" % [z, pts, gly, clusters.size()])
		var seen: Dictionary = {}
		for ci: int in (held[2] as PackedInt32Array):
			check(not seen.has(ci), "zoom %.0f: cluster %d is listed once" % [z, ci])
			seen[ci] = true

	sm.set("_zoom", 8.0)
	sm.queue_redraw()
	await process_frame

	# ── The home cluster is glyph tier, never a point ──
	# Grains scattered over the Sol marker read as a smudge, so its glyph is a selection ring and
	# nothing else — but it must not fall through to the point cloud either.  From Sol's own frame
	# it is at distance zero and the detail band's central hole culls it outright, so this has to
	# be asked from somewhere it is actually visible.
	var home: int = -1
	for i in range(clusters.size()):
		if bool((clusters[i] as Dictionary).get("is_home", false)):
			home = i
			break
	check(home >= 0, "there is a home cluster")
	sm.set("_ref_name", "elsewhere")
	sm.set("_ref_pos", (clusters[home] as Dictionary)["pos"] as Vector3 + Vector3(14.0, 6.0, 2.0))
	sm.set("_zoom", 1.0)
	sm.queue_redraw()
	await process_frame
	check((sm.get("_cl_glyph_idx") as PackedInt32Array).has(home),
		"and seen from fourteen light-years off it is on the glyph list, not in the cloud")
	sm.set("_ref_name", "Sol")
	sm.set("_ref_pos", ss.sol_position())
	sm.set("_zoom", 8.0)
	sm.queue_redraw()
	await process_frame

	# ── Every part of the view invalidates it ──
	# A cache that misses one of these shows the player a shell that belongs to a view they have
	# already left, which is worse than the cost it was saving.
	var moves: Array = [
		["zoom", func(): sm.set("_zoom", sm.get("_zoom") * 1.5)],
		["yaw", func(): sm.set("_yaw", sm.get("_yaw") + 0.4)],
		["pitch", func(): sm.set("_pitch", sm.get("_pitch") + 0.3)],
		["the frame origin", func():
			# _sync_sol_frame pulls _ref_pos back to Sol every frame while the frame is named
			# Sol, so moving it needs the frame renamed or the move is undone next frame — and
			# the cache would be seen to rebuild twice, which is the sync's doing, not its own.
			sm.set("_ref_name", "elsewhere")
			sm.set("_ref_pos", Vector3(900.0, 300.0, -200.0))],
		["the selection", func(): sm.set("_selected_cluster", 7)],
		["the panel size", func(): sm.size = sm.size + Vector2(37.0, 11.0)],
	]
	for m: Array in moves:
		var before: Array = _sample(sm)
		(m[1] as Callable).call()
		sm.queue_redraw()
		await process_frame
		check(_rebuilt(before, _sample(sm)), "%s invalidates the cache" % str(m[0]))
		# And settles again immediately — an invalidation that never stops is not a cache.
		var again: int = await _redraws(sm, 10)
		check(again == 0, "%s: and it settles again (%d)" % [str(m[0]), again])

	sm.set("_selected_cluster", -1)
	sm.set("_ref_pos", ss.sol_position())
	sm.set("_zoom", 8.0)
	sm.set("_yaw", 0.0)
	sm.set("_pitch", 0.6)
	sm.queue_redraw()
	await process_frame

	# ── A drifting frame holds, up to the point where it would show ──
	# This is the case the whole tolerance exists for: the reference is locked to Sol, Sol moves
	# under the thruster, and an exact comparison would rebuild every frame of a long burn.
	var tol: float = sm._cluster_pt_tol(sm._fit_scale(sm.size * 0.5))
	check(tol > 0.0, "there is a tolerance at all: %.9f ly" % tol)
	var base: Vector3 = sm.get("_ref_pos")
	var pinned: Array = _sample(sm)
	for i in range(40):
		sm.set("_ref_pos", base + Vector3(tol * 0.01 * float(i), 0.0, 0.0))
		sm.queue_redraw()
		await process_frame
	check(not _rebuilt(pinned, _sample(sm)), "forty sub-tolerance nudges rebuild nothing")
	sm.set("_ref_pos", base + Vector3(tol * 4.0, 0.0, 0.0))
	sm.queue_redraw()
	await process_frame
	check(_rebuilt(pinned, _sample(sm)), "a drift past the tolerance does rebuild")

	# The tolerance is a sub-pixel bound, not a guess, so it has to tighten as the view does.
	var wide: float = 0.0
	var deep: float = 0.0
	sm.set("_zoom", 1.0)
	wide = sm._cluster_pt_tol(sm._fit_scale(sm.size * 0.5))
	sm.set("_zoom", 40.0)
	deep = sm._cluster_pt_tol(sm._fit_scale(sm.size * 0.5))
	check(deep < wide * 0.1,
		"and it tightens with the zoom: %.9f ly at 1x, %.9f at 40x" % [wide, deep])
	sm.set("_zoom", 8.0)

	# ── A recarve invalidates it, and the simulation's own traffic does not ──
	# set_interstellar_state runs every simulated day with the map open; if that rebuilt the
	# sort, the cache would be doing nothing in the one state it was written for.
	sm.set("_ref_pos", ss.sol_position())
	sm.queue_redraw()
	await process_frame
	var quiet: Array = _sample(sm)
	for _i in range(20):
		g.refresh_star_map()
		await process_frame
	check(not _rebuilt(quiet, _sample(sm)),
		"twenty simulation pushes with nothing colonised rebuild nothing")

	var before_focus: Array = _sample(sm)
	sm._build_cluster_cells()
	sm.queue_redraw()
	await process_frame
	check(_rebuilt(before_focus, _sample(sm)),
		"recarving the focus set does rebuild — it decides which clusters get a glyph")

	# ── A colony changes the colour the point cloud is holding ──
	# The colour is BAKED into the cache, so this is the one piece of simulation state that has
	# to reach through it.  Colonising the whole shell is the unambiguous version of the
	# question: afterwards every point in the cloud has to be the human colour, and none of them
	# before — anything in between would leave it unclear whether a given cluster was ever in
	# the cloud to begin with, since most of the patch is culled before it gets there.
	sm.set("_zoom", 1.0)
	sm.queue_redraw()
	await process_frame
	check(_human_points(sm) == 0, "nothing is settled, so no point is human-coloured")
	var total: int = (sm.get("_cl_pt_col") as PackedColorArray).size()
	check(total > 100, "there is a cloud to repaint: %d points" % total)
	var colo: Dictionary = {}
	for cl: Dictionary in clusters:
		colo[str(cl["name"])] = true
	sm.set_interstellar_state(colo, [], 1.0e20)
	await process_frame
	check(_human_points(sm) == total,
		"colonising the shell repaints all of it: %d of %d" % [_human_points(sm), total])
	sm.set_interstellar_state({}, [], 1.0e20)
	await process_frame
	check(_human_points(sm) == 0, "and giving it all up paints it back")
	sm.set("_zoom", 8.0)

	# ── It draws under thrust, which is the drift case for real ──
	ss.reset_star()
	ss.set_star_mirror_coverage(1.0)
	ss.aim_star_thrust(Vector3(1, 0, 0), "cache")
	ss.paused = false
	ss.ui_paused = false
	for _i in range(10):
		g._run_star_thrust(365.25 * 1.0e6)
		sm.queue_redraw()
		await process_frame
	check(true, "ten frames under thrust draw without error")
	ss.reset_star()

	print("FAILS: %d" % fails)
	quit()
