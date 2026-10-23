extends SceneTree

## Automated launches: what they carry, and when they fire.
##
## Two things were wrong and they looked like one. A standing Supply Run flew with an empty hold
## for ever — the same launch, the same cost, nothing delivered — because the rule had no
## manifest and the executor had nothing to pass. And _process_automation() was called only from
## the day-mode block, so every standing order stopped the moment the game went to fast mode,
## which is also the moment the planets stop being drawn as bodies and become blurs. Flights
## already out went on landing, so it read as the rules having run out of things to do rather
## than having stopped being asked.

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
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var ss: Node = root.get_node("SolarSystem")

	# ── Automation runs on BOTH clocks ──
	# The whole point of a standing order is unattended operation, which is exactly what fast
	# mode is for; a rule that stops when the clock speeds up is a rule that never runs when it
	# is wanted.
	var src: String = FileAccess.get_file_as_string("res://Game.gd")
	var fast_at: int = src.find("func _on_years_advanced_fast")
	check(fast_at > 0, "the fast-mode entry point is there")
	var fast_body: String = src.substr(fast_at, 3000)
	check(fast_body.find("_process_automation()") >= 0,
		"and it drives automation, not only the day clock")

	# Measured, not only read: a rule that can afford itself launches on a fast tick.
	g._automation_rules = [{
		"id": 1, "type": "launch", "mission": "Research Probe", "origin": "earth",
		"target": "mars", "fuel": str((MissionData.FUELS[0] as Dictionary)["id"]),
		"arrival": "orbit", "keep": 2, "enabled": true,
	}]
	g._add_stockpile("Rocket", 1.0e14, "earth")
	for f in MissionData.FUELS:
		g._add_stockpile(str((f as Dictionary)["id"]), 1.0e14, "earth")
	var before: int = g.active_launches.size()
	g._on_years_advanced_fast(1)
	check(g.active_launches.size() > before,
		"a fast tick starts what the fleet is short of: %d -> %d" % [
			before, g.active_launches.size()])
	# And it is blurred-planet territory, which is the state this was reported in.
	# Set and checked with no frames in between: _update_timescale re-derives seconds_per_day
	# from the player's chosen multiplier every year, so a rate poked in by hand does not
	# survive a tick, and the first version of this check was reading the restored value.
	ss.paused = false
	ss.ui_paused = false
	ss.seconds_per_day = ss.TIMESCALE_BASE / 1000.0
	check(not ss.orbits_resolvable(),
		"at this rate the planets are drawn as blurs (x%.0f)" % ss.speed_multiplier())
	var mid: int = g.active_launches.size()
	g._automation_rules[0]["keep"] = 6
	g._on_years_advanced_fast(1)
	check(g.active_launches.size() > mid,
		"and automation still fires there: %d -> %d" % [mid, g.active_launches.size()])
	ss.seconds_per_day = ss.TIMESCALE_BASE

	# ── A rule carries what it was told to carry ──
	var cm: String = _cargo_mission()
	check(cm != "", "there is a mission with a hold: %s" % cm)
	g._add_stockpile("Steel", 5.0e12, "earth")
	var held_before: float = float(g._planet_inv("earth").get("Steel", 0.0))
	g._automation_rules = [{
		"id": 2, "type": "launch", "mission": cm, "origin": "earth", "target": "mars",
		"fuel": str((MissionData.FUELS[0] as Dictionary)["id"]), "arrival": "orbit",
		"keep": 1, "cargo": {"Steel": 1.0e9}, "enabled": true,
	}]
	var n0: int = g.active_launches.size()
	g._process_automation()
	check(g.active_launches.size() > n0, "the cargo rule launches")
	var found := {}
	for l in g.active_launches:
		if str((l as Dictionary).get("mission", "")) == cm:
			found = (l as Dictionary).get("cargo", {})
	check(not found.is_empty(), "and the hold is not empty: %s" % str(found))
	check(absf(float(found.get("Steel", 0.0)) - 1.0e9) < 1.0,
		"carrying what the rule said: %s" % str(found))
	check(float(g._planet_inv("earth").get("Steel", 0.0)) < held_before,
		"loaded out of the origin's own stores")

	# ── A manifest it cannot fill simply waits ──
	# The same thing a rule that cannot afford its rockets already does — not an error, not a
	# launch that flies empty.
	g._automation_rules = [{
		"id": 3, "type": "launch", "mission": cm, "origin": "earth", "target": "mars",
		"fuel": str((MissionData.FUELS[0] as Dictionary)["id"]), "arrival": "orbit",
		"keep": 9, "cargo": {"Steel": 1.0e30}, "enabled": true,
	}]
	var n1: int = g.active_launches.size()
	g._process_automation()
	check(g.active_launches.size() == n1,
		"a hold the world cannot fill launches nothing: %d" % g.active_launches.size())

	# ── The rule survives a save ──
	g._automation_rules = [{
		"id": 4, "type": "launch", "mission": cm, "origin": "earth", "target": "mars",
		"fuel": str((MissionData.FUELS[0] as Dictionary)["id"]), "arrival": "orbit",
		"keep": 1, "cargo": {"Steel": 2.5e8}, "enabled": true,
	}]
	g.save_game("user://saves/autocargo.json")
	g._automation_rules = []
	g.load_game("user://saves/autocargo.json")
	var kept: Dictionary = {}
	for r in g._automation_rules:
		if int((r as Dictionary).get("id", 0)) == 4:
			kept = (r as Dictionary).get("cargo", {})
	check(absf(float(kept.get("Steel", 0.0)) - 2.5e8) < 1.0,
		"the manifest comes back: %s" % str(kept))

	print("FAILS: %d" % fails)
	quit()
