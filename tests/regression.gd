extends SceneTree
## Consolidated regression for the stellar-engineering work and the bodies' surface maps.
## The sun figures are the values captured from the ORIGINAL fixed-curve implementation, before
## any of it existed: a pristine star must still reproduce them exactly.
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
	var rt: Node = root.get_node("ResearchTree")
	var sm = load("res://star_model.gd")

	# ── 1. A pristine star reproduces the original curve ──
	var golden := [
		[1945, 1.0000001854, 0.004650000452], [2026, 1.0000001931, 0.004650000471],
		[1000000, 1.0000953147, 0.0046502325], [1000000000, 1.1, 0.0048825],
		[5400000000, 1.8, 0.006975], [7000000000, 50.0, 0.0465],
		[7500000000, 1200.0, 0.465], [7590000000, 2700.0, 0.99975],
		[7591000000, 50.0, 0.0465], [7700000000, 60.0, 0.05115],
		[8000000000, 500.0, 0.2325], [8200000000, 4000.0, 0.7905],
		[8210000000, 3000.0, 99999.0], [9000000000, 3000.0, 99999.0]]
	var worst := 0.0
	for row in golden:
		var y: int = int(row[0])
		var l: float = ss.sun_luminosity_lsun(float(y))
		var r: float = g._get_sun_radius_au(y)
		worst = maxf(worst, absf(l - float(row[1])) / maxf(float(row[1]), 1e-9))
		worst = maxf(worst, absf(r - float(row[2])) / maxf(float(row[2]), 1e-9))
	print("worst drift vs the original curve: ", worst)
	check(worst < 1.0e-6, "pristine curve unchanged (worst %s)" % worst)
	check(int(g.sun_red_giant_year()) == 7590000000, "red giant 7.59 B")
	check(int(g.sun_nebula_year()) == 8210000000, "nebula 8.21 B")
	check(is_equal_approx(g._climate_capacity_factor(), 1.0), "pristine climate 1.0")

	# ── 2. Fates ──
	for row in [[1.0, "red giant", true], [0.49, "no giant", false], [0.08, "extinguished", false]]:
		ss.set_star_mass(float(row[0]))
		check(str(ss.sun_fate_text()).contains(str(row[1])), "%s → %s" % [row[0], row[1]])
		check(ss.sun_fate_dates_known() == bool(row[2]), "%s dates known = %s" % [row[0], row[2]])
	ss.set_star_mass(0.45)
	check(is_inf(ss.sun_nebula_year()) and g._get_sun_radius_au(8210000000) < 0.05,
		"no giant phase means no engulfment and no nebula")
	ss.reset_star()

	# ── 3. Lifting, husbandry, shades ──
	g.planet_buildings["sun"] = []
	for i in range(100): g.planet_buildings["sun"].append("Star Lifter")
	g._mark_prod_dirty(); g._recompute_production_cache()
	rt.resources["energy"] = 1.0e38
	g._run_star_lifters(365.25 * 1000.0)
	check(ss.star_lifted_msun > 0.0, "lifting removes mass")
	check(float(g._planet_inv("sun").get("H2", 0.0)) > 0.0, "and banks hydrogen")
	ss.reset_star()
	g.planet_buildings["sun"] = []
	for i in range(100): g.planet_buildings["sun"].append("Core Mixing Array")
	g._mark_prod_dirty(); g._recompute_production_cache()
	g.year = 1000000; g._update_timescale()
	rt.resources["energy"] = 1.0e38
	g._run_husbandry(365.25 * 1000.0)
	check(ss.star_age_offset_years > 0.0, "husbandry winds the clock back")
	ss.reset_star()
	g.planet_buildings["sun"] = []
	for i in range(200): g.planet_buildings["sun"].append("Sunshade Constellation")
	g._mark_prod_dirty(); g._recompute_production_cache()
	check(ss.star_shade_fraction > 0.0, "shades register from the roster")

	# ── 4. The new station and its carriers ──
	var def: Dictionary = g._find_building_def("Orbital Construction Station")
	check(float(def.get("mc_capacity", 0.0)) > 0.0 and (def.get("allowed_types", []) as Array).has("star"),
		"the station exists and flies")
	# Storage in solar orbit is the Orbital Vault's job.  The Matter Depot is silos and bunkers
	# and was deliberately put back on the ground when the vault took over the flying role.
	check((g._find_building_def("Orbital Vault").get("allowed_types", []) as Array).has("star"),
		"the vault may fly")
	check(not (g._find_building_def("Matter Depot").get("allowed_types", []) as Array).has("star"),
		"the depot stays on the ground")
	var carriers := 0
	for m in load("res://missions.gd").MISSION_TYPES:
		if str(m.get("structure", "")) != "": carriers += 1
	check(carriers == 2, "both carriers exist")

	# ── 5. Surface maps ──
	# Every body carries the same 4096x2048 BPTC map all the time.  There used to be a runtime
	# LOD swap that rasterised the SELECTED body at twice its imported size; once the imports
	# themselves went to 4096 and VRAM compression, that swap was rasterising 8192x4096 and
	# handing the renderer 171 MB of UNCOMPRESSED texture per click — more than every map in
	# the game costs together — so it was removed rather than retuned.
	g.planet_buildings["sun"] = []
	g._mark_prod_dirty()
	g.select_planet("earth")
	for _i in range(120): await process_frame
	var earth: MeshInstance3D = g.get_node("WorldRoot/Planets/earth")
	var tex = (earth.material_override as ShaderMaterial).get_shader_parameter("albedo_tex")
	check(tex.get_width() == 4096, "the map is 4096 wide: %d" % tex.get_width())
	check(tex.get_image().get_format() == Image.FORMAT_BPTC_RGBA,
		"and VRAM-compressed: format %d" % tex.get_image().get_format())
	# Selecting must not swap it for anything.
	g.select_planet("mars")
	for _i in range(120): await process_frame
	var after = (earth.material_override as ShaderMaterial).get_shader_parameter("albedo_tex")
	check(after == tex, "selection does not swap the map any more")
	var mars_tex = ((g.get_node("WorldRoot/Planets/mars") as MeshInstance3D).material_override \
		as ShaderMaterial).get_shader_parameter("albedo_tex")
	check(mars_tex.get_width() == 4096, "the newly selected body is 4096 too: %d" % mars_tex.get_width())
	ss.reset_star()
	print("FAILS: ", fails)
	quit()
