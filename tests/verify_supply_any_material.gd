extends SceneTree

## A Supply Run can ship anything the origin is holding.
##
## Both manifest pickers — the Launches panel's and a standing order's — read one map built by
## Game._build_launch_stock(), and that map used to be a WHITELIST of the goods a launch is
## PRICED in: Rocket, the propellants, and the bills of materials of the structures a carrier
## mission flies. So the hold could be filled with airframes and fuel and not one thing a colony
## would actually ask for — no steel, no water, no food.
##
## In a standing order it was narrower still. On a world that has not stockpiled rockets or
## propellant every key in that map reads zero, and the pickers skip a zero — leaving ENERGY,
## the civilisation-wide reserve, as the only offer. Which is the one thing that cannot usefully
## be shipped at all: it is a global pool, so the executor deducts it here and the arrival adds
## it straight back to the same pool. The player paid for rockets and nothing moved.
##
## The executor was never the limit. It ships any compound by key and always could.
##
## What has to hold:
##   the stock map reports what a world HOLDS, not what a launch costs
##   both pickers offer those materials
##   a global pool is not freight, in either picker or in the executor
##   and an arbitrary material actually flies, is charged, and lands

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _cargo_mission() -> String:
	for m in MissionData.MISSION_TYPES:
		if bool((m as Dictionary).get("cargo", false)):
			return str((m as Dictionary)["name"])
	return ""

