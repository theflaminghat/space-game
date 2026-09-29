extends SceneTree
var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	# Pin the global RNG BEFORE the scene loads.  Game._ready sets galaxy_seed = randi(), so
	# without this the generated sky — and every polity, colony and war seeded off it — differs
	# from one run of this test to the next, and the counts asserted below are a coin toss.
	seed(20260927)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(25): await process_frame
	var SC = load("res://star_chunks.gd")
	var SM = load("res://StarMapPanel.gd")
	var seed_a := 12345
	var year := 2026.0

	# ── 1. Determinism ──
	var idx := Vector3i(7, -3, 11)
	var a: Array = SC.generate_chunk(idx, seed_a, year)
	var b: Array = SC.generate_chunk(idx, seed_a, year)
	check(a.size() == b.size(), "same chunk, same count")
	var same := true
	for i in range(a.size()):
		if str(a[i]["name"]) != str(b[i]["name"]) or not (a[i]["pos"] as Vector3).is_equal_approx(b[i]["pos"]):
			same = false
	check(same, "same chunk, identical stars")
	check(SC.generate_chunk(idx, seed_a + 1, year).size() != a.size()
		or str(SC.generate_chunk(idx, seed_a + 1, year)[0]["name"]) != str(a[0]["name"]) if a.size() > 0 else true,
		"a different galaxy seed gives a different chunk")
	# Order of visiting must not matter: generate neighbours first, then re-ask.
	for d in [Vector3i(1,0,0), Vector3i(0,1,0), Vector3i(-1,0,1)]:
		SC.generate_chunk(idx + d, seed_a, year)
	var c: Array = SC.generate_chunk(idx, seed_a, year)
	check(c.size() == a.size(), "visiting neighbours first changes nothing")

	# ── 2. Density: the field must obey the canon law ──
	# Sample chunks at a range of galactic positions and compare counts to the law.
	print("chunk | density | expected | actual (20 chunks)")
	var worst_ratio := 0.0
	for probe in [[Vector3(0, 0, 0), "Sol"], [Vector3(2000, 0, 0), "2 kly out"],
			[Vector3(0, 0, 3000), "3 kly up"], [Vector3(-8000, 0, 0), "inward"]]:
		var base: Vector3i = SC.chunk_of(probe[0] as Vector3)
		var total := 0
		var expect := 0.0
		for n in range(20):
			var ci: Vector3i = base + Vector3i(n, 0, 0)
			total += SC.generate_chunk(ci, seed_a, year).size()
			var dens: float = SM.galactic_density(SC.chunk_centre(ci))
			expect += dens * SM.STARS_PER_LY3_PER_DENSITY * pow(SC.CHUNK_LY, 3.0) * SC.SAMPLE
		print("%s | %.4f | %.1f | %d" % [probe[1], SM.galactic_density(SC.chunk_centre(base)), expect, total])
		if expect > 20.0:     # only judge where the sample is big enough to mean anything
			worst_ratio = maxf(worst_ratio, absf(float(total) / expect - 1.0))
	check(worst_ratio < 0.35, "counts track the density law (worst deviation %.0f%%)" % (worst_ratio * 100.0))

	# ── 3. A big sample: mean density and the type mix ──
	var n_stars := 0
	var vol := 0.0
	var types := {}
	var civs := 0
	var standing := 0
	var visible := 0
	for x in range(-6, 6):
		for y in range(-3, 3):
			for z in range(-6, 6):
				var ci := Vector3i(x, y, z)
				# cached_chunk is the whole population, born or not; generate_chunk is the
				# subset visible at a given year.  The 6:4 split is a property of the former
				# — asking the latter at 2026 gets only the stars that already exist, which
				# is what it is for.
				var all_: Array = SC.cached_chunk(ci, seed_a)
				var st: Array = SC.generate_chunk(ci, seed_a, year)
				vol += pow(SC.CHUNK_LY, 3.0)
				n_stars += all_.size()
				visible += st.size()
				for s in all_:
					types[str(s["spectral"])] = int(types.get(str(s["spectral"]), 0)) + 1
					if bool(s.get("civ", false)): civs += 1
					if not s.has("born"): standing += 1
	print("sampled %s ly^3: %d stars ever, %d standing, %d visible at %d, %d civilisations" % [
		Units.format_si(vol, ""), n_stars, standing, visible, int(year), civs])
	print("type mix: ", types)
	var m_share: float = float(types.get("M", 0)) / maxf(float(n_stars), 1.0)
	check(absf(m_share - 0.74) < 0.06, "M dwarfs dominate as the table says: %.2f" % m_share)
	# Civilisation frequency: the setup's 6-per-home-ball rate.
	var civ_expected: float = vol * float(SC.CIV_PER_LY3)
	print("civilisations: %d seen, %.1f expected at the canon rate" % [civs, civ_expected])
	check(absf(float(civs) - civ_expected) <= maxf(3.0 * sqrt(maxf(civ_expected, 1.0)), 2.0),
		"civilisation frequency matches the setup screen")
	# The standing:future split, over every star the volume will ever hold.
	var future: int = n_stars - standing
	check(absf(float(standing) / maxf(float(n_stars), 1.0) - 0.6) < 0.12,
		"standing:future split is about 6:4 (%d:%d)" % [standing, future])
	# And the filter: at the present year the visible set is the standing stars, give or take
	# the handful of future ones whose birth year happens to fall in the past already.
	check(visible >= standing and visible < standing + maxi(20, standing / 50),
		"the year filter shows the standing stars and no more (%d visible vs %d standing)" % [
			visible, standing])

	# ── 4. Time: a chunk only ever gains stars ──
	var young: Array = SC.generate_chunk(idx, seed_a, 2026.0)
	var old: Array = SC.generate_chunk(idx, seed_a, 1.0e12)
	var young_names := {}
	for s in young: young_names[str(s["name"])] = true
	var kept := true
	var old_names := {}
	for s in old: old_names[str(s["name"])] = true
	for nm in young_names:
		if not old_names.has(nm): kept = false
	check(kept, "every star present now is still present in deep time")
	check(old.size() >= young.size(), "and the sky only fills up: %d → %d" % [young.size(), old.size()])

	# ── 5. The home catalogue is left alone ──
	var inner: Array = SC.stars_near(Vector3.ZERO, 15.0, seed_a, year)
	check(inner.is_empty(), "nothing invented inside the real catalogue's sphere: %d" % inner.size())

	# ── 6. stars_near agrees with the chunks it covers ──
	var near: Array = SC.stars_near(Vector3(500, 0, 0), 120.0, seed_a, year)
	var ok := true
	for s in near:
		if (s["pos"] as Vector3).distance_to(Vector3(500, 0, 0)) > 120.0: ok = false
	check(ok, "stars_near returns only stars inside the radius")
	check(near.size() > 0, "and finds some: %d" % near.size())
	print("FAILS: ", fails)
	quit()
