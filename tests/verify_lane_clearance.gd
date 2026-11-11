extends SceneTree

## Orbital infrastructure is one size, its lanes do not reach each other, and no body's band
## reaches another body's.
##
## ── What was wrong ──
##
## THE SIZES were whatever each model had been authored at: 0.178 world units for a relay
## satellite against 0.453 for a ring store, a spread of 2.5x across hardware meant to read as
## one class of thing. And they were a FIXED world size on every body, because the draw loop
## divided the body's scale back out — so around Mercury, whose radius is 0.161 units, a single
## orbital habitat was twice the width of the planet it orbited.
##
## THE LANES were 0.04 scale units apart, which is 0.013 world units around Mercury and 0.188
## around the Sun — in every case closer than the structures flying in them were wide. Every
## lane's hardware stood inside its neighbours', and what kept it apart was the angle between
## the orbital planes rather than any gap in radius. The first moon of every planet orbited at
## 1.3 scale units, through the middle of a band running 1.020 to 1.780.
##
## THE SUN'S BAND reached Mercury's. Its outermost lane stood at 8.367 world units and Mercury's
## own band reaches 0.573 inward from a perihelion of 8.578, so the two overlapped by 4% of the
## distance between them, once an orbit, for the whole run.
##
## ── What holds now ──
##
## One size: every model normalised so its longest dimension is INFRA_SIZE_FRAC of whatever body
## it orbits. One gap: INFRA_LANE_STEP, four thirds of that size, so a structure fills three
## quarters of the space between its lane and the next and no two shells can touch. Both in the
## body's own scale units, so the whole band is the same shape around Mercury as around the Sun.
##
## The band ends at 1.590 rather than 1.780 to buy the Sun the room Mercury needs. Moving the
## planets outward instead does not work: the Dyson swarm is placed in AU and moves out with
## them, into the inner edge of the band being made room for.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

## Where a body's orbit is closest to and furthest from the Sun, in world units, on the same
## log-radial map the orbits are drawn with.
func _peri(b: Node) -> float:
	return log(float(b._semi_major_axis_au) * (1.0 - float(b._eccentricity)) + 1.0) \
		* float(b.orbit_radius_mult)

func _apo(b: Node) -> float:
	return log(float(b._semi_major_axis_au) * (1.0 + float(b._eccentricity)) + 1.0) \
		* float(b.orbit_radius_mult)


