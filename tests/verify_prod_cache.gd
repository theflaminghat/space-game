extends SceneTree

## The production rebuild sums each world ONCE and keeps the answer.
##
## It is the most-called expensive function in the game — a build, a demolish, a switch, a
## research unlock or a panel read all force it, several times a second under automation — and
## it used to walk every standing structure twice: once to tally the roster and once again,
## inside _compute_storage_caps, asking each of thirteen thousand buildings a question about its
## TYPE.  That second walk alone was 81 % of it.
##
## Both fixes trade correctness for speed if they are wrong, so what matters is the equivalence:
## a rebuild that reuses cached worlds must produce exactly what rebuilding all of them does.
## That is checked here against every figure the rebuild publishes, not a sample of them, and
## against each way the cache can go stale:
##
##   - a world named dirty, the others reused
##   - a roster mutated with nothing marked dirty at all (the length backstop)
##   - the solar factor moving under a cache that was not told (star shades)
##   - a world ceasing to exist

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

## Every figure the rebuild publishes, flattened so two rebuilds can be compared outright.
##
## Compared EXACTLY, not to a tolerance.  Both paths add the same per-world terms in the same
## order — they both walk planet_buildings — so equal inputs have to give bit-identical floats,
## and a tolerance would only hide a real difference.
func _snapshot(g: Node) -> Array:
	var parts: Array = []
	for f: String in ["_bld_compute", "_bld_minerals", "_bld_energy", "_bld_radiator",
			"_bld_beam_send", "_bld_beam_recv", "_bld_upkeep", "_cached_detection",
			"_cached_nuclear", "_off_world_energy", "_live_fossil_energy"]:
		parts.append([f, float(g.get(f))])
	for f: String in ["_cached_storage_caps", "_cached_planet_stats", "_cached_planet_counts",
			"_cached_planet_built_mc", "_cached_planet_built_farm", "_cached_planet_hab",
			"_cached_planet_built_ranch", "_cached_planet_fuel", "_cached_planet_plants"]:
		parts.append([f, _stable(g.get(f))])
	return parts

## The same value with every dictionary turned into key-sorted pairs, so two dictionaries that
## are equal compare equal whatever order they were filled in.
func _stable(v: Variant) -> Variant:
	if v is Dictionary:
		var keys: Array = (v as Dictionary).keys()
		keys.sort()
		var out: Array = []
		for k in keys:
			out.append([str(k), _stable((v as Dictionary)[k])])
		return out
	if v is Array:
		var out2: Array = []
		for e in v:
			out2.append(_stable(e))
		return out2
	return v

## What a full rebuild of every world produces at the current state.
func _from_scratch(g: Node) -> Array:
	g._prod_planet.clear()
	g._mark_prod_dirty()
	g._recompute_production_cache()
	return _snapshot(g)

