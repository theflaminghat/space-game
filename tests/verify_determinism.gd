extends SceneTree

## Save scumming: reload the save and try the disaster again until it goes your way.
##
## The decisions that used to be scummable came from the global RNG, which is not seeded and whose
## state is not saved, so every load rolled fresh. They are now derived from
## (galaxy_seed, decision, occasion), and the point of that — rather than a saved stream position
## — is the independence checked in part 3: the answer does not depend on how the player reached
## the year, only on which year it is.

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
	for _i in range(25): await process_frame
	var g: Node = current_scene

	# ── 1. A roll is fixed by its occasion ──
	# Same tag, same salt, same answer — however many other rolls happen in between.
	var a: float = g._roll("pandemic_fires", 2180)
	for i in range(50):
		g._roll("something_else", i)
	var b: float = g._roll("pandemic_fires", 2180)
	check(is_equal_approx(a, b), "the same occasion gives the same roll: %f vs %f" % [a, b])
	check(not is_equal_approx(g._roll("pandemic_fires", 2180), g._roll("pandemic_fires", 2181)),
		"a different year gives a different roll")
	check(not is_equal_approx(g._roll("pandemic_fires", 2180), g._roll("pandemic_kill", 2180)),
		"two decisions in the same year are not the same number")

	# The galaxy is what makes a run its own: the same year in another galaxy rolls differently.
	var here: float = g._roll("pandemic_fires", 2180)
	var was: int = g.galaxy_seed
	g.galaxy_seed = was + 1
	check(not is_equal_approx(here, g._roll("pandemic_fires", 2180)),
		"another galaxy rolls differently")
	g.galaxy_seed = was

	# ── 2. The rolls are not degenerate ──
	# A hash that is repeatable but clumped would make every plague land on the same world.
	var lo := 0
	var sum := 0.0
	for y in range(2000, 3000):
		var r: float = g._roll("pandemic_fires", y)
		sum += r
		if r < 0.5:
			lo += 1
	check(absf(sum / 1000.0 - 0.5) < 0.05, "rolls average about a half: %.3f" % (sum / 1000.0))
	check(absf(float(lo) / 1000.0 - 0.5) < 0.06, "and split evenly about a half: %.3f" % (float(lo) / 1000.0))
	var spread := {}
	for y in range(2000, 3000):
		spread[g._roll_pick("impact_target", 5, y)] = true
	check(spread.size() == 5, "a pick reaches every option: %d of 5" % spread.size())
	var ints := {}
	for y in range(2000, 2500):
		ints[g._roll_int("impact_schedule", 10, 14, y)] = true
	check(ints.size() == 5, "a whole-number roll covers its range inclusively: %s" % str(ints.keys()))

	# ── 3. Save, let the disaster happen, reload, and get the same disaster ──
	# This is the scumming attempt. The save is taken the year before; between the two attempts
	# the game is deliberately put through a DIFFERENT amount of work, which is what would throw
	# a saved stream position out of step.
	var path := "user://saves/determinism.json"
	g.year = 2179
	g.save_game(path)

	var first: Dictionary = _play_a_year(g)
	g.load_game(path)
	# Waste some rolls, the way a player replaying a year differently would.
	for i in range(137):
		g._roll("noise", i)
	var second: Dictionary = _play_a_year(g)

	# A test that compares nothing passes for the wrong reason.
	check(first.size() >= 8, "the year actually produced outcomes to compare: %d" % first.size())
	for key: String in first:
		check(_same(first[key], second[key]),
			"reloading gives the same %s (%s vs %s)" % [key, str(first[key]), str(second[key])])
	print("outcome of year 2180, both attempts: ", JSON.stringify(first))

	# ── 4. And the consequence, through the real event path ──
	# Not the roll but what it costs: an actual strike, an actual razed roster, an actual death
	# toll. This is the number a player would reload to improve.
	var tolls: Array = []
	var razed: Array = []
	for attempt in range(2):
		g.load_game(path)
		for i in range(attempt * 211):
			g._roll("noise", i)          # a differently-played replay of the same year
		g.year = 2180
		g._next_impact_year = 2180
		g._impact_cooldown_ms = 0
		var before: float = g._total_population()
		var built_before: int = (g.planet_buildings.get("earth", []) as Array).size()
		g._check_asteroid_impact()       # rolls the strike and raises the warning
		var threat: Dictionary = g._pending_threat
		# Take the warning's own figures through to the impact, as accepting the card does.
		g._trigger_asteroid_impact(str(threat.get("target", "")), float(threat.get("kill_frac", -1.0)))
		tolls.append(before - g._total_population())
		razed.append(built_before - (g.planet_buildings.get("earth", []) as Array).size())
		g.get_node("/root/SolarSystem").ui_paused = false
		g.get_tree().paused = false
	check(tolls[0] > 0.0, "the strike actually killed somebody: %s" % str(tolls[0]))
	check(_same(tolls[0], tolls[1]),
		"reloading gives the same death toll: %s vs %s" % [str(tolls[0]), str(tolls[1])])
	check(razed[0] == razed[1],
		"and razes the same amount of industry: %d vs %d" % [razed[0], razed[1]])
	print("death toll on both attempts: %s and %s" % [str(tolls[0]), str(tolls[1])])

	print("FAILS: %d" % fails)
	quit()


## Force each catastrophe to decide for the year, and report what it decided. The probabilities
## are pushed to a coin flip so the answer is the roll rather than a foregone conclusion.
func _play_a_year(g: Node) -> Dictionary:
	g.year = 2180
	var out: Dictionary = {}
	# Whether each one fires, at the threshold where the roll is what decides it.
	out["pandemic_fires"] = g._roll("pandemic_fires", g.year) < 0.5
	out["nuclear_fires"]  = g._roll("nuclear_fires", g.year) < 0.5
	# What the asteroid does, taken through the real code path.
	var targets: Array = g._impact_targets()
	out["impact_target"] = str(targets[g._roll_pick("impact_target", targets.size(), g.year)])
	out["impact_kill"]   = g._roll_range("impact_kill", 0.50, 0.85, g.year)
	out["pandemic_kill"] = g._roll_range("pandemic_kill", 0.70, 0.95, g.year)
	out["nuclear_kill"]  = g._roll_range("nuclear_kill", 0.55, 0.90, g.year)
	out["next_impact"]   = g._roll_int("impact_schedule", g.IMPACT_GAP_MIN, g.IMPACT_GAP_MAX, g.year)
	# And the toll the warning dialog would quote, which is the number the player would reload to
	# improve: _raise_asteroid_threat writes it into _pending_threat.
	g._pending_threat = {}
	g._raise_asteroid_threat()
	out["quoted_target"] = str(g._pending_threat.get("target", ""))
	out["quoted_kill"]   = float(g._pending_threat.get("kill_frac", -1.0))
	# _raise_asteroid_threat pauses the game to show the card; undo that.
	g.get_node("/root/SolarSystem").ui_paused = false
	g.get_tree().paused = false
	return out


func _same(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return is_equal_approx(float(a), float(b))
	return a == b
