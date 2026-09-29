extends SceneTree
var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(25): await process_frame
	var g: Node = current_scene
	var ss: Node = root.get_node("SolarSystem")
	var sm = load("res://star_model.gd")

	# ── The physics ──
	# A full one-sided mirror on today's Sun: thrust = MIRROR_THRUST_EFFICIENCY x L/c.  The
	# efficiency started as a guessed 0.30 and was recalibrated to 0.0016 to land on the
	# accelerations the published Class-A Shkadov figures give, which is the assertion below
	# that actually has physics behind it.
	var full: float = sm.shkadov_thrust_n(1.0, 1.0)
	var accel: float = sm.shkadov_accel_ms2(1.0, 1.0, 1.0)
	# Printed in units of 1e-15 m/s^2: str() on the raw value just rounds it to 0.
	print("full-coverage thrust: %s N; acceleration %f e-15 m/s^2" % [full, accel * 1.0e15])
	var expect: float = float(sm.MIRROR_THRUST_EFFICIENCY) * 3.828e26 / 2.998e8
	check(absf(full / expect - 1.0) < 0.01, "thrust is EFFICIENCY x L/c: %s vs %s" % [full, expect])
	check(accel > 1.0e-16 and accel < 1.0e-14,
		"acceleration is in the published Class-A range: %s m/s^2" % accel)
	check(sm.shkadov_thrust_n(1.0, 2700.0) > full * 1000.0, "a red giant pushes far harder")
	check(sm.shkadov_accel_ms2(1.0, 1.0, 0.5) > sm.shkadov_accel_ms2(1.0, 1.0, 1.0),
		"a lighter star is easier to push")

	# ── The building ──
	var def: Dictionary = g._find_building_def("Shkadov Mirror")
	check(not def.is_empty() and float(def.get("mirror_coverage", 0.0)) > 0.0, "the mirror exists")
	check((def.get("allowed_types", []) as Array) == ["star"], "it belongs on the star")
	check(str(load("res://unlocks.gd").BUILDING_UNLOCK_REQUIREMENTS.get("Shkadov Mirror", "")) == "stellar_propulsion",
		"gated by stellar propulsion")
	check(root.get_node("ResearchTree").get_research_node("stellar_propulsion") != null, "the node exists")

	# ── Nothing without mirrors, and nothing without an aim ──
	ss.reset_star()
	g.planet_buildings["sun"] = []
	g._mark_prod_dirty(); g._recompute_production_cache()
	g._run_star_thrust(365.25 * 1.0e6)
	check(ss.star_drift_ly.length() == 0.0, "no mirrors, no motion")
	for i in range(2000): g.planet_buildings["sun"].append("Shkadov Mirror")
	g._mark_prod_dirty(); g._recompute_production_cache()
	print("coverage from 2000 mirrors: ", ss.star_mirror_coverage)
	check(ss.star_mirror_coverage > 0.0, "the mirrors register")
	g._run_star_thrust(365.25 * 1.0e6)
	check(ss.star_drift_ly.length() == 0.0, "unaimed, it does not move the star")

	# ── Aimed, it moves — and the distance to the target really falls ──
	var target := "Barnard's Star"
	var d0: float = g._star_distance_ly(target)
	check(g.aim_star_thruster(target), "the thruster can be aimed")
	check(ss.star_thrust_target == target, "and remembers its aim")
	# 600 Myr in 1 Myr steps.  2000 mirrors are only 10% coverage, and distance goes as
	# acceleration x time squared, so 200 Myr covers 0.2 ly - nowhere near the light-year
	# milestone checked at the end.  600 Myr covers about 1.9.
	for i in range(600):
		g._run_star_thrust(365.25 * 1.0e6)
	var d1: float = g._star_distance_ly(target)
	print("after 600 Myr: moved %s ly at %s m/s; %s %.4f ly → %.4f ly" % [
		ss.star_drift_ly.length(), ss.star_velocity_ms, target, d0, d1])
	check(ss.star_drift_ly.length() > 0.0, "the star moved")
	check(d1 < d0, "the target is closer than it was")
	check(absf((d0 - d1) - ss.star_drift_ly.length()) < 0.01, "it closed by exactly what it travelled")
	# A star the other way gets further off.
	var behind := ""
	for s2 in load("res://StarMapPanel.gd").STARS:
		var dir: Vector3 = (s2["pos"] as Vector3)
		if dir.normalized().dot(ss.star_thrust_dir) < -0.5:
			behind = str(s2["name"]); break
	if behind != "":
		check(g._star_distance_ly(behind) > float(g._star_lookup(behind)["dist"]),
			"%s behind it is further away" % behind)

	# ── Milestones, save/load, and the panel ──
	var notes: Array = g._pending_event_notifications.filter(func(n): return str(n["id"]).begins_with("star_drift_"))
	check(notes.size() >= 1, "crossing a light-year is announced")
	if notes.size() > 0: print("announcement: ", notes[0]["title"])
	g.save_game("user://saves/shkadov.json")
	var moved: Vector3 = ss.star_drift_ly
	ss.reset_star()
	g.load_game("user://saves/shkadov.json")
	check(ss.star_drift_ly.is_equal_approx(moved), "the drift survives a save: %s" % ss.star_drift_ly)
	check(ss.star_thrust_target == target, "so does the aim")
	var sun_data: Dictionary = g.get_planet_data("sun")
	check(float(sun_data["star"]["drift"]) > 0.0, "the Sun's panel reports the drift")

	# ── The star map frame follows the star ──
	var smp = g.sidebar.star_map
	smp._ref_name = "Sol"
	smp._sync_sol_frame()
	check(smp._ref_pos.is_equal_approx(ss.sol_position()), "the Sol frame moved with the star")
	ss.reset_star()
	print("FAILS: ", fails)
	quit()
