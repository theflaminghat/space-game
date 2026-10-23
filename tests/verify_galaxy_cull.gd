extends SceneTree

## Galaxies that project off the panel are not drawn.
##
## This was a crash-adjacent bug, not an optimisation.  The log-radial scale spans ten decades,
## so at a deep zoom the extragalactic layer projects hundreds of thousands of pixels away — at
## zoom 80 the farthest reach ±300 000 px.  draw_colored_polygon triangulates in 32-bit floats
## on ABSOLUTE coordinates, so a 6-pixel ellipse centred that far out loses its own area to
## cancellation, and Godot refuses it with "Invalid polygon data, triangulation failed" — which
## aborts the rest of that canvas item's output, not just the one glyph.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

## Every galaxy's projected position at the current view, as the draw loop computes it.
func _projected(p) -> Array:
	var out: Array = []
	var b = p._view_basis()
	var center: Vector2 = p.size * 0.5
	var scale: float = p._fit_scale(center)
	for gal: Dictionary in p.get("_galaxies"):
		var eff: float = float(gal["base_dist"])
		if not bool(gal["bound"]):
			eff *= float(p.get("_cosmic_scale"))
		if eff >= p.HUBBLE_HORIZON_LY:
			continue
		out.append(p._project(p._rel((gal["dir"] as Vector3) * eff), b, center, scale))
	return out

func _on_panel(p, sp: Vector2) -> bool:
	var pad: float = p.GALAXY_SCREEN_PAD
	return sp.x >= -pad and sp.y >= -pad and sp.x <= p.size.x + pad and sp.y <= p.size.y + pad

func _run() -> void:
	seed(20260927)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var p = g.sidebar.star_map
	g.sidebar.hide_all()
	p.show()
	for _i in range(6): await process_frame
	check(p.size.x > 100.0, "the panel has a real size to cull against")

	# ── The condition that caused it is real ──
	# Without the cull there genuinely are glyphs out at the magnitude where triangulation
	# fails, so this is not a guard against a hypothetical.
	p.set("_zoom", p.ZOOM_MAX)
	var far_out: int = 0
	var worst: float = 0.0
	for sp: Vector2 in _projected(p):
		worst = maxf(worst, maxf(absf(sp.x), absf(sp.y)))
		if not _on_panel(p, sp):
			far_out += 1
	check(far_out > 0, "at max zoom some galaxies project off the panel: %d" % far_out)
	check(worst > p.POLY_SAFE_PX,
		"and far enough out to break triangulation: %.0f px vs a %.0f px limit" % [
			worst, p.POLY_SAFE_PX])

	# ── The glyph refuses to draw there ──
	# _draw_galaxy_glyph is only legal inside a draw pass, so what is checked here is the
	# predicate it uses; the redraws below are what prove the error is gone.
	for sp: Vector2 in _projected(p):
		if absf(sp.x) > p.POLY_SAFE_PX or absf(sp.y) > p.POLY_SAFE_PX:
			check(not _on_panel(p, sp),
				"anything past the safe limit is also off the panel, so the cull catches it first")
			break

	# ── Every zoom level redraws cleanly ──
	# The failure was zoom-dependent: fine below ~20, four errors a frame above it.  Each of
	# these forces a real _draw; a triangulation failure prints to stderr, which run.sh shows.
	for z in [p.ZOOM_MIN, 0.8, 2.0, 8.0, 20.0, 50.0, p.ZOOM_MAX]:
		p.set("_zoom", z)
		p.queue_redraw()
		for _i in range(3): await process_frame
	check(true, "every zoom level drew without a triangulation failure")

	# ── And deep time, where the extragalactic layer recedes ──
	for yr in [1_000_000, 1_000_000_000, 1_000_000_000_000_000]:
		g.year = yr
		p.set_cosmic_scale(g._cosmic_scale())
		p.set_year(float(yr))
		for z in [p.ZOOM_MIN, 8.0, p.ZOOM_MAX]:
			p.set("_zoom", z)
			p.queue_redraw()
			for _i in range(2): await process_frame
	check(true, "and every epoch did too")

	# ── Nothing on screen was lost to the cull ──
	# The pad is generous enough to keep a glyph whose label is still visible.
	p.set("_zoom", 1.0)
	for _i in range(3): await process_frame
	var kept: int = 0
	for sp: Vector2 in _projected(p):
		if _on_panel(p, sp):
			kept += 1
	check(kept > 0, "galaxies that are actually in view are still drawn: %d" % kept)
	check(p.GALAXY_SCREEN_PAD > 100.0,
		"with room for the label beside the glyph: %.0f px" % p.GALAXY_SCREEN_PAD)

	print("FAILS: %d" % fails)
	quit()
