extends SceneTree

## The star pass is cached, and a cache that does not invalidate is a wrong answer drawn
## confidently.
##
## Measured before this existed: the per-star loop WAS the whole of the map's frame cost — six
## thousand stars at 31.5 ms, against 6.9 ms for a frame with the map hidden. None of it depends
## on anything but the star, the camera, the frame origin, the selection, who holds what and the
## filter, so a frame that moves none of those reuses the answer.
##
## The two that can go silently wrong, and why each is checked here:
##   who-holds-what enters the key as COUNTS, so a colony swapped for another at the same count
##     would be missed — _marked_version is what covers it, and secession makes that an ordinary
##     event rather than a theoretical one
##   _st_held / _st_fac are indexed BY CATALOGUE POSITION, and the procedural field is filtered
##     by live distance from Sol — so a travelling star rebuilds the catalogue, dropping some
##     stars and gaining others, and can come out the same length

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(20261025)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var sm = g.sidebar.star_map
	g.sidebar.show_star_map()
	g.refresh_star_map()
	for _i in range(10): await process_frame

	check(not sm._st_key.is_empty(), "the pass has been built")
	check(sm._st_pts.size() > 0, "and produced a point cloud: %d" % sm._st_pts.size())
	var k0: Array = sm._st_key.duplicate()

	# ── An idle frame reuses it: that is the whole point ──
	for _i in range(5):
		sm.queue_redraw()
		await process_frame
	check(sm._st_key == k0, "an idle frame reuses the pass")

	# ── Everything it depends on invalidates it ──
	var moves: Array = [
		["zoom",      func(): sm._zoom += 0.7],
		["yaw",       func(): sm._yaw += 0.3],
		["pitch",     func(): sm._pitch += 0.2],
		["selection", func(): sm._selected = 5],
	]
	for m: Array in moves:
		var before: Array = sm._st_key.duplicate()
		(m[1] as Callable).call()
		sm.queue_redraw()
		await process_frame
		check(sm._st_key != before, "moving the %s rebuilds the pass" % str(m[0]))

	var kf: Array = sm._st_key.duplicate()
	sm.set_layer_shown("stars", false)
	sm.queue_redraw()
	await process_frame
	check(sm._st_key != kf, "and so does the layer filter")
	sm.set_layer_shown("stars", true)
	sm.queue_redraw()
	await process_frame

	# ── A colony appearing, and the swap the counts alone would miss ──
	var st: Array = sm.all_stars()
	check(st.size() > 2, "there are stars to mark")
	var a: String = str((st[0] as Dictionary)["name"])
	var b: String = str((st[1] as Dictionary)["name"])
	var k1: Array = sm._st_key.duplicate()
	sm.set_interstellar_state({a: true}, [], 0.0)
	sm.queue_redraw()
	await process_frame
	check(sm._st_key != k1, "a colony appearing rebuilds the pass")
	check(sm._st_held.size() == st.size(),
		"the holder arrays cover the catalogue: %d vs %d" % [sm._st_held.size(), st.size()])
	var ia: int = -1
	var ib: int = -1
	for i in range(st.size()):
		var nm: String = str((st[i] as Dictionary)["name"])
		if nm == a:
			ia = i
		elif nm == b:
			ib = i
	check(ia >= 0 and ib >= 0, "both test stars are in the catalogue")
	if ia >= 0 and ib >= 0:
		check(sm._st_held[ia] == 1, "and the right one is flagged as ours")
		check(sm._st_held[ib] == 0, "and the other is not")
		# The swap: same COUNT, different star. Missed by a count, caught by the version.
		var k2: Array = sm._st_key.duplicate()
		sm.set_interstellar_state({b: true}, [], 0.0)
		sm.queue_redraw()
		await process_frame
		check(sm._st_key != k2,
			"one colony swapped for another rebuilds it, though the count did not move")
		check(sm._st_held[ib] == 1 and sm._st_held[ia] == 0,
			"and the flags follow the swap: %d/%d" % [sm._st_held[ia], sm._st_held[ib]])

	# ── A rebuilt catalogue invalidates the index arrays ──
	# The flags are positions in all_stars(), and that list is rebuilt as Sol travels. A version
	# that did not move would leave a colony marker sitting on whichever star happened to land
	# at that index.
	var cv0: int = sm.catalogue_version()
	check(sm._st_held_cat == cv0,
		"the holder arrays record the catalogue they were built against: %d vs %d" % [
			sm._st_held_cat, cv0])
	sm.set_observation_range(sm.observation_range() * 3.0 + 500.0)
	var after: Array = sm.all_stars()
	check(sm.catalogue_version() != cv0,
		"widening the observation range rebuilds the catalogue: %d -> %d" % [
			cv0, sm.catalogue_version()])
	sm.queue_redraw()
	await process_frame
	check(sm._st_held_cat == sm.catalogue_version(),
		"and the holder arrays are rebuilt against the new one")
	check(sm._st_held.size() == after.size(),
		"to the new length: %d vs %d" % [sm._st_held.size(), after.size()])

	print("FAILS: %d" % fails)
	quit()
