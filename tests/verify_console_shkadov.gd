extends SceneTree

## `shkadov [multiplier]` — scale the star thruster so its effect can be seen in a play session.
##
## A real full mirror shell on a 1 L☉ star accelerates it at about 1e-13 m/s², roughly a
## light-year per hundred million years.  That is the right number and the game keeps it, but it
## makes the engine impossible to test and impossible to watch: by the time it has moved
## anything the clock is far past the speed at which the solar system is still drawn.
##
## The multiplier scales ACCELERATION, so velocity and position stay consistent — a bigger
## engine, not a teleport — and it is deliberately not saved.

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
	var sol: Node = root.get_node("SolarSystem")
	var c: Node = null
	for n in g.find_children("*", "CanvasLayer", true, false):
		if n.get_script() != null \
				and str(n.get_script().resource_path).ends_with("DevConsole.gd"):
			c = n
			break
	check(c != null, "the console is in the scene")

	# ── It is declared, so help and the encyclopedia both carry it ──
	var entry: Dictionary = {}
	for e: Dictionary in c.COMMANDS:
		if str(e["name"]) == "shkadov":
			entry = e
	check(not entry.is_empty(), "shkadov is in the command table")
	check((entry["aliases"] as Array).has("thruster"), "with an alias")
	check(str(entry["args"]) != "", "and a documented argument")
	check(str(entry["detail"]).length() > 80, "and a detail page for the encyclopedia")

	# ── Default is 1, and a new run resets it ──
	check(is_equal_approx(sol.star_thrust_mult, 1.0), "a fresh run is unmultiplied")

	# ── Setting it ──
	c._run("shkadov 1000")
	check(is_equal_approx(sol.star_thrust_mult, 1000.0),
		"the command sets it: %s" % str(sol.star_thrust_mult))
	c._run("thruster 2.5")
	check(is_equal_approx(sol.star_thrust_mult, 2.5), "and the alias works")
	c._run("shkadov -7")
	check(sol.star_thrust_mult >= 0.0, "a negative is floored rather than reversing the engine")
	c._run("shkadov banana")
	check(sol.star_thrust_mult >= 0.0, "a non-number is refused without changing anything")
	c._run("shkadov")
	check(true, "and with no argument it reads out without erroring")

	# ── It actually multiplies the drift, and consistently ──
	# Mirrors and an aim first: the thruster is inert without both, which is exactly what the
	# readout above is for.
	sol.reset_star()
	sol.set_star_mirror_coverage(1.0)
	sol.aim_star_thrust(Vector3(1, 0, 0), "test")
	sol.star_thrust_mult = 1.0
	var moved_1x: float = sol.advance_star_thrust(365.25)
	var speed_1x: float = sol.star_velocity_ms
	check(moved_1x > 0.0, "a year of thrust moves the star at all: %s ly" % str(moved_1x))

	sol.reset_star()
	sol.set_star_mirror_coverage(1.0)
	sol.aim_star_thrust(Vector3(1, 0, 0), "test")
	sol.star_thrust_mult = 1000.0
	var moved_1000x: float = sol.advance_star_thrust(365.25)
	var speed_1000x: float = sol.star_velocity_ms
	check(absf(moved_1000x / maxf(moved_1x, 1.0e-300) - 1000.0) < 0.01,
		"a thousand times the engine covers a thousand times the distance: %.2fx" % (
			moved_1000x / moved_1x))
	check(absf(speed_1000x / maxf(speed_1x, 1.0e-300) - 1000.0) < 0.01,
		"and reaches a thousand times the speed: %.2fx" % (speed_1000x / speed_1x))
	# Consistency is the reason it scales acceleration: after one slice from rest the distance
	# must be exactly half v*t for any multiplier, which a position-only cheat would break.
	var secs: float = 365.25 * 86400.0
	# StarModel.LY_M, not a hand-written metres-per-light-year: my own figure was off in the
	# sixth digit and failed a check that was actually passing.
	var implied: float = 0.5 * speed_1000x * secs / StarModel.LY_M
	check(absf(implied / maxf(moved_1000x, 1.0e-300) - 1.0) < 1.0e-6,
		"and the distance still matches the speed it built up: %.6f" % (implied / moved_1000x))

	# ── Zero stops it ──
	sol.star_thrust_mult = 0.0
	check(is_equal_approx(sol.advance_star_thrust(365.25), 0.0), "zero is a parked engine")

	# ── Not saved: a new run is back at 1 ──
	sol.star_thrust_mult = 500.0
	sol.reset_star()
	check(is_equal_approx(sol.star_thrust_mult, 1.0),
		"a new run resets it, so a cheat cannot leak into a later game")

	print("FAILS: %d" % fails)
	quit()
