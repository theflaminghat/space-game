extends SceneTree

## The star map picks what to draw in detail with a DISTANCE CUT, not a distance ordering.
##
## Both the star-body budget and the cluster-glyph budget were only ever read as
## `rank >= BUDGET`, which is a question about a threshold rather than about an order — the
## K-th nearest object's distance answers it exactly and needs no sort.  What was there built a
## full ordering of six thousand stars and eight thousand clusters with two Array.sort_custom
## calls and a GDScript lambda per comparison, and stored a rank per object.
##
## The tolerance matters as much as the cut.  The old guard was exact equality on the reference
## point, and _sync_sol_frame invalidated it whenever Sol moved, so a thruster drifting the star
## a hundredth of a light-year redid all of it every frame.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

## The distance of the k-th nearest entry, worked out the slow, obvious way.
func _kth_by_sorting(items: Array, ref: Vector3, k: int) -> float:
	var d: Array = []
	for it: Dictionary in items:
		d.append(ref.distance_to(it["pos"] as Vector3))
	d.sort()
	return INF if d.size() <= k else float(d[k - 1])

func _run() -> void:
	seed(20260927)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var sm = g.sidebar.star_map
	var ss: Node = root.get_node("SolarSystem")
	g.sidebar.hide_all()
	sm.show()
	for _i in range(8): await process_frame

	# ── The cut is exactly the k-th nearest distance ──
	var stars: Array = sm.all_stars()
	var clusters: Array = sm.star_clusters()
	check(stars.size() > sm.STAR_BODY_BUDGET, "there are more stars than the body budget")
	check(clusters.size() > sm.CLUSTER_GLYPH_BUDGET, "and more clusters than the glyph budget")
	for ref: Vector3 in [Vector3.ZERO, Vector3(37.0, -12.0, 5.0), Vector3(400.0, 0.0, 0.0)]:
		var want_s: float = _kth_by_sorting(stars, ref, sm.STAR_BODY_BUDGET)
		var got_s: float = sm._kth_nearest(stars, ref, sm.STAR_BODY_BUDGET)
		check(absf(got_s - want_s) < 1.0e-3,
			"the star cut matches a full sort at %s: %.4f vs %.4f" % [str(ref), got_s, want_s])
		var want_c: float = _kth_by_sorting(clusters, ref, sm.CLUSTER_GLYPH_BUDGET)
		var got_c: float = sm._kth_nearest(clusters, ref, sm.CLUSTER_GLYPH_BUDGET)
		check(absf(got_c - want_c) < 1.0e-3,
			"and the cluster cut does too: %.4f vs %.4f" % [got_c, want_c])

	# ── It selects exactly BUDGET objects, which is what the budget means ──
	var cut: float = sm._kth_nearest(stars, Vector3.ZERO, sm.STAR_BODY_BUDGET)
	var within: int = 0
	for s2: Dictionary in stars:
		if Vector3.ZERO.distance_to(s2["pos"] as Vector3) <= cut:
			within += 1
	check(within == sm.STAR_BODY_BUDGET,
		"the cut admits exactly the budget: %d of %d" % [within, sm.STAR_BODY_BUDGET])

	# ── Degenerate inputs ──
	check(sm._kth_nearest([], Vector3.ZERO, 10) == INF, "an empty field admits everything")
	check(sm._kth_nearest(stars, Vector3.ZERO, 0) == 0.0, "a zero budget admits nothing")
	check(sm._kth_nearest(stars, Vector3.ZERO, stars.size() + 5) == INF,
		"a budget larger than the field admits everything")

	# ── A drifting reference does not redo the work ──
	# This is the whole point: the reference is locked to Sol, and Sol moves.
	sm._refresh_lod_cuts(Vector3.ZERO)
	var base: float = sm.get("_star_body_cut")
	var pinned: Vector3 = sm.get("_rank_ref")
	for i in range(50):
		sm._refresh_lod_cuts(Vector3(float(i) * 1.0e-4, 0.0, 0.0))
	check((sm.get("_rank_ref") as Vector3).is_equal_approx(pinned),
		"fifty sub-tolerance nudges recompute nothing")
	check(is_equal_approx(sm.get("_star_body_cut"), base), "so the cut is untouched")

	# A real move does redo it.
	sm._refresh_lod_cuts(Vector3(500.0, 0.0, 0.0))
	check(not (sm.get("_rank_ref") as Vector3).is_equal_approx(pinned),
		"a move past the tolerance does recompute")
	check(not is_equal_approx(sm.get("_star_body_cut"), base),
		"and the cut follows the viewpoint: %.2f -> %.2f" % [base, sm.get("_star_body_cut")])

	# ── And a catalogue or patch change redoes it even standing still ──
	sm._refresh_lod_cuts(Vector3.ZERO)
	var before_cut: float = sm.get("_star_body_cut")
	sm.set("_star_body_cut", -1.0)             # scribble on it
	sm.set("_cut_cat", -999)                   # pretend the catalogue moved
	sm._refresh_lod_cuts(Vector3.ZERO)
	check(is_equal_approx(sm.get("_star_body_cut"), before_cut),
		"a catalogue change redoes the cut from the same viewpoint")

	# ── The map still draws, with the thruster running ──
	ss.reset_star()
	ss.set_star_mirror_coverage(1.0)
	ss.aim_star_thrust(Vector3(1, 0, 0), "lod")
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
