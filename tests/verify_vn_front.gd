extends SceneTree

## Somebody else's probes, and the rule that makes them matter.
##
## The swarm is exponential, so nothing of fixed size stays relevant to it — a rival replicator
## is the only opponent that stays the same size relative to the player for ever.
##
## But the front is the cheap half. What did not exist was DENIAL: probe targeting asked only
## "have I taken this already", so a volume could be entirely somebody else's and the swarm
## would still fly into it. Whoever reaches a volume first now holds it, both ways.
##
## What has to hold:
##   the front cannot take a share of a cell the player got to first
##   the player's probes will not fly into a cell the front has taken — stars OR clusters
##   its signature is light-delayed, so it is nearer than it looks when you first see it
##   the setup screen can turn it off, and then nothing changes at all
##   it survives a save

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(20261030)
	root.get_node("GameSession").should_load_on_start = false
	var gs: Node = root.get_node("GameSession")
	# "Underway" is the default; name it rather than relying on that staying true.
	gs.setup = {"front": 2}
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var FD = load("res://vn_front.gd")


	# ── The rules, before any front exists ──
	check(FD.claimed_after(0.0, 1.0, 0.0) == 0.0, "no time, no claim")
	check(FD.claimed_after(0.2, 1.0, 1000.0) > 0.2, "a held cell fills over time")
	check(FD.claimed_after(0.9, 1.0, 1.0e9) <= 1.0, "and never past the whole cell")
	# The first-come-first-served rule, in the arithmetic.
	check(FD.claimed_after(0.0, 0.0, 1.0e9) == 0.0,
		"a cell the player wholly holds leaves the front nothing")
	check(FD.claimed_after(0.1, 0.3, 1.0e9) <= 0.3 + 1.0e-9,
		"and a part-held one caps it at what is left: %s"
			% str(FD.claimed_after(0.1, 0.3, 1.0e9)))
	check(FD.claimed_after(0.8, 0.3, 1000.0) <= 0.8,
		"a front already past the cap does not grow into it")
	check(FD.denies(FD.DENIED_SHARE), "a cell at the threshold is spoken for")
	check(not FD.denies(FD.DENIED_SHARE - 0.01), "and just under it is still contested")
	check(FD.DENIED_SHARE < 1.0,
		"the threshold is short of the whole cell, because a cell is thousands of ly across")
	# Light delay.
	check(not FD.detected(1000.0, 0.0, 999.0), "a signature a thousand ly out is not seen early")
	check(FD.detected(1000.0, 0.0, 1000.0), "and is seen exactly on time")


	# ── It exists, it started at the centre, and it has a head start ──
	check(g.front_active(), "this run has a front")
	check(not g.front_cells.is_empty(), "which holds cells: %d" % g.front_cells.size())
	check(g.front_year < float(g.year),
		"and has been running since before the game began: %s vs %d" % [
			str(g.front_year), g.year])
	var centre_id: String = g._region_id(g._region_origin())
	check(g.front_cells.has(centre_id),
		"seeded at the galactic centre: %s in %s" % [centre_id, str(g.front_cells.keys().size())])
	check(g.front_cells.size() > 1,
		"and the head start spread it beyond one cell: %d" % g.front_cells.size())
	var d0: float = g._front_distance_ly()
	check(d0 > 1000.0, "it is a long way off: %s ly" % str(d0))


	# ── The player is not told until the light arrives ──
	check(not g.front_seen, "nothing has been seen yet")
	check(g.front_state().is_empty(), "so the map is told nothing")
	g.year = int(g.front_year + d0) + 1
	g._check_front_detected()
	check(g.front_seen, "once the signature has had time to cross, it is seen")
	var st: Dictionary = g.front_state()
	check(not st.is_empty(), "and the map is told: %s" % str(st.keys()))
	check(int(st["held"]) > 0, "how many cells it holds: %d" % int(st["held"]))


	# ── Denial: the player's probes will not fly into it ──
	var held_id: String = ""
	for id: String in g.front_cells:
		if float(g.front_cells[id]) >= FD.DENIED_SHARE:
			held_id = id
	# Force one cell fully taken, so the test does not depend on how the rolls fell.
	if held_id == "":
		held_id = centre_id
		g.front_cells[held_id] = 1.0
	var inside: Vector3 = g._region_center(held_id)
	check(g.front_denies_pos(inside),
		"a position inside a taken cell is denied: share %s" % str(g.front_share(held_id)))
	# A cell it has barely touched is still contested, and still ours to race for.
	var fresh: String = "999,999"
	g.front_cells[fresh] = 0.01
	check(not g.front_denies_pos(g._region_center(fresh)),
		"a cell it has barely entered is not denied")
	g.front_cells.erase(fresh)
	# And somewhere it has never been is simply open.
	check(not g.front_denies_pos(Vector3(5.0, 0.0, 0.0)),
		"Sol's own neighbourhood is open")
	# The filter every candidate passes must honour it.
	var fake_star: Dictionary = {"name": "Front Test Star", "pos": inside, "dist": 1.0}
	var cand: Array = []
	var kept: bool = g._consider_target(cand, fake_star, inside, 1.0, 4, {}, {}, false)
	check(not kept, "so _consider_target refuses a star inside the front")
	check(cand.is_empty(), "and keeps nothing")
	# Outside it, the same star is fine — proving the refusal was the front and not the star.
	var open_pos: Vector3 = Vector3(12.0, 3.0, 1.0)
	var cand2: Array = []
	check(g._consider_target(cand2, {"name": "Open Star", "pos": open_pos, "dist": 1.0},
			open_pos, 1.0, 4, {}, {}, false),
		"while an identical star outside it is accepted")


	# ── "Empty" turns it off, and then the targeting is exactly what it was ──
	var saved_on: bool = g.front_on
	g.front_on = false
	check(not g.front_active(), "with the front off there is no front")
	check(not g.front_denies_pos(inside),
		"and nothing is denied, even inside cells it was holding")
	var cand3: Array = []
	check(g._consider_target(cand3, fake_star, inside, 1.0, 4, {}, {}, false),
		"so a star it was blocking is accepted again")
	g.front_on = saved_on
	check(g.front_denies_pos(inside), "and turning it back on restores the denial")

	# ── The balance is the point, so it is pinned ──
	# Sol sits ~26 000 ly from the galactic centre and cells are 3 753 ly across, so a front
	# seeded at the centre has about seven cells of runway. If a head start ever covers Sol's own
	# cell the run is unplayable from the first frame.
	check(not g.front_denies_pos(Vector3.ZERO),
		"Sol's own cell is never denied at setup: share %s"
			% str(g.front_share(g._region_id(Vector3.ZERO))))
	check(FrontData.YEARS_PER_CELL > 3.0e4,
		"the front is slower than light: %s yr to cross 3753 ly"
			% str(FrontData.YEARS_PER_CELL))
	check(3753.0 / FrontData.YEARS_PER_CELL < 1.0,
		"which is %.3f c" % (3753.0 / FrontData.YEARS_PER_CELL))

	# ── The player's claim is a ceiling the front cannot pass ──
	var contested: String = g._region_id(Vector3(400.0, 0.0, 0.0))
	var reg: Dictionary = g._get_region(contested)
	reg["colonizable"] = 1000.0
	reg["colonized"] = 1000.0           # the player holds all of it
	g.front_cells[contested] = 0.0
	for _i in range(12):
		g._advance_front(2.0e4)
	check(float(g.front_cells[contested]) <= 0.001,
		"a cell the player wholly holds stays the player's: %s"
			% str(g.front_cells[contested]))
	# Half-held: the front can take the other half and no more.
	reg["colonized"] = 500.0
	for _i in range(20):
		g._advance_front(2.0e4)
	check(float(g.front_cells[contested]) <= 0.5 + 0.01,
		"and half-held leaves it half: %s" % str(g.front_cells[contested]))
	check(float(g.front_cells[contested]) > 0.3,
		"which it does take: %s" % str(g.front_cells[contested]))


	# ── The map is told, and only once the light has arrived ──
	var sm = g.sidebar.star_map
	g.sidebar.show_star_map()
	g.refresh_star_map()
	for _i in range(4): await process_frame
	check(not sm._front.is_empty(),
		"the map is given the front's cells: %d" % sm._front.size())
	check((sm._front[0] as Array)[0] is Vector3,
		"as positions, not hex ids: %s" % str((sm._front[0] as Array)[0]))
	check(float((sm._front[0] as Array)[1]) > 0.0, "each with its share")
	check(sm._front.size() == g.front_map_cells().size(),
		"all of them: %d vs %d" % [sm._front.size(), g.front_map_cells().size()])
	# A cell the front has but has not taken any of is not drawn.
	g.front_cells["7,-7"] = 0.0
	check(g.front_map_cells().size() == sm._front.size(),
		"an empty cell is not pushed: %d" % g.front_map_cells().size())
	g.front_cells.erase("7,-7")

	# Undetected means invisible. This is the whole reason the reveal lands at all.
	g.front_seen = false
	check(g.front_map_cells().is_empty(),
		"an unseen front is pushed as nothing: %d" % g.front_map_cells().size())
	g.refresh_star_map()
	for _i in range(2): await process_frame
	check(sm._front.is_empty(), "so the map holds nothing to draw")
	g.front_seen = true
	g.refresh_star_map()
	for _i in range(2): await process_frame
	check(not sm._front.is_empty(), "and seeing it again restores the draw")

	# It has its own layer, and turning it off stops it being drawn.
	check(sm._layers.has("front"), "the front is a map layer")
	check(sm._layer_boxes.has("front"), "with a checkbox of its own")
	check(sm.layer_shown("front"), "on by default")
	# A front is a GALACTIC-scale object — the nearest cell is thousands of light-years out — so
	# like the clusters and the galaxies it is only in band when the map is pulled back. The
	# default view is the neighbourhood, where it is correctly culled.
	var deep_zoom: float = sm._zoom
	sm.queue_redraw()
	await process_frame
	check(sm._fr_pts.is_empty(),
		"at the default neighbourhood zoom the front is out of band: %d" % sm._fr_pts.size())
	sm._zoom = 1.0
	sm.queue_redraw()
	await process_frame
	check(not sm._fr_pts.is_empty(),
		"pulled back to galactic scale, it is drawn: %d marks" % sm._fr_pts.size())
	sm.set_layer_shown("front", false)
	check(not sm.layer_shown("front"), "and it can be turned off")
	sm.queue_redraw()
	await process_frame
	check(sm._fr_pts.is_empty(),
		"which stops it being drawn, and clears the buffer: %d" % sm._fr_pts.size())
	sm.set_layer_shown("front", true)
	sm.queue_redraw()
	await process_frame
	check(not sm._fr_pts.is_empty(), "and turning it back on rebuilds it")
	sm._zoom = deep_zoom
	# What is drawn SOLID is exactly what is closed to the swarm, so the map cannot promise a
	# volume the targeting refuses.
	check(sm.FRONT_HELD_COLOR != sm.FRONT_CONTESTED_COLOR,
		"held and contested are different colours")
	# And the DRAW actually uses both. Only alpha is scaled per mark, so every colour in the
	# buffer has the rgb of one constant or the other — which makes this exact rather than a
	# guess, and it is the assertion that matters: what is drawn solid is what the swarm will
	# not fly into, so a map that painted them alike would promise volumes the targeting
	# refuses.
	# Tested on ONE position carrying both shares, rather than on the real front's geometry:
	# held and contested cells sit at different distances from Sol, so at any given zoom one of
	# the two bands may be out of view and the test would be measuring the camera instead of
	# the draw. Two entries at the same place are either both visible or both not.
	sm._zoom = 1.0
	var vis_pos: Vector3 = Vector3.ZERO
	var real_front: Array = sm._front
	for e2 in real_front:
		sm.set_front([[(e2 as Array)[0], 1.0]])
		sm.queue_redraw()
		await process_frame
		if not sm._fr_pts.is_empty():
			vis_pos = (e2 as Array)[0]
			break
	check(vis_pos != Vector3.ZERO, "some cell of the front is on screen at galactic zoom")
	sm.set_front([[vis_pos, 1.0], [vis_pos, 0.1]])
	sm.queue_redraw()
	await process_frame
	check(sm._fr_col.size() == 2,
		"both marks are built: %d" % sm._fr_col.size())
	var seen_held: bool = false
	var seen_contested: bool = false
	var stray: int = 0
	for c: Color in sm._fr_col:
		var rgb := Color(c.r, c.g, c.b)
		if rgb.is_equal_approx(Color(sm.FRONT_HELD_COLOR.r, sm.FRONT_HELD_COLOR.g,
				sm.FRONT_HELD_COLOR.b)):
			seen_held = true
		elif rgb.is_equal_approx(Color(sm.FRONT_CONTESTED_COLOR.r,
				sm.FRONT_CONTESTED_COLOR.g, sm.FRONT_CONTESTED_COLOR.b)):
			seen_contested = true
		else:
			stray += 1
	check(stray == 0, "every mark is one of the two colours: %d stray" % stray)
	check(seen_held, "a share of 1.0 is drawn as held")
	check(seen_contested, "and a share of 0.1 as contested")
	sm.set_front(real_front)
	sm._zoom = deep_zoom

	# ── It survives a save ──
	var want_cells: int = g.front_cells.size()
	var want_year: float = g.front_year
	g.save_game("user://saves/front.json")
	g.front_cells = {}
	g.front_year = -1.0
	g.front_seen = false
	g.load_game("user://saves/front.json")
	check(g.front_cells.size() == want_cells,
		"the front comes back: %d vs %d" % [g.front_cells.size(), want_cells])
	check(absf(g.front_year - want_year) < 1.0, "with its start date")
	check(g.front_seen, "and the fact that it has been seen")
	check(g.front_active(), "and is still running")

	print("FAILS: %d" % fails)
	quit()
