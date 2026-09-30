extends SceneTree

## Every orbital structure around the Sun sits inside Mercury's orbit, and outside the Sun.
##
## "Inside Mercury's orbit" is measured against its PERIHELION, not its mean distance: Mercury is
## eccentric enough (0.21) that its closest approach is 8.58 world units against a mean of 10.47,
## so a band sized to the mean would be swallowed once a year.

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

	print("FAILS: %d" % fails)
	quit()
