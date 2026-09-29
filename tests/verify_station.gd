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
	for _i in range(25): await process_frame
	var g: Node = current_scene
	var rt: Node = root.get_node("ResearchTree")
	var unlocks = load("res://unlocks.gd")
	var md = load("res://missions.gd")

	# ── The station ──
	var def: Dictionary = g._find_building_def("Orbital Construction Station")
	check(not def.is_empty(), "the station is in the catalogue")
	check(float(def.get("mc_capacity", 0.0)) > 0.0, "it provides manufacturing capacity: %s" % def.get("mc_capacity", 0))
	var allowed: Array = def.get("allowed_types", [])
	check(allowed.has("star"), "buildable in solar orbit")
	check(allowed.has("gas_giant") and allowed.has("belt"), "and anywhere else with no ground")
	check(str(unlocks.BUILDING_UNLOCK_REQUIREMENTS.get("Orbital Construction Station", "")) == "precision_orbital_construction",
		"gated by orbital construction")

	# ── Orbital storage is the vault's job ──
	# The Matter Depot briefly flew; it is silos and bunkers, so the Orbital Vault took the
	# role over and the depot went back to needing ground.
	check((g._find_building_def("Orbital Vault").get("allowed_types", []) as Array).has("star"),
		"the vault is allowed in solar orbit")
	check(not (g._find_building_def("Matter Depot").get("allowed_types", []) as Array).has("star"),
		"the depot is not")
	g.current_planet = "sun"
	rt.force_unlock("precision_orbital_construction")
	var names: Array = []
	for r in g._get_catalog_for_display():
		names.append(str(r.get("name", "")))
	check(names.has("Orbital Construction Station"), "the station is offered at the Sun")
	check(names.has("Orbital Vault"), "the vault is offered at the Sun")
	check(not names.has("Matter Depot"), "the depot is not offered at the Sun")

	# ── A station raises the Sun's build rate ──
	var base_mc: float = g._planet_mc_capacity("sun")
	g.planet_buildings["sun"] = ["Orbital Construction Station"]
	g._mark_prod_dirty()
	g._recompute_production_cache()   # capacity is read off the cache, not the roster
	var with_station: float = g._planet_mc_capacity("sun")
	print("sun MC: %s bare, %s with one station" % [base_mc, with_station])
	check(with_station > base_mc, "the station adds capacity where there is no ground")

	# ── The delivery missions ──
	var found := {}
	for m in md.MISSION_TYPES:
		if str(m.get("structure", "")) != "":
			found[str(m["name"])] = str(m["structure"])
	print("structure missions: ", found)
	check(found.size() == 2, "two carriers exist")
	check(found.values().has("Orbital Construction Station") and found.values().has("Orbital Vault"),
		"one for each structure")
	for m in md.MISSION_TYPES:
		if str(m.get("structure", "")) != "":
			check(bool(m.get("sun_only", false)), "%s is Sun-only" % m["name"])
	print("FAILS: ", fails)
	quit()
