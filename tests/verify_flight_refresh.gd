extends SceneTree

## Sending a flight must not make the star map rebuild itself sixty times a second.
##
## Two separate things turned a launch into a frame-rate drop, and both are about work done to
## animate something that animates itself.
##
## ── The cache was thrown away on every push ──
##
## set_interstellar_state bumped _marked_version unconditionally, and _marked_version is in the
## star cache's key — including the view-independent half, which holds _rel(pos) for every star
## and is the expensive one. The UI pass calls refresh_star_map() while the map is open, so from
## the moment anything was in flight the whole pass was rebuilt every frame. The version exists
## to catch a colony lost and another gained between two frames, which the counts miss; it does
## not need to fire when nothing moved.
##
## ── The push itself is a full rebuild ──
##
## refresh_star_map() duplicates the whole colony roster, walks every cluster in the patch and
## rebuilds the faction map. None of that is what makes a flight move: each track carries its
## own window and the panel places it from _flight_year, which its own _process advances. So it
## is throttled, like the panel refresh beside it.
##
## Measured at 4 000 colonies: 80.8 ms a frame before, 15.0 ms after.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(20261101)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var SM = load("res://StarMapPanel.gd")
	g.sidebar.show_star_map()
	var m: Control = g.sidebar.star_map
	for _i in range(5): await process_frame


	# ── A push that changes nothing does not invalidate the cache ──
	g.refresh_star_map()
	var v0: int = m._marked_version
	for _i in range(10):
		g.refresh_star_map()
	check(m._marked_version == v0,
		"ten pushes with nothing changed move the version not at all: %d -> %d" % [
			v0, m._marked_version])

	# ── A push that DOES change something still invalidates it ──
	# The whole point: this is not "stop bumping", it is "bump when it means something".
	var star: String = ""
	for s in SM.all_stars():
		star = str((s as Dictionary)["name"])
		break
	g._colonize_star(star)
	g.refresh_star_map()
	check(m._marked_version > v0,
		"settling a star does move it: %d -> %d" % [v0, m._marked_version])
	var v1: int = m._marked_version
	g.refresh_star_map()
	check(m._marked_version == v1, "and then settles again: %d" % m._marked_version)

	# A faction appearing moves it too, by the same rule.
	m.set_star_factions({"Somewhere": "aggressive"})
	var v2: int = m._marked_version
	check(v2 > v1, "a faction appearing moves it: %d -> %d" % [v1, v2])
	m.set_star_factions({"Somewhere": "aggressive"})
	check(m._marked_version == v2, "pushing the same factions again does not: %d" % m._marked_version)
	# And a SWAP at equal size, which is the case the version exists for and the counts miss.
	m.set_star_factions({"Elsewhere": "aggressive"})
	check(m._marked_version > v2,
		"a swap at equal size still moves it — this is why the version exists: %d -> %d" % [
			v2, m._marked_version])


	# ── The push is throttled, not per frame ──
	check(g.get("_star_map_accum") != null, "the star map has its own accumulator")
	check(g._star_map_accum != g._ui_refresh_accum or g._star_map_accum == 0.0,
		"separate from the panel refresh's, so the two rebuilds need not land together")
	var src: String = FileAccess.get_file_as_string("res://Game.gd")
	var at: int = src.find("_star_map_accum += delta")
	check(at > 0, "the accumulator is driven from the frame delta")
	var window: String = src.substr(at, 240)
	check(window.find("UI_REFRESH_SEC") >= 0,
		"and gated on the refresh interval rather than firing every frame")
	check(window.find("refresh_star_map()") >= 0, "with the rebuild behind the gate")


	# ── A flight still moves between pushes ──
	# This is the reason the throttle is safe: the panel places each track from its own clock.
	m._missions = [{
		"target": star, "progress": 0.0, "kind": "colony", "mission": "colonize",
		"start_year": 1000.0, "end_year": 3000.0,
		"accel_time_frac": 0.5, "accel_dist_frac": 0.5,
	}]
	m._flight_year = 1500.0
	var p0: float = m._track_progress(m._missions[0])
	m._flight_year = 2500.0
	var p1: float = m._track_progress(m._missions[0])
	check(p1 > p0,
		"a track advances on the panel's own clock, with no push at all: %f -> %f" % [p0, p1])

	print("FAILS: %d" % fails)
	quit()
