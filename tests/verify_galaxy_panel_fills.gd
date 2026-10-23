extends SceneTree

## The galaxy panel's filled polygons are refused when they cannot be triangulated.
##
## draw_colored_polygon triangulates, and two things make that fail — a sliver whose area rounds
## to nothing, and a shape so far from the origin that 32-bit cancellation eats its area.  A
## refusal aborts the REST of that canvas item's output, not just the one shape, so a single
## bad cell blanks everything drawn after it.
##
## Both shapes here are cross-sections: Voronoi territory cells sliced at an arbitrary plane,
## and the hexagonal top faces of the region prisms.  At any scale some cell can be clipped
## edge-on, which is why this reproduced at zoom 10 while 0.15 and 500 were clean — it is not an
## extreme-zoom problem and a zoom limit would not have fixed it.

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
	var gp = g.sidebar.galaxy_debug
	check(gp != null, "the galaxy panel exists")
	g.sidebar.hide_all()
	gp.show()
	for _i in range(5): await process_frame

	# ── The predicate itself ──
	var square := PackedVector2Array([
		Vector2(0, 0), Vector2(40, 0), Vector2(40, 40), Vector2(0, 40)])
	check(gp._polygon_fillable(square), "an ordinary square is fillable")
	check(not gp._polygon_fillable(PackedVector2Array([Vector2(0, 0), Vector2(5, 5)])),
		"two points are not a polygon")
	# A sliver: three points on a line.  This is the shape a cell clipped edge-on becomes.
	check(not gp._polygon_fillable(PackedVector2Array([
		Vector2(0, 0), Vector2(50, 50), Vector2(100, 100)])),
		"a collinear sliver is refused")
	# Real area, but below a pixel.
	check(not gp._polygon_fillable(PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.4)])),
		"a sub-pixel triangle is refused")
	# Far from the origin, where the triangulator loses the area to cancellation.
	var far := PackedVector2Array()
	for p in square:
		far.append(p + Vector2(400000.0, 400000.0))
	check(not gp._polygon_fillable(far), "a shape far outside the panel is refused")
	var nan_poly := PackedVector2Array([
		Vector2(0, 0), Vector2(40, 0), Vector2(NAN, 40)])
	check(not gp._polygon_fillable(nan_poly), "a polygon with a non-finite corner is refused")

	# ── A real draw at the zoom that reproduced it ──
	# A triangulation failure prints to stderr, which run.sh surfaces, so a regression fails the
	# suite rather than passing quietly.  One zoom rather than a sweep: each redraw re-slices
	# the Voronoi partition, and the suite gives each test 240 s.
	gp.set("_zoom", 10.0)
	gp.queue_redraw()
	for _i in range(4): await process_frame
	check(true, "the zoom that used to fail now draws cleanly")

	# ── The cells are still being drawn, so the guard has not blanked the map ──
	gp.set("_territory_z", 0.0)
	var slices: Array = g.sidebar.star_map.cluster_slice(0.0)
	# A handful, not the whole shell: only Sol's own cell and the ones bordering it are carved
	# now, so a cross-section has that many cells in it and no more.  The rest of the patch is
	# drawn as points and has no cross-section to take.
	check(slices.size() >= 3, "the slice has cells in it: %d" % slices.size())
	var b = gp._view_basis()
	var centre: Vector2 = gp.size * 0.5
	var s: float = gp._scale_px(centre)
	var fillable: int = 0
	for cell: Dictionary in slices:
		var scr := PackedVector2Array()
		for wp: Vector3 in (cell["poly"] as PackedVector3Array):
			scr.append(gp._project(wp, b, centre, s))
		if gp._polygon_fillable(scr):
			fillable += 1
	check(fillable > slices.size() / 2,
		"most cells are still filled, not refused: %d of %d" % [fillable, slices.size()])

	print("FAILS: %d" % fails)
	quit()
