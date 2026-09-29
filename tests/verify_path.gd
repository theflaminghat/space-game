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
	for _i in range(30): await process_frame
	var g: Node = current_scene
	var rt: Node = root.get_node("ResearchTree")
	var md = load("res://missions.gd")
	var sun: Node3D = g.get_node("WorldRoot/Planets/sun")
	rt.force_unlock("precision_orbital_construction")
	rt.force_unlock("automated_logistics")
	rt.force_unlock("space_power_infrastructure")

	# ── The vault replaced the depot ──
	var carriers := {}
	for m in md.MISSION_TYPES:
		if str(m.get("structure", "")) != "":
			carriers[str(m["name"])] = str(m["structure"])
	print("carriers: ", carriers)
	check(carriers.values().has("Orbital Vault"), "a vault carrier exists")
	check(not carriers.values().has("Matter Depot"), "no depot carrier")
	check(not (g._find_building_def("Matter Depot").get("allowed_types", []) as Array).has("star"),
		"the depot is ground-bound again")
	check((g._find_building_def("Orbital Vault").get("allowed_types", []) as Array).has("star"),
		"the vault belongs in solar orbit")

	# ── A lane berth is a real point out at the lane's radius, not the body's centre ──
	g.planet_buildings["sun"] = []
	g._mark_prod_dirty(); g._recompute_production_cache()
	for _i in range(5): await process_frame
	var berth: Vector3 = sun.infra_slot_world_pos("Orbital Construction Station", 0, 1)
	var from_centre: float = (berth - sun.global_position).length()
	print("berth is %.3f units from the Sun's centre (sun scale %.3f)" % [from_centre, sun.scale.x])
	check(from_centre > sun.scale.x * 0.5, "the berth is outside the star, not in it")
	var berth2: Vector3 = sun.infra_slot_world_pos("Orbital Vault", 0, 1)
	check((berth2 - sun.global_position).length() > sun.scale.x * 0.5, "so is the vault's")
	check(not berth.is_equal_approx(berth2), "different lanes, different berths")
	# Two deliveries of the same structure reserve different berths.
	var a: Vector3 = sun.infra_slot_world_pos("Orbital Construction Station", 0, 2)
	var b: Vector3 = sun.infra_slot_world_pos("Orbital Construction Station", 1, 2)
	check(not a.is_equal_approx(b), "two reserved berths differ")

	# ── The carrier flies to its berth, and never through the star ──
	var inv: Dictionary = g._planet_inv("earth")
	for res in ["Steel", "Al", "Microchip", "Superconductor", "Rocket", "Propellant"]:
		inv[res] = 1.0e20
	rt.resources["energy"] = 1.0e20
	g._on_launch_requested({
		"mission": "Construction Station", "origin": "earth", "target": "sun",
		"cargo": {}, "start_offset": 0, "duration": 400, "rockets": 20,
		"fuel_id": "Propellant", "fuel_amount": 320.0, "arrival": "orbit"})
	check(g.active_launches.size() == 1, "launched")
	var sat: Node3D = g._launch_satellites.get(int(g.active_launches[0]["id"]), null)
	check(sat != null, "a craft was spawned")
	if sat == null:
		print("FAILS: ", fails); quit(); return
	check(sat.arrival_mode == "swarm", "it flies to a berth, not into orbit: '%s'" % sat.arrival_mode)
	check(sat.slot_provider.is_valid(), "and tracks the berth as the lane turns")
	# Fly it and watch how close it comes to the star.
	#
	# The craft is moved by the satellite node's OWN _process, so the tree has to really process
	# frames: calling Game._process() by hand advances the simulation but never the craft, which
	# then sits at the origin — and the Sun is at the origin too, so every sample reads zero and
	# looks exactly like flying through the star.
	var ss: Node = root.get_node("SolarSystem")
	ss.seconds_per_day = 5.0e-4    # the fastest pace that is still day-mode
	var closest: float = 1.0e30
	var samples: Array = []
	var alive_frames := 0
	for i in range(4000):
		# An event card pauses the game and the tree; clear both or the flight freezes.
		ss.paused = false
		ss.ui_paused = false
		g.get_tree().paused = false
		await process_frame
		if not is_instance_valid(sat):
			break
		alive_frames += 1
		# craft_position(), not global_position: the node stays at the origin and only its dot
		# moves, and the Sun is at the origin too, so the node's own transform reads as a
		# distance of zero for the whole flight.
		var d: float = (sat.craft_position() - sun.global_position).length()
		closest = minf(closest, d)
		if alive_frames % 400 == 1:
			samples.append("%.2f" % d)
	print("distance from the Sun over %d frames: %s  closest %.3f (star radius %.3f)" % [
		alive_frames, str(samples), closest, sun.scale.x * 0.5])
	check(alive_frames > 10, "the craft was in flight long enough to watch: %d frames" % alive_frames)
	check(closest > sun.scale.x * 0.5, "the craft never entered the star (closest %.3f vs radius %.3f)" % [
		closest, sun.scale.x * 0.5])
	# And it is gone once the structure is there.
	var guard := 0
	while is_instance_valid(sat) and guard < 20000:
		ss.paused = false
		ss.ui_paused = false
		g.get_tree().paused = false
		await process_frame
		guard += 1
	check(not is_instance_valid(sat), "the craft removed itself on arrival")
	check((g.planet_buildings.get("sun", []) as Array).has("Orbital Construction Station"),
		"and the station is on station")
	print("FAILS: ", fails)
	quit()
