extends SceneTree

## Four bugs found by auditing, each pinned so it cannot come back.
##
##   1  a structure mission was CHARGED before the fuel and rocket checks, three `return`s
##      above the point of no return — and a standing automation rule repeated that every tick
##   2  a Colony Ship could be flown Earth → Earth, after which the home world was counted
##      twice everywhere _home_worlds() is summed
##   3  the launch panel's stock was cast to int, which saturates to INT64_MIN past 2^63, so a
##      developed civilisation's reserves read as a large negative and gated launches shut
##   4  two warnings raised in one tick left the clock stopped with no way to answer it back on

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(20261023)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var rt: Node = root.get_node("ResearchTree")
	var ss: Node = root.get_node("SolarSystem")
	for n: ResearchNode in load("res://ResearchTreeData.gd").build():
		rt.force_unlock(str(n.id))
	for key: String in rt.resources:
		rt.resources[key] = 1.0e30
	if not g.compound_inventory.has("earth"):
		g.compound_inventory["earth"] = {}
	var inv: Dictionary = g.compound_inventory["earth"]
	var fuel_id: String = str((MissionData.FUELS[0] as Dictionary)["id"])


	# ── 1. A refused structure launch spends nothing ──
	var sm: Dictionary = {}
	for m: Dictionary in MissionData.MISSION_TYPES:
		if str(m.get("structure", "")) != "":
			sm = m
			break
	check(not sm.is_empty(), "there is a mission that ferries a finished structure")
	if not sm.is_empty():
		var sname: String = str(sm["structure"])
		var cost: Dictionary = g._find_building_def(sname).get("cost", {})
		check(not cost.is_empty(), "%s has a bill of materials" % sname)
		# Exactly the bill, and nothing to fly it with.
		inv.clear()
		for res: String in cost:
			if not (res in g.GLOBAL_POOLS):
				inv[res] = float(cost[res])
		inv["Rocket"] = 0.0
		inv[fuel_id] = 0.0
		var before: Dictionary = inv.duplicate()
		check(g._can_afford_structure(sname, "earth"),
			"the origin can afford the structure itself")
		var n0: int = g.active_launches.size()
		g._on_launch_requested({
			"mission": str(sm["name"]), "origin": "earth", "target": "sun",
			"cargo": {}, "start_offset": 0.0, "duration": 30.0, "rockets": 50,
			"fuel_id": fuel_id, "fuel_amount": 1.0e9, "arrival": "orbit",
		})
		check(g.active_launches.size() == n0, "with no rockets, nothing launches")
		for res: String in before:
			check(absf(float(inv.get(res, 0.0)) - float(before[res])) < 1.0,
				"and the %s is still there: %s of %s" % [res, str(inv.get(res, 0.0)), str(before[res])])

		# The same thing a standing rule does, every tick, for as long as it cannot fly.
		inv.clear()
		for res: String in cost:
			if not (res in g.GLOBAL_POOLS):
				inv[res] = float(cost[res]) * 5.0
		inv["Rocket"] = 0.0
		inv[fuel_id] = 0.0
		var stocked: Dictionary = inv.duplicate()
		g._automation_rules = [{
			"id": 1, "type": "launch", "mission": str(sm["name"]), "origin": "earth",
			"target": "sun", "fuel": fuel_id, "arrival": "orbit", "keep": 1,
			"cargo": {}, "enabled": true,
		}]
		for _t in range(5):
			g._process_automation()
		for res: String in stocked:
			check(absf(float(inv.get(res, 0.0)) - float(stocked[res])) < 1.0,
				"five ticks of a rule it cannot fly cost no %s: %s of %s" % [
					res, str(inv.get(res, 0.0)), str(stocked[res])])
		g._automation_rules = []


	# ── 2. Earth cannot colonise itself, and is never counted twice ──
	inv.clear()
	inv["Rocket"] = 1.0e22
	inv[fuel_id] = 1.0e22
	var n1: int = g.active_launches.size()
	g._on_launch_requested({
		"mission": "Colony Ship", "origin": "earth", "target": "earth",
		"cargo": {}, "start_offset": 0.0, "duration": 30.0, "rockets": 50,
		"fuel_id": fuel_id, "fuel_amount": 1.0e9, "arrival": "land",
	})
	check(g.active_launches.size() == n1,
		"a Colony Ship to the world we live on is refused: %d launches" % g.active_launches.size())
	check(not g.colonized_planets.has("earth"), "so Earth never becomes its own colony")
	# A ship already in the air when the rule changed still lands, and is refused there too.
	g.colonized_planets.erase("earth")
	# And whatever put it there, the lists do not count it twice.
	g.colonized_planets.append("earth")
	var homes: Array = g._home_worlds()
	var seen: Dictionary = {}
	var dupes: Array = []
	for w: String in homes:
		if seen.has(w):
			dupes.append(w)
		seen[w] = true
	check(dupes.is_empty(), "_home_worlds() holds no world twice: %s" % str(homes))
	var targets: Array = g._impact_targets()
	seen = {}
	dupes = []
	for w: String in targets:
		if seen.has(w):
			dupes.append(w)
		seen[w] = true
	check(dupes.is_empty(), "nor does _impact_targets(): %s" % str(targets))
	# The two things the duplicate actually broke.
	inv.clear()
	inv["Rocket"] = 10.0
	check(absf(g._player_item_count("Rocket") - 10.0) < 1.0e-6,
		"ten rockets count as ten: %s" % str(g._player_item_count("Rocket")))
	check(not g._consume_player_item("Rocket", 15.0), "fifteen cannot be spent")
	check(absf(float(inv.get("Rocket", 0.0)) - 10.0) < 1.0e-6,
		"and the refusal spent nothing: %s" % str(inv.get("Rocket", 0.0)))
	inv["Wheat"] = 1.0e14
	var w0: float = float(inv["Wheat"])
	g._consume_food(1.0)
	var with_dupe: float = w0 - float(inv.get("Wheat", 0.0))
	g.colonized_planets.erase("earth")
	inv["Wheat"] = 1.0e14
	g._consume_food(1.0)
	var clean: float = 1.0e14 - float(inv.get("Wheat", 0.0))
	check(absf(with_dupe - clean) <= clean * 1.0e-6,
		"and Earth eats one world's rations either way: %s vs %s" % [
			str(with_dupe), str(clean)])
	# A save that already has it heals on load.
	g.colonized_planets.append("earth")
	g.save_game("user://saves/audit_fix.json")
	g.load_game("user://saves/audit_fix.json")
	check(not g.colonized_planets.has("earth"),
		"an affected save loads clean: %s" % str(g.colonized_planets))


	# ── 3. Reserves past 2^63 reach the panel as themselves ──
	# Re-acquired: load_game above replaced compound_inventory wholesale, so the dictionary
	# this test was holding is no longer the one the game reads.
	if not g.compound_inventory.has("earth"):
		g.compound_inventory["earth"] = {}
	inv = g.compound_inventory["earth"]
	var p = g.launch_panel
	inv["Rocket"] = 1.0e22
	inv[fuel_id] = 1.0e22
	rt.resources["energy"] = 1.0e26
	var st: Dictionary = (g._build_launch_stock()["earth"] as Dictionary)
	check(float(st["Rocket"]) > 0.0,
		"1e22 g of rockets is not a negative number: %s" % str(st["Rocket"]))
	check(absf(float(st["Rocket"]) - 1.0e22) <= 1.0e22 * 1.0e-9,
		"it is the figure itself: %s" % str(st["Rocket"]))
	check(float(st["energy"]) > 0.0,
		"and 1e26 J of energy likewise: %s" % str(st["energy"]))
	check(absf(float(st["energy"]) - 1.0e26) <= 1.0e26 * 1.0e-9,
		"to the joule: %s" % str(st["energy"]))
	p.show()
	g.refresh_launch_panel()
	for _i in range(4): await process_frame
	check(p._origin_stock("Rocket") > 0.0,
		"the panel's gate agrees: %s" % str(p._origin_stock("Rocket")))
	check(p._origin_stock("Rocket") >= MissionData.ROCKET_UNIT_MASS_G,
		"so one rocket is affordable with 1e22 g on hand")


	# ── 4. One warning at a time, and answering it restarts the clock ──
	check(not ss.ui_paused, "the clock is running")
	var atk: Dictionary = {"target": "earth", "kind": "missile", "count": 1,
		"arrival_year": g.year}
	g.incoming_attacks = [atk]
	g._raise_strike_threat(atk)
	check(not g._pending_threat.is_empty(), "a strike raises a warning")
	check(ss.ui_paused, "and stops the clock")
	var kind_before: String = str(g._pending_threat.get("kind", ""))
	# The same tick's asteroid check, four lines later in the real loop.
	g._check_asteroid_impact()
	g._raise_asteroid_threat()
	check(str(g._pending_threat.get("kind", "")) == kind_before,
		"a second warning does not replace the first: %s" % str(g._pending_threat.get("kind")))
	g._on_threat_accept()
	check(not ss.ui_paused, "and answering it starts the clock again")
	check(g._pending_threat.is_empty(), "with nothing left pending")
	# The postponed rock is not lost: with the warning cleared it can be raised.
	g._raise_asteroid_threat()
	check(not g._pending_threat.is_empty(),
		"the impact that was held off is still to come: %s" % str(g._pending_threat))
	g._on_threat_accept()
	check(not ss.ui_paused, "and that one hands the clock back too")

	print("FAILS: %d" % fails)
	quit()