func _run() -> void:
	seed(20261031)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	# Autoload IDENTIFIERS do not resolve in a SceneTree script; the live node does.
	var rt: Node = root.get_node("ResearchTree")

	# A material that is in NO launch bill of materials and no fuel list, so it can only reach
	# the picker if the stock map reports the inventory rather than the cost keys.
	var odd: String = "Spinach"
	var inv: Dictionary = g._planet_inv("earth")
	check(not inv.has(odd) or float(inv.get(odd, 0.0)) == 0.0,
		"%s is not something Earth starts with" % odd)
	g._add_stockpile(odd, 4.0e9, "earth")
	# Guard the premise: if this ever became a launch cost the test would pass vacuously.
	var priced := false
	for m in MissionData.MISSION_TYPES:
		var sname: String = str((m as Dictionary).get("structure", ""))
		if sname != "" and (g._find_building_def(sname).get("cost", {}) as Dictionary).has(odd):
			priced = true
	for f in MissionData.FUELS:
		if str((f as Dictionary)["id"]) == odd:
			priced = true
	check(not priced, "and it is not part of any launch's cost, so the whitelist would miss it")


	# ── The stock map reports the world, not the price list ──
	var stock: Dictionary = g._build_launch_stock()
	check(stock.has("earth"), "Earth is in the stock map")
	var earth: Dictionary = stock.get("earth", {})
	check(float(earth.get(odd, 0.0)) > 0.0,
		"and the map carries an arbitrary held material: %s = %s" % [
			odd, str(earth.get(odd, "missing"))])
	# The cost keys are still there, and still definite when the world has none of them — a gate
	# wants a number rather than a missing key.
	check(earth.has("Rocket"), "the launch cost keys survive: Rocket")
	for f in MissionData.FUELS:
		var fid: String = str((f as Dictionary)["id"])
		check(earth.has(fid), "and every propellant: %s" % fid)
	# Not aliased to the live inventory: a panel holding this must not be able to write to it.
	var probe: float = float(g._planet_inv("earth").get(odd, 0.0))
	earth[odd] = -1.0
	check(absf(float(g._planet_inv("earth").get(odd, 0.0)) - probe) < 1.0,
		"and the map is a copy, so a panel cannot write the inventory through it")


	# ── Both pickers offer it ──
	var cm: String = _cargo_mission()
	check(cm != "", "there is a mission with a hold: %s" % cm)

	# The Launches panel.
	var lp: Node = g.launch_panel
	check(lp != null, "the launch panel exists")
	for i in range(lp.mission_option.item_count):
		if lp.mission_option.get_item_text(i) == cm:
			lp.mission_option.selected = i
			break
	lp.set_current_planet("earth")
	lp.set_launch_stock(g._build_launch_stock())
	lp._refresh_cargo()
	var offered: Array = []
	for i in range(lp._cargo_pick.item_count):
		offered.append(lp._cargo_pick.get_item_text(i))
	check(offered.has(odd),
		"the launches panel offers it: %d entries, %s" % [offered.size(), str(offered.slice(0, 8))])
	check(offered.size() > 2,
		"and more than the two or three a cost whitelist would give: %d" % offered.size())
	# A global pool is not freight. It is in the stock map (the gates want the figure) and must
	# not be in the hold.
	check(float(earth.get("energy", 0.0)) > 0.0, "energy is still reported for the gates")
	check(not offered.has("energy"),
		"but it is not offered as cargo: %s" % str(offered))

	# A standing order's picker, which is the one that had nothing but energy in it.
	var ap: Node = g.sidebar.automation_panel
	check(ap != null, "the automation panel exists")
	ap.set_launch_stock(g._build_launch_stock())
	for i in range(ap._l_origin.item_count):
		if str(ap._l_origin.get_item_text(i)).to_lower() == "earth":
			ap._l_origin.selected = i
			break
	ap._refresh_cargo_choices()
	var rule_offered: Array = []
	for i in range(ap._l_cargo_pick.item_count):
		rule_offered.append(ap._l_cargo_pick.get_item_text(i))
	check(rule_offered.has(odd),
		"a standing order offers it too: %d entries, %s" % [
			rule_offered.size(), str(rule_offered.slice(0, 8))])
	check(not rule_offered.has("energy"),
		"and no longer offers energy as its only cargo: %s" % str(rule_offered))


	# ── It flies, is charged, and lands ──
	var held_before: float = float(g._planet_inv("earth").get(odd, 0.0))
	var mars_before: float = float(g._planet_inv("mars").get(odd, 0.0))
	g._add_stockpile("Rocket", 1.0e14, "earth")
	for f in MissionData.FUELS:
		g._add_stockpile(str((f as Dictionary)["id"]), 1.0e14, "earth")
	g._automation_rules = [{
		"id": 71, "type": "launch", "mission": cm, "origin": "earth", "target": "mars",
		"fuel": str((MissionData.FUELS[0] as Dictionary)["id"]), "arrival": "orbit",
		"keep": 1, "cargo": {odd: 1.0e9}, "enabled": true,
	}]
	var n0: int = g.active_launches.size()
	g._process_automation()
	check(g.active_launches.size() > n0, "the rule launches: %d -> %d" % [n0, g.active_launches.size()])
	var flew: Dictionary = {}
	for l in g.active_launches:
		if str((l as Dictionary).get("mission", "")) == cm:
			flew = (l as Dictionary).get("cargo", {})
	check(absf(float(flew.get(odd, 0.0)) - 1.0e9) < 1.0,
		"carrying the material it was told to: %s" % str(flew))
	check(float(g._planet_inv("earth").get(odd, 0.0)) < held_before,
		"charged to the origin: %s -> %s" % [
			str(held_before), str(g._planet_inv("earth").get(odd, 0.0))])
	# Landed. Fast-forward the flight rather than waiting out the transfer. A year in the PAST,
	# so the arrival has passed whichever basis the stored month/day are in — _process_launch_arrivals
	# compares against the 0-based `month`/`day` while the panel hands it 1-based ones.
	for l in g.active_launches:
		var d: Dictionary = l
		if str(d.get("mission", "")) == cm:
			d["end_year"] = g.year - 1
			d["end_month"] = 1
			d["end_day"] = 1
	g._process_launch_arrivals()
	check(float(g._planet_inv("mars").get(odd, 0.0)) > mars_before,
		"and unloaded at the target: %s -> %s" % [
			str(mars_before), str(g._planet_inv("mars").get(odd, 0.0))])


	# ── A saved rule that names a global pool does not charge for a round trip to nowhere ──
	# Standing orders persist, so a manifest written before this rule existed can still arrive.
	# Two separate symptoms, so two cases.

	# (a) The pool's mass is counted in GRAMS, so a reserve-sized figure asks for more lift than
	# the world can build and the rule silently never fires at all.
	var rk_before: float = float(g._planet_inv("earth").get("Rocket", 0.0))
	g._automation_rules = [{
		"id": 72, "type": "launch", "mission": cm, "origin": "earth", "target": "mars",
		"fuel": str((MissionData.FUELS[0] as Dictionary)["id"]), "arrival": "orbit",
		"keep": 40, "cargo": {"energy": 1.0e12, odd: 2.0e8}, "enabled": true,
	}]
	var n1: int = g.active_launches.size()
	g._process_automation()
	check(g.active_launches.size() > n1, "the rest of the hold still flies: %d -> %d" % [
		n1, g.active_launches.size()])
	var mixed: Dictionary = {}
	for l in g.active_launches:
		var d: Dictionary = l
		if str(d.get("mission", "")) == cm and (d.get("cargo", {}) as Dictionary).has(odd) \
				and absf(float((d.get("cargo", {}) as Dictionary)[odd]) - 2.0e8) < 1.0:
			mixed = d.get("cargo", {})
	check(not mixed.is_empty(), "and that flight is the mixed one: %s" % str(mixed))
	check(not mixed.has("energy"), "with the pool dropped from it: %s" % str(mixed))
	# 1e12 grams of "energy" is 5 000 rockets nobody asked for, which is what made the rule
	# unaffordable; the 2e8 of real cargo is one.
	var spent: float = rk_before - float(g._planet_inv("earth").get("Rocket", 0.0))
	var pool_lift: float = 1.0e12 / MissionData.CARGO_PER_ROCKET_G * MissionData.ROCKET_UNIT_MASS_G
	check(spent < pool_lift,
		"nor are rockets priced to lift it: spent %s, lifting it alone would cost %s" % [
			str(spent), str(pool_lift)])

	# (b) And at a figure the world CAN lift, the launch fires and the pool is still raided —
	# deducted here, handed straight back to the same global pool on arrival. Pinned to a known
	# reserve so "unchanged" is a tight assertion rather than a rounding tolerance.
	rt.resources["energy"] = 1.0e9
	g._automation_rules = [{
		"id": 73, "type": "launch", "mission": cm, "origin": "earth", "target": "mars",
		"fuel": str((MissionData.FUELS[0] as Dictionary)["id"]), "arrival": "orbit",
		"keep": 80, "cargo": {"energy": 2.0e8, odd: 1.0e8}, "enabled": true,
	}]
	var n2: int = g.active_launches.size()
	g._process_automation()
	check(g.active_launches.size() > n2,
		"an affordable pool figure launches: %d -> %d" % [n2, g.active_launches.size()])
	check(absf(float(rt.resources.get("energy", 0.0)) - 1.0e9) < 1.0,
		"and the reserve is untouched by it: %s" % str(rt.resources.get("energy", 0.0)))

	print("FAILS: %d" % fails)
	quit()
