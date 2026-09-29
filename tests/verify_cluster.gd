extends SceneTree
var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	# Pin the global RNG BEFORE the scene loads.  Game._ready sets galaxy_seed = randi(), so
	# without this the generated sky — and every polity, colony and war seeded off it — differs
	# from one run of this test to the next, and the counts asserted below are a coin toss.
	seed(20260927)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(25): await process_frame
	var g: Node = current_scene
	var SM = load("res://StarMapPanel.gd")
	# A cluster that is not the home one.
	var cname := ""
	var cpos := Vector3.ZERO
	for c in SM.star_clusters():
		if not bool(c.get("is_home", false)):
			cname = str(c["name"]); cpos = c["pos"]; break
	print("test cluster: ", cname)

	# ── Landing seeds it at exactly nothing ──
	g.cluster_colonized = {}
	g._pending_event_notifications = []
	check(not g.cluster_colonized.has(cname), "unseeded to start")
	g.cluster_colonized[cname] = 0.0        # what the arrival does
	check(is_equal_approx(float(g.cluster_colonized[cname]), 0.0), "starts at 0%")
	check(g._holdings_beyond_sol() >= 1, "a probe on the ground counts as a holding at 0%")

	# ── It fills itself, at the region law's rate ──
	var rate: float = float(g.CLUSTER_SATURATE_RATE)
	check(is_equal_approx(rate, float(g.REGION_SATURATE_RATE)), "same law as the regions")
	g._cluster_last_year = float(g.year)
	var samples: Array = []
	for step in [1000, 10000, 50000, 100000, 250000, 400000]:
		g.year = 2026 + step
		g._cluster_last_year = 2026.0           # cluster settling has its own clock
		g.cluster_colonized[cname] = 0.0
		g._update_regions()
		samples.append("%d yr: %.1f%%" % [step, float(g.cluster_colonized[cname]) * 100.0])
	print("settling: ", " | ".join(samples))
	# The shape: linear in the rate, saturating at 1.
	g.cluster_colonized[cname] = 0.0
	g.year = 2026 + 100000
	g._cluster_last_year = 2026.0
	g._update_regions()
	check(absf(float(g.cluster_colonized[cname]) - rate * 100000.0) < 1.0e-6,
		"fills at the stated rate: %s" % g.cluster_colonized[cname])
	# One clean fill, from empty to full in steps, with the queue cleared first: the sampling
	# above deliberately rewound a finished cluster several times, which the game never does and
	# which would otherwise leave its announcements lying in the queue.
	g._pending_event_notifications.clear()
	g.cluster_colonized[cname] = 0.0
	g._cluster_last_year = 2026.0
	for step in [200000, 400000, 600000, 1000000]:
		g.year = 2026 + step
		g._update_regions()
	check(is_equal_approx(float(g.cluster_colonized[cname]), 1.0), "and stops at 100%")
	var done: Array = g._pending_event_notifications.filter(func(n): return str(n["id"]) == "cluster_done_%s" % cname)
	check(done.size() == 1, "completion announced once across the whole fill: %d" % done.size())

	# ── One probe is the whole requirement ──
	var seeded_targets: Array = g._vn_candidate_targets(Vector3.ZERO, 1.0e9, 20) \
		if g.has_method("_vn_candidate_targets") else []
	check(not seeded_targets.has(cname), "a seeded cluster is no longer offered as a probe target")
	# …even though it is nowhere near full.
	g.cluster_colonized[cname] = 0.02
	var again: Array = g._vn_candidate_targets(Vector3.ZERO, 1.0e9, 20) \
		if g.has_method("_vn_candidate_targets") else []
	check(not again.has(cname), "still not offered at 2% settled")

	# ── Saves keep a seeded-but-empty cluster ──
	g.cluster_colonized = {cname: 0.0}
	g.save_game("user://saves/cluster.json")
	g.cluster_colonized = {}
	g.load_game("user://saves/cluster.json")
	check(g.cluster_colonized.has(cname), "a 0% cluster survives a save")
	print("FAILS: ", fails)
	quit()
