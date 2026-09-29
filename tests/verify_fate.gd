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
	var sm = load("res://star_model.gd")

	# ── Thresholds ──
	check(float(sm.MIN_MASS_MSUN) == 0.08, "the floor is now the hydrogen-burning limit: %s" % sm.MIN_MASS_MSUN)
	for pair in [[1.0, "red giant"], [0.6, "red giant"], [0.5, "red giant"],
			[0.49, "no giant"], [0.2, "no giant"], [0.08, "extinguished"]]:
		ss.set_star_mass(pair[0])
		var txt: String = ss.sun_fate_text()
		check(txt.contains(pair[1]), "%s M☉ → %s (got '%s')" % [pair[0], pair[1], txt])
		print("%.2f M☉: %s | dates known: %s" % [ss.star_mass_msun, txt, ss.sun_fate_dates_known()])

	# ── Above the line, nothing changed ──
	ss.reset_star()
	check(int(g.sun_red_giant_year()) == 7590000000, "pristine red giant unchanged")
	check(int(g.sun_nebula_year()) == 8210000000, "pristine nebula unchanged")
	check(ss.sun_fate_dates_known(), "pristine star still has dates")
	check(is_equal_approx(ss.insolation_at_earth(2026.0), 1.0), "pristine insolation is 1.0")

	# ── Below helium ignition: the endgame stops existing ──
	ss.set_star_mass(0.45)
	check(is_inf(ss.sun_red_giant_year()), "no red-giant date: %s" % ss.sun_red_giant_year())
	check(is_inf(ss.sun_nebula_year()), "no nebula date")
	check(is_inf(ss.sun_warning_year()), "no HUD warning")
	check(not ss.sun_fate_dates_known(), "flagged as undated")
	# The photosphere never reaches anything: Earth survives every year the track used to kill it.
	for y in [7590000000, 8200000000, 8210000000, 100000000000]:
		check(g._get_sun_radius_au(y) < 0.05, "year %d: sun stays small (%s AU)" % [y, g._get_sun_radius_au(y)])
	check(ss.sun_luminosity_lsun(1.0e11) <= float(sm.WD_LUMINOSITY_LSUN) + 1e-12, "it ends as a fading dwarf")
	# The extinction check must not fire.
	g.year = 9000000000
	g._update_timescale()
	g.game_over = false
	g._check_extinction_events()
	check(not g.game_over, "the run does not end at the old nebula year")

	# ── Extinguished ──
	ss.set_star_mass(0.08)
	check(ss.sun_luminosity_lsun(2026.0) <= float(sm.BD_LUMINOSITY_LSUN) + 1e-12,
		"an extinguished sun puts out almost nothing: %s" % ss.sun_luminosity_lsun(2026.0))
	check(str(ss.sun_fate_text()).contains("extinguished"), "and says so")

	# ── Dimming costs the biosphere ──
	ss.reset_star()
	g.atmospheric_co2.erase("earth")
	var bright: float = g._climate_capacity_factor()
	ss.set_star_mass(0.75)
	var dim: float = g._climate_capacity_factor()
	ss.set_star_mass(0.08)
	var dark: float = g._climate_capacity_factor()
	print("climate factor: pristine %.3f, 25%% lifted %.3f, extinguished %.3f" % [bright, dim, dark])
	check(is_equal_approx(bright, 1.0), "pristine climate untouched")
	check(dim < bright, "a dimmer sun costs capacity")
	check(dark <= 0.06, "an extinguished sun collapses it")

	# ── The visuals follow the fate ──
	var sun: Node3D = g.get_node("WorldRoot/Planets/sun")
	ss.reset_star()
	sun._update_sun_appearance(2026)
	var s_bright: Vector3 = sun.scale
	ss.set_star_mass(0.2)
	sun._update_sun_appearance(2026)
	print("sun disc: pristine %s, 0.2 M☉ %s" % [s_bright.x, sun.scale.x])
	check(sun.scale.x < s_bright.x, "a red dwarf is drawn smaller")
	ss.reset_star()
	print("FAILS: ", fails)
	quit()
