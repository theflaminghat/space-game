extends SceneTree

## Our own galaxy regions are on the star map, drawn the way the rival front is, in green.
##
## The front was the only territory the star map drew.  Pulled back to galactic scale, the
## regions humanity had settled showed as nothing at all — the galaxy map painted them green and
## the star map, looking at the same volume, did not — so the race the front exists to set up
## could only be seen from one side.
##
## What has to hold:
##   Game hands the map every tile we hold a share of, with the share the galaxy map paints
##   the map draws one mark per tile, by the front's own rule (solid past FrontData.DENIED_SHARE,
##     faint below it), in the human green rather than the front's colours
##   it is a layer of its own: on by default, and switching it off neither touches the front nor
##     is touched by it

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _rgb(c: Color) -> Color:
	return Color(c.r, c.g, c.b)

## Draw one frame and hand back the region marks' colours.
func _drawn(sm: Control) -> PackedColorArray:
	sm.queue_redraw()
	await process_frame
	return sm._region_marks.col

func _run() -> void:
	seed(20261112)
	var gs: Node = root.get_node("GameSession")
	gs.should_load_on_start = false
	gs.setup = {"front": 2}
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var sm: Control = g.sidebar.star_map
	var FD = load("res://vn_front.gd")

	# Settle a region well away from Sol, most of the way, and one barely touched.
	var far_id: String = ""
	var thin_id: String = ""
	for rg: Dictionary in g.galaxy_region_grid():
		var c: Vector3 = rg["center"]
		if c.length() > 8000.0 and c.length() < 12000.0 and float(rg["frac"]) == 0.0:
			if far_id == "":
				far_id = str(rg["id"])
			elif thin_id == "":
				thin_id = str(rg["id"])
				break
	check(far_id != "" and thin_id != "", "two empty tiles to settle: %s, %s" % [far_id, thin_id])
	if far_id == "" or thin_id == "":
		print("FAILS: %d" % fails); quit(); return
	var far: Dictionary = g._get_region(far_id)
	far["colonized"] = float(far["colonizable"]) * 0.8
	var thin: Dictionary = g._get_region(thin_id)
	thin["colonized"] = maxf(float(thin["colonizable"]) * 0.05, 1.0)

	# ── What Game hands over ──
	var want: Dictionary = {}
	for rg: Dictionary in g.galaxy_region_grid():
		if float(rg["frac"]) > 0.0:
			want[rg["center"]] = float(rg["frac"])
	var cells: Array = g.held_region_map_cells()
	var got: Dictionary = {}
	for e in cells:
		got[(e as Array)[0]] = float((e as Array)[1])
	check(got.size() == want.size() and got.size() >= 3,
		"one entry per tile the galaxy map paints green: %d of %d" % [got.size(), want.size()])
	var wrong: int = 0
	for pos in want:
		if not got.has(pos) or not is_equal_approx(float(got[pos]), float(want[pos])):
			wrong += 1
	check(wrong == 0, "each at the galaxy map's own share: %d differ" % wrong)
	var far_c: Vector3 = g._region_center(far_id)
	check(got.has(far_c) and is_equal_approx(float(got[far_c]), 0.8),
		"the settled region is there at 0.8: %s" % str(got.get(far_c, "missing")))
	check(got.has(g._region_center(g._region_id(Vector3.ZERO))), "and Sol's own tile")

	g.sidebar.show_star_map()
	g.refresh_star_map()          # which pushes only while the map is open
	for _i in range(4): await process_frame
	check(sm._held_regions.size() == cells.size(),
		"the star map is given them on refresh: %d" % sm._held_regions.size())

	# ── A layer of its own ──
	check(sm._layers.has("regions") and sm._layer_boxes.has("regions"),
		"our regions are a map layer, with a checkbox")
	check(sm.layer_shown("regions"), "on by default")

	# Galactic scale, where territory is in band.
	var deep_zoom: float = sm._zoom
	sm._zoom = 1.0
	var cols: PackedColorArray = await _drawn(sm)
	check(not cols.is_empty(), "pulled back, our regions are drawn: %d marks" % cols.size())

	# Exactly the two greens, by the front's threshold.  One place carrying both shares, so both
	# marks are on screen or neither is — the same trick the front's own test uses.
	var vis: Vector3 = Vector3.INF
	for e in cells:
		sm.set_held_regions([[(e as Array)[0], 1.0]])
		if not (await _drawn(sm)).is_empty():
			vis = (e as Array)[0]
			break
	check(vis != Vector3.INF, "some tile of ours is on screen at galactic zoom")
	sm.set_held_regions([[vis, 1.0], [vis, FD.DENIED_SHARE * 0.5]])
	cols = await _drawn(sm)
	check(cols.size() == 2, "both marks are built: %d" % cols.size())
	var held_rgb: Color = _rgb(sm.REGION_HELD_COLOR)
	var part_rgb: Color = _rgb(sm.REGION_SETTLING_COLOR)
	check(cols.size() == 2 and _rgb(cols[0]).is_equal_approx(held_rgb),
		"a tile past the threshold is drawn in the held green: %s" % str(cols[0] if cols.size() > 0 else "none"))
	check(cols.size() == 2 and _rgb(cols[1]).is_equal_approx(part_rgb),
		"a tile short of it in the fainter one: %s" % str(cols[1] if cols.size() > 1 else "none"))
	check(cols.size() == 2 and cols[0].a > cols[1].a, "and the more of it is ours, the more solid")
	check(held_rgb.is_equal_approx(_rgb(sm.STATUS_COL_HUMAN)),
		"the held green is the colour our own stars are drawn in")
	check(not held_rgb.is_equal_approx(_rgb(sm.FRONT_HELD_COLOR))
		and not part_rgb.is_equal_approx(_rgb(sm.FRONT_CONTESTED_COLOR)),
		"and neither green is a front colour")

	# ── The two territory layers do not reach into each other ──
	sm.set_layer_shown("regions", false)
	cols = await _drawn(sm)
	check(cols.is_empty(), "switched off, ours is not drawn and its buffer is cleared: %d" % cols.size())
	sm.set_layer_shown("regions", true)
	cols = await _drawn(sm)
	check(not cols.is_empty(), "and switched back on it is rebuilt")
	sm.set_front([[vis, 1.0]])
	sm.set_layer_shown("front", false)
	cols = await _drawn(sm)
	check(not cols.is_empty(), "the front switched off leaves ours alone")
	sm.set_layer_shown("front", true)
	sm.set_layer_shown("regions", false)
	await _drawn(sm)
	check(not sm._front_marks.pts.is_empty(), "and ours switched off leaves the front alone")
	sm.set_layer_shown("regions", true)
	sm._zoom = deep_zoom

	print("FAILS: %d" % fails)
	quit()
