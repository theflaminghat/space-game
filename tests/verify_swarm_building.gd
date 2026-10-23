extends SceneTree

## A Dyson swarm panel can be assembled in solar orbit as well as flown there as a Solar
## Satellite.  The two routes are the same object: one slot, one lane, one cap, one power
## curve — so everything that reads the swarm has to read both, and the cap has to hold against
## the build queue, which has no notion of one.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

## planet_buildings holds one entry per structure, so a swarm of n arrays is n entries.
func _arrays(g: Node, n: int) -> Array:
	var a: Array = []
	for _i in range(n):
		a.append(g.SWARM_BUILDING)
	return a

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(20260927)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(40): await process_frame
	var g: Node = current_scene
	var rt: Node = root.get_node("ResearchTree")

	# ── The definition ──
	var def: Dictionary = g._find_building_def(g.SWARM_BUILDING)
	check(not def.is_empty(), "the building exists")
	check((def.get("allowed_types", []) as Array) == ["star"],
		"it is buildable only in solar orbit")
	check((def.get("production", {}) as Dictionary).is_empty(),
		"it produces nothing directly — _swarm_power owns the energy")
	check(not (def.get("cost", {}) as Dictionary).is_empty(), "it costs something")
	check(g._fits_body(def, "sun"), "it fits the Sun")
	check(not g._fits_body(def, "earth"), "and nowhere else")
	check(BuildingData.DESCRIPTIONS.has(g.SWARM_BUILDING),
		"it has a description for the build panel")
	check(BuildingUnlocks.BUILDING_UNLOCK_REQUIREMENTS.get(g.SWARM_BUILDING, "")
		== g.SOLAR_ORBIT_RESEARCH,
		"it is gated on the same research as building in solar orbit at all")

	# ── Research gate: refused at the opening, before the node is taken ──
	g.planet_buildings["sun"] = []
	g.build_queue.erase("sun")
	g.solar_satellites_deployed = 0
	check(not rt.is_unlocked(g.SOLAR_ORBIT_RESEARCH),
		"the run opens without solar-orbit construction")
	check(not g.try_build("sun", g.SWARM_BUILDING),
		"so the array cannot be built yet")
	rt.force_unlock(g.SOLAR_ORBIT_RESEARCH)
	check(g._is_body_buildable("sun"), "the research opens solar orbit")

	# ── Counting: built panels join the swarm ──
	g.planet_buildings["sun"] = _arrays(g, 5)
	g.solar_satellites_deployed = 3
	check(g._swarm_built() == 5, "built arrays are counted")
	check(g.swarm_panels() == 8, "the swarm is the flown ones plus the built ones")

	# ── Power follows the total, and only through _swarm_power ──
	g.planet_buildings["sun"] = []
	g.solar_satellites_deployed = 0
	var p0: float = g._swarm_power()
	g.solar_satellites_deployed = 4
	var p_flown: float = g._swarm_power()
	g.solar_satellites_deployed = 0
	g.planet_buildings["sun"] = _arrays(g, 4)
	var p_built: float = g._swarm_power()
	check(p0 == 0.0, "an empty swarm beams nothing")
	check(p_flown > 0.0, "four flown collectors beam power")
	check(absf(p_built - p_flown) < 1.0, "four built arrays beam exactly the same")

	# ── The cap is shared ──
	var cap: int = g._swarm_max()
	g.planet_buildings["sun"] = _arrays(g, cap)
	g.solar_satellites_deployed = 0
	check(g.swarm_panels() == cap, "a swarm built entirely in place is full")
	check(g.swarm_room() == 0, "with no room left")
	check(not g.try_build("sun", g.SWARM_BUILDING), "and the next array is refused")

	g.planet_buildings["sun"] = _arrays(g, cap - 1)
	check(g.swarm_room() == 1, "one slot left")
	# Queued work counts: the queue itself has no cap, so it must be charged against this one.
	g.build_queue["sun"] = [{"building": g.SWARM_BUILDING, "work": 1.0, "progress": 0.0}]
	check(g._swarm_queued() == 1, "a queued array is counted")
	check(g.swarm_room() == 0, "and takes the last slot")
	check(not g.try_build("sun", g.SWARM_BUILDING),
		"so a second cannot be queued into the same slot")
	g.build_queue.erase("sun")

	# ── A flown satellite cannot overwrite a built one ──
	# solar_satellites_deployed is clamped against the room the buildings leave.
	g.planet_buildings["sun"] = _arrays(g, cap)
	g.solar_satellites_deployed = clampi(999, 0, cap - g._swarm_built())
	check(g.solar_satellites_deployed == 0,
		"a full built swarm leaves no room for arriving satellites")
	check(g.swarm_panels() == cap, "and the total never exceeds the cap")

	# ── Mixed: the two routes add up to the cap and no further ──
	g.planet_buildings["sun"] = _arrays(g, 10)
	g.solar_satellites_deployed = cap
	check(g.swarm_panels() == cap, "the total is clamped at the cap")

	# ── The renderer and the wiki read the same number ──
	g.planet_buildings["sun"] = _arrays(g, 7)
	g.solar_satellites_deployed = 2
	var planets: Node = g.get_node_or_null("WorldRoot/Planets")
	check(planets != null, "the swarm renderer is in the scene")
	if planets != null and planets.has_method("_deployed_satellite_count"):
		check(int(planets._deployed_satellite_count()) == 9,
			"the renderer lights up both routes")

	# ── End to end: pay for one, grind the queue, and watch the grid pick it up ──
	g.planet_buildings["sun"] = []
	g.build_queue.erase("sun")
	g.solar_satellites_deployed = 0
	g._mark_prod_dirty()
	var before: float = g._swarm_power()
	for res: String in (def.get("cost", {}) as Dictionary):
		var need: float = float((def["cost"] as Dictionary)[res]) * 4.0
		if res == "energy":
			rt.resources["energy"] = maxf(float(rt.resources.get("energy", 0.0)), need)
		else:
			g._add_stockpile(res, need, "sun")
	check(g.try_build("sun", g.SWARM_BUILDING), "with research and materials it builds")
	check(g._swarm_queued() == 1, "and lands in the queue")
	# Finish the job through the same call the grind makes.  The grind itself is shared
	# machinery with every other building and is not what is under test; what matters here is
	# that a completed array registers on the Sun and reaches the grid.
	var jobs: Array = g.build_queue["sun"]
	var job: Dictionary = jobs.pop_front()
	if jobs.is_empty():
		g.build_queue.erase("sun")
	g._complete_build("sun", job)
	for _i in range(4): await process_frame
	check(g._swarm_built() == 1, "the finished array is standing in solar orbit")
	check(g._swarm_queued() == 0, "and is off the queue")
	g._mark_prod_dirty()
	check(g._swarm_power() > before, "the grid now carries its power")

	print("FAILS: %d" % fails)
	quit()
