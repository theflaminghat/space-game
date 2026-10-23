extends SceneTree

## A soak: drive the game hard and check the things that must never stop being true.
##
## Not a feature test. Everything here is an INVARIANT — a statement that holds whatever the
## player did — so a failure is a bug somewhere upstream rather than a changed decision.
##
##   nothing is NaN or infinite, anywhere a number is kept
##   no population exceeds the capacity that is supposed to cap it
##   the incremental production cache agrees with a full rebuild
##   a save round-trips to the same state, twice over

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()


## Every float reachable from a dictionary of numbers, checked for NaN/inf.
func _finite(d: Dictionary, where: String) -> void:
	for k in d:
		var v = d[k]
		if v is float:
			if is_nan(v) or is_inf(v):
				fails += 1
				print("FAIL: %s[%s] is %s" % [where, str(k), str(v)])
		elif v is Dictionary:
			_finite(v, "%s[%s]" % [where, str(k)])


func _run() -> void:
	seed(20261023)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var rt: Node = root.get_node("ResearchTree")
	var ss: Node = root.get_node("SolarSystem")

	# ── Build a civilisation worth stressing ──
	for n: ResearchNode in load("res://ResearchTreeData.gd").build():
		rt.force_unlock(str(n.id))
	for key: String in rt.resources:
		rt.resources[key] = 1.0e30
	g._mark_prod_dirty()
	g._recompute_production_cache()

	# Put real rosters on several worlds, switch some of it off, and settle some stars.
	var bnames: Array = []
	for b: Dictionary in load("res://buildings.gd").all():
		bnames.append(str(b["name"]))
	check(bnames.size() > 10, "there are buildings to put up: %d" % bnames.size())
	for p: String in ["earth", "luna", "mars", "mercury"]:
		if not g.planet_buildings.has(p):
			g.planet_buildings[p] = []
		for i in range(bnames.size()):
			(g.planet_buildings[p] as Array).append(str(bnames[i]))
		g._mark_prod_dirty(p)
	g.set_active_count("earth", str(bnames[0]), 1)
	g.set_active_count("mars", str(bnames[1]), 0)
	for i in range(6):
		var star: String = "Probe Star %d" % i
		g.colonized_stars.append(star)
		g._col_star_set[star] = true
		g._colony_year[star] = g.year - 500_000 * i
		g.world_pop[star] = 1.0e6 * float(i + 1)
		g._world_stock[star] = StockData.found("standard", [], StockData.baseline())
	g._recompute_production_cache()
	g._combine_production()

	# ── The incremental cache must agree with a full rebuild ──
	# This is the one that matters: _planet_contribution is cached per world behind a dirty set
	# and a roster-length backstop, so anything that changes a world's output WITHOUT saying so
	# shows up here and nowhere else.
	var fields: Array = ["compute", "minerals", "energy", "radiator", "beam_send", "beam_recv",
		"upkeep", "detection", "nuclear"]
	var incr: Dictionary = {}
	for f: String in fields:
		incr[f] = 0.0
	for p: String in g._prod_planet:
		for f: String in fields:
			incr[f] = float(incr[f]) + float((g._prod_planet[p] as Dictionary).get(f, 0.0))
	# Throw the whole cache away and do it again from nothing.
	g._prod_planet = {}
	g._prod_dirty_all = true
	g._recompute_production_cache()
	for f: String in fields:
		var full: float = 0.0
		for p: String in g._prod_planet:
			full += float((g._prod_planet[p] as Dictionary).get(f, 0.0))
		var want: float = float(incr[f])
		check(absf(full - want) <= absf(want) * 1.0e-9 + 1.0e-9,
			"the cached %s agrees with a full rebuild: %.6f vs %.6f" % [f, want, full])

	# ── Run a long way, checking as it goes ──
	# Fast mode, because that is the path a late run actually spends its time on and the one
	# the day loop's assumptions are least often tested against.
	var worst_over: float = 0.0
	var worst_world: String = ""
	for step in range(6):
		g._on_years_advanced_fast(2000)
		g._combine_production()
		_finite(rt.resources, "resources")
		_finite(g.stats, "stats")
		for w: String in g.world_pop:
			var pop: float = float(g.world_pop[w])
			if is_nan(pop) or is_inf(pop):
				fails += 1
				print("FAIL: world_pop[%s] is %s" % [w, str(pop)])
				break
			if pop < 0.0:
				fails += 1
				print("FAIL: world_pop[%s] went negative: %s" % [w, str(pop)])
				break
			# Capacity is a ceiling, not something growth merely tends toward.
			var k: float = g._world_capacity(w)
			if pop > k * 1.000001 + 1.0:
				var over: float = pop / maxf(k, 1.0)
				if over > worst_over:
					worst_over = over
					worst_world = "%s (%s people, capacity %s, year %d)" % [
						w, str(pop), str(k), g.year]
	check(worst_over == 0.0, "no world is over its capacity: worst was %.3fx on %s" % [
		worst_over, worst_world])
	check(float(g.stats.get("current_population", 0.0)) >= 0.0,
		"the headcount is not negative: %s" % str(g.stats.get("current_population")))

	# ── Stockpiles ──
	for p: String in g.compound_inventory:
		for c: String in (g.compound_inventory[p] as Dictionary):
			var v: float = float((g.compound_inventory[p] as Dictionary)[c])
			if is_nan(v) or is_inf(v) or v < 0.0:
				fails += 1
				print("FAIL: stockpile %s/%s is %s" % [p, c, str(v)])
				break

	# ── A save round-trips, and round-trips AGAIN to the same thing ──
	# Saving twice catches the half of a load bug that a single trip hides: a field that is
	# dropped on load looks identical to one that was never written.
	# Close a full population cycle first. stats.current_population is accumulated as deltas
	# and only re-summed when the POP_SLICES cycle closes, so a figure read mid-cycle lags any
	# population this harness set directly — which is a property of the test, not the game.
	for _c in range(g.POP_SLICES + 1):
		g._update_population(1.0)
	print("  stats.current_population before save: %s" % str(g.stats.get("current_population")))
	print("  _total_population() before save:       %s" % str(g._total_population()))
	g.save_game("user://saves/audit_a.json")
	g.load_game("user://saves/audit_a.json")
	print("  stats.current_population after load:   %s" % str(g.stats.get("current_population")))
	print("  _total_population() after load:        %s" % str(g._total_population()))
	g.save_game("user://saves/audit_b.json")
	print("  stats.current_population at 2nd save:  %s" % str(g.stats.get("current_population")))
	var fa := FileAccess.open("user://saves/audit_a.json", FileAccess.READ)
	var a: Dictionary = JSON.parse_string(fa.get_as_text())
	fa.close()
	var fb := FileAccess.open("user://saves/audit_b.json", FileAccess.READ)
	var b: Dictionary = JSON.parse_string(fb.get_as_text())
	fb.close()
	var drifted: Array = []
	for k: String in a:
		if not b.has(k):
			drifted.append("%s vanished" % k)
		elif JSON.stringify(a[k]) != JSON.stringify(b[k]):
			var sa: String = JSON.stringify(a[k])
			var sb: String = JSON.stringify(b[k])
			drifted.append("%s: %s… vs %s…" % [k, sa.substr(0, 60), sb.substr(0, 60)])
	for k: String in b:
		if not a.has(k):
			drifted.append("%s appeared" % k)
	check(drifted.is_empty(), "a save round-trips unchanged: %s" % str(drifted))

	print("FAILS: %d" % fails)
	quit()
