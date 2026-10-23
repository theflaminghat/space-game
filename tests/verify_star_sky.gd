extends SceneTree

## The night sky is built from the game's own star catalogue, not from a photograph.
##
## It used to be a PanoramaSkyMaterial over my_image.png — a fixed picture of somebody else's
## sky, which said nothing true about where the player is and could not change when the Sun
## moved.  The background behind it is now a flat dark blue, and the stars are one quad per
## catalogued star in its real direction, sized and coloured by what that star actually is.
##
## Everything here checks star_points(), which is the whole derivation with nothing in it that
## touches the rendering server.  That separation is not stylistic: under --headless the
## renderer is a dummy and MultiMesh instance data is not stored, so reading transforms back out
## of the shell reports identity for every one of them however correct the input was.

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
	for _i in range(45): await process_frame
	var g: Node = current_scene

	# ── The background is a flat dark blue, with no sky resource at all ──
	var env: Environment = g.get_node("WorldRoot/WorldEnvironment").environment
	check(env != null, "the world has an environment")
	check(env.background_mode == Environment.BG_COLOR,
		"it draws a flat colour, not a sky: mode %d" % env.background_mode)
	check(env.sky == null, "and carries no panorama resource")
	var bg: Color = env.background_color
	check(bg.b > bg.r and bg.b > bg.g, "the colour is blue: %s" % str(bg))
	check(bg.v < 0.25, "and dark: value %.3f" % bg.v)

	# ── The shell exists and holds one point per catalogued star ──
	var sky: Node3D = g.get_node_or_null("WorldRoot/StarSky")
	check(sky != null, "the star sky was hung on the world")
	var shell := sky.get_node_or_null("StarShell") as MultiMeshInstance3D
	check(shell != null, "with a shell to draw into")
	var cat: Array = g.sidebar.star_map.all_stars()
	var pts: Array = sky.star_points()
	check(cat.size() > 100, "the catalogue has stars in it: %d" % cat.size())
	check(pts.size() == cat.size(), "one point per star: %d of %d" % [pts.size(), cat.size()])
	check(shell.multimesh.instance_count == pts.size(),
		"and the shell was given all of them: %d" % shell.multimesh.instance_count)

	# ── Every point is a direction on the shell ──
	for p: Dictionary in pts:
		var d: Vector3 = p["dir"]
		if absf(d.length() - 1.0) > 1.0e-4:
			check(false, "a direction was not normalised: %s" % str(d))
			break
	var sz_lo: float = INF
	var sz_hi: float = 0.0
	for p: Dictionary in pts:
		sz_lo = minf(sz_lo, float(p["size"]))
		sz_hi = maxf(sz_hi, float(p["size"]))
	check(sz_lo >= sky.SIZE_MIN - 1.0e-4 and sz_hi <= sky.SIZE_MAX + 1.0e-4,
		"sizes stay inside the ramp: %.1f .. %.1f" % [sz_lo, sz_hi])
	check(sz_hi > sz_lo, "and the ramp is actually used")

	# ── Stars point where the catalogue says they are ──
	# A real named star is the sharpest check available: its direction on the shell must be the
	# direction of its catalogued position, or the sky and the star map disagree about the sky.
	var checked := 0
	for name: String in ["Sirius", "Procyon", "Alpha Centauri A", "Barnard's Star"]:
		var want := Vector3.ZERO
		for s: Dictionary in cat:
			if str(s["name"]) == name:
				want = (s["pos"] as Vector3).normalized()
		if want == Vector3.ZERO:
			continue
		var best: float = -2.0
		for p: Dictionary in pts:
			best = maxf(best, (p["dir"] as Vector3).dot(want))
		check(best > 0.99999, "%s is drawn in its catalogued direction" % name)
		checked += 1
	check(checked >= 3, "several named stars were available to check: %d" % checked)

	# ── Brighter stars are bigger ──
	# Sirius is 8.7 ly away and twice the Sun's mass; Proxima is 4.2 ly away and a tenth of it.
	# Nearer, so the naive answer is "Proxima" — only luminosity makes Sirius the brighter.
	var by_name: Dictionary = {}
	var idx := 0
	for s: Dictionary in cat:
		if (s["pos"] as Vector3).length() < 1.0e-4:
			continue
		by_name[str(s["name"])] = idx
		idx += 1
	if by_name.has("Sirius") and by_name.has("Proxima Centauri"):
		var sirius: Dictionary = pts[int(by_name["Sirius"])]
		var prox: Dictionary = pts[int(by_name["Proxima Centauri"])]
		check(float(sirius["size"]) > float(prox["size"]),
			"Sirius outshines Proxima despite being twice as far: %.1f vs %.1f" % [
				float(sirius["size"]), float(prox["size"])])
		check(float(sirius["color"].a) > float(prox["color"].a),
			"and is drawn brighter")

	# ── Colour comes from the star, not from a palette ──
	if by_name.has("Sirius"):
		var sc: Color = pts[int(by_name["Sirius"])]["color"]
		check(sc.b >= sc.r, "Sirius is drawn blue-white: %s" % str(sc))
	if by_name.has("Barnard's Star"):
		var bc: Color = pts[int(by_name["Barnard's Star"])]["color"]
		check(bc.r > bc.b, "and an M dwarf red: %s" % str(bc))

	# ── Sol is not in its own sky ──
	# The catalogue is Sol-relative, so the Sun sits at the origin and has no direction at all;
	# it is drawn as a body, not as a point of light.
	var at_origin := 0
	for p: Dictionary in pts:
		if (p["dir"] as Vector3).length() < 0.5:
			at_origin += 1
	check(at_origin == 0, "nothing is drawn at the observer's own position")
	check(pts.size() == cat.size(), "and the count is unaffected, because Sol is not catalogued")

	# ── The camera can see that far ──
	var cam := sky.get_viewport().get_camera_3d()
	if cam != null:
		for _i in range(4): await process_frame
		check(cam.far >= sky.SKY_RADIUS,
			"the far plane reaches the shell: %.0f vs %.0f" % [cam.far, sky.SKY_RADIUS])

	print("FAILS: %d" % fails)
	quit()
