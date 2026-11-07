extends SceneTree
## Surface area of a built cap, in the star's local units.
func _cap_area(mesh: Mesh) -> float:
	var arr: Array = mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var area: float = 0.0
	for t in range(0, ix.size(), 3):
		var a: Vector3 = vs[ix[t]]
		area += 0.5 * (vs[ix[t + 1]] - a).cross(vs[ix[t + 2]] - a).length()
	return area

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
	check(int(def.get("max_count", 0)) == 1, "and there is one of it")
	# Every tier carries the cap, or the bigger ones would be uncapped: _scaled() erases
	# "min_count" (a floor belongs to the base tier alone) and must NOT erase this.
	for tier: String in BuildingData.tiers("Shkadov Mirror"):
		check(int(g._find_building_def(tier).get("max_count", 0)) == 1,
			"%s carries the cap too" % tier)
	# Levelling it up is the only way to make it push harder, so each tier must cover more sky
	# than the one below it, and the biggest of them is what the achievement asks for.
	var covs: Array = []
	for tier: String in BuildingData.tiers("Shkadov Mirror"):
		covs.append(float(g._find_building_def(tier).get("mirror_coverage", 0.0)))
	check(covs.size() >= 2, "it has tiers at all: %d" % covs.size())
	for i in range(1, covs.size()):
		check(float(covs[i]) > float(covs[i - 1]),
			"tier %d covers more sky than tier %d: %s vs %s" % [
				i + 1, i, str(covs[i]), str(covs[i - 1])])
	check(absf(BuildingData.max_mirror_coverage() - float(covs[covs.size() - 1])) < 1.0e-12,
		"and the catalogue's biggest coverage is the top tier's: %s" % str(
			BuildingData.max_mirror_coverage()))
	print("mirror coverage by tier: %s" % str(covs))
	check(str(load("res://unlocks.gd").BUILDING_UNLOCK_REQUIREMENTS.get("Shkadov Mirror", "")) == "stellar_propulsion",
		"gated by stellar propulsion")
	check(root.get_node("ResearchTree").get_research_node("stellar_propulsion") != null, "the node exists")

	# ── Nothing without mirrors, and nothing without an aim ──
	ss.reset_star()
	g.planet_buildings["sun"] = []
	g._mark_prod_dirty(); g._recompute_production_cache()
	g._run_star_thrust(365.25 * 1.0e6)
	check(ss.star_drift_ly.length() == 0.0, "no mirrors, no motion")
	var top: String = str(BuildingData.tiers("Shkadov Mirror")[-1])
	g.planet_buildings["sun"] = [top]
	g._mark_prod_dirty(); g._recompute_production_cache()
	print("coverage from one %s: %s" % [top, str(ss.star_mirror_coverage)])
	check(absf(ss.star_mirror_coverage - BuildingData.max_mirror_coverage()) < 1.0e-12,
		"the one mirror registers at its own coverage")
	g._run_star_thrust(365.25 * 1.0e6)
	check(ss.star_drift_ly.length() == 0.0, "unaimed, it does not move the star")

	# ── Aimed, it moves — and the distance to the target really falls ──
	var target := "Barnard's Star"
	var d0: float = g._star_distance_ly(target)
	check(g.aim_star_thruster(target), "the thruster can be aimed")
	check(ss.star_thrust_target == target, "and remembers its aim")
	# 800 Myr in 1 Myr steps.  One mirror at full size covers 6.125 % of the sky, which
	# accelerates Sol at 6.3e-17 m/s^2, and distance goes as acceleration x time squared - so a
	# century of it is nothing and 800 Myr is about 2.1 ly, far enough past the light-year
	# milestone checked at the end and nowhere near overshooting the target 6 ly away.
	for i in range(800):
		g._run_star_thrust(365.25 * 1.0e6)
	var d1: float = g._star_distance_ly(target)
	print("after 800 Myr: moved %s ly at %s m/s; %s %.4f ly → %.4f ly" % [
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

	# ── The panel says what the mirror is pushing with ──
	#
	# The journey is the wrong readout to judge a retrofit by: drift reads 0.000 ly and the
	# speed a ten-thousandth of a metre per second for the whole of a normal run, at every size
	# of mirror.  So the Sun's panel carries the sail's own figures instead, and they have to
	# move when it is retrofitted or nothing on screen says it did anything.
	var pushed: Array = []
	for tier: String in BuildingData.tiers("Shkadov Mirror"):
		g.planet_buildings["sun"] = [tier]
		g._mark_prod_dirty(); g._recompute_production_cache()
		var sd: Dictionary = (g.get_planet_data("sun").get("star", {}) as Dictionary)
		check(sd.has("mirror_thrust"), "%s: the panel is told the thrust" % tier)
		check(absf(float(sd.get("mirrors", 0.0))
				- float(g._find_building_def(tier).get("mirror_coverage", 0.0))) < 1.0e-12,
			"%s: and the share of the sky it covers" % tier)
		pushed.append(float(sd.get("mirror_thrust", 0.0)))
	print("panel thrust by tier: %s" % str(pushed))
	for i in range(1, pushed.size()):
		check(float(pushed[i]) > float(pushed[i - 1]) * 3.0,
			"a bigger mirror pushes harder: %s vs %s" % [str(pushed[i]), str(pushed[i - 1])])
	# The same number the integrator runs on, not a second one worked out another way.
	check(absf(float(pushed[pushed.size() - 1]) / sm.shkadov_thrust_n(
			ss.star_mirror_coverage, ss.sun_luminosity_lsun()) - 1.0) < 1.0e-9,
		"and it is the thrust, not a figure of its own")
	g.planet_buildings["sun"] = []
	g._mark_prod_dirty(); g._recompute_production_cache()

	# ── One mirror, and only one ──
	#
	# The cap is enforced in try_build and not only greyed out in the panel, because automation
	# rules and the dev console build through the same call.  Counted across the WHOLE FAMILY:
	# the tiers are separate catalogue entries, so a cap read per entry would let the player
	# stand three mirrors by building one of each size.
	ss.reset_star()
	g.planet_buildings["sun"] = []
	g.build_queue.erase("sun")
	g._mark_prod_dirty(); g._recompute_production_cache()
	var rt: Node = root.get_node("ResearchTree")
	rt.force_unlock("stellar_propulsion")
	rt.force_unlock(g.SOLAR_ORBIT_RESEARCH)
	# The tier gate, so the retrofit below is refused by the cap or by nothing.
	rt.force_unlock("precision_manufacturing")
	check(g._is_body_buildable("sun"), "solar orbit is a build site")
	# Pay for four of EVERY tier, so what refuses the second mirror is the cap and not the bill -
	# the one failure mode an "it was refused" assertion cannot tell apart on its own.
	for tier: String in BuildingData.tiers("Shkadov Mirror"):
		for res: String in (g._find_building_def(tier).get("cost", {}) as Dictionary):
			var need: float = float((g._find_building_def(tier)["cost"] as Dictionary)[res]) * 4.0
			if res == "energy":
				rt.resources["energy"] = maxf(float(rt.resources.get("energy", 0.0)), need)
			else:
				g._add_stockpile(res, need, "sun")
	check(g.build_room("sun", "Shkadov Mirror") == 1, "with none standing there is room for one")
	check(g.try_build("sun", "Shkadov Mirror"), "and the first one is built")
	check(g.build_room("sun", "Shkadov Mirror") == 0,
		"which takes the only slot while it is still in the queue")
	check(not g.try_build("sun", "Shkadov Mirror"), "so a second is refused")
	check(not g.try_build("sun", "Shkadov Mirror II"),
		"and so is a bigger one — the cap counts every tier together")
	# Finish the job, and the cap holds against the standing structure rather than the queue.
	var mjobs: Array = g.build_queue["sun"]
	check(mjobs.size() == 1, "exactly one mirror is queued: %d" % mjobs.size())
	g._complete_build("sun", mjobs[0])
	g.build_queue["sun"] = []
	g._mark_prod_dirty(); g._recompute_production_cache()
	check(g._count_building("sun", "Shkadov Mirror") == 1, "the mirror is standing")
	check(g.build_room("sun", "Shkadov Mirror") == 0, "and still fills the only slot")
	check(not g.try_build("sun", "Shkadov Mirror III"), "nothing else may join it")
	# Everything else in the catalogue is uncapped and says so, or a cap bug would quietly stop
	# the game being playable rather than showing up here.
	check(g.build_room("sun", "Orbital Habitat") >= 1000,
		"an uncapped structure has room without limit: %d" % g.build_room("sun", "Orbital Habitat"))
	# Retrofitting is how it gets bigger, and the cap must not stand in the way of it.
	check(g.try_upgrade("sun", "Shkadov Mirror"), "the standing mirror can be retrofitted")
	var ujobs: Array = g.build_queue["sun"]
	check(ujobs.size() == 1 and str(ujobs[0].get("upgrade_from", "")) == "Shkadov Mirror",
		"the retrofit is queued against the mirror standing")
	check(g.build_room("sun", "Shkadov Mirror") == 0,
		"and the family is still at its cap, not over it")
	g._complete_build("sun", ujobs[0])
	g.build_queue["sun"] = []
	g._mark_prod_dirty(); g._recompute_production_cache()
	check(g._count_building("sun", "Shkadov Mirror") == 0
		and g._count_building("sun", "Shkadov Mirror II") == 1,
		"the retrofit consumed the mirror and left the bigger one")
	check(g.build_room("sun", "Shkadov Mirror") == 0, "which is still the only one there can be")
	# What the build panel is handed, which is the other half of the cap: without the room in
	# the row its "+" buttons stay live and every click is silently refused.
	var was_planet: String = g.current_planet
	g.current_planet = "sun"
	var mrow: Dictionary = {}
	for row: Dictionary in g._get_catalog_for_display():
		if str(row.get("name", "")) == "Shkadov Mirror":
			mrow = row
	g.current_planet = was_planet
	check(not mrow.is_empty(), "the build panel is offered the mirror")
	check(int(mrow.get("max_count", 0)) == 1, "with its cap")
	check(int(mrow.get("build_room", -1)) == 0, "and with no room left while one stands")

	# ── A save from before the cap carries a fleet, and comes back as one mirror ──
	#
	# Nothing takes the extras away on its own: build_room refuses MORE mirrors but a loaded
	# fleet would stand over its cap for ever, with its coverage saturated at a full sky. And
	# the one kept has to come back SWITCHED ON, or a fleet the player had idled restores as a
	# single idle mirror - a thruster that silently stopped working, which is the failure
	# save_schema.gd's own header is about.
	g.planet_buildings["sun"] = []
	g.build_queue.erase("sun")
	for _i in range(40):
		g.planet_buildings["sun"].append("Shkadov Mirror")
	for _i in range(3):
		g.planet_buildings["sun"].append("Shkadov Mirror II")
	g.planet_buildings["sun"].append("Orbital Habitat")
	g.active_buildings["sun"] = {"Shkadov Mirror": 0, "Shkadov Mirror II": 0}
	g.save_game("user://saves/shkadov_fleet.json")
	g.planet_buildings["sun"] = []
	g.active_buildings.erase("sun")
	g.load_game("user://saves/shkadov_fleet.json")
	check(g._count_building("sun", "Shkadov Mirror") == 0,
		"the fleet is gone: %d left" % g._count_building("sun", "Shkadov Mirror"))
	check(g._count_building("sun", "Shkadov Mirror II") == 1,
		"and the biggest tier it held is the one kept")
	check(g._count_building("sun", "Orbital Habitat") == 1, "nothing else on the Sun is touched")
	check(g.build_room("sun", "Shkadov Mirror") == 0,
		"the loaded roster is AT its cap, not over it")
	check(g.active_count("sun", "Shkadov Mirror II") == 1,
		"the mirror kept is switched on, whatever the fleet's switches said")
	check(ss.star_mirror_coverage > 0.0,
		"so the thruster works after the load: %s" % str(ss.star_mirror_coverage))

	# ── Drawn as the share of sky it is pushing with ──
	#
	# The mirror is not laid out in a lane: there is one of it, it does not orbit, and it stands
	# on the photosphere.  It is a spherical cap built from SolarSystem.star_mirror_coverage -
	# the same number StarModel.shkadov_thrust_n turns into newtons - and because a cap on a
	# shell concentric with the star covers exactly (1 - cos th)/2 of it, what is on screen is
	# not proportional to the physics, it IS the physics.  That is what the area assertion below
	# measures, off the built mesh rather than off the formula that built it.
	var P = load("res://planet.gd")
	for spec: Dictionary in P.INFRA_LANES:
		check(str(spec["type"]) != "Shkadov Mirror", "the mirror has no orbital lane")
	var sun: Node3D = g.get_node("WorldRoot/Planets/sun")
	var mnode: MeshInstance3D = sun.get_node_or_null("sun_shkadov_mirror")
	check(mnode != null, "the star raised the mirror's node")
	if mnode != null:
		# The angle is the only place the coverage enters, so it has to invert exactly.
		for cov: float in [5.0e-3, 1.75e-2, 6.125e-2, 0.25, 1.0]:
			var th: float = P.mirror_half_angle(cov)
			check(absf((1.0 - cos(th)) * 0.5 - cov) < 1.0e-9,
				"%s of the sky inverts to %.2f deg and back" % [str(cov), rad_to_deg(th)])
		# A full sky is a cap that has closed into a shell, not a runaway: the flat disc this
		# replaced sent its rim to infinity at a right angle and had to be clamped.
		check(absf(P.mirror_half_angle(1.0) - PI) < 1.0e-9,
			"the whole sky is a closed shell: %.2f deg" % rad_to_deg(P.mirror_half_angle(1.0)))
		check(P.mirror_half_angle(1.75e-2) > P.mirror_half_angle(5.0e-3)
			and P.mirror_half_angle(6.125e-2) > P.mirror_half_angle(1.75e-2),
			"and levelling it up opens the cap wider every time")

		var stand: float = P.mirror_standoff()
		check(stand > 0.5, "the sail flies clear of the photosphere at 0.5: %.3f" % stand)
		print("sail: standoff %.3f, half-angle by tier %.2f / %.2f / %.2f deg, rim %.4f at full"
			% [stand, rad_to_deg(P.mirror_half_angle(5.0e-3)),
				rad_to_deg(P.mirror_half_angle(1.75e-2)),
				rad_to_deg(P.mirror_half_angle(6.125e-2)), P.mirror_radius(6.125e-2)])

		# The mesh itself, at every size the game or the console can ask for.
		for cov: float in [5.0e-3, 1.75e-2, 6.125e-2, 0.25, 1.0]:
			var mesh: ArrayMesh = P.mirror_cap_mesh(P.mirror_half_angle(cov))
			check(mesh.get_surface_count() == 1,
				"the cap is one surface: %d" % mesh.get_surface_count())
			var arr: Array = mesh.surface_get_arrays(0)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			check(vs.size() > 0 and ns.size() == vs.size()
				and (arr[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() == vs.size(),
				"every vertex has a normal and a UV")
			# EVERY point of it stands at the same height, rim included.  This is the whole
			# reason it is a cap and not a disc: a flat sheet standing on the star has its rim
			# further out than its centre, so a wide one reached into the Dyson swarm's inner
			# lane, and the standoff had to be solved around a boom that would otherwise end up
			# inside the photosphere.  "It sits at the surface of the Sun" is exact here.
			var worst: float = 0.0
			for v: Vector3 in vs:
				worst = maxf(worst, absf(v.length() - stand))
			check(worst < 1.0e-6,
				"at %s every point of the sail is at the standoff: worst %s" % [
					str(cov), str(worst)])
			# Not mirrored.  A surface wound the other way has its front where its back should
			# be: the renderer culls the faces pointing at you and keeps the ones facing away,
			# which is the fault the orbital structures and then the belt were both shaded by.
			var back: int = 0
			for t in range(0, ix.size(), 3):
				var a: Vector3 = vs[ix[t]]
				var face: Vector3 = (vs[ix[t + 2]] - a).cross(vs[ix[t + 1]] - a)
				if face.dot(ns[ix[t]]) <= 0.0:
					back += 1
			check(back == 0, "at %s no triangle is wound against its normal: %d of %d"
				% [str(cov), back, ix.size() / 3])
			# And the payoff: the cap's own area over the sphere's is the coverage the thrust
			# was computed from.  Measured off the triangles, so it answers for the mesh that is
			# actually drawn rather than for the formula that built it.  A sixteen-ring cap
			# under-measures a fraction of a percent, being chords across arcs.
			var area: float = 0.0
			for t in range(0, ix.size(), 3):
				var a2: Vector3 = vs[ix[t]]
				area += 0.5 * (vs[ix[t + 1]] - a2).cross(vs[ix[t + 2]] - a2).length()
			var drawn_cov: float = area / (4.0 * PI * stand * stand)
			check(absf(drawn_cov / cov - 1.0) < 0.01,
				"at %s the sail covers the sky it claims: %.6f drawn" % [str(cov), drawn_cov])

		# Where it stands: a pure rotation onto MIRROR_SIDE, nothing scaled and nothing moved.
		# The star's own scale is inherited through the parent, which is what keeps a share of
		# the sky a share of the sky as the star swells up the giant branch.
		var xf: Transform3D = P.mirror_transform()
		check(xf.origin.is_equal_approx(Vector3.ZERO),
			"the sail's node sits at the star's centre; the mesh carries the standoff")
		check(xf.basis.determinant() > 0.0,
			"and is not drawn mirrored: determinant %+.4f" % xf.basis.determinant())
		check(xf.basis.get_scale().is_equal_approx(Vector3.ONE),
			"nothing is scaled: %s" % str(xf.basis.get_scale()))
		check(xf.basis.y.normalized().dot((P.MIRROR_SIDE as Vector3).normalized()) > 0.9999,
			"and it faces the side of the star it was put on")

		# No map and NO SELF-LIGHT.  Everything in the system is lit by the sun and nothing
		# else, so the face turned away from the star is black - which is what it would be, and
		# from outside it is the only face there is.  The sail briefly carried a 1300 K glow for
		# the back it would really radiate; it does not any more, and a lane material is checked
		# beside it so "no emission" is the same rule for both rather than two coincidences.
		var mat := mnode.material_override as StandardMaterial3D
		check(mat != null and not mat.emission_enabled, "the sail does not light itself")
		check(mat != null and mat.albedo_texture == null, "and is a bare surface, with no map")
		var lane_mat := sun._infra_material(
			"res://models/orbital_habitat_albedo.png") as StandardMaterial3D
		check(lane_mat != null and not lane_mat.emission_enabled,
			"nor does a lane material")

		# The node follows the roster: hidden with no mirror, built at the coverage standing.
		ss.set_star_mirror_coverage(0.0)
		sun._update_star_mirror()
		check(not mnode.visible, "no coverage, no mirror drawn")
		ss.set_star_mirror_coverage(5.0e-3)
		sun._update_star_mirror()
		check(mnode.visible and mnode.mesh != null, "the mirror standing is drawn")
		var small: float = _cap_area(mnode.mesh)
		ss.set_star_mirror_coverage(6.125e-2)
		sun._update_star_mirror()
		check(_cap_area(mnode.mesh) > small * 5.0,
			"and retrofitting it rebuilds a bigger one: %.4f -> %.4f" % [
				small, _cap_area(mnode.mesh)])

	ss.reset_star()
	print("FAILS: ", fails)
	quit()
