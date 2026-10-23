extends SceneTree

## Standing orders to shoot down what is coming at a world.
##
## An interception is a decision with one sensible answer whenever the shot is affordable, and
## being stopped to make it every time across a million years is the opposite of automation. A
## defence rule answers the warning instead of raising it.
##
## It is an ANSWER, not a promise: told to defend a world with no array built or no energy for
## the shot, the game still stops and says so, because then there is a real decision again.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(20261020)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var rt: Node = root.get_node("ResearchTree")
	var ss: Node = root.get_node("SolarSystem")
	# Taken off the live nodes, not by loading the scripts as classes: StarMapPanel.gd and
	# planet.gd both reference autoloads, which do not resolve when a SceneTree script pulls
	# them in standalone — the whole run fails to compile rather than the line failing.
	var sm = g.sidebar.star_map
	var earth: Node = g.get_node("WorldRoot/Planets/earth")

	# ── The rule only covers what it says it covers ──
	g._automation_rules = [{"id": 1, "type": "defend", "planet": "earth",
		"asteroids": true, "weapons": false, "enabled": true}]
	check(g._defence_covers("earth", "asteroid"), "Earth is covered against asteroids")
	check(not g._defence_covers("earth", "missile"), "but not against weapons")
	check(not g._defence_covers("mars", "asteroid"), "and Mars is not covered at all")
	g._automation_rules[0]["weapons"] = true
	check(g._defence_covers("earth", "missile"), "turning weapons on covers a missile")
	check(g._defence_covers("earth", "berserker"), "and a berserker swarm")
	g._automation_rules[0]["enabled"] = false
	check(not g._defence_covers("earth", "asteroid"), "a disabled rule covers nothing")
	g._automation_rules[0]["enabled"] = true

	# ── "Everywhere" covers what a dropdown of eight planets cannot ──
	# Projectiles are aimed at interstellar colonies too, and there are too many of those to
	# name one at a time.
	var any: String = g.sidebar.automation_panel.DEFEND_ANY
	g._automation_rules = [{"id": 2, "type": "defend", "planet": any,
		"asteroids": false, "weapons": true, "enabled": true}]
	check(g._defence_covers("Alpha Centauri A", "missile"), "a colony four light-years out")
	check(g._defence_covers("neptune", "berserker"), "and Neptune, from the one rule")
	check(not g._defence_covers("earth", "asteroid"),
		"but it still only covers what it says: this one is not watching for rocks")
	g._automation_rules = [{"id": 1, "type": "defend", "planet": "earth",
		"asteroids": true, "weapons": true, "enabled": true}]

	# ── Without an array there is no shot, so the warning still comes up ──
	check(not g._has_orbital_laser(), "nothing is built yet")
	check(not g._auto_defend("earth", "asteroid"),
		"so a standing order cannot take the shot")

	# ── With one, it fires and pays for it ──
	for n: ResearchNode in load("res://ResearchTreeData.gd").build():
		rt.force_unlock(str(n.id))
	if not g.planet_buildings.has("earth"):
		g.planet_buildings["earth"] = []
	var laser_name: String = ""
	for spec: Dictionary in earth.INFRA_LANES:
		if str(spec["type"]).find("Laser") >= 0:
			laser_name = str(spec["type"])
	check(laser_name != "", "there is an orbital laser to build: %s" % laser_name)
	(g.planet_buildings["earth"] as Array).append(laser_name)
	g._mark_prod_dirty("earth")
	g._recompute_production_cache()
	check(g._has_orbital_laser(), "the array is standing")

	var cost: float = sm.laser_energy(0.0)
	rt.resources["energy"] = cost * 0.5
	check(not g._auto_defend("earth", "asteroid"),
		"an array that cannot be charged does not fire")
	rt.resources["energy"] = cost * 4.0
	var before: float = float(rt.resources["energy"])
	check(g._auto_defend("earth", "asteroid"), "charged, it fires")
	check(absf(float(rt.resources["energy"]) - (before - cost)) < 1.0,
		"and the shot is paid for: %s" % str(rt.resources["energy"]))

	# ── An incoming projectile is destroyed without stopping the clock ──
	rt.resources["energy"] = cost * 10.0
	var atk: Dictionary = {"target": "earth", "kind": "missile", "count": 1,
		"arrival_year": g.year}
	g.incoming_attacks = [atk]
	var paused_before: bool = ss.ui_paused
	g._raise_strike_threat(atk)
	check(g._pending_threat.is_empty(),
		"a covered strike raises no warning: %s" % str(g._pending_threat))
	check(ss.ui_paused == paused_before, "and does not stop the clock")
	check(not g.incoming_attacks.has(atk), "the projectile is gone")

	# Uncovered, the warning goes up exactly as before.
	g._automation_rules[0]["weapons"] = false
	var atk2: Dictionary = {"target": "earth", "kind": "missile", "count": 1,
		"arrival_year": g.year}
	g.incoming_attacks = [atk2]
	g._raise_strike_threat(atk2)
	check(not g._pending_threat.is_empty(), "an uncovered strike still asks")
	check(g.incoming_attacks.has(atk2), "and the projectile is still coming")
	g._on_threat_accept()

	# ── An asteroid on a covered world never reaches the surface ──
	rt.resources["energy"] = cost * 10.0
	g._automation_rules = [{"id": 2, "type": "defend", "planet": "earth",
		"asteroids": true, "weapons": true, "enabled": true}]
	var pop_before: float = float(g.world_pop.get("earth", 0.0))
	g._raise_asteroid_threat()
	check(g._pending_threat.is_empty(), "a covered impactor raises no warning")
	check(float(g.world_pop.get("earth", 0.0)) >= pop_before * 0.999,
		"and nobody dies: %s vs %s" % [g.world_pop.get("earth", 0.0), pop_before])

	# ── The rule survives a save ──
	g.save_game("user://saves/defence.json")
	g._automation_rules = []
	g.load_game("user://saves/defence.json")
	var kept: Dictionary = {}
	for r in g._automation_rules:
		if str((r as Dictionary).get("type", "")) == "defend":
			kept = r
	check(not kept.is_empty(), "the defence rule comes back: %s" % str(g._automation_rules))
	check(bool(kept.get("asteroids", false)) and bool(kept.get("weapons", false)),
		"with what it protects against: %s" % str(kept))

	print("FAILS: %d" % fails)
	quit()
