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

	# ── Drawn at the width its coverage claims ──
	#
	# The mirror is not laid out in a lane: there is one of it, it does not orbit, and it stands
	# at the photosphere.  Its size comes off SolarSystem.star_mirror_coverage, the same number
	# StarModel.shkadov_thrust_n turns into newtons, so what follows is what stops the picture
	# drifting from the physics.
	var P = load("res://planet.gd")
	for spec: Dictionary in P.INFRA_LANES:
		check(str(spec["type"]) != "Shkadov Mirror", "the mirror has no orbital lane")
	var sun: Node3D = g.get_node("WorldRoot/Planets/sun")
	var mnode: MeshInstance3D = sun.get_node_or_null("sun_shkadov_mirror")
	check(mnode != null, "the star raised the mirror's node")
	if mnode != null:
		check(mnode.mesh != null and not (mnode.mesh is BoxMesh),
			"with its model and not the box fallback")
		var bounds: AABB = mnode.mesh.get_aabb()
		var model_r: float = bounds.size.x * 0.5
		var model_back: float = -bounds.position.y
		check(model_r > 0.0 and model_back > 0.0,
			"the sail is a disc with a boom behind it: radius %.3f, reach %.3f" % [
				model_r, model_back])
		print("sail model: radius %.3f, reaches %.3f back towards the star" % [
			model_r, model_back])
		# The angle is the only place the coverage enters, so it has to invert exactly: a cap of
		# half-angle th covers (1 - cos th)/2 of the sky.  Up to the clamp, which 0.14 is under.
		for cov: float in [5.0e-3, 1.75e-2, 6.125e-2, 0.14]:
			var th: float = P.mirror_half_angle(cov)
			check(absf((1.0 - cos(th)) * 0.5 - cov) < 1.0e-9,
				"%s of the sky inverts to %.2f deg and back" % [str(cov), rad_to_deg(th)])
		# Two invariants, at every size the game or the console can ask for.
		for cov: float in [5.0e-3, 1.75e-2, 6.125e-2, 0.14, 1.0]:
			var th: float = P.mirror_half_angle(cov)
			var d: float = P.mirror_standoff(cov, bounds)
			var r: float = P.mirror_radius(cov, bounds)
			check(absf(r / d - tan(th)) < 1.0e-9,
				"at %s its rim subtends the angle it is drawn for: %.6f vs %.6f" % [
					str(cov), r / d, tan(th)])
			# The deepest point of the structure - the statite bus on its boom, not the plating -
			# flies MIRROR_GAP above the photosphere at EVERY size.  That is what "it sits at the
			# surface of the Sun" means for a model that reaches back towards the star: hung at a
			# flat 0.5 + gap, its bus would be a third of the way inside the photosphere by the
			# time the sail was full size.
			var deepest: float = d - model_back * (r / model_r)
			check(absf(deepest - (0.5 + P.MIRROR_GAP)) < 1.0e-6,
				"and its bus flies at the surface: %.6f vs %.6f" % [deepest, 0.5 + P.MIRROR_GAP])
		var r1: float = P.mirror_radius(5.0e-3, bounds)
		var r2: float = P.mirror_radius(1.75e-2, bounds)
		var r3: float = P.mirror_radius(6.125e-2, bounds)
		print("drawn radius by tier: %.4f, %.4f, %.4f; standoff %.4f, %.4f, %.4f (surface 0.500)"
			% [r1, r2, r3, P.mirror_standoff(5.0e-3, bounds),
				P.mirror_standoff(1.75e-2, bounds), P.mirror_standoff(6.125e-2, bounds)])
		check(r2 > r1 and r3 > r2,
			"levelling it up makes it wider: %.4f < %.4f < %.4f" % [r1, r2, r3])
		# The whole sail has to stay clear of the band, or the biggest mirror would be drawn
		# through the innermost lane of orbital infrastructure (the Core Mixing Array at 1.020).
		var rim: float = sqrt(pow(P.mirror_standoff(6.125e-2, bounds), 2.0) + r3 * r3)
		var innermost: float = INF
		for spec: Dictionary in P.INFRA_LANES:
			innermost = minf(innermost, float(spec["radius"]))
		check(rim < innermost,
			"and at full size its rim is still inside the band: %.4f vs %.4f" % [rim, innermost])
		# Driven to 1.0 by the dev console and by the tests above, where the standoff's own
		# denominator would otherwise run to zero and solve the sail to the size of the system.
		check(P.mirror_half_angle(1.0) <= P.MIRROR_MAX_HALF_ANGLE + 1.0e-9,
			"a full sky is held at the widest the picture can carry: %.2f deg" % rad_to_deg(
				P.mirror_half_angle(1.0)))
		check(is_finite(P.mirror_radius(1.0, bounds)) and P.mirror_radius(1.0, bounds) > r3,
			"and is still a number: %s" % str(P.mirror_radius(1.0, bounds)))

		var xf: Transform3D = P.mirror_transform(6.125e-2, bounds)
		check(xf.basis.determinant() > 0.0,
			"it is not drawn mirrored: determinant %+.4f" % xf.basis.determinant())
		check(xf.basis.y.normalized().dot(xf.origin.normalized()) > 0.9999,
			"+Y points away from the star, which is what the model is built to")
		check(P.mirror_transform(1.75e-2, bounds).basis.get_scale().x
			> P.mirror_transform(5.0e-3, bounds).basis.get_scale().x,
			"and the transform carries the width as scale")

		# The node itself: hidden with no mirror, shown at the coverage standing.
		ss.set_star_mirror_coverage(0.0)
		sun._update_star_mirror()
		check(not mnode.visible, "no coverage, no mirror drawn")
		ss.set_star_mirror_coverage(6.125e-2)
		sun._update_star_mirror()
		check(mnode.visible, "the mirror standing is drawn")
		check(absf(mnode.transform.origin.length() - P.mirror_standoff(6.125e-2, bounds))
			< 1.0e-6, "where the geometry puts it: %.4f" % mnode.transform.origin.length())
		# Scaled WITH the star, unlike every lane, because coverage is an angle: the drawn rim
		# has to hold the same share of the sky however big the star has grown.
		var drawn: float = mnode.transform.basis.get_scale().x * model_r
		check(absf(drawn - r3) < 1.0e-5,
			"and as wide as its coverage says: %.4f vs %.4f" % [drawn, r3])

		# The sail's back RADIATES, and it is the only thing in the game that does.  The sun's
		# six lights all sit on the photosphere, inside the sail's standoff, so not one of them
		# can reach its outward face: without this a full-size mirror viewed down its own axis
		# measures 0,0,0 across the whole disc - a hole in the frame rather than a
		# megastructure.  It is a temperature (about 1300 K at the flux it stands in), not the
		# faint stand-in emission that was removed from every lane, which is why the lane
		# materials have to stay dark for this assertion to mean anything.
		var mat := mnode.material_override as StandardMaterial3D
		check(mat != null and mat.emission_enabled, "the sail's back radiates")
		check(mat != null and mat.albedo_texture != null, "and still carries its baked map")
		var lane_mat := sun._infra_material(
			"res://models/orbital_habitat_albedo.png") as StandardMaterial3D
		check(lane_mat != null and not lane_mat.emission_enabled,
			"while a lane material carries no self-light at all")

	ss.reset_star()
	print("FAILS: ", fails)
	quit()
