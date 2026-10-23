extends SceneTree

## The Sun's panel reports the Dyson swarm's output.
##
## The swarm is not building production — _swarm_power() prices each lane by its own 1/r² flux
## and scales the whole thing with the star's current luminosity — so it never passed through the
## per-body roster that feeds the planet panels.  The power reached the grid through _bld_energy
## with no body's name on it, and the Sun read 0 W with a finished megastructure around it.

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

	# ── Nothing deployed, nothing claimed ──
	g.solar_satellites_deployed = 0
	g.planet_buildings["sun"] = []
	g._mark_prod_dirty()
	check(is_equal_approx(g._swarm_power(), 0.0), "an empty swarm generates nothing")
	check(is_equal_approx(float(g.get_planet_data("sun").get("energy", -1.0)), 0.0),
		"and the Sun reports nothing")

	# ── Flown out as satellites ──
	g.solar_satellites_deployed = 400
	g._mark_prod_dirty()
	var swarm: float = g._swarm_power()
	check(swarm > 0.0, "400 collectors generate power: %s" % Units.format_si(swarm, "W"))
	var shown: float = float(g.get_planet_data("sun").get("energy", 0.0))
	check(shown > 0.0, "and the Sun's panel is no longer zero: %s" % Units.format_si(shown, "W"))
	# The same two multipliers the global pool applies, and nothing else.
	var boosted: float = swarm * (1.0 + root.get_node("ResearchTree").get_boost("energy_production")) \
		* g._policy_energy_mult()
	check(absf(shown / maxf(boosted, 1.0) - 1.0) < 1.0e-6,
		"it is exactly the swarm's output, boosted as the grid boosts it: %s vs %s" % [
			Units.format_si(shown, "W"), Units.format_si(boosted, "W")])

	# ── Built in place, same answer ──
	# The two routes to a collector are the same object, so they must read the same.
	g.solar_satellites_deployed = 0
	var arr: Array = []
	for _i in range(400):
		arr.append(g.SWARM_BUILDING)
	g.planet_buildings["sun"] = arr
	g._mark_prod_dirty()
	check(absf(g._swarm_power() / maxf(swarm, 1.0) - 1.0) < 1.0e-9,
		"400 built arrays generate the same as 400 flown ones")
	check(absf(float(g.get_planet_data("sun").get("energy", 0.0)) / maxf(shown, 1.0) - 1.0) < 1.0e-6,
		"and the Sun reports the same")

	# ── More collectors, more power ──
	g.solar_satellites_deployed = 0
	g.planet_buildings["sun"] = []
	g._mark_prod_dirty()
	g.solar_satellites_deployed = 800
	g._mark_prod_dirty()
	check(float(g.get_planet_data("sun").get("energy", 0.0)) > shown,
		"doubling the swarm raises the figure")

	# ── It is a readout, not a second source ──
	# _combine_production already adds _swarm_power() to the global pool exactly once; asking the
	# panel for it must not make the civilisation's total grow.
	g.solar_satellites_deployed = 400
	g._mark_prod_dirty()
	var total_before: float = float(g._get_total_production().get("energy", 0.0))
	var _unused: Dictionary = g.get_planet_data("sun")
	var total_after: float = float(g._get_total_production().get("energy", 0.0))
	check(absf(total_after - total_before) < 1.0,
		"reading the panel does not change the grid total")

	# ── The figure is GENERATION, like every other body's ──
	# It is deliberately not what the grid receives.  A swarm with no rectennas or relays offers
	# 6.8e23 W down a link that carries 2e12, and the Sun's panel showing its output while the
	# grid total stays small is exactly how a missing link is meant to read — the alternative
	# would report the collectors as broken.  Earth's panel is generation too, so the two agree
	# on what the column means.
	var sun_gen: float = float(g.get_planet_data("sun").get("energy", 0.0))
	check(sun_gen > float(g.get("_link_delivered")),
		"an unlinked swarm generates more than the beam network carries")
	check(absf(float(g.get("_link_offered")) / maxf(swarm, 1.0) - 1.0) < 1.0e-6,
		"and what it generates is what the link is offered")
	check(float(g.get_planet_data("earth").get("energy", 0.0)) > 0.0,
		"Earth's own column is generation on the same terms")

	# ── Other bodies are unaffected ──
	check(is_equal_approx(float(g.get_planet_data("mercury").get("energy", -1.0)), 0.0),
		"an empty neighbour still reports nothing")

	print("FAILS: %d" % fails)
	quit()