func _run() -> void:
	seed(20260927)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var P = load("res://planet.gd")

	# The belt is under Planets too and has lanes of its own, but they ring the SUN rather than
	# a body and are keyed by their heliocentric radius. It gets its own section at the end.
	var bodies: Array = []
	var belt: Node = null
	for n: Node in g.get_node("WorldRoot/Planets").get_children():
		if not (n is Node3D) or (n as Node3D).get("_infra") == null:
			continue
		if str(n.name) == "asteroid_belt":
			belt = n
		else:
			bodies.append(n)
	check(bodies.size() >= 9, "every body is here: %d" % bodies.size())
	check(belt != null, "and the belt")


	# ── One size, whatever the model was authored at ──
	# Asserted against the mesh's own AABB rather than against the constant alone, so a model
	# re-exported at a different size in Blender is still drawn at this one.
	# Checked on two bodies of very different size: one under the world cap and one over it.
	var raw: Array = []
	for kind: String in P.LANE_MODELS:
		var a: AABB = P._model_mesh(kind).get_aabb()
		var longest: float = maxf(a.size.x, maxf(a.size.y, a.size.z))
		raw.append(longest)
		for sc: float in [0.3221, 4.7005]:
			var drawn: float = longest * P.infra_model_scale(kind, sc) * sc   # world units
			check(is_equal_approx(drawn, P.infra_structure_size(sc)),
				"%s is drawn at the band's size on a body of scale %.2f: %.4f vs %.4f" % [
					kind, sc, drawn, P.infra_structure_size(sc)])
	raw.sort()
	# And the normalisation is doing something: the authored sizes really do differ.
	check(float(raw[raw.size() - 1]) > float(raw[0]) * 1.5,
		"the models are authored at different sizes: %.3f .. %.3f" % [raw[0], raw[raw.size() - 1]])


	# ── A lane's hardware does not reach the next lane ──
	# Read off the live lanes, in the body's own units, and in world units too — the second is
	# the one that used to fail, because the gap scaled with the body and the structures did not.
	for b: Node in bodies:
		var lanes: Array = b.get("_infra")
		var radii: Array = []
		for lane: Dictionary in lanes:
			radii.append(float(lane["radius"]))
		radii.sort()
		var size_local: float = P.infra_structure_size(b.scale.x) / b.scale.x
		for i in range(radii.size() - 1):
			var gap: float = float(radii[i + 1]) - float(radii[i])
			check(gap >= size_local,
				"%s: lanes %.3f and %.3f are %.4f apart, structures are %.4f across" % [
					str(b.name), radii[i], radii[i + 1], gap, size_local])
		# The innermost lane clears the body it orbits, structure and all.
		check(float(radii[0]) - size_local * 0.5 > 0.5,
			"%s: the innermost lane clears the surface: %.3f vs 0.5" % [str(b.name), radii[0]])


	# ── The outermost lane of one body clears every other body's ──
	# Measured at closest approach, which for Mercury is 2 world units nearer than its mean.
	var envelope: Dictionary = {}
	for b: Node in bodies:
		var outer: float = 0.0
		for lane: Dictionary in (b.get("_infra") as Array):
			outer = maxf(outer, float(lane["radius"]))
		envelope[str(b.name)] = outer * b.scale.x + P.infra_structure_size(b.scale.x) * 0.5
	for a: Node in bodies:
		for b: Node in bodies:
			if str(a.name) >= str(b.name):
				continue
			var room: float = 0.0
			if str(a.name) == "sun":
				room = _peri(b)
			elif str(b.name) == "sun":
				room = _peri(a)
			elif _peri(b) > _apo(a):
				room = _peri(b) - _apo(a)
			elif _peri(a) > _apo(b):
				room = _peri(a) - _apo(b)
			else:
				check(false, "%s and %s cross orbits" % [str(a.name), str(b.name)])
				continue
			var used: float = float(envelope[str(a.name)]) + float(envelope[str(b.name)])
			check(used < room, "%s and %s: bands %.3f, closest approach %.3f" % [
				str(a.name), str(b.name), used, room])
	var tight: String = ""
	var worst: float = 1.0e9
	for b: Node in bodies:
		if str(b.name) == "sun":
			continue
		var m: float = _peri(b) - float(envelope["sun"]) - float(envelope[str(b.name)])
		if m < worst:
			worst = m
			tight = str(b.name)
	print("tightest pair: sun-%s, %.3f world units of clear space" % [tight, worst])


	# ── A moon does not fly through its own planet's band ──
	for b: Node in bodies:
		var outer: float = 0.0
		for lane: Dictionary in (b.get("_infra") as Array):
			outer = maxf(outer, float(lane["radius"]))
		outer += P.infra_structure_size(b.scale.x) * 0.5 / b.scale.x
		for n: Node in b.get_children():
			if not str(n.name).contains("_moon_"):
				continue
			var m3: Node3D = n as Node3D
			var r: float = m3.position.length()
			check(r - m3.scale.x * 0.5 > outer,
				"%s orbits outside the band: %.3f vs %.3f" % [str(n.name), r, outer])

	# ── The belt's heliocentric lanes, by the same rule ──
	# No body to be proportional to, so its hardware is three quarters of its own lane gap.
	if belt != null:
		var br: Array = []
		for lane: Dictionary in (belt.get("_infra") as Array):
			br.append(float(lane["r_vis"]))
		br.sort()
		var bsize: float = belt._infra_size()
		check(bsize > 0.0, "the belt's structures have a size: %.3f" % bsize)
		# What is DRAWN, not what was intended: the lane's own model scale against the mesh it
		# carries. The gap check below is satisfied by the intention alone, and the belt builds
		# its instance transforms by hand rather than through a planet's draw loop.
		for lane: Dictionary in (belt.get("_infra") as Array):
			var mesh_kind: String = ""
			for spec: Dictionary in P.INFRA_LANES:
				if str(spec["type"]) == str(lane["type"]):
					mesh_kind = str(spec["mesh"])
			var a2: AABB = P._model_mesh(mesh_kind).get_aabb()
			var drawn: float = maxf(a2.size.x, maxf(a2.size.y, a2.size.z)) * float(lane["mscale"])
			check(is_equal_approx(drawn, bsize),
				"the belt draws %s at its own size: %.4f vs %.4f" % [str(lane["type"]), drawn, bsize])
		for i in range(br.size() - 1):
			check(float(br[i + 1]) - float(br[i]) >= bsize,
				"belt lanes %.3f and %.3f are %.4f apart, structures %.4f across" % [
					br[i], br[i + 1], float(br[i + 1]) - float(br[i]), bsize])
		# And the belt's own band clears the planets either side of it.
		for b: Node in bodies:
			if str(b.name) == "sun":
				continue
			var e: float = float(envelope[str(b.name)])
			check(_apo(b) + e < float(br[0]) - bsize * 0.5 \
					or _peri(b) - e > float(br[br.size() - 1]) + bsize * 0.5,
				"%s clears the belt's lanes: %.3f..%.3f vs belt %.3f..%.3f" % [
					str(b.name), _peri(b) - e, _apo(b) + e, br[0], br[br.size() - 1]])

	print("FAILS: %d" % fails)
	quit()
