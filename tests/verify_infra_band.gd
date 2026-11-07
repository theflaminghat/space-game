extends SceneTree

## Every orbital structure around the Sun sits inside Mercury's orbit, outside the Sun, and
## clear of the Dyson swarm.
##
## "Inside Mercury's orbit" is measured against its PERIHELION, not its mean distance: Mercury is
## eccentric enough (0.21) that its closest approach is 8.58 world units against a mean of 10.47,
## so a band sized to the mean would be swallowed once a year.
##
## "Clear of the swarm" is the one that was broken: the infrastructure band ran 3.01 .. 7.99 and
## the collector shell 3.05 .. 5.30, so almost every structure was embedded in the swarm.  Both
## bands scale with the star by the same factor, so holding them apart once holds them apart at
## every stage of its life.
##
## The Shkadov Mirror is the exception and is checked as one: it has no lane, because there is
## only ever one of it and it stands on the photosphere rather than orbiting.  That puts it
## INSIDE everything above, in the gap between the star and the swarm, so what is asked of it is
## the other way round — that it clears the photosphere, and that it does not reach out into
## either band however wide it is opened.
##
## It holds at ANY size, which is what being a spherical cap buys: every point of it stands at
## the same distance from the star, so the sail's widest point is its only point.  Drawn as a
## flat disc it did not — a disc standing on the star has its rim further out than its centre,
## and the biggest mirror's rim reached 1.6 solar radii, into the swarm's inner lane at 1.3.

