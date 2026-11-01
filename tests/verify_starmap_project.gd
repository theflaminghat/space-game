extends SceneTree

## The inlined projection has to agree with _project, exactly.
##
## The star field and the cluster shell are fifteen thousand points on a charted map, and both
## loops used to call _project and _detail_alpha once per point. Between them those re-derived
## the view radius, the camera distance, the near plane and the detail band on EVERY call — frame
## constants, recomputed fifteen thousand times, through two nested GDScript calls each.
##
## They are now hoisted once per frame and the arithmetic is written out inline in the two hot
## loops. That is a deliberate duplication of a formula, and the reason it is safe is this file:
## _project and _detail_alpha stay the definition of record, every other caller still goes
## through them, and a change to either that the inlined copies do not follow fails here rather
## than showing up as a star field quietly drawn in the wrong place.

## Beyond this a projected coordinate is far outside any panel and only its relative accuracy
## means anything; within it, a disagreement is something the player could see.
const DRAWABLE_PX: float = 1.0e5

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(20261031)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	g.sidebar.show_star_map()
	var m: Control = g.sidebar.star_map
	m.size = Vector2(1200, 800)
	for _i in range(5): await process_frame

	# Across a spread of views, not one: the near-plane clamp in _persp only bites at some of
	# them, and a formula that matches at the default zoom can still be wrong where it does.
	var views: Array = [
		[1.0, 0.0, 0.0], [1.0, 0.7, -0.3], [4.0, 2.4, 0.9],
		[0.25, -1.1, 0.45], [18.0, 3.9, -1.2],
	]
	var worst_p: float = 0.0
	var worst_rel: float = 0.0
	var worst_a: float = 0.0
	var checked: int = 0
	for v: Array in views:
		m._zoom = float(v[0])
		m._yaw = float(v[1])
		m._pitch = float(v[2])
		var center: Vector2 = m.size * 0.5
		var b: Basis = m._view_basis()
		var ppu: float = m._fit_scale(center)
		# The same hoist _draw does.
		var bx: Vector3 = b.x
		var by: Vector3 = b.y
		var bz: Vector3 = b.z
		var vr_now: float = m._view_radius_now()
		var cam_d: float = vr_now * m.CAMERA_DIST_VR
		var near_d: float = vr_now * m.NEAR_CLIP_VR
		var band_r: float = m._max_display_radius() / m._zoom
		var band_hi: float = band_r * m.LABEL_OUTER_FRAC
		var band_lo: float = band_r * m.LABEL_INNER_FRAC
		var band_span: float = band_hi - band_lo
		check(band_span > 0.0, "the detail band is not degenerate at zoom %f" % m._zoom)

		# Real catalogue positions, so the depths and radii are the ones the map actually sees,
		# plus a few extremes to reach the near-plane clamp and the band edges.
		var pts: Array = []
		var stars: Array = m.all_stars()
		for i in range(0, stars.size(), maxi(1, stars.size() / 120)):
			pts.append(m._rel((stars[i] as Dictionary)["pos"]))
		for extra: Vector3 in [Vector3.ZERO, Vector3(0, 0, 1e6), Vector3(0, 0, -1e6),
				Vector3(1e5, -2e5, 3e5), Vector3(1e-7, 1e-7, 1e-7)]:
			pts.append(extra)

		for p: Vector3 in pts:
			checked += 1
			# ── the projection ──
			var want: Vector2 = m._project(p, b, center, ppu)
			var sc: float = ppu * (cam_d / maxf(cam_d - p.dot(bz), near_d))
			var got := Vector2(center.x + p.dot(bx) * sc, center.y - p.dot(by) * sc)
			var err: float = (want - got).length()
			# Absolute agreement is only meaningful where a pixel is meaningful. The synthetic
			# extremes below project to hundreds of millions of pixels, where single-precision
			# rounding alone is tens of pixels — so those are held to a RELATIVE tolerance and
			# anything that could actually be drawn is held to a fraction of a pixel.
			if absf(want.x) < DRAWABLE_PX and absf(want.y) < DRAWABLE_PX:
				worst_p = maxf(worst_p, err)
			worst_rel = maxf(worst_rel, err / maxf(want.length(), 1.0))
			# ── the detail alpha ──
			var dr: float = p.length()
			var want_a: float = m._detail_alpha(dr)
			var got_a: float = 0.0
			if dr > band_lo and dr < band_hi:
				var t: float = (dr - band_lo) / band_span
				got_a = clampf(t / m.LABEL_FADE, 0.0, 1.0) * clampf((1.0 - t) / m.LABEL_FADE, 0.0, 1.0)
			worst_a = maxf(worst_a, absf(want_a - got_a))

	check(checked > 300, "enough points were compared: %d" % checked)
	# Bit-for-bit is not required, but anything a pixel could notice is.
	check(worst_p < 0.01,
		"the inlined projection matches _project where it matters: worst %f px over %d points" % [
			worst_p, checked])
	check(worst_rel < 1.0e-5,
		"and agrees to rounding even at absurd depth: worst relative error %.8f" % worst_rel)
	check(worst_a < 1.0e-6,
		"and the inlined band matches _detail_alpha: worst error %f" % worst_a)

	print("FAILS: %d" % fails)
	quit()
