extends SceneTree

## The sandbox save is written fresh by SandboxSave.write() every time the start menu loads
## (StartMenu.gd), so it is generated rather than edited — and these are the properties the
## generator is supposed to give it.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(20260927)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(30): await process_frame
	var g: Node = current_scene
	var rt: Node = root.get_node("ResearchTree")
	var ss: Node = root.get_node("SolarSystem")
	var SB = load("res://sandbox_save.gd")

	SB.write()
	g.load_game(SB.SAVE_PATH)
	for _i in range(5): await process_frame

	# ── The Dyson swarm is full ──
	# SWARM_COLLECTORS is a constant because the generator is static and cannot reach the lane
	# geometry. This is what stops it drifting away from the real cap.
	check(g._swarm_max() == int(SB.SWARM_COLLECTORS),
		"SandboxSave.SWARM_COLLECTORS still matches the swarm cap (%d vs %d)" % [
			int(SB.SWARM_COLLECTORS), g._swarm_max()])
	check(g.swarm_panels() == g._swarm_max(),
		"the swarm loads full: %d of %d" % [g.swarm_panels(), g._swarm_max()])
	# ...and not OVER-full.  This used to check the launched count alone, and it was the cap:
	# the save then stood a lane of every array tier on top, so the built arrays were surplus a
	# full sky never showed, and demolishing one took nothing out of it.
	check(g.solar_satellites_deployed + g._swarm_built() == g._swarm_max(),
		"launched and built panels together fill it exactly: %d + %d of %d" % [
			g.solar_satellites_deployed, g._swarm_built(), g._swarm_max()])
	check(g._swarm_built() > 0, "some of it is built arrays, which can be demolished: %d"
		% g._swarm_built())
	# And the FILE says so, not just the game after loading it: load_game trims an over-full swarm
	# on its own, which would hide a generator that went back to writing one.
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SB.SAVE_PATH))
	var file_built: int = 0
	var sun_counts: Dictionary = (raw.get("planet_buildings", {}) as Dictionary).get("sun", {})
	for nm: String in sun_counts:
		file_built += int(sun_counts[nm]) * g._swarm_panels_of(nm)
	check(int(raw.get("solar_satellites_deployed", -1)) + file_built == g._swarm_max(),
		"the sandbox file itself is exactly full: %d launched + %d built of %d" % [
			int(raw.get("solar_satellites_deployed", -1)), file_built, g._swarm_max()])

	# Which is the whole point: in the sandbox, demolishing an array takes a panel out of the sky —
	# at every tier, and with the game paused, as a loaded save starts.
	var sky: Node = g.get_node("WorldRoot/Planets")
	sky._process(float(sky.SWARM_POLL_SEC) + 0.01)
	var drawn0: int = sky._swarm_mm.visible_instance_count
	check(drawn0 == g._swarm_max(), "the sky starts full: %d" % drawn0)
	var gone: int = 0
	for tier: String in ["Swarm Collector Array", "Swarm Collector Array II", "Swarm Collector Array III"]:
		g._on_demolish_requested("sun", tier, 1)
		gone += 1
		sky._process(float(sky.SWARM_POLL_SEC) + 0.01)
		check(g.swarm_panels() == g._swarm_max() - gone,
			"demolishing a %s leaves %d panels: %d" % [tier, g._swarm_max() - gone, g.swarm_panels()])
		check(sky._swarm_mm.visible_instance_count == drawn0 - gone,
			"and the sky shows %d: %d" % [drawn0 - gone, sky._swarm_mm.visible_instance_count])

	# The lane geometry is written out twice — Game computes the capacity, init_planets.gd draws
	# the lanes — and the two constants are kept in sync by hand.  If they drift, Game hands out
	# slots the renderer has nowhere to put.
	# init_planets.gd is the script ON WorldRoot/Planets, not a child of it.
	var swarm_node: Node = g.get_node("WorldRoot/Planets")
	check(swarm_node.has_method("get_swarm_max"), "the swarm renderer is where it is expected")
	check(int(swarm_node.get_swarm_max()) == g._swarm_max(),
		"Game and the renderer agree on the swarm cap: %d vs %d" % [
			int(swarm_node.get_swarm_max()), g._swarm_max()])

	# ── Everything that can stand in solar orbit is standing there ──
	var U = load("res://unlocks.gd")
	var missing: Array = []
	var locked: Array = []
	var undrawn: Array = []
	for b: Dictionary in load("res://buildings.gd").all():
		var nm: String = str(b["name"])
		if not (b.get("allowed_types", []) as Array).has("star"):
			continue
		var n: int = g._count_building("sun", nm)
		# A structure there can only be one of stands as exactly one, on the BASE tier alone:
		# the cap counts every tier of it together (buildings.gd "max_count"), so a sandbox
		# that gave each tier its own would load three mirrors against a cap of one.
		var cap: int = int(b.get("max_count", 0))
		if cap > 0:
			var want: int = cap if int(b.get("level", 1)) == 1 else 0
			if n != want:
				missing.append("%s (%d standing, wanted %d)" % [nm, n, want])
		elif n <= 0:
			missing.append(nm)
		var req: String = str(U.BUILDING_UNLOCK_REQUIREMENTS.get(nm, ""))
		if req != "" and not rt.is_unlocked(req):
			locked.append(nm)
		# planet.gd will not draw more of a type than INFRA_MAX_PER_LANE, so asking for more
		# would cost materials for structures the player can never see.
		if n > load("res://planet.gd").INFRA_MAX_PER_LANE:
			undrawn.append("%s x%d" % [nm, n])
	check(missing.is_empty(), "every star-capable structure is on the Sun: missing %s" % str(missing))
	check(locked.is_empty(), "and its research is open: still locked %s" % str(locked))
	check(undrawn.is_empty(), "and none overflows its orbital lane: %s" % str(undrawn))

	# The Sun has to be openable for any of that to be reachable.
	check(g._is_body_buildable("sun"), "the Sun is a build site")
	g.current_planet = "sun"
	check(g._get_catalog_for_display().size() > 0, "and its build list is populated")

	# ── It loads into a going concern, not a crisis ──
	# The sunshades dim Earth slightly, which is the model working; what matters is that the
	# save settles and stays settled rather than sliding.
	var marks: Array = []
	ss.seconds_per_day = 5.0e-4
	for block in range(3):
		for _i in range(900):
			ss.paused = false
			ss.ui_paused = false
			g.get_tree().paused = false
			await process_frame
		marks.append(g._total_population())
	check(not g.game_over, "it survives being run")
	check(marks[0] > 5.0e9, "with a population worth playing: %s" % str(marks[0]))
	check(absf(marks[2] - marks[1]) / maxf(marks[1], 1.0) < 0.01,
		"and settles rather than sliding: %s -> %s" % [str(marks[1]), str(marks[2])])
	print("pop %.3fB settled | insolation %.5f | shade %s | mirror %s" % [
		marks[2] / 1.0e9, ss.insolation_at_earth(),
		str(ss.star_shade_fraction), str(ss.star_mirror_coverage)])
	print("sun: %d kinds, %d structures" % [
		(g._cached_planet_counts.get("sun", {}) as Dictionary).size(),
		(g.planet_buildings.get("sun", []) as Array).size()])

	print("FAILS: %d" % fails)
	quit()
