extends SceneTree

## The rival front is on the galaxy map, not only on the star map.
##
## The front spreads over the galaxy map's own hexes — the region grid is what both of them are
## simulated on — and the galaxy map drew none of it: density and our own settlement, and a tile
## the front had taken outright looked the same as an empty one.  Its info panel had no row for
## it either.
##
## What has to hold, the same as on the star map:
##   nothing shows until the front's signature has reached Sol
##   then every tile shows what the front holds of it, in the star map's colours, solid where
##     the swarm will not fly and faint where it is still contested
##   the info panel says how much of a tile is theirs, and whether it is closed
##   a run with no front shows nothing at all

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _grid_front(g: Node) -> Dictionary:
	var out: Dictionary = {}
	for rg: Dictionary in g.galaxy_region_grid():
		out[str(rg["id"])] = float(rg.get("front", -1.0))
	return out

func _rgb_is(c: Color, want: Color) -> bool:
	return is_equal_approx(c.r, want.r) and is_equal_approx(c.g, want.g) \
		and is_equal_approx(c.b, want.b)

func _run() -> void:
	seed(20261112)
	var gs: Node = root.get_node("GameSession")
	gs.should_load_on_start = false
	gs.setup = {"front": 2}          # "Underway": a head start, so it holds cells from the off
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var gm: Control = g.sidebar.galaxy_map
	var FD = load("res://vn_front.gd")
	var SM = load("res://StarMapPanel.gd")
	check(g.front_active() and g.front_cells.size() > 1, "this run has a front: %d cells"
		% g.front_cells.size())

	# A tile the front holds outright, one it is still contesting, and one it has not reached.
	var grid_ids: Dictionary = _grid_front(g)
	var held: String = ""
	var contested: String = ""
	for id: String in g.front_cells:
		if not grid_ids.has(id):
			continue
		var sh: float = float(g.front_cells[id])
		if FD.denies(sh) and held == "":
			held = id
		elif sh > 0.0 and not FD.denies(sh) and contested == "":
			contested = id
	var clear: String = g._region_id(Vector3.ZERO)      # Sol's own tile
	check(held != "" and contested != "", "the front holds a tile outright and contests another: %s, %s"
		% [held, contested])
	check(not g.front_cells.has(clear), "and has not reached Sol's tile")
	if held == "" or contested == "":
		print("FAILS: %d" % fails); quit(); return

	# ── Nothing shows before the light arrives ──
	check(not g.front_seen, "its signature has not reached Sol yet")
	var before: Dictionary = _grid_front(g)
	var shown_early: int = 0
	for id: String in before:
		if float(before[id]) != 0.0:
			shown_early += 1
	check(before[held] == 0.0 and shown_early == 0,
		"so the grid carries no front at all: %d tiles show one" % shown_early)
	check(gm.front_fill(float(before[held])).a == 0.0, "and the tile it holds draws as untouched")
	gm._selected = held
	gm._refresh_info()
	check((gm._info_rows["Rival front"] as Label).text == "—",
		"its info row says nothing: %s" % (gm._info_rows["Rival front"] as Label).text)

	# ── The signature arrives ──
	g.year = int(g.front_year + g._front_distance_ly()) + 1
	g._check_front_detected()
	check(g.front_seen, "the front has been seen")
	var after: Dictionary = _grid_front(g)
	var wrong: Array = []
	for id: String in after:
		var want: float = float(g.front_cells.get(id, 0.0))
		if not is_equal_approx(float(after[id]), want):
			wrong.append("%s: %s vs %s" % [id, str(after[id]), str(want)])
	check(wrong.is_empty(), "every tile carries the share the front holds of it: %s" % str(wrong.slice(0, 4)))
	check(float(after[held]) > 0.0 and float(after[clear]) == 0.0,
		"the held tile shows it and Sol's does not: %s, %s" % [str(after[held]), str(after[clear])])

	# The fill: the star map's colours, the held one where FrontData closes the tile.
	var f_held: Color = gm.front_fill(float(after[held]))
	var f_cont: Color = gm.front_fill(float(after[contested]))
	check(f_held.a > 0.0 and _rgb_is(f_held, SM.FRONT_HELD_COLOR),
		"a closed tile is filled in the star map's held colour: %s" % str(f_held))
	check(f_cont.a > 0.0 and _rgb_is(f_cont, SM.FRONT_CONTESTED_COLOR),
		"a contested one in its contested colour: %s" % str(f_cont))
	check(f_held.a > f_cont.a, "and the more they hold, the more solid: %.2f vs %.2f" % [f_held.a, f_cont.a])
	check(gm.front_fill(0.0).a == 0.0, "a tile they hold none of is not tinted")

	# The info panel.
	gm._selected = held
	gm._refresh_info()
	var row_held: String = (gm._info_rows["Rival front"] as Label).text
	check(row_held.begins_with("%d%%" % int(round(float(after[held]) * 100.0))) and row_held.contains("closed"),
		"the held tile's row gives its share and says it is closed: %s" % row_held)
	gm._selected = contested
	gm._refresh_info()
	var row_cont: String = (gm._info_rows["Rival front"] as Label).text
	check(row_cont.contains("contested") and not row_cont.contains("closed"),
		"the contested one says so: %s" % row_cont)
	gm._selected = clear
	gm._refresh_info()
	check((gm._info_rows["Rival front"] as Label).text == "—", "Sol's tile has no front: %s"
		% (gm._info_rows["Rival front"] as Label).text)

	# ── It follows the front as it moves ──
	# The grid is a cache patched in place, so a share that changes has to reach it.
	g.front_cells[contested] = 0.99
	check(is_equal_approx(float(_grid_front(g)[contested]), 0.99),
		"a share that grows shows on the next read: %s" % str(_grid_front(g)[contested]))

	# ── A run with no front shows none ──
	g.front_on = false
	var off: Dictionary = _grid_front(g)
	check(float(off[held]) == 0.0, "with the front off the grid carries none: %s" % str(off[held]))
	gm._selected = held
	gm._refresh_info()
	check((gm._info_rows["Rival front"] as Label).text == "—", "and the row is empty")

	print("FAILS: %d" % fails)
	quit()
