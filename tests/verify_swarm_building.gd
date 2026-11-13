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

	# ── Demolishing one takes its panel out of the sky, even with the clock stopped ──
	# The renderer re-read the count only once it was past its pause guard, so an array
	# demolished while paused — which is when anybody is in the build panel — stayed drawn until
	# time ran again.  Driven through the renderer's own _process with a whole poll interval of
	# delta: the harness runs thousands of frames a second, and its real deltas would not reach
	# the throttle.
	var ss: Node = root.get_node("SolarSystem")
	var poll: float = float(planets.SWARM_POLL_SEC) + 0.01
	g.planet_buildings["sun"] = _arrays(g, 3)
	g.solar_satellites_deployed = 0
	ss.paused = false
	planets._process(poll)
	check(planets._swarm_mm.visible_instance_count == 3, "three arrays, three panels drawn: %d"
		% planets._swarm_mm.visible_instance_count)
	ss.paused = true
	g._on_demolish_requested("sun", g.SWARM_BUILDING, 1)
	check(g.swarm_panels() == 2, "demolishing one leaves two: %d" % g.swarm_panels())
	planets._process(poll)
	check(planets._swarm_mm.visible_instance_count == 2,
		"and the sky shows two while paused: %d" % planets._swarm_mm.visible_instance_count)
	# The same with the solar system frozen (a run past the orbit-resolving speed, paused to look).
	ss.solar_system_active = false
	g._on_demolish_requested("sun", g.SWARM_BUILDING, 1)
	planets._process(poll)
	check(planets._swarm_mm.visible_instance_count == 1,
		"and while frozen: %d" % planets._swarm_mm.visible_instance_count)
	ss.solar_system_active = true

	# And the other way: an array added while paused is drawn without waiting for the clock.
	# (Where it is drawn cannot be checked here: the headless renderer keeps no MultiMesh
	# transforms, so every instance reads back as the origin.)
	(g.planet_buildings["sun"] as Array).append(g.SWARM_BUILDING)
	planets._process(poll)
	check(planets._swarm_mm.visible_instance_count == 2, "an array added while paused is drawn: %d"
		% planets._swarm_mm.visible_instance_count)
	ss.paused = false

	# ── Every tier of the array is a panel; a retrofit is not a new one ──
	# The count matched the base NAME, so an upgraded array left the swarm and one built at II or
	# III was never in it.
	var t2: String = g.SWARM_BUILDING + " II"
	var t3: String = g.SWARM_BUILDING + " III"
	check(not g._find_building_def(t2).is_empty() and not g._find_building_def(t3).is_empty(),
		"the array has tiers II and III")
	g.solar_satellites_deployed = 0
	g.planet_buildings["sun"] = [g.SWARM_BUILDING, t2, t3]
	g.build_queue["sun"] = []
	check(g._swarm_built() == 3, "an array is a panel at every tier: %d" % g._swarm_built())
	check(g.swarm_panels() == 3, "and the swarm counts all three: %d" % g.swarm_panels())
	var room0: int = g.swarm_room()
	g.build_queue["sun"] = [{"building": t2, "upgrade_from": g.SWARM_BUILDING,
		"work": 1.0, "progress": 0.0}]
	check(g.swarm_room() == room0, "a queued retrofit takes no slot: %d vs %d" % [g.swarm_room(), room0])
	g.build_queue["sun"] = [{"building": t2, "work": 1.0, "progress": 0.0}]
	check(g.swarm_room() == room0 - 1, "a queued tier-II array does: %d vs %d" % [g.swarm_room(), room0 - 1])
	g.build_queue["sun"] = []

	# ── A save written over-full comes back exactly full ──
	# Launched panels may not outnumber the slots built arrays leave.  The launch path keeps that
	# on every arrival, but a save could still break it: the sandbox wrote a full swarm of launched
	# panels with arrays on top, and a player who upgraded arrays under the name-only count could
	# have launched into slots that only looked free.  Over-full, the surplus is invisible, and
	# demolishing a built array takes nothing out of the sky.
	g.planet_buildings["sun"] = _arrays(g, 3)
	g.solar_satellites_deployed = g._swarm_max()
	g.save_game("user://saves/swarm_overfull.json")
	g.load_game("user://saves/swarm_overfull.json")
	check(g.solar_satellites_deployed == g._swarm_max() - 3,
		"the launched count gives way to the built arrays: %d of %d" % [
			g.solar_satellites_deployed, g._swarm_max() - 3])
	check(g.swarm_panels() == g._swarm_max(), "the swarm is still full: %d" % g.swarm_panels())
	g._on_demolish_requested("sun", g.SWARM_BUILDING, 1)
	check(g.swarm_panels() == g._swarm_max() - 1, "and demolishing an array now shows: %d"
		% g.swarm_panels())
	g.solar_satellites_deployed = 0
	g.planet_buildings["sun"] = []

	# ── It is listed with the other generators ──
	# Under Power in the build panel, as drawn: the array makes energy, so a player looking for
	# the swarm looks there.  It used to be filed under Support beside the Sunshade.  Checked on
	# the rendered list — the heading each card actually sits under — not only on the data.
	check(str(def.get("category", "")) == "power", "it is filed under power: '%s'"
		% str(def.get("category", "")))
	g.current_planet = "sun"
	g.build_panel.set_planet("sun", g._get_catalog_for_display())
	for _i in range(2): await process_frame
	var section: String = ""
	var under: String = ""
	for n: Node in g.build_panel.build_list.get_children():
		if n.is_queued_for_deletion():
			continue
		if n is Label:
			section = (n as Label).text
		elif n is VBoxContainer and n.get_child_count() > 0:
			var head: Node = n.get_child(0)
			if head.get_child_count() > 0 and head.get_child(0) is Button \
					and (head.get_child(0) as Button).text.ends_with(g.SWARM_BUILDING):
				under = section
	print("the array is listed under: '%s'" % under)
	check(under.begins_with(str(BuildingData.CATEGORY_LABELS["power"])),
		"the build panel lists it under Power: '%s'" % under)
	# And the encyclopedia files it in the same place, from the same field.
	var wiki: Script = load("res://wiki_data.gd")
	var filed: String = ""
	for e: Dictionary in wiki.build_index(g):
		if str(e["cat"]) == "Buildings" and str(e["key"]) == g.SWARM_BUILDING:
			filed = str(e["group"])
	check(filed == str(BuildingData.CATEGORY_LABELS["power"]),
		"the encyclopedia files it under Power too: '%s'" % filed)

	print("FAILS: %d" % fails)
	quit()