func _run() -> void:
	seed(20261008)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var ss: Node = root.get_node("SolarSystem")

	# A roster worth caching, spread over several worlds — one world cannot show the difference,
	# because the one world that moved IS every world.
	var seed_roster: Array = (g.planet_buildings["earth"] as Array).duplicate()
	var worlds: Array = ["earth", "mars", "luna", "europa"]
	for w: String in worlds:
		if not g.planet_buildings.has(w):
			g.planet_buildings[w] = []
	for i in range(seed_roster.size()):
		(g.planet_buildings[str(worlds[i % worlds.size()])] as Array).append(seed_roster[i])
	g._prod_planet.clear()
	g._mark_prod_dirty()
	g._recompute_production_cache()
	var total: int = 0
	for p: String in g.planet_buildings:
		total += (g.planet_buildings[p] as Array).size()
	print("%d buildings over %d worlds" % [total, (g.planet_buildings.keys() as Array).size()])
	check(total > 1000, "there is a roster worth caching")
	check((g.planet_buildings.keys() as Array).size() >= 4, "and more than one world to cache")

	# ── Storage caps are the same worked per kind as per structure ──
	# This is the 81 %: the figure must not have moved, only the way it is reached.
	var want: Dictionary = {"minerals": 0.0, "energy": 0.0}
	for r: String in want:
		want[r] += g._PLANET_BASE_STORAGE[r]
	for _p: String in g.colonized_planets:
		for r: String in want:
			want[r] += g._PLANET_BASE_STORAGE[r]
	for p: String in g.planet_buildings:
		for b in g.planet_buildings[p]:
			var stor: Dictionary = (g._bdef_cache.get(str(b), {}) as Dictionary).get("storage", {})
			for r: String in stor:
				if want.has(r):
					want[r] += float(stor[r])
	var got: Dictionary = g._compute_storage_caps()
	for r: String in want:
		check(absf(float(got[r]) - float(want[r])) <= absf(float(want[r])) * 1.0e-9,
			"storage cap %s matches a per-structure walk: %s vs %s" % [r, got[r], want[r]])

	# ── Naming one world gives what rebuilding all of them gives ──
	# The equivalence everything else rests on.  Checked after a real change, not a no-op, so a
	# cache that simply ignored the change would not pass.
	(g.planet_buildings["mars"] as Array).append("Mine")
	g._mark_prod_dirty("mars")
	g._recompute_production_cache()
	var incremental: Array = _snapshot(g)
	check(incremental == _from_scratch(g),
		"one world named dirty == every world rebuilt")

	# A switch is the same question about active_buildings rather than the roster.
	g.set_active_count("mars", "Mine", 0)
	g._recompute_production_cache()
	var after_switch: Array = _snapshot(g)
	check(after_switch != incremental, "switching a building off changes the sums")
	check(after_switch == _from_scratch(g), "and a named switch == every world rebuilt")

	# ── A roster mutated with nothing marked dirty is still caught ──
	# The backstop that makes naming a world an optimisation rather than a trap: the rosters are
	# mutated in sixteen places, and a scheme where missing one gave a WRONG number instead of a
	# slower rebuild would not be worth having.
	(g.planet_buildings["luna"] as Array).append("Nuclear Plant")
	g._prod_dirty = true                       # a rebuild is due; nobody said which world
	g._prod_dirty_all = false
	g._prod_dirty_set.clear()
	g._recompute_production_cache()
	check(_snapshot(g) == _from_scratch(g),
		"an unannounced roster change is caught by the length check")

	# ── The solar factor moving is caught too ──
	# Collectors are rated against the light that reaches them, and that moves for reasons that
	# are not any world's roster: the Sun brightens on its own, and star shades dim every world
	# at once.  Without this they would stay rated against the light that used to arrive.
	#
	# There have to be collectors for the question to mean anything, and the 1945 roster has
	# none — so some are built, on a world that is NOT the one named dirty afterwards.
	for _i in range(40):
		(g.planet_buildings["luna"] as Array).append("Solar Farm")
	g._prod_planet.clear()
	g._mark_prod_dirty()
	g._recompute_production_cache()
	var before_shade: float = float(g.get("_bld_energy"))

	# Shades, built the way the player builds them.  set_star_shade cannot be used directly:
	# _sync_star_shades re-derives the fraction from what is standing at the end of every
	# rebuild, so a hand-set figure is overwritten by the very call under test.
	if not g.planet_buildings.has("sun"):
		g.planet_buildings["sun"] = []
	for _i in range(6000):
		(g.planet_buildings["sun"] as Array).append("Sunshade Constellation")
	# The first rebuild only notices the shades are STANDING: _sync_star_shades runs at the end
	# of it, so the factor the collectors were rated against this pass was the old one.  That
	# one-rebuild lag is how it has always worked and is not what is under test here.
	g._mark_prod_dirty("sun")
	g._recompute_production_cache()
	check(ss.insolation_mult() < 1.0, "the shades are intercepting light: %s" % ss.insolation_mult())
	# Now the test proper, and the strongest form of it: a rebuild is due and NO world is named
	# at all.  Only the solar-factor check can catch this, and every world's collectors have to
	# come out re-rated anyway.
	g._prod_dirty = true
	g._prod_dirty_all = false
	g._prod_dirty_set.clear()
	g._recompute_production_cache()
	var shaded: Array = _snapshot(g)
	check(float(g.get("_bld_energy")) < before_shade,
		"shading the star cuts the grid: %s -> %s" % [before_shade, g.get("_bld_energy")])
	check(shaded == _from_scratch(g), "and the shaded sums == every world rebuilt")
	(g.planet_buildings["sun"] as Array).clear()
	g._mark_prod_dirty()
	g._recompute_production_cache()
	g._mark_prod_dirty()
	g._recompute_production_cache()
	check(absf(float(g.get("_bld_energy")) - before_shade)
			<= absf(before_shade) * 1.0e-9,
		"taking them down puts it back: %s vs %s" % [g.get("_bld_energy"), before_shade])

	# But a factor that has barely moved does not justify re-walking every roster.  This is the
	# Sun's own brightening, which is about a percent per hundred million years: over a century
	# of play it is far inside the tolerance and must cost nothing.
	g._mark_prod_dirty()
	g._recompute_production_cache()
	var pinned: Dictionary = {}
	for p: String in g._prod_planet:
		pinned[p] = g._prod_planet[p]
	g.year += 100
	g._prod_dirty = true
	g._prod_dirty_all = false
	g._prod_dirty_set.clear()
	g._recompute_production_cache()
	var reused: int = 0
	for p: String in pinned:
		if is_same(pinned[p], g._prod_planet.get(p)):
			reused += 1
	check(reused == pinned.size(),
		"a century of the Sun's brightening reuses every world: %d of %d" % [
			reused, pinned.size()])

	# A hundred million years of it does not.
	g.year += 200_000_000
	g._prod_dirty = true
	g._prod_dirty_all = false
	g._prod_dirty_set.clear()
	g._recompute_production_cache()
	var still: int = 0
	for p: String in pinned:
		if is_same(pinned[p], g._prod_planet.get(p)):
			still += 1
	check(still == 0, "two hundred million years of it re-rates all of them: %d still cached" % still)
	check(_snapshot(g) == _from_scratch(g), "and the re-rated sums are right")
	g.year -= 200_000_100

	# ── A world that stops existing leaves nothing behind ──
	g._mark_prod_dirty()
	g._recompute_production_cache()
	check(g._prod_planet.has("europa"), "europa is cached while it exists")
	g.planet_buildings.erase("europa")
	g._mark_prod_dirty()
	g._recompute_production_cache()
	check(not g._prod_planet.has("europa"), "and its record goes when it does")
	check(_snapshot(g) == _from_scratch(g), "the sums after a world is lost are right too")

	# ── The cached stats are shared, not copied, so nobody may write to them ──
	# _cached_planet_stats and _cached_planet_counts hand out the cache's own dictionaries.  Every
	# reader is read-only today; this says so, so a future writer finds out here rather than
	# through a drifting figure.
	var st: Dictionary = g._cached_planet_stats["earth"]
	check(is_same(st, (g._prod_planet["earth"] as Dictionary)["st"]),
		"the published stats ARE the cached record")
	check(is_same(g._cached_planet_counts["earth"],
			(g._prod_planet["earth"] as Dictionary)["tally"]),
		"and so are the published counts")

	print("FAILS: %d" % fails)
	quit()
