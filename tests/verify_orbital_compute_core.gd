extends SceneTree

## The AI Research Hub is gone, and the Orbital Compute Core stands in its place.
##
## The hub was the densest compute a civilisation could build, a warehouse cluster on the ground.
## Its replacement is the same compute flown in orbit, where cooling is free: buildable over any
## world, in the belt and in solar orbit, drawn in a lane of its own, and unlocked where the hub
## was.
##
## What has to hold:
##   nothing in the catalogue, the unlocks or the sandbox still names the hub
##   the core is the hub's compute, at every tier, on the hub's research node, and it builds over
##     every kind of body there is — the star included, which the hub never could
##   every body and the belt draw a lane for it, and the lane shows what is built
##   a save written with hubs loads with cores, one for one and tier for tier: in the rosters, in
##     the build queue, in the switched-on counts and in the automation rules
##   where a save holds both, what was switched on stays switched on

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

const OLD: String = "AI Research Hub"
const NEW: String = "Orbital Compute Core"
const SUFFIXES: Array = ["", " II", " III"]
## What the hub produced at level 1, which the core takes over.
const HUB_COMPUTE: float = 1.0e25

func _run() -> void:
	seed(20261113)
	var gs: Node = root.get_node("GameSession")
	gs.should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(40): await process_frame
	var g: Node = current_scene
	var BD = load("res://buildings.gd")
	var UL = load("res://unlocks.gd")
	var P = load("res://planet.gd")

	# ── The hub is gone ──
	var left: Array = []
	for b: Dictionary in BD.all():
		if str(b["name"]).begins_with(OLD):
			left.append(str(b["name"]))
	check(left.is_empty(), "no tier of the hub is in the catalogue: %s" % str(left))
	check(not UL.BUILDING_UNLOCK_REQUIREMENTS.has(OLD), "nor in the unlocks")
	check(not BD.DESCRIPTIONS.has(OLD), "nor in the encyclopedia")
	check(not load("res://sandbox_save.gd").PLANET_LOADOUT.has(OLD), "nor in the sandbox")

	# ── The core in its place ──
	for i in range(SUFFIXES.size()):
		var nm: String = NEW + str(SUFFIXES[i])
		var d: Dictionary = g._find_building_def(nm)
		check(not d.is_empty(), "%s exists" % nm)
		if d.is_empty():
			continue
		var want: float = HUB_COMPUTE * pow(BD.LEVEL_OUTPUT_MULT, float(i))
		var got: float = float((d.get("production", {}) as Dictionary).get("compute", 0.0))
		check(is_equal_approx(got, want), "%s computes what the hub's tier did: %s vs %s"
			% [nm, str(got), str(want)])
		check(str(d.get("category", "")) == "science", "%s is filed under science" % nm)
	check(str(UL.BUILDING_UNLOCK_REQUIREMENTS.get(NEW, "?")) == "machine_learning_systems",
		"unlocked by the node that unlocked the hub: %s" % str(UL.BUILDING_UNLOCK_REQUIREMENTS.get(NEW)))
	check(BD.DESCRIPTIONS.has(NEW), "the encyclopedia has an entry for it")
	var core: Dictionary = g._find_building_def(NEW)
	for body: String in ["earth", "mars", "jupiter", "neptune", "asteroid_belt", "sun"]:
		check(g._fits_body(core, body), "it can be built over %s (%s)" % [body, str(g.PLANET_TYPES.get(body))])

	# ── A lane of its own, on every body ──
	var spec: Dictionary = {}
	for s: Dictionary in P.INFRA_LANES:
		if str(s["type"]) == NEW:
			spec = s
	check(not spec.is_empty(), "it has a lane")
	check(not bool(spec.get("ground", false)), "and the lane is not a ground one: it is in orbit everywhere")
	var orders: Dictionary = {}
	for s: Dictionary in P.INFRA_LANES:
		orders[int(s["order"])] = true
	check(orders.size() == P.INFRA_LANES.size(), "no two lanes share an order: %d of %d"
		% [orders.size(), P.INFRA_LANES.size()])
	var planets: Node = g.get_node("WorldRoot/Planets")
	for body: String in ["sun", "earth", "jupiter", "asteroid_belt"]:
		var n: Node = planets.get_node_or_null(body)
		var has_lane := false
		if n != null:
			for lane: Dictionary in n._infra:
				if str(lane["type"]) == NEW:
					has_lane = true
		check(has_lane, "%s draws the lane" % body)

	# Built over Earth, the lane shows them.
	var roster: Array = g.planet_buildings.get("earth", [])
	for _k in range(5):
		roster.append(NEW)
	g.planet_buildings["earth"] = roster
	g._mark_prod_dirty("earth")
	g._recompute_production_cache()
	var earth: Node = planets.get_node("earth")
	var shown: int = -1
	for lane: Dictionary in earth._infra:
		if str(lane["type"]) == NEW:
			earth._infra_poll = 1.0
			earth._update_infra(0.0)
			shown = (lane["mm"] as MultiMesh).visible_instance_count
	check(shown == 5, "five built over Earth, five drawn: %d" % shown)
	check(earth.infra_slot_world_pos(NEW, 0, 5).distance_to(earth.global_position) > 0.5 * earth.scale.x,
		"and a craft bound for one flies to the lane, not to the planet's centre")

	# ── A save written with hubs ──
	var path: String = "user://verify_orbital_compute_core.json"
	g.planet_buildings["earth"] = (g.planet_buildings["earth"] as Array).filter(
		func(b: Variant) -> bool: return str(b) != NEW)
	g.planet_buildings["mars"] = []
	g.build_queue.clear()
	g.active_buildings.clear()
	check(g.save_game(path), "saved")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var pb: Dictionary = data["planet_buildings"]
	(pb["earth"] as Dictionary)[OLD] = 2
	(pb["earth"] as Dictionary)[OLD + " II"] = 1
	(pb["earth"] as Dictionary)[OLD + " III"] = 3
	# Mars holds both, as no save ever did: two hubs with one of them switched off, and three
	# cores with no entry, so all three on.  Four of the five are on.
	pb["mars"] = {OLD: 2, NEW: 3}
	data["build_queue"] = {"earth": [{"building": OLD + " II", "work": 10.0, "progress": 2.0}]}
	data["active_buildings"] = {"earth": {OLD + " III": 1}, "mars": {OLD: 1}}
	data["automation_rules"] = [{"type": "build", "planet": "earth", "building": OLD + " III",
		"target": 4, "enabled": true}]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	g.load_game(path)
	for _i in range(3): await process_frame

	var er: Array = g.planet_buildings.get("earth", [])
	check(er.count(NEW) == 2 and er.count(NEW + " II") == 1 and er.count(NEW + " III") == 3,
		"Earth's hubs are cores, one for one and tier for tier: %d, %d, %d"
			% [er.count(NEW), er.count(NEW + " II"), er.count(NEW + " III")])
	var stale: Array = []
	for pname: String in g.planet_buildings:
		for b in g.planet_buildings[pname]:
			if str(b).begins_with(OLD):
				stale.append("%s on %s" % [b, pname])
	check(stale.is_empty(), "no hub is left standing anywhere: %s" % str(stale))
	var q: Array = g.build_queue.get("earth", [])
	check(q.size() == 1 and str((q[0] as Dictionary).get("building", "")) == NEW + " II",
		"the hub under construction finishes as a core: %s" % str(q))
	check(g.active_count("earth", NEW + " III") == 1,
		"the third-tier hubs that were switched off stay off: %d of 3 on" % g.active_count("earth", NEW + " III"))
	check(g.active_count("earth", NEW) == 2, "and the ones that were on stay on: %d" % g.active_count("earth", NEW))
	check(g.active_count("mars", NEW) == 4,
		"a world with both keeps on what was on: %d of 5" % g.active_count("mars", NEW))
	var rule: Dictionary = (g._automation_rules[0] as Dictionary) if not g._automation_rules.is_empty() else {}
	check(str(rule.get("building", "")) == NEW + " III",
		"a rule keeping hubs keeps cores: %s" % str(rule.get("building", "none")))
	# The compute came with them.
	var want_c: float = HUB_COMPUTE * (2.0 + 1.0 * BD.LEVEL_OUTPUT_MULT
		+ 1.0 * pow(BD.LEVEL_OUTPUT_MULT, 2.0))
	var got_c: float = 0.0
	for nm: String in [NEW, NEW + " II", NEW + " III"]:
		got_c += float((g._find_building_def(nm)["production"] as Dictionary)["compute"]) \
			* g.active_count("earth", nm)
	check(is_equal_approx(got_c, want_c), "Earth's switched-on cores compute what its hubs did: %s vs %s"
		% [Units.format_si(got_c, "FLOP/s"), Units.format_si(want_c, "FLOP/s")])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	print("FAILS: %d" % fails)
	quit()
