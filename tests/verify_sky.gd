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
	for _i in range(25): await process_frame
	var g: Node = current_scene
	var ss: Node = root.get_node("SolarSystem")
	var SM = load("res://StarMapPanel.gd")

	# The galaxy seed is randomised per run, so pin it: without this the chunk contents — and
	# every distance measured off them — change from one run of this test to the next.
	SM.set_galaxy_seed(20260927)
	g.galaxy_seed = 20260927

	# ── At home, the sky is what it always was ──
	SM.set_sky_frame(Vector3.ZERO, 2026.0)
	var home: Array = SM.all_stars()
	var chunked_at_home := 0
	for s in home:
		if bool(s.get("chunked", false)): chunked_at_home += 1
	print("at home: %d stars resolved, %d of them generated" % [home.size(), chunked_at_home])
	check(home.size() > 5000, "the original field is intact: %d" % home.size())
	check(chunked_at_home == 0, "nothing generated inside the home cell: %d" % chunked_at_home)

	# ── Travel: the sky refills instead of emptying ──
	# What "refills" means is set by the density law, not by a fixed number of stars: the field
	# thins as Sol climbs out of the disc and is genuinely empty once it leaves the galaxy.  So
	# the contract tested here is that inside the galaxy the generator keeps the sky populated
	# out to the telescopes' reach, and that leaving the galaxy empties it down to the real
	# catalogue rather than to nothing.
	print("drift | density | resolved | generated | nearest star")
	var aim := Vector3(0, 0, 1)
	var reach: float = SM.observation_range()
	for d in [0.0, 200.0, 600.0, 2000.0, 20000.0]:
		ss.star_drift_ly = aim * d
		var here: Vector3 = ss.sol_position()
		SM.set_sky_frame(here, 2026.0)
		var list: Array = SM.all_stars()
		var gen := 0
		var nearest := 1.0e30
		var nearest_name := ""
		for s in list:
			if bool(s.get("chunked", false)): gen += 1
			var dist: float = (s["pos"] as Vector3).distance_to(here)
			if dist < nearest:
				nearest = dist
				nearest_name = str(s["name"])
		var dens: float = SM.galactic_density(here)
		print("%.0f ly | %.4f | %d | %d | %s at %.2f ly" % [d, dens, list.size(), gen, nearest_name, nearest])
		if dens > 0.005:
			# Inside the disc: the generator has to keep up with the density law.
			var ball: float = 4.0 / 3.0 * PI * pow(reach, 3.0)
			var expect: float = dens * SM.STARS_PER_LY3_PER_DENSITY * ball * load("res://star_chunks.gd").SAMPLE
			check(float(list.size()) > 0.25 * expect,
				"the sky keeps up with the density law at %.0f ly: %d resolved, %.0f expected" % [
					d, list.size(), expect])
			check(nearest < reach * 0.25,
				"there is something well inside the telescopes' reach at %.0f ly: %.2f" % [d, nearest])
			if d > 0.0:
				check(gen > 0, "the generator is what refills it at %.0f ly" % d)
		else:
			# Outside the galaxy the sky SHOULD be empty.  The catalogue is still there, because
			# those stars are real and bright, and that is the floor the map never drops below.
			check(list.size() >= SM.STARS.size(),
				"leaving the galaxy leaves the catalogue standing: %d" % list.size())

	# ── A generated star is addressable, and its distance is live ──
	ss.star_drift_ly = aim * 2000.0
	SM.set_sky_frame(ss.sol_position(), 2026.0)
	var sample := ""
	for s in SM.all_stars():
		if bool(s.get("chunked", false)):
			sample = str(s["name"]); break
	check(sample != "", "found a generated star to address")
	var looked: Dictionary = g._star_lookup(sample)
	check(not looked.is_empty(), "it can be looked up by name: %s" % sample)
	if not looked.is_empty():
		var d_live: float = g._star_distance_ly(sample)
		var d_geo: float = (looked["pos"] as Vector3).distance_to(ss.sol_position())
		check(absf(d_live - d_geo) < 1.0e-4, "and its distance is measured from Sol now: %.3f vs %.3f" % [d_live, d_geo])
		print("addressed %s at %.2f ly" % [sample, d_live])

	# ── Returning restores the same sky ──
	ss.star_drift_ly = aim * 2000.0
	SM.set_sky_frame(ss.sol_position(), 2026.0)
	var first: Array = SM.all_stars().duplicate()
	ss.star_drift_ly = Vector3.ZERO
	SM.set_sky_frame(ss.sol_position(), 2026.0)
	var _away: Array = SM.all_stars()
	ss.star_drift_ly = aim * 2000.0
	SM.set_sky_frame(ss.sol_position(), 2026.0)
	var again: Array = SM.all_stars()
	check(again.size() == first.size(), "the same place gives the same sky: %d vs %d" % [again.size(), first.size()])
	ss.reset_star()
	SM.set_sky_frame(Vector3.ZERO, 2026.0)
	print("FAILS: ", fails)
	quit()
