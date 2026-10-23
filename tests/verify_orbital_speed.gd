extends SceneTree

## Moons and orbital infrastructure move on the GAME clock, like the worlds carrying them.
##
## Both used to advance on wall-clock seconds — the moons deliberately, with a comment saying
## they were decoupled from the timescale — so a world fast-forwarded through a century had its
## moon going round at exactly the pace it did at 1x, and they were the only things on screen
## that did not react to the speed control.
##
## The base rung is unchanged: SolarSystem.speed_multiplier() is 1.0 there by construction.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _phases(body: Node3D) -> Array:
	var out: Array = []
	for lane: Dictionary in body._infra:
		out.append(float(lane["phase"]))
	return out

func _run() -> void:
	seed(20260927)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var ss: Node = root.get_node("SolarSystem")
	var earth: Node3D = g.get_node("WorldRoot/Planets/earth")
	var sun: Node3D = g.get_node("WorldRoot/Planets/sun")

	check(not earth._moons.is_empty(), "Earth has a moon to move")
	check(not sun._infra.is_empty(), "the Sun has orbital lanes to move")

	ss.paused = false
	ss.ui_paused = false

	# ── The base rung is exactly 1.0, so nothing changed there ──
	ss.seconds_per_day = ss.TIMESCALE_BASE
	check(absf(ss.speed_multiplier() - 1.0) < 1.0e-6,
		"the base rung multiplies by one: %.4f" % ss.speed_multiplier())

	# ── A moon advances proportionally to the speed ──
	var m: Dictionary = earth._moons[0]
	var speed: float = float(m["speed"])
	check(speed != 0.0, "the moon has a rate")

	m["angle"] = 0.0
	earth._update_moons(1.0 * ss.speed_multiplier())
	var at_1x: float = float(m["angle"])
	check(absf(at_1x - speed) < 1.0e-6,
		"one second at 1x moves it by its own rate: %.5f vs %.5f" % [at_1x, speed])

	ss.seconds_per_day = ss.TIMESCALE_BASE / 100.0
	check(absf(ss.speed_multiplier() - 100.0) < 0.01,
		"the 100x rung multiplies by a hundred: %.2f" % ss.speed_multiplier())
	m["angle"] = 0.0
	earth._update_moons(1.0 * ss.speed_multiplier())
	var at_100x: float = float(m["angle"])
	check(absf(at_100x / maxf(at_1x, 1.0e-9) - 100.0) < 0.01,
		"the same second at 100x moves it a hundred times as far: %.2fx" % (at_100x / at_1x))

	# ── So does an orbital structure ──
	ss.seconds_per_day = ss.TIMESCALE_BASE
	for lane: Dictionary in sun._infra:
		lane["phase"] = 0.0
	sun._update_infra(0.05)
	var slow: Array = _phases(sun)
	var moved: int = 0
	for p in slow:
		if absf(float(p)) > 1.0e-9:
			moved += 1
	check(moved == slow.size(), "every lane moved at 1x: %d of %d" % [moved, slow.size()])

	ss.seconds_per_day = ss.TIMESCALE_BASE / 100.0
	for lane: Dictionary in sun._infra:
		lane["phase"] = 0.0
	sun._update_infra(0.05)
	var fast: Array = _phases(sun)
	var ratios: Array = []
	for i in range(slow.size()):
		# Phase wraps at TAU, so only lanes whose fast step stayed inside one turn are
		# comparable — the rest have lapped, which is itself the point.
		var a: float = absf(float(slow[i]))
		var b: float = absf(float(fast[i]))
		if a > 1.0e-9 and b > a:
			ratios.append(b / a)
	check(ratios.size() > 0, "some lanes are comparable without having lapped")
	var worst: float = 0.0
	for r in ratios:
		worst = maxf(worst, absf(float(r) - 100.0))
	check(worst < 0.5,
		"and each moved a hundred times as far: worst deviation %.3f" % worst)

	# ── Nothing moves while the clock is stopped ──
	ss.seconds_per_day = ss.TIMESCALE_BASE
	ss.paused = true
	for lane: Dictionary in sun._infra:
		lane["phase"] = 0.0
	sun._update_infra(0.5)
	var held: Array = _phases(sun)
	var still := true
	for p in held:
		if absf(float(p)) > 1.0e-9:
			still = false
	check(still, "a paused game holds the lanes where they are")
	ss.paused = false

	# ── The count-refresh throttle stays on the wall clock ──
	# It is a UI refresh rate, not motion: speeding the game up must not make it re-poll the
	# building roster a thousand times a frame.
	ss.seconds_per_day = ss.TIMESCALE_BASE / 1000.0
	sun.set("_infra_poll", 0.0)
	sun._update_infra(0.1)
	check(absf(float(sun.get("_infra_poll")) - 0.1) < 1.0e-6,
		"the poll timer counts real seconds: %.4f" % float(sun.get("_infra_poll")))
	ss.seconds_per_day = ss.TIMESCALE_BASE

	print("FAILS: %d" % fails)
	quit()
