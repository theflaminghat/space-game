extends SceneTree

## The top bar reports the SOLAR SYSTEM, not the galaxy.
##
## Three of the four readouts always did, by accident of where they come from: Matter, Energy and
## Heat are summed off `planet_buildings`, and an interstellar colony has no entry there. Its
## infrastructure is the abstracted model in `_colony_infra_at`, and what it mines goes into its
## own stores to be traded for (`_advance_colony_economy`).
##
## Compute did not. It is driven by population, and `_pop_weighted_compute` walks every world —
## so the figure driving research counted the minds of colonies four hundred light-years out.
## Forty colonies multiplied it by 139; a late-game roster is thousands, and the solar system's
## own contribution rounds to nothing against them.
##
## That contradicts the rest of the design rather than merely inflating a number. The same
## light-lag that makes a colony ungovernable — every order describes a four-hundred-year-old
## situation — means it cannot be thinking for you now. What it produces reaches you as freight.
##
## What has to hold:
##   an interstellar colony moves NONE of the four readouts
##   an in-system colony moves them — this is locality, not a blanket exclusion
##   the galaxy-wide figure is still tracked, because it is a real and interesting number

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _snapshot(g: Node) -> Dictionary:
	g._prod_dirty = true
	g._recompute_production_cache()
	g._update_hud()
	var p: Dictionary = g._get_total_production()
	return {
		"minerals": float(p.get("minerals", 0.0)),
		"energy":   float(p.get("energy", 0.0)),
		"compute":  g._get_compute_rate(),
		"heat":     g._cached_radiator_cap,
	}

func _run() -> void:
	seed(20261031)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(50): await process_frame
	var g: Node = current_scene
	for _i in range(20): g._update_population(1.0)
	var before: Dictionary = _snapshot(g)
	check(before["compute"] > 0.0, "there is a compute figure to start with: %s" % str(before["compute"]))
	check(before["minerals"] > 0.0, "and a matter figure")


	# ── Forty interstellar colonies, each with more people than Earth ──
	var names: Array = []
	for s in load("res://StarMapPanel.gd").all_stars():
		names.append(str((s as Dictionary)["name"]))
		if names.size() >= 40:
			break
	check(names.size() == 40, "forty stars to settle: %d" % names.size())
	var earth_pop: float = float(g.world_pop.get("earth", 0.0))
	for nm: String in names:
		g._colonize_star(nm)
		g._colony_year[nm] = g.year - 5000
		g.world_pop[nm] = earth_pop * 4.0
	for _i in range(60): g._update_population(1.0)
	var after: Dictionary = _snapshot(g)

	# The galaxy now holds ~160x Earth's population. None of it is on the top bar.
	var gal: float = g._total_population()
	var sol: float = g._solar_population()
	check(gal > sol * 50.0,
		"the galaxy holds far more people than the solar system: %s vs %s" % [str(gal), str(sol)])
	for k: String in ["minerals", "energy", "compute", "heat"]:
		var b: float = float(before[k])
		var a: float = float(after[k])
		# Earth's own population grows over those ticks, so compute moves a little on its own.
		check(a <= b * 1.05,
			"%s does not follow the colonies: %s -> %s (x%.3f)" % [
				k, str(b), str(a), a / maxf(b, 1.0)])
	# Stated as its own assertion, because compute is the one that was wrong and the one a
	# regression would hit.
	check(after["compute"] <= before["compute"] * 1.05,
		"compute in particular: x%.3f" % (float(after["compute"]) / maxf(float(before["compute"]), 1.0)))

	# The galaxy-wide sum is still kept — it is a real number, just not this one.
	check(g._pop_weighted_compute > g._pop_weighted_compute_sol * 10.0,
		"the galaxy-wide weighted sum is still tracked: %s vs solar %s" % [
			str(g._pop_weighted_compute), str(g._pop_weighted_compute_sol)])


	# ── An IN-SYSTEM colony does move it ──
	# Locality, not a blanket exclusion: zeroing every colony's contribution would pass every
	# assertion above and be wrong.
	var pre: Dictionary = _snapshot(g)
	var pre_sol: float = g._pop_weighted_compute_sol
	if not g.colonized_planets.has("mars"):
		g.colonized_planets.append("mars")
	g._establish_colony_base("mars")
	# The production cache has to be rebuilt BEFORE the population ticks: a world's capacity is
	# read from _cached_planet_hab and throttled by _planet_power, and with no entry for Mars yet
	# its capacity is zero and the population sheds to nothing on the first tick.
	g._prod_dirty = true
	g._recompute_production_cache()
	g.world_pop["mars"] = earth_pop * 3.0
	for _i in range(60): g._update_population(1.0)
	var post: Dictionary = _snapshot(g)
	# Measured against what Mars actually HOLDS, not what it was handed: an in-system colony is
	# capped by the life support its own grid runs, so it sheds to capacity within a tick or two.
	# Asserting on the figure it was given would be asserting the capacity model away.
	var mars_held: float = float(g.world_pop.get("mars", 0.0))
	check(mars_held > 0.0, "Mars holds somebody: %s" % str(mars_held))
	# Measured as the solar sum MINUS Earth's own people, not as a rise from `pre_sol`. Earth
	# grows by about nine million over these sixty ticks and Mars only holds six, so a before/
	# after comparison is satisfied by Earth alone and never tests Mars at all — which is exactly
	# how the first version of this passed with every colony excluded.
	var sol_beyond_earth: float = g._pop_weighted_compute_sol - float(g.world_pop.get("earth", 0.0))
	# Not 1.0: the solar sum is published when a population CYCLE closes, and Mars goes on
	# growing between that close and this read, so the live figure runs a little ahead of the
	# published one (measured at ~0.9). Wide enough for that, nowhere near wide enough to be
	# satisfied by zero — which is what excluding in-system colonies would give.
	check(sol_beyond_earth >= mars_held * 0.8,
		"and those people are in the solar sum: beyond Earth %s, Mars holds %s (pre_sol %s)" % [
			str(sol_beyond_earth), str(mars_held), str(pre_sol)])
	check(post["minerals"] > pre["minerals"],
		"its mines reach the matter pool: %s -> %s" % [
			str(pre["minerals"]), str(post["minerals"])])
	# And the contrast that makes the point: the same people, placed at a star instead, would
	# have moved nothing above.
	check(post["compute"] > pre["compute"],
		"so compute does move for a world in the system: %s -> %s" % [
			str(pre["compute"]), str(post["compute"])])

	print("FAILS: %d" % fails)
	quit()