## The innermost orbital lane, in planet radii — the floor the mirror has to stay under.
func _innermost_lane(P) -> float:
	var r: float = INF
	for spec: Dictionary in P.INFRA_LANES:
		r = minf(r, float(spec["radius"]))
	return r

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
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var sun: Node3D = g.get_node("WorldRoot/Planets/sun")
	var P = load("res://planet.gd")

	# The log-radial mapping the orbits are drawn with, at Mercury's closest approach.
	const MERCURY_PERIHELION_AU := 0.3075
	var mercury_min: float = log(MERCURY_PERIHELION_AU + 1.0) * 32.0
	var surface: float = sun.scale.x * 0.5
	check(mercury_min > surface, "there is a band to fit into at all")

	var innermost: float = INF
	var outermost: float = 0.0
	var worst_in: String = ""
	var worst_out: String = ""
	for spec: Dictionary in P.INFRA_LANES:
		var t: String = str(spec["type"])
		var d: float = sun.infra_slot_world_pos(t, 0, 1).distance_to(sun.global_position)
		check(d > surface, "%s clears the Sun's surface: %.3f vs %.3f" % [t, d, surface])
		check(d < mercury_min,
			"%s is inside Mercury's perihelion: %.3f vs %.3f" % [t, d, mercury_min])
		if d < innermost:
			innermost = d
			worst_in = t
		if d > outermost:
			outermost = d
			worst_out = t
	print("band %.3f (%s) .. %.3f (%s) ; surface %.3f, Mercury perihelion %.3f" % [
		innermost, worst_in, outermost, worst_out, surface, mercury_min])

	# The Dyson swarm shares the band and must also stay inside it.
	var IP = load("res://init_planets.gd")
	var swarm_out: float = log(IP.SWARM_OUTER_AU + 1.0) * 32.0
	var swarm_in: float = log(IP.SWARM_INNER_AU + 1.0) * 32.0
	check(swarm_in > surface, "the swarm clears the surface: %.3f" % swarm_in)
	check(swarm_out < mercury_min,
		"and stays inside Mercury too: %.3f vs %.3f" % [swarm_out, mercury_min])
	print("swarm %.3f .. %.3f across %d lanes" % [swarm_in, swarm_out, IP.SWARM_LANES])

	# ── The two bands do not intersect ──
	# The swarm hugs the star and the infrastructure servicing it rings the outside, so a
	# collector and a radiator can never occupy the same shell.
	check(innermost > swarm_out,
		"the infrastructure band starts outside the swarm: %.3f (%s) vs %.3f" % [
			innermost, worst_in, swarm_out])
	for spec: Dictionary in P.INFRA_LANES:
		var t: String = str(spec["type"])
		var d: float = sun.infra_slot_world_pos(t, 0, 1).distance_to(sun.global_position)
		check(d < swarm_in or d > swarm_out,
			"%s is not inside the collector shell: %.3f in %.3f..%.3f" % [
				t, d, swarm_in, swarm_out])

	# ── The mirror stands in the gap, not in either band ──
	#
	# It used to hold the innermost lane of the band at 0.980 planet radii.  Now it has none, so
	# the sweep above is complete without it and its own clearances are checked here.
	for spec: Dictionary in P.INFRA_LANES:
		check(str(spec["type"]) != "Shkadov Mirror",
			"the mirror is not in the band: it stands on the star")
	check(sun.get_node_or_null("sun_shkadov_mirror") != null, "the star raised the mirror")
	# Local units, where the star's surface is at 0.5; the sail is a child of the (scaled) star,
	# so one local unit is sun.scale.x world units.  The standoff is the WHOLE geometry: a cap
	# has no point further out than any other, so this one number answers for every size of it.
	var stand: float = P.mirror_standoff()
	print("mirror: standoff %.3f local = %.3f world (surface %.3f, band from %.3f, swarm from %.3f)"
		% [stand, stand * sun.scale.x, surface, _innermost_lane(P), swarm_in])
	check(stand * sun.scale.x > surface,
		"the sail clears the photosphere: %.3f vs %.3f" % [stand * sun.scale.x, surface])
	check(stand < _innermost_lane(P),
		"and stays inside the band: %.3f vs %.3f" % [stand, _innermost_lane(P)])
	check(stand * sun.scale.x < swarm_in,
		"and inside the collector shell: %.3f vs %.3f" % [stand * sun.scale.x, swarm_in])
	# At every coverage, including the full sky, which is the cap closed into a shell.
	for cov: float in [BuildingData.max_mirror_coverage(), 0.5, 1.0]:
		var vs: PackedVector3Array = P.mirror_cap_mesh(
			P.mirror_half_angle(cov)).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var out: float = 0.0
		var inn: float = INF
		for v: Vector3 in vs:
			out = maxf(out, v.length())
			inn = minf(inn, v.length())
		check(out * sun.scale.x < swarm_in and inn * sun.scale.x > surface,
			"at %s of the sky the whole sail is in the gap: %.3f .. %.3f world" % [
				str(cov), inn * sun.scale.x, out * sun.scale.x])

	# ── The lane spacing is what the swarm constants say it is ──
	# Both halvings, and the three added lanes, are geometry the capacity depends on, so a
	# stray edit to one constant without the other shows up here.
	var gap: float = (IP.SWARM_OUTER_AU - IP.SWARM_INNER_AU) / float(IP.SWARM_LANES - 1)
	check(absf(gap - 0.00235294) < 1.0e-6, "lanes are a quarter of the original gap: %.8f" % gap)
	check(IP.SWARM_LANES == 21, "and there are 21 of them: %d" % IP.SWARM_LANES)
	check(IP.SWARM_LANES == g.SWARM_LANES, "Game agrees on the lane count")
	check(absf(IP.SWARM_OUTER_AU - g.SWARM_OUTER_AU) < 1.0e-9, "and on the outer radius")
	check(absf(IP.SWARM_INNER_AU - g.SWARM_INNER_AU) < 1.0e-9, "and on the inner radius")

	# ── The planes are spread, which is what lets the band be this tight ──
	# Tightened, consecutive lanes are closer in radius than the structures are wide; what keeps
	# them clear of each other is the angle between their orbital planes.
	var incls: Array = []
	for lane: Dictionary in g.get_node("WorldRoot/Planets/sun")._infra:
		incls.append(float(lane["incl"]))
	check(incls.size() == P.INFRA_LANES.size(), "every lane was built: %d" % incls.size())
	var spread: float = 0.0
	for i in range(incls.size()):
		for j in range(i + 1, incls.size()):
			spread = maxf(spread, absf(float(incls[i]) - float(incls[j])))
	check(spread > 1.0,
		"the orbital planes are spread across the sphere, not a narrow band: %.2f rad" % spread)
	var adjacent_min: float = INF
	for i in range(incls.size() - 1):
		adjacent_min = minf(adjacent_min, absf(float(incls[i]) - float(incls[i + 1])))
	check(adjacent_min > 0.2,
		"and no two CONSECUTIVE lanes share a plane: closest %.3f rad" % adjacent_min)

	# ── Past 100x the lanes stop being drawn ──
	# The bodies are already replaced by motion-blur rings there; a few hundred structures
	# smeared round the Sun says nothing about where anything is.
	var ss: Node = root.get_node("SolarSystem")
	ss.paused = false
	ss.ui_paused = false
	ss.seconds_per_day = ss.TIMESCALE_BASE / 1.0          # 1x
	for _i in range(4): await process_frame
	check(ss.orbits_resolvable(), "1x resolves orbits")
	check(_lanes_drawn(sun), "so the lanes are drawn")

	ss.seconds_per_day = ss.TIMESCALE_BASE / 100.0        # exactly 100x still draws
	for _i in range(4): await process_frame
	check(ss.orbits_resolvable(), "100x itself still resolves")
	check(_lanes_drawn(sun), "and still draws them")

	ss.seconds_per_day = ss.TIMESCALE_BASE / 1000.0       # past the cutoff
	for _i in range(4): await process_frame
	check(not ss.orbits_resolvable(), "1000x does not resolve")
	check(not _lanes_drawn(sun), "so the lanes are not drawn")

	# Pausing is how the player inspects a blurred system, and the lanes come back for it —
	# the same exception the bodies and the swarm take.
	ss.paused = true
	for _i in range(4): await process_frame
	check(_lanes_drawn(sun), "pausing brings them back to be looked at")
	ss.paused = false
	ss.seconds_per_day = ss.TIMESCALE_BASE

	# ── No orbital structure is drawn MIRRORED ──
	# Planet.infra_orientation builds each instance's basis, and Basis(x, y, z) is right-handed
	# only when x cross y is z.  Built the other way round every instance has a determinant of
	# -1 — a mirror, which reverses the effective winding, so the renderer culls the near faces,
	# keeps the far ones, and the structure is shaded from the inside.  It was wrong for every
	# lane and visible on exactly one: a mirrored box is a box, and the Orbital Vault is the only
	# lane that draws a modelled hull.
	#
	# Asserted against the FUNCTION, not against the lanes.  A headless run has no renderer, so
	# MultiMesh.set_instance_transform keeps nothing and get_instance_transform returns the
	# identity — an assertion made by reading the lanes back passes whatever the maths does, as
	# the first version of this check did.
	var worst_det: float = INF
	var bad: Array = []
	var dirs: Array = [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1),
		Vector3(-1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1),
		Vector3(0.0, 0.999, 0.044), Vector3(0.0, -0.999, 0.044)]
	for i in range(64):
		var a: float = TAU * float(i) / 64.0
		var e: float = -1.2 + 2.4 * float(i % 7) / 6.0
		dirs.append(Vector3(cos(a) * cos(e), sin(e), sin(a) * cos(e)) * (1.0 + float(i % 3)))
	for d: Vector3 in dirs:
		var b: Basis = P.infra_orientation(d, P.infra_orbit_normal(0.9))
		worst_det = minf(worst_det, b.determinant())
		if b.determinant() <= 0.0:
			bad.append(str(d))
		# +Y is the radial: the models are built to that contract and the depot is taller than
		# it is deep because of it.
		var want_up: Vector3 = d.normalized() if d.length_squared() > 1e-9 else Vector3.UP
		if b.y.normalized().dot(want_up) < 0.999:
			bad.append("up %s" % str(d))
		# And it is a rotation, not a shear: the lanes scale it uniformly afterwards.
		if absf(b.x.length() - 1.0) > 1.0e-4 or absf(b.z.length() - 1.0) > 1.0e-4 \
				or absf(b.x.dot(b.y)) > 1.0e-4 or absf(b.x.dot(b.z)) > 1.0e-4:
			bad.append("not orthonormal %s" % str(d))
	check(bad.is_empty(), "every orbital structure is right-handed, +Y out, orthonormal: %s"
		% str(bad.slice(0, 5)))
	check(worst_det > 0.0, "worst determinant over %d directions: %+.4f" % [dirs.size(), worst_det])
	print("orientation: %d directions, worst determinant %+.4f" % [dirs.size(), worst_det])

	# ── And it is CONTINUOUS all the way round an orbit ──
	# A frame built from a fixed world axis has to flip somewhere — there is no continuous
	# non-vanishing tangent field on a sphere — and the old one flipped when a structure came
	# within 0.95 of straight overhead.  Five of the twenty-one lanes are inclined steeply
	# enough to cross that, four times an orbit, turning up to 171 degrees in a single frame:
	# a structure visibly spinning part way round its orbit and then back.
	#
	# Swept finely and compared step to step, because that is what "it rotates part way round"
	# is as a number.  A smooth frame turns by about the step; nothing may turn by much more.
	var steps: int = 720
	var step_deg: float = 360.0 / float(steps)
	var worst_jump: float = 0.0
	var worst_lane: String = ""
	var lane_i: int = 0
	for spec2: Dictionary in P.INFRA_LANES:
		var incl2: float = fposmod(float(lane_i) * P.INFRA_PLANE_ANGLE, PI)
		lane_i += 1
		var rr: float = float(spec2["radius"])
		var onormal: Vector3 = P.infra_orbit_normal(incl2)
		var prev: Basis = Basis()
		for s in range(steps + 1):
			var th: float = TAU * float(s) / float(steps)
			var zz: float = rr * sin(th)
			var pp := Vector3(rr * cos(th), zz * sin(incl2), zz * cos(incl2))
			var bb: Basis = P.infra_orientation(pp, onormal)
			if s > 0:
				var rel: Basis = bb * prev.inverse()
				var tr: float = clampf((rel.x.x + rel.y.y + rel.z.z - 1.0) * 0.5, -1.0, 1.0)
				var jump: float = rad_to_deg(acos(tr))
				if jump > worst_jump:
					worst_jump = jump
					worst_lane = str(spec2["type"])
			prev = bb
	check(worst_jump < step_deg * 3.0,
		"no structure jumps as it orbits: worst %.1f deg on %s, against a %.2f deg step" % [
			worst_jump, worst_lane, step_deg])
	print("continuity: worst turn %.2f deg per %.2f deg of orbit (%s)" % [
		worst_jump, step_deg, worst_lane])


	# ── The BELT's structures were the ones still drawn mirrored ──
	#
	# Same hardware from the same models, but orbiting the SUN among the rocks rather than a
	# planet, which makes asteroid_belt.gd a second copy of the per-instance maths — and it kept
	# both of the faults above after the planets' copy was fixed. Basis(t1, radial, radial × t1)
	# is left-handed, so every structure in the belt was shaded from the inside: bright on the
	# face turned away from the Sun. The sideways axis came from a fixed world reference too.
	#
	# Asserted through AsteroidBelt.infra_transform, which is the whole of what the draw loop
	# calls, for the same reason as above: the MultiMesh cannot be read back headless.
	var AB = load("res://asteroid_belt.gd")
	var belt: Node3D = g.get_node_or_null("WorldRoot/Planets/asteroid_belt") as Node3D
	check(belt != null, "the belt is in the system")
	var lanes: Array = belt._infra if belt != null else []
	check(lanes.size() >= 8, "and it draws orbital structure lanes: %d" % lanes.size())
	var b_bad: Array = []
	var b_det: float = INF
	var b_perp: float = 0.0          # worst |lane normal · a direction in the lane's plane|
	var b_track: float = 1.0         # worst alignment of the sideways axis with the motion
	var b_jump: float = 0.0
	var b_lane: String = ""
	var bsteps: int = 360
	var bstep_deg: float = 360.0 / float(bsteps)
	for lane: Dictionary in lanes:
		# Swept on a copy: the live lane's phase belongs to the running game.
		var ln: Dictionary = lane.duplicate()
		var onormal: Vector3 = AB.infra_plane_normal(ln)
		var prev := Basis()
		for st in range(bsteps + 1):
			var th: float = TAU * float(st) / float(bsteps)
			ln["phase"] = th
			var xf: Transform3D = AB.infra_transform(ln, 0, 1)
			# Where it is a moment later, which is the direction it is travelling.
			ln["phase"] = th + 1.0e-3
			var vel: Vector3 = (AB.infra_position(ln, 0, 1) - xf.origin).normalized()
			var radial: Vector3 = xf.origin.normalized()
			b_det = minf(b_det, xf.basis.determinant())
			# Both of these lie in the lane's plane, so its normal is perpendicular to both.
			b_perp = maxf(b_perp, absf(onormal.dot(radial)))
			b_perp = maxf(b_perp, absf(onormal.dot(vel)))
			b_track = minf(b_track, xf.basis.x.dot(vel))
			if xf.basis.y.dot(radial) < 0.999:
				b_bad.append("%s: +Y off the radial" % str(lane["type"]))
			# The frame's third axis is the lane's own plane normal, which is how the normal the
			# draw loop PASSES is checked rather than only the one this test computes.
			# Tightly: the lanes are inclined by at most 4 degrees, so a normal that ignores
			# the node is still within 0.01 of the right one, and a loose bound would let it
			# through. The noise floor here is 1e-6.
			if absf(absf(xf.basis.z.dot(onormal)) - 1.0) > 1.0e-3:
				b_bad.append("%s: not flat in its lane's plane" % str(lane["type"]))
			if absf(xf.basis.x.length() - 1.0) > 1.0e-4 \
					or absf(xf.basis.x.dot(xf.basis.y)) > 1.0e-4:
				b_bad.append("%s: not a rotation" % str(lane["type"]))
			if st > 0:
				var rel: Basis = xf.basis * prev.inverse()
				var tr: float = clampf((rel.x.x + rel.y.y + rel.z.z - 1.0) * 0.5, -1.0, 1.0)
				var jump: float = rad_to_deg(acos(tr))
				if jump > b_jump:
					b_jump = jump
					b_lane = str(lane["type"])
			prev = xf.basis
	check(b_det > 0.0,
		"nothing in the belt is drawn mirrored: worst determinant %+.4f" % b_det)
	check(b_bad.is_empty(),
		"+Y points away from the Sun and the frame is a rotation: %s" % str(b_bad.slice(0, 4)))
	check(b_perp < 0.01,
		"the lane normal is its own plane's: worst |n . dir| %.6f" % b_perp)
	check(b_track > 0.9,
		"and the sideways axis runs WITH the motion: worst %+.3f" % b_track)
	check(b_jump < bstep_deg * 3.0,
		"no structure jumps as it goes round: worst %.1f deg on %s, against a %.2f deg step" % [
			b_jump, b_lane, bstep_deg])
	print("belt: %d lanes, det %+.4f, |n . dir| %.6f, along-track %+.3f, worst turn %.2f deg" % [
		lanes.size(), b_det, b_perp, b_track, b_jump])

	print("FAILS: %d" % fails)
	quit()


## Whether any of a body's orbital-infrastructure lanes is currently being rendered.
func _lanes_drawn(body: Node3D) -> bool:
	for lane: Dictionary in body._infra:
		var mmi = lane.get("mmi")
		if mmi != null and mmi.visible:
			return true
	return false
