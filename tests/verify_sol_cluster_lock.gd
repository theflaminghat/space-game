extends SceneTree

## The Sol cluster is the Voronoi cell around the Sun — the ground the player starts on.  Until
## they hold a star outside it, it is not an object to inspect but simply where they are, and a
## click near the Sun should reach the Sun rather than a readout about Sol's own neighbourhood.
## Settling anything beyond the cell latches it open, and the latch survives losing that colony.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _home_index(p) -> int:
	var cl: Array = p.star_clusters()
	for i in range(cl.size()):
		if bool((cl[i] as Dictionary).get("is_home", false)):
			return i
	return -1

func _run() -> void:
	seed(20260927)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(40): await process_frame
	var g: Node = current_scene
	var p = g.sidebar.star_map
	g.sidebar.hide_all()
	p.show()
	for _i in range(4): await process_frame

	var home: int = _home_index(p)
	check(home >= 0, "the home cluster exists")
	var home_name: String = str((p.star_clusters()[home] as Dictionary)["name"])

	# ── Closed at the opening of a run ──
	check(not g.left_sol_cell, "a new run has not left the home cell")
	check(not p._cluster_pickable(home), "so the home cluster is not pickable")
	check(p.focus_star(home_name) == false, "and cannot be focused")
	check(p.get("_selected_cluster") == -1, "nothing got selected by trying")

	# Every other cluster is pickable throughout — this locks one object, not the shell.
	var others := 0
	for ci in range(p.star_clusters().size()):
		if ci == home:
			continue
		if p._cluster_pickable(ci):
			others += 1
	check(others == p.star_clusters().size() - 1, "every other cluster stays pickable")

	# ── The home cell test itself ──
	check(not g._outside_sol_cell(Vector3.ZERO), "Sol is inside the home cell")
	var reach: float = p.sol_cell_reach_ly()
	check(reach > 0.0, "the home cell has an outer reach")
	check(g._outside_sol_cell(Vector3(reach * 4.0, 0.0, 0.0)),
		"a point well past the reach is outside it")
	var inside_star := ""
	for s: Dictionary in p.all_stars():
		if not g._outside_sol_cell(s["pos"] as Vector3):
			inside_star = str(s["name"]); break
	check(inside_star != "", "the catalogue has a star inside the cell")

	# ── Colonising inside the cell does not open it ──
	g._colonize_star(inside_star)
	check(not g.left_sol_cell, "a colony inside the cell does not unlock it")
	check(not p._cluster_pickable(home), "and the cluster is still locked")

	# ── Colonising outside does ──
	# The cluster shell lies beyond the catalogue, so one of its own stars is reliably outside.
	var far_cluster := ""
	for ci in range(p.star_clusters().size()):
		if ci == home:
			continue
		far_cluster = str((p.star_clusters()[ci] as Dictionary)["name"]); break
	check(g._outside_sol_cell(g._star_pos(far_cluster)), "a cluster is outside the home cell")
	g._colonize_star(far_cluster)
	check(g.left_sol_cell, "holding something beyond the cell latches it open")

	g.refresh_star_map()
	for _i in range(4): await process_frame
	check(p._cluster_pickable(home), "the map was told, and the cluster is pickable")
	check(p.focus_star(home_name), "and it can now be focused")
	check(str(p.selected_star()) == home_name, "focusing selects it")

	# ── The latch does not reverse when the colony is lost ──
	g._uncolonize_star(far_cluster)
	g.refresh_star_map()
	for _i in range(4): await process_frame
	check(g.left_sol_cell, "losing the distant colony does not relock it")
	check(p._cluster_pickable(home), "so the map object does not vanish again")

	# ── Withdrawing the right clears a standing selection ──
	p.focus_star(home_name)
	check(str(p.selected_star()) == home_name, "the home cluster is selected")
	p.set_home_cluster_selectable(false)
	check(p.get("_selected_cluster") == -1, "closing the lock drops the selection")
	p.set_home_cluster_selectable(true)

	# ── It survives a save/load ──
	var data: Dictionary = {}
	SaveSchema.encode(g, root.get_node("SolarSystem"))
	g.left_sol_cell = true
	data = SaveSchema.encode(g, root.get_node("SolarSystem"))
	check(bool(data.get("left_sol_cell", false)), "the latch is written to the save")
	g.left_sol_cell = false
	SaveSchema.decode(data, g, root.get_node("SolarSystem"))
	check(g.left_sol_cell, "and restored from it")

	# ── A legacy save without the key re-derives from the colonies it holds ──
	g.left_sol_cell = false
	g.colonized_stars = [far_cluster]
	g._resync_colonized_stars()
	g._recheck_sol_cell()
	check(g.left_sol_cell, "an old save with a distant colony opens the lock on load")

	print("FAILS: %d" % fails)
	quit()
