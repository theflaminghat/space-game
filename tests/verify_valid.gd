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
	var md = load("res://missions.gd")

	# ── Kinds ──
	for pair in [["sun", "star"], ["earth", "rocky"], ["jupiter", "gas_giant"],
			["asteroid_belt", "belt"], ["earth_moon_0", "rocky"]]:
		check(g.body_kind(pair[0]) == pair[1], "%s is %s (got %s)" % [pair[0], pair[1], g.body_kind(pair[0])])
	check(g.body_kind("nowhere") == "", "an unknown body has no kind")

	# ── The rules themselves ──
	var by_name := {}
	for m in md.MISSION_TYPES:
		by_name[str(m["name"])] = m
	check(not md.allows_target(by_name["Colony Ship"], "star"), "no colony on the Sun")
	check(md.allows_target(by_name["Colony Ship"], "rocky"), "colonies go to worlds")
	check(not md.allows_target(by_name["Mining Ops"], "gas_giant"), "no mining a gas giant")
	check(md.allows_target(by_name["Mining Ops"], "belt"), "the belt can be mined")
	check(md.allows_target(by_name["Supply Run"], "star"), "cargo may go to solar orbit")
	check(not md.allows_target(by_name["Solar Deployment"], "rocky"), "collectors only go to the Sun")
	check(not md.allows_target(by_name["Construction Station"], "rocky"), "so do the station carriers")
	check(md.allows_target(by_name["Construction Station"], "star"), "…which do fly to the Sun")
	check(not md.allows_arrival(by_name["Survey"], "star", "land"), "nothing lands on a star")
	check(not md.allows_arrival(by_name["Survey"], "gas_giant", "land"), "nothing lands on a gas giant")
	check(md.allows_arrival(by_name["Survey"], "rocky", "land"), "a rocky world can be landed on")
	check(md.allows_arrival(by_name["Survey"], "gas_giant", "orbit"), "but it can be orbited")
	check(str(md.refusal(by_name["Colony Ship"], "star", "orbit")) != "", "a refusal explains itself")
	check(str(md.refusal(by_name["Survey"], "rocky", "land")) == "", "a valid combination has no refusal")

	# ── The launch itself refuses what the panels would not offer ──
	var rt: Node = root.get_node("ResearchTree")
	var inv: Dictionary = g._planet_inv("earth")
	for res in ["Steel", "Al", "Microchip", "Superconductor", "Rocket", "Propellant"]:
		inv[res] = 1.0e20
	rt.resources["energy"] = 1.0e20
	var base := {"origin": "earth", "cargo": {}, "start_offset": 0, "duration": 300,
		"rockets": 4, "fuel_id": "Propellant", "fuel_amount": 50.0}
	for bad in [
			{"mission": "Colony Ship", "target": "sun", "arrival": "orbit"},
			{"mission": "Survey", "target": "sun", "arrival": "land"},
			{"mission": "Survey", "target": "jupiter", "arrival": "land"},
			{"mission": "Mining Ops", "target": "jupiter", "arrival": "orbit"},
			{"mission": "Solar Deployment", "target": "mars", "arrival": "orbit"}]:
		var p: Dictionary = base.duplicate()
		p.merge(bad, true)
		var before: int = g.active_launches.size()
		g._on_launch_requested(p)
		check(g.active_launches.size() == before, "refused: %s → %s (%s)" % [bad["mission"], bad["target"], bad["arrival"]])
	# …and still accepts a good one.
	var ok_params: Dictionary = base.duplicate()
	ok_params.merge({"mission": "Survey", "target": "mars", "arrival": "land"}, true)
	var n: int = g.active_launches.size()
	g._on_launch_requested(ok_params)
	check(g.active_launches.size() == n + 1, "a valid survey still flies")

	# ── The panels offer only what is valid ──
	var lp = g.launch_panel
	lp.show()
	for _i in range(5): await process_frame
	# Point it at the Sun: landing and the world-only missions must close.
	lp.planet_option.selected = lp._target_ids.find("sun")
	lp._refresh_validity()
	check(lp.arrival_option.is_item_disabled(1), "Land is closed for the Sun")
	var colony_idx := -1
	for i in range(md.MISSION_TYPES.size()):
		if str(md.MISSION_TYPES[i]["name"]) == "Colony Ship": colony_idx = i
	check(lp.mission_option.is_item_disabled(colony_idx), "Colony Ship is closed for the Sun")
	check(not md.allows_target(md.MISSION_TYPES[lp.mission_option.selected], "star")
		== false, "the selected mission is one the Sun accepts")
	# Point it at a gas giant: landing closes, Colony Ship opens.
	lp.planet_option.selected = lp._target_ids.find("jupiter")
	lp._refresh_validity()
	check(lp.arrival_option.is_item_disabled(1), "Land is closed for a gas giant")
	check(not lp.mission_option.is_item_disabled(colony_idx), "Colony Ship opens for a gas giant")
	# A rocky world takes everything.
	lp.planet_option.selected = lp._target_ids.find("mars")
	lp._refresh_validity()
	check(not lp.arrival_option.is_item_disabled(1), "Land opens for Mars")

	# Selecting a Sun-only mission with a planet selected moves the selection off it.
	var solar_idx := -1
	for i in range(md.MISSION_TYPES.size()):
		if str(md.MISSION_TYPES[i]["name"]) == "Solar Deployment": solar_idx = i
	check(lp.mission_option.is_item_disabled(solar_idx), "Solar Deployment is closed for Mars")

	# ── Automation ──
	var ap = g.sidebar.automation_panel
	ap.set_body_kinds(g.body_kinds())
	ap._l_target.selected = ap.TARGETS.find("Sun")
	ap._refresh_launch_validity()
	check(ap._l_arrival.is_item_disabled(1), "automation: Land closed for the Sun")
	check(ap._l_mission.is_item_disabled(colony_idx), "automation: Colony Ship closed for the Sun")
	check(not ap._l_mission.is_item_disabled(solar_idx), "automation: Solar Deployment open for the Sun")
	check(md.allows_target(md.MISSION_TYPES[ap._l_mission.selected], "star"),
		"automation: the stale selection moved to a valid mission")
	var warn: String = ap._describe({"type": "launch", "mission": "Colony Ship", "origin": "earth",
		"target": "sun", "fuel": "Propellant", "arrival": "orbit", "keep": 1})
	check(warn.contains("never fires"), "a saved impossible rule is flagged: %s" % warn)
	print("FAILS: ", fails)
	quit()
