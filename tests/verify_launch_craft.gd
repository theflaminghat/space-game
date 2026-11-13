extends SceneTree

## Launch craft belong to the launch board, and they go when the launch does.
##
## Three things were wrong with the dots that fly a mission across the solar system.
##
## ── They were always there ──
##
## A craft was drawn whenever the solar system was, so a civilisation running a dozen standing
## launch orders had a dozen dots wandering its sky at all times, saying nothing to a player who
## was not looking at the launch board.  They are a readout of that board now and are drawn only
## while it is open.
##
## ── Nothing could be asked where it was going ──
##
## The arc each craft flies was computed frame by frame and nowhere else, so there was no way to
## see a flight plan — only the dot, somewhere along it.  Clicking a flight in the list now draws
## its whole plan as a dashed line, which means the arc had to become something that can be
## SAMPLED: the one stateful step (the unwrapped prograde sweep) is split off from the point
## functions, so asking a craft for its path 180 times cannot move it.
##
## ── And they never left ──
##
## An "orbit" arrival settled into a parking orbit and followed its target for the rest of the
## run.  Every mission ever flown left a dot circling the world it arrived at, and the dictionary
## that tracked them was written and never read, so it kept a dead reference per mission too.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

## Everything a Survey off Earth needs, so a refusal is never about the bill.
func _stock_earth(g: Node, fuel_id: String) -> void:
	var inv: Dictionary = g._planet_inv("earth")
	for res: String in ["Rocket", fuel_id]:
		inv[res] = 1.0e20
	root.get_node("ResearchTree").resources["energy"] = 1.0e20

func _craft_of(g: Node, launch_id: int) -> Node:
	var sat: Variant = g._launch_satellites.get(launch_id)
	return sat as Node if sat is Node and is_instance_valid(sat) else null

