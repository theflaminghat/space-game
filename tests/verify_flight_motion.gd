extends SceneTree

## Everything in flight on the star map — colony ships, von Neumann probes, recon probes, laser
## pulses, relativistic missiles and berserker swarms — should travel along its line rather than
## hold one position for a whole game year and then hop.  `year` is an integer that only ticks on
## 31 December, so anything placed against it is frozen in between, and the pushed figure was
## only recomputed when the map happened to refresh.  The map now carries its own continuous
## calendar and interpolates each track's flight window against it every frame.

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
	# Autoloads are not reachable as bare identifiers from a --script runner.
	var sol: Node = root.get_node("SolarSystem")

	# ── The continuous calendar ──
	g.year = 2200; g.month = 0; g.day = 0
	check(absf(g.year_continuous() - 2200.0) < 1.0e-6, "1 January is the integer year")
	g.month = 6; g.day = 1                       # 1 July: 181 days in
	var mid: float = g.year_continuous()
	check(mid > 2200.4 and mid < 2200.6, "midyear lands near the half, got %f" % mid)
	g.month = 11; g.day = 30
	check(g.year_continuous() > 2200.99, "31 December is just short of the next year")
	check(g.year_continuous() < 2201.0, "and never reaches it")

	# ── A probe's position follows that calendar, not the integer year ──
	g.month = 0; g.day = 0
	var m: Dictionary = {
		"target": "Sirius", "progress": 0.0, "origin": "",
		"kind": "vn", "mission": "colonize",
		"start_year": 2200.0, "end_year": 2400.0,
		"accel_time_frac": 0.5, "accel_dist_frac": 0.5,
	}
	p.set("_flight_year", 2200.0)
	var at_start: float = p._track_progress(m)
	p.set("_flight_year", 2300.0)
	var at_half: float = p._track_progress(m)
	p.set("_flight_year", 2400.0)
	var at_end: float = p._track_progress(m)
	check(at_start == 0.0, "a probe starts at its origin")
	check(at_half > at_start and at_half < at_end, "it is partway at the halfway year")
	check(absf(at_end - 1.0) < 1.0e-6, "it arrives at the target")

	# Within a single calendar year the position must still change — this is the whole defect.
	p.set("_flight_year", 2300.0)
	var a: float = p._track_progress(m)
	p.set("_flight_year", 2300.5)
	var b: float = p._track_progress(m)
	check(b > a, "the probe moves inside one calendar year")

	# ── A flight past its end stays put at the target, not beyond it ──
	p.set("_flight_year", 9999.0)
	check(p._track_progress(m) == 1.0, "progress is clamped at arrival")

	# ── Anything without a flight window keeps the pushed figure ──
	var colony: Dictionary = {"target": "Sirius", "progress": 0.33, "kind": "colony"}
	check(absf(p._track_progress(colony) - 0.33) < 1.0e-9,
		"a colony ship still uses the pushed progress")
	var degenerate: Dictionary = m.duplicate()
	degenerate["end_year"] = 2200.0            # zero-length flight
	degenerate["progress"] = 0.42
	check(absf(p._track_progress(degenerate) - 0.42) < 1.0e-9,
		"a zero-length window falls back rather than dividing by zero")

	# ── Powered craft follow their profile; weapons cross linearly ──
	# A ship that spends a quarter of its flight time accelerating covers a tenth of the
	# distance in it, so at tf = 0.25 the profile and a straight line disagree sharply.  That is
	# what separates a crewed ship or a probe from a laser pulse already at speed.
	var powered: Dictionary = {
		"progress": 0.0, "start_year": 2200.0, "end_year": 2400.0,
		"accel_time_frac": 0.25, "accel_dist_frac": 0.1,
	}
	var weapon: Dictionary = {
		"progress": 0.0, "start_year": 2200.0, "end_year": 2400.0,
	}
	p.set("_flight_year", 2250.0)                       # tf = 0.25
	check(absf(p._track_progress(powered) - 0.1) < 1.0e-6,
		"a powered craft is still in its burn at a quarter of the way through")
	check(absf(p._track_progress(weapon) - 0.25) < 1.0e-6,
		"a weapon with no profile crosses linearly")
	p.set("_flight_year", 2300.0)
	check(p._track_progress(weapon) > 0.49 and p._track_progress(weapon) < 0.51,
		"and is halfway at the halfway year")

	# ── Every track type carries a window once it reaches the map ──
	g.month = 0; g.day = 0
	g.sidebar.hide_all()
	p.show()
	g.interstellar_missions.clear()
	g.probe_missions.clear()
	g.interstellar_attacks.clear()
	g.incoming_attacks.clear()
	g.interstellar_missions.append({
		"vn": false, "target": "Sirius", "origin": "", "progress": 0.0,
		"start_year": float(g.year), "end_year": float(g.year) + 300.0,
		"accel_time_frac": 0.5, "accel_dist_frac": 0.5,
	})
	g.probe_missions.append({
		"target": "Procyon", "start_year": float(g.year), "end_year": float(g.year) + 200.0,
		"accel_time_frac": 0.5, "accel_dist_frac": 0.5,
	})
	g.interstellar_attacks.append({
		"target": "Sirius", "kind": "laser", "power": 1.0,
		"start_year": float(g.year), "end_year": float(g.year) + 9.0,
	})
	g.incoming_attacks.append({
		"source": "Sirius", "target": "earth", "kind": "missile",
		"start_year": float(g.year), "end_year": float(g.year) + 50.0,
	})
	g.refresh_star_map()
	for _i in range(4): await process_frame

	for entry: Dictionary in (p.get("_missions") as Array):
		check(entry.has("end_year"),
			"a %s track carries its window" % str(entry.get("kind", "probe")))
		check(entry.has("accel_time_frac"), "a craft carries its burn profile")
	check((p.get("_missions") as Array).size() == 2, "both the ship and the recon probe are there")
	for entry: Dictionary in (p.get("_attacks") as Array):
		check(entry.has("end_year"), "an outgoing salvo carries its window")
		check(not entry.has("accel_time_frac"), "and no burn profile, so it crosses linearly")
	check((p.get("_attacks") as Array).size() == 1, "the salvo reached the map")
	for entry: Dictionary in (p.get("_incoming") as Array):
		check(entry.has("end_year"), "an incoming volley carries its window")
		check(not entry.has("accel_time_frac"), "and crosses linearly too")
	check((p.get("_incoming") as Array).size() == 1, "the volley reached the map")

	# ── The clock advances by itself, and stops when the game does ──
	g.sidebar.hide_all()
	p.show()
	g.interstellar_missions.append({
		"vn": true, "target": "Sirius", "origin": "", "progress": 0.0,
		"mission": "colonize", "start_year": float(g.year), "end_year": float(g.year) + 400.0,
		"accel_time_frac": 0.5, "accel_dist_frac": 0.5,
	})
	g.refresh_star_map()
	for _i in range(4): await process_frame
	check(absf(float(p.get("_flight_year")) - g.year_continuous()) < 0.01,
		"a refresh resyncs the map's calendar to the simulation")

	sol.paused = false
	sol.ui_paused = false
	sol.seconds_per_day = 0.1
	var t0: float = float(p.get("_flight_year"))
	for _i in range(20): await process_frame
	var t1: float = float(p.get("_flight_year"))
	check(t1 > t0, "the calendar advances between refreshes")

	sol.paused = true
	for _i in range(10): await process_frame
	var t2: float = float(p.get("_flight_year"))
	for _i in range(10): await process_frame
	check(absf(float(p.get("_flight_year")) - t2) < 1.0e-9,
		"and holds still while the game is paused")
	sol.paused = false

	print("FAILS: %d" % fails)
	quit()
