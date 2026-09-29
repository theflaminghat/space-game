extends SceneTree
## Round-trip audit: mutate a lot of state, save, wipe, load, and compare.
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
	var rt: Node = root.get_node("ResearchTree")

	# Make the world interesting.
	g.year = 250000
	g._update_timescale()
	rt.force_unlock("early_rocketry")
	rt.resources["energy"] = 1.23e20
	rt.resources["minerals"] = 4.56e18
	ss.set_star_mass(0.82)
	ss.star_age_offset_years = 12345.0
	ss.star_drift_ly = Vector3(3, -4, 12)
	ss.star_velocity_ms = 42.0
	ss.aim_star_thrust(Vector3(1, 0, 0), "Sirius")
	g.planet_buildings["sun"] = ["Star Lifter", "Shkadov Mirror", "Orbital Construction Station"]
	g._mark_prod_dirty(); g._recompute_production_cache()
	g.cluster_colonized = {"Cluster C-001": 0.33}
	g.colonized_planets = ["mars"]
	g._planet_inv("sun")["H2"] = 9.87e25
	g.atmospheric_co2["earth"] = 3.0e19
	g.entropy_exported = 7.77e33
	for _n in range(3):
		g._spread_aliens(20000.0)
	var snapshot := {
		"year": g.year, "mass": ss.star_mass_msun, "rejuv": ss.star_age_offset_years,
		"drift": ss.star_drift_ly, "vel": ss.star_velocity_ms, "aim": ss.star_thrust_target,
		"mirror": ss.star_mirror_coverage, "shade": ss.star_shade_fraction,
		"sun_h2": float(g._planet_inv("sun").get("H2", 0.0)),
		"co2": float(g.atmospheric_co2.get("earth", 0.0)),
		"entropy": g.entropy_exported, "energy": float(rt.resources["energy"]),
		"aliens": g.star_factions.size(), "polities": g.star_polity.size(),
		"factions": g._factions.size(), "clusters": g.cluster_colonized.duplicate(),
		"sun_buildings": (g.planet_buildings.get("sun", []) as Array).size(),
	}
	g.save_game("user://saves/audit.json")

	# Wipe everything we can reach, then load.
	ss.reset_star()
	g.year = 1945
	g.star_factions = {}
	g.star_polity = {}
	g._factions = {}
	g.cluster_colonized = {}
	g.planet_buildings["sun"] = []
	g.atmospheric_co2 = {}
	g.entropy_exported = 0.0
	rt.resources["energy"] = 0.0
	g.compound_inventory = {}
	g.load_game("user://saves/audit.json")
	for _i in range(3): await process_frame

	check(g.year == int(snapshot["year"]), "year")
	check(is_equal_approx(ss.star_mass_msun, float(snapshot["mass"])), "star mass: %s" % ss.star_mass_msun)
	check(is_equal_approx(ss.star_age_offset_years, float(snapshot["rejuv"])), "rejuvenation")
	check((ss.star_drift_ly as Vector3).is_equal_approx(snapshot["drift"]), "drift: %s" % ss.star_drift_ly)
	check(is_equal_approx(ss.star_velocity_ms, float(snapshot["vel"])), "velocity: %s" % ss.star_velocity_ms)
	check(ss.star_thrust_target == str(snapshot["aim"]), "thruster aim: '%s'" % ss.star_thrust_target)
	check(is_equal_approx(ss.star_mirror_coverage, float(snapshot["mirror"])), "mirror coverage: %s" % ss.star_mirror_coverage)
	check(is_equal_approx(ss.star_shade_fraction, float(snapshot["shade"])), "shade fraction")
	check(is_equal_approx(float(g._planet_inv("sun").get("H2", 0.0)), float(snapshot["sun_h2"])), "lifted hydrogen")
	check(is_equal_approx(float(g.atmospheric_co2.get("earth", 0.0)), float(snapshot["co2"])), "atmospheric CO2")
	check(is_equal_approx(g.entropy_exported, float(snapshot["entropy"])), "entropy")
	check(is_equal_approx(float(rt.resources["energy"]), float(snapshot["energy"])), "energy reserve")
	check(g.star_factions.size() == int(snapshot["aliens"]), "alien systems: %d vs %d" % [g.star_factions.size(), snapshot["aliens"]])
	check(g.star_polity.size() == int(snapshot["polities"]), "polity holdings: %d vs %d" % [g.star_polity.size(), snapshot["polities"]])
	check(g._factions.size() == int(snapshot["factions"]), "faction registry: %d vs %d" % [g._factions.size(), snapshot["factions"]])
	check(g.cluster_colonized.size() == (snapshot["clusters"] as Dictionary).size(), "clusters")
	check((g.planet_buildings.get("sun", []) as Array).size() == int(snapshot["sun_buildings"]), "sun roster")
	print("FAILS: ", fails)
	quit()
