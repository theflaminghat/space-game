extends SceneTree
var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)
func stock(g, res, world) -> float:
	return g._get_stockpile(res, world)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(25): await process_frame
	var g: Node = current_scene
	var rt: Node = root.get_node("ResearchTree")
	var md = load("res://missions.gd")
	var station := "Orbital Construction Station"
	g.planet_buildings["sun"] = []
	g._mark_prod_dirty(); g._recompute_production_cache()

	# The carriers are gated on the research that makes the structures buildable at all, and
	# _can_afford_structure enforces it — without this the launch is refused for a reason that
	# has nothing to do with what this test is about.
	rt.force_unlock("precision_orbital_construction")

	# Stock Earth with everything a carrier needs.
	var inv: Dictionary = g._planet_inv("earth")
	for res in ["Steel", "Al", "Microchip", "Superconductor", "Rocket", "LH2", "Kerosene", "Methane"]:
		inv[res] = 1.0e20
	rt.resources["energy"] = 1.0e20
	# Stock the propellant this launch will actually burn rather than a guessed list of names:
	# FUELS[0] is "Propellant", which was not among them, and the launch was refused for want
	# of fuel long before anything this test cares about was reached.
	var fuel_id: String = str(md.FUELS[0]["id"])
	inv[fuel_id] = 1.0e20

	var params := {
		"mission": "Construction Station", "origin": "earth", "target": "sun",
		"cargo": {}, "start_offset": 0, "duration": 300, "rockets": 20,
		"fuel_id": fuel_id, "fuel_amount": 320.0, "arrival": "orbit",
	}

	# ── Wrong target is refused, and costs nothing ──
	var steel_before: float = stock(g, "Steel", "earth")
	var wrong: Dictionary = params.duplicate(); wrong["target"] = "mars"
	g._on_launch_requested(wrong)
	check(g.active_launches.is_empty(), "a carrier to Mars is refused")
	check(is_equal_approx(stock(g, "Steel", "earth"), steel_before), "and charges nothing")

	# ── A real launch charges the structure's bill at the origin ──
	g._on_launch_requested(params)
	check(g.active_launches.size() == 1, "the launch went up: %d" % g.active_launches.size())
	if g.active_launches.is_empty():
		print("FAILS: ", fails); quit(); return
	var l: Dictionary = g.active_launches[0]
	check(str(l.get("structure", "")) == station, "it is carrying the station: '%s'" % l.get("structure", ""))
	var def: Dictionary = g._find_building_def(station)
	var spent: float = steel_before - stock(g, "Steel", "earth")
	print("steel charged: %s (station bill %s)" % [spent, def["cost"]["Steel"]])
	check(spent >= float(def["cost"]["Steel"]), "the structure's steel was charged")
	check(not (g.planet_buildings.get("sun", []) as Array).has(station), "nothing at the Sun yet")

	# ── On arrival it is standing at the Sun ──
	g._pending_event_notifications = []
	l["arrival_year"] = g.year - 1 if l.has("arrival_year") else null
	# Drive the clock until the carrier lands.
	root.get_node("SolarSystem").paused = false
	g.set_speed_tier(9)
	var guard := 0
	while not (g.planet_buildings.get("sun", []) as Array).has(station) and guard < 4000:
		g._process(1.0)
		guard += 1
	check((g.planet_buildings.get("sun", []) as Array).has(station),
		"the station is on station after %d ticks" % guard)
	var notes: Array = g._pending_event_notifications.filter(func(n): return str(n["id"]).begins_with("structure_"))
	check(notes.size() >= 1, "the arrival is announced")
	if notes.size() > 0:
		print("announcement: ", notes[0]["title"], " — ", notes[0]["desc"])

	# ── And it is doing its job ──
	g._mark_prod_dirty(); g._recompute_production_cache()
	check(g._planet_mc_capacity("sun") > 1.0e11, "the Sun now has real industry: %s" % g._planet_mc_capacity("sun"))

	# ── Too poor to build one: refused ──
	var inv2: Dictionary = g._planet_inv("earth")
	inv2["Superconductor"] = 0.0
	var n_before: int = g.active_launches.size()
	g._on_launch_requested(params)
	check(g.active_launches.size() == n_before, "a carrier with no superconductor is refused")
	print("FAILS: ", fails)
	quit()
