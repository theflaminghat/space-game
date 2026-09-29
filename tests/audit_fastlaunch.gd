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
	for _i in range(30): await process_frame
	var g: Node = current_scene

	g.active_launches.clear()
	g.planet_buildings["sun"] = []
	g.active_launches.append({
		"id": 9001, "mission": "Construction Station", "status": "active",
		"target": "sun", "origin": "earth", "structure": "Orbital Construction Station",
		"end_year": g.year + 3, "end_month": 0, "end_day": 1,
		"cargo": {}, "payload": 0,
	})
	# Exactly what fast mode does to the clock: whole years, month and day reset.
	g.year += 5
	g.month = 0
	g.day = 0
	g._on_years_advanced_fast(5)

	var active := 0
	for l in g.active_launches:
		if int(l.get("id", 0)) == 9001: active += 1
	check(active == 0, "launch still in flight after a fast-mode year jump")
	check((g.planet_buildings.get("sun", []) as Array).has("Orbital Construction Station"),
		"delivered structure joined the sun roster")
	print("FAILS: %d" % fails)
	quit()
