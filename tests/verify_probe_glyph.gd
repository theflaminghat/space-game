extends SceneTree

## The chevron on a von Neumann probe track marks the craft itself.  It is worth drawing only
## where the map is drawing something for it to be over: past STATUS_COLOR_LY a star is a bare
## status point, and a cluster is never a body at all, so a probe flying between two such places
## got a glyph over blank sky — thousands of them once the swarm is running.  The ROUTE still
## draws in every case; only the glyph is conditional.

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
	var p = g.sidebar.star_map
	g.sidebar.hide_all()
	p.show()
	for _i in range(4): await process_frame

	var cut: float = p.STATUS_COLOR_LY

	# A near star, a far star, and a cluster, all named from what the map itself resolves.
	var near := ""
	var far := ""
	for s: Dictionary in p.all_stars():
		var d: float = (s["pos"] as Vector3).length()
		if d < cut * 0.5 and near == "":
			near = str(s["name"])
		elif d > cut * 2.0 and far == "":
			far = str(s["name"])
	var clusters: Array = p.star_clusters()
	check(near != "", "found a star inside the cutoff")
	check(far != "", "found a star beyond the cutoff")
	check(clusters.size() > 0, "the cluster shell exists")
	var clu: String = str((clusters[0] as Dictionary)["name"])

	# Positions as the renderer resolves them, through the same path the draw loop uses.
	var np: Array = []; var fp: Array = []; var cp: Array = []
	check(p._target_pos(near, np), "the near star resolves")
	check(p._target_pos(far, fp),  "the far star resolves")
	check(p._target_pos(clu, cp),  "the cluster resolves")

	# ── The endpoint test itself, in the Sol frame ──
	check(p._endpoint_resolved("", Vector3.ZERO), "home is resolved")
	check(p._endpoint_resolved(near, np[0]), "a star inside the cutoff is resolved")
	check(not p._endpoint_resolved(far, fp[0]), "a star beyond the cutoff is not")
	check(not p._endpoint_resolved(clu, cp[0]), "a cluster is never resolved")

	# ── The three combinations the glyph must be dropped for ──
	# The draw loop shows the ship when EITHER end is resolved.
	var far2 := ""
	for s: Dictionary in p.all_stars():
		var d: float = (s["pos"] as Vector3).length()
		if d > cut * 2.0 and str(s["name"]) != far:
			far2 = str(s["name"]); break
	check(far2 != "", "found a second star beyond the cutoff")
	var fp2: Array = []
	p._target_pos(far2, fp2)
	var cp2: Array = []
	if clusters.size() > 1:
		p._target_pos(str((clusters[1] as Dictionary)["name"]), cp2)

	var far_far: bool = p._endpoint_resolved(far, fp[0]) or p._endpoint_resolved(far2, fp2[0])
	check(not far_far, "distant star to distant star: no ship")
	var far_clu: bool = p._endpoint_resolved(far, fp[0]) or p._endpoint_resolved(clu, cp[0])
	check(not far_clu, "distant star to cluster: no ship")
	check(not cp2.is_empty(), "the shell has a second cluster to fly between")
	if not cp2.is_empty():
		var clu_clu: bool = p._endpoint_resolved(clu, cp[0]) \
			or p._endpoint_resolved(str((clusters[1] as Dictionary)["name"]), cp2[0])
		check(not clu_clu, "cluster to cluster: no ship")

	# ── And the ones that must keep it ──
	check(p._endpoint_resolved("", Vector3.ZERO) or p._endpoint_resolved(far, fp[0]),
		"home to a distant star: ship kept")
	check(p._endpoint_resolved(near, np[0]) or p._endpoint_resolved(far, fp[0]),
		"a near star to a distant star: ship kept")
	check(p._endpoint_resolved("", Vector3.ZERO) or p._endpoint_resolved(clu, cp[0]),
		"home to a cluster: ship kept")

	# ── Recentring the frame changes the answer, like the rest of the renderer ──
	# A probe between two far stars gets its glyph back once the view is moved out to them.
	p.set("_ref_pos", fp[0])
	check(p._endpoint_resolved(far, fp[0]),
		"the far star is resolved once the frame is centred on it")
	check(not p._endpoint_resolved("", Vector3.ZERO),
		"and home is the distant one from out there")
	p.set("_ref_pos", Vector3.ZERO)

	# ── The route still draws for a suppressed flight: the call must not error ──
	# _draw_probe_track is only legal inside a draw pass, so this exercises the real one.
	g.interstellar_missions.append({
		"kind": "vn", "origin": far, "target": far2, "progress": 0.5,
		"mission": "colonize", "end_year": float(g.year) + 1000.0,
	})
	g.refresh_star_map()
	for _i in range(6): await process_frame
	p.queue_redraw()
	for _i in range(6): await process_frame
	check(true, "a suppressed flight draws without error")

	print("FAILS: %d" % fails)
	quit()