func _run() -> void:
	seed(20261112)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(30): await process_frame
	var g: Node = current_scene
	var md = load("res://missions.gd")
	var sat_script: Script = load("res://satellite.gd")
	var fuel_id: String = str(md.FUELS[0]["id"])
	_stock_earth(g, fuel_id)
	g.launch_panel.hide()
	for _i in range(2): await process_frame

	# ── The scene carries no craft of its own ──
	# A template Satellite sat under Earth with a sphere on it, hidden in _ready and then
	# un-hidden by the first visibility sync that came along.
	check(g.get_node_or_null("WorldRoot/Planets/earth/Node3D") == null,
		"the template craft is out of the scene")

	var params := {
		"mission": "Survey", "origin": "earth", "target": "mars", "cargo": {},
		"start_offset": 0, "duration": 300, "rockets": 1,
		"fuel_id": fuel_id, "fuel_amount": 8.0, "arrival": "orbit",
	}
	g._on_launch_requested(params)
	check(g.active_launches.size() == 1, "the survey went up: %d" % g.active_launches.size())
	if g.active_launches.is_empty():
		print("FAILS: ", fails); quit(); return
	var lid: int = int(g.active_launches[0]["id"])
	var sat: Node = _craft_of(g, lid)
	check(sat != null, "and it has a craft")
	if sat == null:
		print("FAILS: ", fails); quit(); return
	for _i in range(3): await process_frame

	# ── 1. Drawn with the board, and only with it ─────────────────────────────
	var ss: Node = root.get_node("SolarSystem")
	check(not sat.visible, "a craft launched behind a shut board is not drawn")
	check(not sat.board_visible(), "and knows the board is shut")
	# Not merely the frozen-system rule: a pause reveals the planets, and used to reveal these.
	ss.paused = true
	for _i in range(2): await process_frame
	check(not sat.visible, "pausing does not reveal it either")
	ss.paused = false

	g.launch_panel.show()
	for _i in range(3): await process_frame
	check(sat.visible, "opening the board draws it")
	check(sat.board_visible(), "and tells it so")
	g.launch_panel.hide()
	for _i in range(3): await process_frame
	check(not sat.visible, "shutting the board puts it away again")
	g.launch_panel.show()
	for _i in range(3): await process_frame

	# ── 2. The plan can be sampled, and sampling it moves nothing ─────────────
	var plan: PackedVector3Array = sat.path_points(64)
	check(plan.size() == 65, "the plan comes back sampled: %d points" % plan.size())
	var depart: Vector3 = sat.get("_start_pos")
	check(plan[0].distance_to(depart) < 0.05,
		"it starts where the craft left: %.4f away" % plan[0].distance_to(depart))
	# The far end is the parking orbit around where Mars WILL BE on arrival - not where it is
	# now, which over a 300-day flight is most of the way round the Sun from it.
	var mars: Node3D = g.get_node("WorldRoot/Planets/mars")
	var park: float = float(sat.get("_park_radius"))
	var lead0: float = float(sat.get("_flight_days")) - float(sat.get("_elapsed_days"))
	var miss: float = plan[plan.size() - 1].distance_to(mars.position_in_days(lead0))
	check(absf(miss - park) < 0.02,
		"and ends on the parking orbit it is aimed at: %.3f, radius %.3f" % [miss, park])
	check(plan[plan.size() - 1].distance_to(mars.global_position) > park * 2.0,
		"which is nowhere near where Mars is today")

	# A long flight goes ROUND, not straight out.  The bearing to the arrival point fixes the
	# sweep only to within whole revolutions, and the nearest one to what a body out there
	# actually covers in the time is what stops a 300-day transfer creeping outward in a hook
	# twenty pixels long.
	var sweep: float = float(sat.get("_sweep"))
	print("300-day transfer sweeps %.2f rad (%.2f revolutions)" % [sweep, sweep / TAU])
	check(sweep > PI, "a 300-day transfer goes most of the way round: %.2f rad" % sweep)
	# And a whole revolution is ALL that is added: it still ends on the arrival bearing.
	var arel: Vector3 = sat.get("_arrive_rel")
	var ends: float = angle_difference(float(sat.get("_depart_angle")) + sweep,
		atan2(arel.x, arel.z))
	check(absf(ends) < 1.0e-4, "and still ends on the arrival bearing: off by %.6f rad" % ends)

	# Both halves of that rule, on flights long and short enough to show it.  300 days happens
	# to land inside the first revolution, so it pins neither on its own.
	var mars_n: Node3D = g.get_node("WorldRoot/Planets/mars")
	var earth_n: Node3D = g.get_node("WorldRoot/Planets/earth")
	g._spawn_satellite(earth_n, mars_n, "orbit", 9050, 1000.0)
	g._spawn_satellite(earth_n, mars_n, "orbit", 9051, 20.0)
	var slow: Node = _craft_of(g, 9050)
	var quick: Node = _craft_of(g, 9051)
	check(slow != null and quick != null, "two probes to measure the sweep with")
	if slow != null and quick != null:
		var s_long: float = float(slow.get("_sweep"))
		var s_short: float = float(quick.get("_sweep"))
		print("1000 days sweeps %.2f rad, 20 days sweeps %.2f rad" % [s_long, s_short])
		check(s_long > TAU, "a 1000-day transfer goes round more than once: %.2f rad" % s_long)
		var larel: Vector3 = slow.get("_arrive_rel")
		var lends: float = angle_difference(float(slow.get("_depart_angle")) + s_long,
			atan2(larel.x, larel.z))
		check(absf(lends) < 1.0e-4,
			"and whole revolutions are all that was added: off by %.6f rad" % lends)
		check(s_short < TAU, "a 20-day hop gets none of them: %.2f rad" % s_short)
	g._free_launch_craft(9050)
	g._free_launch_craft(9051)
	for _i in range(2): await process_frame

	# THE invariant the refactor exists for: the sweep and the elapsed clock belong to the
	# flight, and a query must not touch either.
	var sweep0: float   = float(sat.get("_sweep"))
	var flown0: float   = float(sat.get("_elapsed_days"))
	var dir0:   float   = float(sat.get("_orbit_dir"))
	var entry0: float   = float(sat.get("_orbit_entry_angle"))
	var where0: Vector3 = sat.craft_position()
	for _i in range(5):
		sat.path_points()
	check(is_equal_approx(float(sat.get("_sweep")), sweep0),
		"asking for the plan leaves the sweep alone: %f vs %f" % [float(sat.get("_sweep")), sweep0])
	check(is_equal_approx(float(sat.get("_elapsed_days")), flown0),
		"and the flight clock")
	check(is_equal_approx(float(sat.get("_orbit_dir")), dir0)
		and is_equal_approx(float(sat.get("_orbit_entry_angle")), entry0),
		"and the insertion it has not reached yet")
	check(sat.craft_position().distance_to(where0) < 1.0e-5, "and the craft where it was")

	# ── THE point of the arc being struck once: it does not follow the planet ──
	# The far end used to be re-read from the target's live position every frame, so the whole
	# trajectory swung round behind Mars as it orbited and the line drawn along it was a picture
	# of this frame rather than a plan.
	var plan0: PackedVector3Array = sat.path_points(48)
	var mars0: Vector3 = mars.global_position
	var planets: Node = g.get_node("WorldRoot/Planets")
	var slot0: Vector3 = planets.swarm_slot_world_pos(0)
	ss.paused = false
	g.set_speed_tier(6)
	for _i in range(120): await process_frame
	ss.paused = true
	for _i in range(2): await process_frame
	var moved: float = mars.global_position.distance_to(mars0)
	check(moved > 0.05, "Mars has moved: %.3f" % moved)

	# The lead is EXACT, which is what lets the arc be struck once and left alone.  Measured by
	# running the clock and then predicting backwards over the days the craft logged: the craft
	# and the planet advance off the same delta, so if the two rates disagreed at all this is
	# where it would show.
	var flown_days: float = float(sat.get("_elapsed_days")) - flown0
	var rewound: float = mars.position_in_days(-flown_days).distance_to(mars0)
	print("%.3f days of travel, planet prediction off by %.6f" % [flown_days, rewound])
	# Absolute, not a fraction of the distance travelled: a rate that is wrong by one per cent
	# is wrong by one per cent OF that distance, which such a tolerance would wave through.
	check(rewound < 1.0e-4,
		"predicting %.3f days lands on the planet's own figure: off by %.6f" % [flown_days, rewound])

	# The lane the carriers fly to is led the same way, off its own constant turn per game-day.
	var lane_back: float = planets.swarm_slot_world_pos(0, -flown_days).distance_to(slot0)
	print("lane prediction off by %.6f over the same %.3f days" % [lane_back, flown_days])
	check(lane_back < 1.0e-3, "and the same for a swarm berth: off by %.6f" % lane_back)
	var plan1: PackedVector3Array = sat.path_points(48)
	var drift: float = 0.0
	for i in range(mini(plan0.size(), plan1.size())):
		drift = maxf(drift, plan0[i].distance_to(plan1[i]))
	check(drift < 1.0e-4, "and the flight plan has not: %.5f drift over %.3f of travel"
		% [drift, moved])

	# Fixed and still right: the far end is where the target WILL BE, one parking radius off,
	# so the craft arrives on the planet rather than where the planet used to be.
	var lead: float = float(sat.get("_flight_days")) - float(sat.get("_elapsed_days"))
	var will_be: Vector3 = mars.position_in_days(lead)
	var reach: float = plan1[plan1.size() - 1].distance_to(will_be)
	check(absf(reach - float(sat.get("_park_radius"))) < 0.02,
		"the plan ends on the parking orbit it will find: %.3f vs %.3f"
			% [reach, float(sat.get("_park_radius"))])

	# A lane delivery is aimed the same way, and its plan is fixed too.
	var earth_p: Node3D = g.get_node("WorldRoot/Planets/earth")
	g._spawn_swarm_satellite(earth_p, earth_p.global_position + Vector3(1.0, 0.0, 0.0),
		9001, 120.0, 0)
	var lane_craft: Node = _craft_of(g, 9001)
	check(lane_craft != null, "a lane delivery is in the air")
	if lane_craft != null:
		var lane: PackedVector3Array = lane_craft.path_points(64)
		check(lane.size() == 65, "its lane-entry arc comes back: %d points" % lane.size())
		var berth: Vector3 = planets.swarm_slot_world_pos(0, 120.0)
		check(lane[lane.size() - 1].distance_to(berth) < 0.05,
			"ending at the berth the lane will have turned to: %.3f away"
				% lane[lane.size() - 1].distance_to(berth))
		# And that is a different place from where the berth is now - a swarm lane goes round
		# in a week and a half, so over a 120-day flight the lead is the whole point.
		check(berth.distance_to(planets.swarm_slot_world_pos(0)) > 0.1,
			"which is not where it is today: %.3f"
				% berth.distance_to(planets.swarm_slot_world_pos(0)))
		g._free_launch_craft(9001)
		for _i in range(2): await process_frame

	# ── 3. Clicking a flight draws it ─────────────────────────────────────────
	g.refresh_launch_panel()
	for _i in range(2): await process_frame
	var rows: Array = g.launch_panel._rows
	check(rows.size() == 1, "the list shows the flight: %d rows" % rows.size())
	if rows.is_empty():
		print("FAILS: ", fails); quit(); return
	var row: Button = rows[0]
	check(int(row.get_meta("launch_id", -1)) == lid, "the row carries its launch id")
	# Only an action, never a hover: nothing is connected to the signals a mouse crossing the
	# row would fire.
	check(row.get_signal_connection_list("mouse_entered").is_empty(),
		"hovering a row does nothing")
	check(row.get_signal_connection_list("focus_entered").is_empty(),
		"and neither does focus")

	check(not sat.path_shown(), "nothing is drawing a path yet")
	row.emit_signal("pressed")
	for _i in range(3): await process_frame
	check(g.launch_panel.selected_launch() == lid, "the click picked the flight")
	check(g._path_launch == lid, "and Game heard which one")
	check(sat.path_shown(), "and the craft is drawing its plan")

	var line: MeshInstance3D = sat.get_node_or_null("PlannedPath") as MeshInstance3D
	check(line != null, "there is a line")
	if line == null:
		print("FAILS: ", fails); quit(); return
	check(line.visible, "and it is drawn")
	check(line.top_level, "in world coordinates, not the parent's")
	check(line.mesh.get_surface_count() == 1, "with geometry on it: %d surfaces"
		% line.mesh.get_surface_count())

	# ── 4. It is DASHED: gaps in it, and the right number of them ─────────────
	var verts: PackedVector3Array = line.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var per_seg: int = int(sat_script.PATH_RING_SEGS) * 6
	check(verts.size() % per_seg == 0, "the tube comes out whole: %d verts" % verts.size())
	var drawn: int = verts.size() / per_seg
	var duty: float = float(drawn) / float(sat_script.PATH_SAMPLES)
	print("ink %d of %d segments (%.2f of the path)" % [drawn, sat_script.PATH_SAMPLES, duty])
	check(duty > 0.35 and duty < 0.80, "more of the line is ink than gap, but not all: %.2f" % duty)
	check(absf(duty - float(sat_script.PATH_DUTY)) < 0.12,
		"and it is the duty the constant asks for: %.2f" % duty)

	# Each segment's 24 verts average to its own midpoint (the ring offsets cancel), so the
	# dashes can be counted off the mesh: a jump between consecutive midpoints is a gap.
	var mids := PackedVector3Array()
	for s in range(drawn):
		var acc := Vector3.ZERO
		for k in range(per_seg):
			acc += verts[s * per_seg + k]
		mids.append(acc / float(per_seg))
	var step: float = INF
	for i in range(1, mids.size()):
		step = minf(step, mids[i - 1].distance_to(mids[i]))
	var runs: int = 1
	for i in range(1, mids.size()):
		if mids[i - 1].distance_to(mids[i]) > step * 2.5:
			runs += 1
	print("dashes: %d (want ~%d)" % [runs, int(sat_script.PATH_DASHES)])
	check(absi(runs - int(sat_script.PATH_DASHES)) <= 2,
		"the line is cut into about PATH_DASHES dashes: %d" % runs)

	# ── 5. Clicking it again puts the line away, and so does shutting the board ──
	row.emit_signal("pressed")
	for _i in range(2): await process_frame
	check(g.launch_panel.selected_launch() == -1, "a second click lets the flight go")
	check(not sat.path_shown() and not line.visible, "and the line with it")

	row.emit_signal("pressed")
	for _i in range(2): await process_frame
	check(sat.path_shown(), "picked again")
	g.launch_panel.hide()
	for _i in range(3): await process_frame
	check(g.launch_panel.selected_launch() == -1, "shutting the board drops the selection")
	check(g._path_launch == -1, "Game drops it too")
	check(not sat.path_shown() and not sat.visible, "and nothing is drawn over the system")
	g.launch_panel.show()
	for _i in range(3): await process_frame

	# ── 6. A second flight, and the list patched rather than rebuilt ──────────
	g.refresh_launch_panel()
	for _i in range(2): await process_frame
	var kept: Array = g.launch_panel._rows.duplicate()
	g.refresh_launch_panel()
	for _i in range(2): await process_frame
	check(g.launch_panel._rows == kept,
		"a push that changes nothing leaves the rows standing")
	g.launch_panel._rows[0].emit_signal("pressed")
	for _i in range(2): await process_frame
	var picked_box: StyleBox = g.launch_panel._rows[0].get_theme_stylebox("normal")
	g.refresh_launch_panel()
	for _i in range(2): await process_frame
	check(g.launch_panel._rows[0].get_theme_stylebox("normal") == picked_box,
		"and does not repaint the row it has already marked")

	_stock_earth(g, fuel_id)
	var second := params.duplicate()
	second["target"] = "venus"
	g._on_launch_requested(second)
	for _i in range(2): await process_frame
	g.refresh_launch_panel()
	for _i in range(2): await process_frame
	check(g.launch_panel._rows.size() == 2, "the new flight is in the list")
	check(g.launch_panel.selected_launch() == lid,
		"and the picked one is still picked: %d" % g.launch_panel.selected_launch())
	var still: Node = _craft_of(g, lid)
	check(still != null and still.path_shown(), "still drawing its own plan")

	# ── 7. Nothing is left behind when the launch is done ─────────────────────
	# The orbit arrival is the one that used to park and stay: the craft was still there, in
	# ORBIT, for the rest of the run.
	var before: int = g._launch_satellites.size()
	check(before == 2, "two craft in the air: %d" % before)
	g.year  = int(g.active_launches[0]["end_year"]) + 1
	g.month = int(g.active_launches[0]["end_month"])
	g.day   = int(g.active_launches[0]["end_day"])
	g._process_launch_arrivals()
	for _i in range(4): await process_frame
	check(g.active_launches.is_empty(), "both launches landed: %d left" % g.active_launches.size())
	check(g._launch_satellites.is_empty(),
		"and no craft is still tracked: %d" % g._launch_satellites.size())
	check(g._path_launch == -1, "the drawn path went with the flight")
	var left: int = 0
	# By script rather than by `n is Satellite`: naming the class here would make satellite.gd a
	# compile-time dependency of this test, and it is compiled BEFORE the autoloads exist, so
	# the SolarSystem it talks to in _ready would not resolve and the whole file would fail.
	for n: Node in g.get_node("WorldRoot").get_children():
		if n.get_script() == sat_script:
			left += 1
	check(left == 0, "nothing is still flying over the system: %d craft" % left)
	g.refresh_launch_panel()
	for _i in range(2): await process_frame
	check(g.launch_panel.selected_launch() == -1, "and the list has let the selection go")

	# ── 8. A save written mid-flight comes back with its craft in the air ─────
	_stock_earth(g, fuel_id)
	g._on_launch_requested(params)
	check(g.active_launches.size() == 1, "a third flight for the save")
	var lid3: int = int(g.active_launches[0]["id"])
	# Written half-way through, so the craft has to come back part-way along its arc rather
	# than back at the pad with the whole flight still to fly.
	var mid: Array = g._date_add_days(int(g.active_launches[0]["start_year"]),
		int(g.active_launches[0]["start_month"]), int(g.active_launches[0]["start_day"]), 150)
	g.year = int(mid[0]); g.month = int(mid[1]); g.day = int(mid[2])
	g.save_game("user://saves/launch_craft.json")

	# One more AFTER the file is written, so it is in the sky and not in the save: a load has to
	# clear what it is loading over, or the last run's craft fly on through the next one.
	_stock_earth(g, fuel_id)
	var ghost := params.duplicate()
	ghost["target"] = "venus"
	g._on_launch_requested(ghost)
	var ghost_id: int = int(g.active_launches[g.active_launches.size() - 1]["id"])
	check(_craft_of(g, ghost_id) != null, "the unsaved flight is in the air")

	g.load_game("user://saves/launch_craft.json")
	for _i in range(4): await process_frame
	check(g.active_launches.size() == 1, "the flight is restored: %d" % g.active_launches.size())
	check(_craft_of(g, ghost_id) == null, "and the unsaved one is not still flying")
	var back: Node = _craft_of(g, lid3)
	check(back != null, "and it has a craft again")
	if back != null:
		var flown: float = float(back.get("_elapsed_days"))
		print("restored craft %.0f days into a %.0f-day flight"
			% [flown, float(back.get("_flight_days"))])
		check(flown > 1.0, "picked up part-way along, not back at the pad: %.0f days" % flown)
		check(back.path_points(32).size() == 33, "and can be asked for its plan")


	# ── 9. A craft that frees itself takes its entry with it ──────────────────
	# A lander spirals down and a swarm carrier hands over to the collector it was carrying:
	# both call queue_free on their own say-so, with no launch being marked done.
	if back != null:
		back.queue_free()
		for _i in range(3): await process_frame
		check(not g._launch_satellites.has(lid3),
			"a craft that frees itself is no longer tracked")

	# ── 10. A local orbit insertion plans the orbit it settles into ───────────
	# There is no interplanetary cruise to draw: the target IS the launch site, so the plan is
	# the parking orbit, and a transfer arc sampled from a zero-length sweep would be a dot.
	g.active_launches.clear()
	g._clear_launch_craft()
	_stock_earth(g, fuel_id)
	var local := params.duplicate()
	local["target"] = "earth"
	g._on_launch_requested(local)
	check(g.active_launches.size() == 1, "a local insertion went up")
	if not g.active_launches.is_empty():
		var lsat: Node = _craft_of(g, int(g.active_launches[0]["id"]))
		check(lsat != null, "with a craft of its own")
		if lsat != null:
			var ring: PackedVector3Array = lsat.path_points(48)
			var earth: Node3D = g.get_node("WorldRoot/Planets/earth")
			var r: float = float(lsat.get("_park_radius"))
			var worst: float = 0.0
			for pt: Vector3 in ring:
				worst = maxf(worst, absf(pt.distance_to(earth.global_position) - r))
			check(worst < 0.01, "every point of it is on the parking orbit: off by %.4f" % worst)
			check(ring[0].distance_to(ring[ring.size() - 1]) < 0.01, "and the ring closes")


	# ── 11. It lands on the planet, not on where the planet used to be ────────
	# The end-to-end of everything above: drive a whole flight and see where the craft ends up.
	# Aimed at a stale position it would finish tens of units from Mars; aimed at the lead it
	# finishes on the parking orbit.
	g.active_launches.clear()
	g._clear_launch_craft()
	var mars_p: Node3D = g.get_node("WorldRoot/Planets/mars")
	g._spawn_satellite(g.get_node("WorldRoot/Planets/earth") as Node3D, mars_p, "orbit",
		9100, 30.0)
	var probe: Node = _craft_of(g, 9100)
	check(probe != null, "a probe to drive to the end")
	if probe != null:
		var aimed: Vector3 = probe.path_points(2)[2]
		var guard: int = 0
		while float(probe.get("_elapsed_days")) < 30.0 and guard < 40000:
			guard += 1
			ss.paused = false
			ss.ui_paused = false
			paused = false   # the SceneTree is us
			await process_frame
		ss.paused = true
		var off: float = probe.craft_position().distance_to(mars_p.global_position)
		var park2: float = float(probe.get("_park_radius"))
		print("flew %d frames; craft %.3f from Mars, parking radius %.3f, aim %.3f off"
			% [guard, off, park2, aimed.distance_to(mars_p.global_position)])
		check(float(probe.get("_elapsed_days")) >= 30.0, "the flight finished: %.1f days"
			% float(probe.get("_elapsed_days")))
		check(off < park2 * 1.15, "and the craft is on Mars: %.3f off a %.3f parking orbit"
			% [off, park2])

	# ── 12. A launch booked for a later date waits for it ─────────────────────
	# The calendar's start date reached the launch record and nothing else: the craft left the
	# moment the button was pressed and flew its duration from today, so it arrived the whole
	# offset early and planning for a better window only changed the bill.
	g.active_launches.clear()
	g._clear_launch_craft()
	g.launch_panel.show()
	_stock_earth(g, fuel_id)
	var booked := params.duplicate()
	booked["start_offset"] = 60
	booked["duration"] = 90
	g._on_launch_requested(booked)
	check(g.active_launches.size() == 1, "the booking is taken")
	if not g.active_launches.is_empty():
		var bl: Dictionary = g.active_launches[0]
		var bsat: Node = _craft_of(g, int(bl["id"]))
		check(bsat != null, "with a craft, so its plan can be looked at before it flies")
		if bsat != null:
			check(absf(float(bsat.days_to_departure()) - 60.0) < 0.01,
				"which is on its pad for 60 days: %.2f" % float(bsat.days_to_departure()))
			var earth_b: Node3D = g.get_node("WorldRoot/Planets/earth")
			check(bsat.craft_position().distance_to(earth_b.global_position) < 1.0e-3,
				"sitting on Earth meanwhile")
			# Its plan is the one for the departure day: from where Earth WILL be, not where it is.
			var bplan: PackedVector3Array = bsat.path_points(32)
			var leave_at: Vector3 = earth_b.position_in_days(60.0)
			check(bplan[0].distance_to(leave_at) < 0.05,
				"the plan leaves from where Earth will be in 60 days: %.4f off"
					% bplan[0].distance_to(leave_at))
			check(bplan[0].distance_to(earth_b.global_position) > 1.0,
				"which is not where it is today: %.3f" % bplan[0].distance_to(earth_b.global_position))
			var mars_b: Node3D = g.get_node("WorldRoot/Planets/mars")
			var reach_b: float = bplan[bplan.size() - 1].distance_to(mars_b.position_in_days(150.0))
			check(absf(reach_b - float(bsat.get("_park_radius"))) < 0.02,
				"and arrives where Mars will be in 60 + 90 days: %.3f" % reach_b)
		g.refresh_launch_panel()
		for _i in range(2): await process_frame
		var brow: String = ""
		for r: Button in g.launch_panel._rows:
			brow = (r.get_node("Row/Status") as Label).text
		check(brow.begins_with("departs in"), "the list says when it leaves: '%s'" % brow)

		# A save written while it waits brings it back waiting, not on its way.
		g.save_game("user://saves/launch_booked.json")
		g.load_game("user://saves/launch_booked.json")
		for _i in range(3): await process_frame
		var back_b: Node = _craft_of(g, int(bl["id"]))
		check(back_b != null and absf(float(back_b.days_to_departure()) - 60.0) < 1.01,
			"a reload keeps it on its pad: %s" % (str(back_b.days_to_departure()) if back_b else "no craft"))

	# End to end, on the craft's own clock: twenty days on the pad, thirty in flight, and it is on
	# Mars when the fifty are up — not twenty days early, and not where Mars was at booking.
	g.active_launches.clear()
	g._clear_launch_craft()
	var earth_e: Node3D = g.get_node("WorldRoot/Planets/earth")
	var mars_e: Node3D = g.get_node("WorldRoot/Planets/mars")
	g._spawn_satellite(earth_e, mars_e, "orbit", 9300, 30.0, -20.0)
	var w: Node = _craft_of(g, 9300)
	check(w != null, "a craft booked twenty days out")
	if w != null:
		var on_pad: bool = true
		var left_on: float = -1.0
		var guard2: int = 0
		while float(w.get("_elapsed_days")) < 30.0 and guard2 < 60000:
			guard2 += 1
			ss.paused = false
			ss.ui_paused = false
			paused = false
			await process_frame
			var el: float = float(w.get("_elapsed_days"))
			if el < 0.0:
				on_pad = on_pad and w.craft_position().distance_to(earth_e.global_position) < 1.0e-3
			elif left_on < 0.0:
				left_on = el
		ss.paused = true
		check(on_pad, "it stayed on Earth for every frame of the wait")
		check(left_on >= 0.0 and left_on < 1.0, "and left on the day: %.3f days past it" % left_on)
		var off_e: float = w.craft_position().distance_to(mars_e.global_position)
		var park_e: float = float(w.get("_park_radius"))
		print("booked flight: left %.3f days late, finished %.3f from Mars (parking %.3f)"
			% [left_on, off_e, park_e])
		check(off_e < park_e * 1.15, "and arrived on Mars: %.3f off a %.3f parking orbit" % [off_e, park_e])

	print("FAILS: %d" % fails)
	quit()
