extends SceneTree

## Every body that has an orbit line actually gets a mesh built into it.
##
## This exists because a rename broke it and nothing caught it.  `_create_orbit_line` builds an
## ArrayMesh in a local and assigns it to _orbit_line.mesh; renaming the local to dodge a
## shadowed-property warning also rewrote that assignment, so the line was built and then
## handed to a property that does not exist.  It failed at RUNTIME, in a function no test
## called, so the file parsed and the whole suite passed.

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
	for _i in range(60): await process_frame
	var g: Node = current_scene

	var with_line: int = 0
	for p in g.get_node("WorldRoot/Planets").get_children():
		if not (p is MeshInstance3D):
			continue
		var line = p.get("_orbit_line")
		if line == null:
			continue        # the Sun has no orbit to draw
		with_line += 1
		check(line is MeshInstance3D, "%s's orbit line is a mesh instance" % p.name)
		check(line.mesh != null, "%s's orbit line has a mesh at all" % p.name)
		if line.mesh != null:
			check(line.mesh.get_surface_count() > 0,
				"%s's orbit line mesh has geometry" % p.name)
			check(line.mesh.surface_get_material(0) != null,
				"%s's orbit line is given its material" % p.name)
			var aabb: AABB = line.mesh.get_aabb()
			check(aabb.size.length() > 0.0,
				"%s's orbit line encloses something: %s" % [p.name, str(aabb.size)])
	check(with_line >= 8, "most of the system has orbit lines: %d" % with_line)

	# The asteroid belt draws its rocks through per-instance transforms built the same way, in
	# a function whose local was renamed in the same batch.
	var belt = g.get_node_or_null("WorldRoot/Planets/asteroid_belt")
	check(belt != null, "the asteroid belt is in the scene")
	if belt != null:
		var drawn: int = 0
		for mm in belt.get("_multimeshes"):
			if mm != null and mm.instance_count > 0:
				drawn += mm.instance_count
		check(drawn > 0, "and has rocks placed in it: %d" % drawn)

	print("FAILS: %d" % fails)
	quit()
