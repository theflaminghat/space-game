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

	# ── And Sol is drawn WHERE SOL IS, not where it started ──
	#
	# The map used to place the Sun at Vector3.ZERO, which is the coordinate origin.  Those are
	# the same point only until the thruster runs; after that the Sun slid off the centre of its
	# own map — 391 px adrift after 5 ly, 1 876 px after 200 — while the frame stayed correctly
	# locked to the moving star.  Every launch and every incoming strike was drawn from the place
	# Sol used to be, too, because they all start at the same projected point.
	smp.show()
	for _i in range(4): await process_frame
	var vb = smp._view_basis()
	var ctr: Vector2 = smp.size * 0.5
	var sc: float = smp._fit_scale(ctr)
	for d: float in [0.0, 5.0, 200.0]:
		ss.star_drift_ly = Vector3(1, 0, 0) * d
		smp._sync_sol_frame()
		var drawn: Vector2 = smp._project(smp._rel(ss.sol_position()), vb, ctr, sc)
		check(drawn.distance_to(ctr) < 0.01,
			"at %.0f ly of drift the Sun is still at the centre of its own map: %.1f px off" % [
				d, drawn.distance_to(ctr)])
		# The origin it left behind must NOT be the centre any more, or the check above is
		# passing for the wrong reason.
		var origin: Vector2 = smp._project(smp._rel(Vector3.ZERO), vb, ctr, sc)
		if d > 0.0:
			check(origin.distance_to(ctr) > 1.0,
				"and the point it started from has visibly moved away: %.1f px" % (
					origin.distance_to(ctr)))
	# ── The star never outruns light ──
	#
	# The integration used to be Newtonian, v += a*t with nothing bounding it.  A full mirror
	# shell accelerates Sol at only ~1e-15 m/s², which sounds harmless and reaches c in 9.2e15
	# years — and this run goes to the heat death at 1e100, so the star genuinely went
	# superluminal on its own: v/c measured 1.081 at 1e16 years with no console multiplier.
	ss.reset_star()
	ss.set_star_mirror_coverage(1.0)
	ss.aim_star_thrust(Vector3(1, 0, 0), "relativity")
	var c_ms: float = StarModel.LIGHT_SPEED_MS
	var walked: float = 0.0
	for mark: float in [1.0, 1.0e6, 1.0e12, 1.0e15, 1.0e16, 1.0e18]:
		ss.advance_star_thrust((mark - walked) * 365.25)
		walked = mark
		check(ss.star_velocity_ms < c_ms,
			"at %s years the star is still subluminal: v/c = %.9f" % [
				Units.format_si(mark, ""), ss.star_velocity_ms / c_ms])
		# And it cannot have covered more ground than light would have in the same time.
		check(ss.star_drift_ly.x < mark,
			"and has gone less far than light: %s ly in %s years" % [
				Units.format_si(ss.star_drift_ly.x, ""), Units.format_si(mark, "")])
	check(ss.star_velocity_ms / c_ms > 0.9,
		"while still getting genuinely relativistic: v/c = %.6f" % (ss.star_velocity_ms / c_ms))

	# ── A slice of any width gives the same answer ──
	# Fast mode hands this function enormous steps, so the integral has to be exact rather than
	# a small-step approximation.  It also has to survive the arithmetic: computed as
	# (c²/a)(γ2 − γ1) it returns exactly zero at ordinary speeds, because (u/c)² is around 1e-32
	# and sqrt(1 + 1e-32) is 1.0 in a double — both gammas are 1 and the difference cancels
	# away.  The star stopped moving entirely.
	ss.reset_star()
	ss.set_star_mirror_coverage(1.0)
	ss.aim_star_thrust(Vector3(1, 0, 0), "slices")
	ss.advance_star_thrust(1.0e15 * 365.25)
	var one_slice: float = ss.star_drift_ly.x
	check(one_slice > 0.0, "one enormous slice moves the star: %s ly" % str(one_slice))
	ss.reset_star()
	ss.set_star_mirror_coverage(1.0)
	ss.aim_star_thrust(Vector3(1, 0, 0), "slices")
	for _i in range(1000):
		ss.advance_star_thrust(1.0e12 * 365.25)
	check(absf(ss.star_drift_ly.x / one_slice - 1.0) < 1.0e-9,
		"and a thousand small ones agree with it: ratio %.9f" % (ss.star_drift_ly.x / one_slice))
	# A single short slice from rest must still move it, which the cancelling form did not.
	ss.reset_star()
	ss.set_star_mirror_coverage(1.0)
	ss.aim_star_thrust(Vector3(1, 0, 0), "slices")
	check(ss.advance_star_thrust(365.25) > 0.0,
		"and one ordinary year of thrust is not rounded away to nothing")

	# ── How far it has come stays a real number, however far that is ──
	#
	# Vector3 is 32-bit per component, so star_drift_ly.length() squares them in float32 and
	# returns inf past about 1.8e19 ly — the stored vector was fine, the magnitude blew up.  A
	# thruster held at near-c for 1e19 years covers that and the run goes to 1e100, so every
	# readout of the journey, and the "crossed another light-year" announcement, became infinity
	# just by letting the game run.  The scalar is 64-bit and is now the authoritative figure.
	ss.reset_star()
	ss.set_star_mirror_coverage(1.0)
	ss.aim_star_thrust(Vector3(1, 0, 0), "overflow")
	var reached: float = 0.0
	for epoch: float in [1.0e15, 1.0e19, 1.0e25, 1.0e100]:
		ss.advance_star_thrust((epoch - reached) * 365.25)
		reached = epoch
		check(is_finite(ss.star_drift_dist_ly),
			"at %s years the distance travelled is a number: %s ly" % [
				Units.format_si(epoch, ""), Units.format_si(ss.star_drift_dist_ly, "")])
		check(ss.star_drift_dist_ly > 0.0, "and a positive one")
		# The POSITION saturates rather than overflowing, so distances measured against it come
		# back enormous but finite.  A nan here would silently poison every comparison that
		# touched it — which is what an unclamped length() produced.
		check(is_finite(ss.star_drift_ly.length()),
			"the position stays finite too: %s" % str(ss.star_drift_ly.length()))
		var to_star: float = (Vector3(5.0, 0.0, 0.0) - ss.sol_position()).length()
		check(is_finite(to_star),
			"and a distance measured from it is still a number: %s ly" % Units.format_si(
				to_star, ""))
	check(ss.star_drift_ly.length() <= ss.DRIFT_POSITION_MAX_LY * 1.0001,
		"the position is held at its cap: %s" % str(ss.star_drift_ly.length()))
	check(ss.star_drift_dist_ly > ss.DRIFT_POSITION_MAX_LY,
		"while the journey itself has gone far past it — the two part company on purpose")

	# ── Both halves survive a save, and an old save derives the scalar ──
	ss.reset_star()
	ss.set_star_mirror_coverage(1.0)
	ss.aim_star_thrust(Vector3(0, 1, 0), "saved")
	ss.advance_star_thrust(1.0e12 * 365.25)
	var kept: float = ss.star_drift_dist_ly
	g.save_game("user://saves/drift_overflow.json")
	ss.reset_star()
	g.load_game("user://saves/drift_overflow.json")
	check(absf(ss.star_drift_dist_ly - kept) < 1.0, "the distance travelled is saved: %s" % str(
		ss.star_drift_dist_ly))
	# A save from before the scalar existed has only the vector; its length is the answer.
	ss.star_drift_ly = Vector3(3.0, 4.0, 0.0)
	ss.star_drift_dist_ly = -1.0          # the schema default, meaning "not in this file"
	g._migrate_star_drift()
	check(absf(ss.star_drift_dist_ly - 5.0) < 1.0e-6,
		"an old save takes it from the vector: %s" % str(ss.star_drift_dist_ly))

	ss.reset_star()
	print("FAILS: ", fails)
	quit()
