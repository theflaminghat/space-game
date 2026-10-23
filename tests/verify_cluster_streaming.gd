extends SceneTree

## The cluster shell is STREAMED around Sol, not a single fixed field.
##
## It used to be one hexagonal tile's worth of clusters, generated once, with nothing beyond the
## tile wall at all.  Now each tile generates its own deterministically from its axial
## coordinates; the loaded patch is Sol's tile plus the six bordering it, and it follows Sol as
## the Shkadov thruster carries the star across borders.  Within that, Sol's own cell and the
## cells bordering it are carved and drawn in full, and everything else is a point.
##
## Two things make this affordable and both are load-bearing: only the focus is carved (carving
## the whole patch measured 9.8 s per crossing), and the in-cell case of set_cluster_origin is
## one distance test (the full check measured 121 ms and runs on every tick the thruster moves).

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
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var sm = g.sidebar.star_map
	var ss: Node = root.get_node("SolarSystem")

	# ── The tile grid agrees with the one Game addresses its regions on ──
	var sol_t: Vector2i = sm.tile_of(Vector3.ZERO)
	check("%d,%d" % [sol_t.x, sol_t.y] == g._region_id(Vector3.ZERO),
		"the panel and Game agree on which tile Sol is in")
	check(sm.tile_center(sol_t).length() < 1.0,
		"and Sol sits at its centre: %s" % str(sm.tile_center(sol_t).length()))
	var mismatches: int = 0
	for i in range(200):
		var q := Vector3(randf_range(-9000.0, 9000.0), randf_range(-9000.0, 9000.0),
			randf_range(-2500.0, 2500.0))
		var a: Vector2i = sm.tile_of(q)
		if "%d,%d" % [a.x, a.y] != g._region_id(q):
			mismatches += 1
	check(mismatches == 0, "and on every tile across the grid: %d mismatches" % mismatches)
	check(sm.tile_neighbours(sol_t).size() == 6, "a tile has six neighbours")
	check(sm.tile_patch(sol_t).size() == 7, "and a patch is it plus those six")

	# ── Seven tiles are loaded, each with its own clusters ──
	var all: Array = sm.star_clusters()
	check(sm.loaded_tiles().size() == 7, "seven tiles are loaded")
	var per: Dictionary = {}
	for c: Dictionary in all:
		var t: Vector2i = c["tile"]
		per[t] = int(per.get(t, 0)) + 1
	check(per.size() == 7, "every loaded tile contributed clusters: %d" % per.size())
	for t: Vector2i in per:
		check(int(per[t]) >= sm.CLUSTER_COUNT, "%s is full: %d" % [str(t), int(per[t])])
	check(all.size() > 7 * sm.CLUSTER_COUNT - 1, "the patch is the sum of them: %d" % all.size())

	# Names are tile-addressed: a bare index means nothing once there is more than one tile.
	for c: Dictionary in [all[1], all[all.size() - 1]]:
		check(str(c["name"]).contains(":"),
			"a cluster is addressed by tile: '%s'" % str(c["name"]))

	# ── Generation is deterministic per tile ──
	var before_names: Array = []
	for c: Dictionary in all:
		before_names.append(str(c["name"]))
	var nb: Vector2i = sm.tile_neighbours(sol_t)[0]
	sm.set_cluster_origin(sm.tile_center(nb))          # leave, evicting three tiles
	sm.set_cluster_origin(Vector3.ZERO)                # and come back
	var after: Array = sm.star_clusters()
	check(after.size() == all.size(), "returning rebuilds the same number of clusters")
	var same: bool = true
	for i in range(after.size()):
		if str((after[i] as Dictionary)["name"]) != str(before_names[i]):
			same = false
			break
	check(same, "and the identical ones — a tile regenerates exactly as it was")

	# ── Sol's own cluster, and the ones bordering it ──
	check(sm.sol_cluster_index() >= 0, "Sol is inside a cluster")
	check(bool((sm.star_clusters()[sm.sol_cluster_index()] as Dictionary).get("is_home", false)),
		"which at the start of a run is the home cluster")
	var focus: PackedInt32Array = sm.focus_cluster_indices()
	check(focus.size() >= 4, "it has bordering clusters: %d" % focus.size())
	check(focus.size() < all.size() / 10,
		"and they are a neighbourhood, not the whole shell: %d of %d" % [focus.size(), all.size()])
	check(focus.has(sm.sol_cluster_index()), "the focus includes Sol's own cluster")
	for i: int in focus:
		check(not (sm.cluster_cell_faces(i) as Array).is_empty(),
			"every focus cluster has a carved cell")
	# Nothing outside the focus is carved — that is what keeps a crossing affordable.
	var carved_outside: int = 0
	for i in range(all.size()):
		if not focus.has(i) and not (sm.cluster_cell_faces(i) as Array).is_empty():
			carved_outside += 1
	check(carved_outside == 0, "and nothing outside it is: %d" % carved_outside)

	# ── Crossing a cluster border swaps the focus ──
	var old_focus: Array = []
	for i: int in focus:
		old_focus.append(str((sm.star_clusters()[i] as Dictionary)["name"]))
	# Step onto a cluster that is NOT currently bordering, and the neighbourhood must change.
	var far_idx: int = -1
	for i in range(all.size()):
		if not focus.has(i):
			far_idx = i
			break
	check(far_idx >= 0, "there is a cluster outside the current focus to move to")
	sm.set_cluster_origin((sm.star_clusters()[far_idx] as Dictionary)["pos"] as Vector3)
	check(sm.sol_cluster_index() == far_idx, "Sol is now in that cluster")
	var new_focus: Array = []
	for i: int in sm.focus_cluster_indices():
		new_focus.append(str((sm.star_clusters()[i] as Dictionary)["name"]))
	check(new_focus.size() >= 4, "it has its own bordering clusters: %d" % new_focus.size())
	var kept: int = 0
	for n in new_focus:
		if old_focus.has(n):
			kept += 1
	check(kept < new_focus.size(),
		"and they are not the old ones: %d of %d carried over" % [kept, new_focus.size()])

	# ── Crossing a TILE border swaps the loaded tiles ──
	var old_tiles: Array = sm.loaded_tiles()
	sm.set_cluster_origin(sm.tile_center(nb))
	var now_tiles: Array = sm.loaded_tiles()
	check(sm.loaded_tile() == nb, "the patch re-centres on the tile Sol entered")
	check(now_tiles.size() == 7, "and is still seven tiles")
	var dropped: int = 0
	for t: Vector2i in old_tiles:
		if not now_tiles.has(t):
			dropped += 1
	check(dropped == 3, "three tiles stop bordering and are evicted: %d" % dropped)
	var added: int = 0
	for t: Vector2i in now_tiles:
		if not old_tiles.has(t):
			added += 1
	check(added == 3, "and three new ones are generated: %d" % added)

	# ── The in-cell path is free, because it runs on every tick ──
	sm.set_cluster_origin(Vector3.ZERO)
	var centre: Vector3 = (sm.star_clusters()[sm.sol_cluster_index()] as Dictionary)["pos"]
	var t0: int = Time.get_ticks_msec()
	for i in range(20000):
		sm.set_cluster_origin(centre + Vector3(float(i) * 1.0e-4, 0.0, 0.0))
	var ms: int = Time.get_ticks_msec() - t0
	check(ms < 400, "20 000 in-cell updates stay cheap: %d ms" % ms)

	# ── Game drives it from Sol's real position ──
	ss.reset_star()
	ss.set_star_mirror_coverage(1.0)
	ss.aim_star_thrust(Vector3(1, 0, 0), "stream")
	ss.star_thrust_mult = 1.0e9          # the console cheat, so the star actually goes somewhere
	var start_cluster: int = sm.sol_cluster_index()
	for _y in range(40):
		g._run_star_thrust(365.25 * 2.0e8)
	check(ss.star_drift_dist_ly > 0.0, "the thruster moved Sol: %s ly" % str(ss.star_drift_dist_ly))
	if ss.star_drift_dist_ly > sm.get("_focus_safe_r"):
		check(sm.sol_cluster_index() != start_cluster,
			"and far enough that it has left its starting cluster")
	ss.reset_star()

	print("FAILS: %d" % fails)
	quit()
