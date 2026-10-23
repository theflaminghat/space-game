extends SceneTree

## Compute buys foresight, and the foresight has to be TRUE.
##
## The forecast is only honest because the catastrophe schedule is deterministic: every scheduled
## year, target and severity is a pure function of (galaxy_seed, tag, year).  So the test that
## matters is not that the forecast returns something plausible — it is that running the
## simulation forward produces exactly what the forecast said it would.

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
	for _i in range(40): await process_frame
	var g: Node = current_scene
	var rt: Node = root.get_node("ResearchTree")

	# ── Gated on the research ──
	check(not rt.is_unlocked(g.FORECAST_RESEARCH), "forecasting starts locked")
	check(is_equal_approx(g.forecast_horizon_years(), 0.0), "and sees nothing until it is known")
	# A budget set before the research exists must not quietly tax science for nothing.
	g._on_compute_alloc_changed("asteroid", "human", 1.0)
	g._on_compute_alloc_changed("pandemic", "ai", 1.0)
	var sci_locked: float = float(g._get_total_production().get("science", 0.0))
	g._init_compute_alloc()
	g._mark_prod_dirty()
	check(is_equal_approx(sci_locked, float(g._get_total_production().get("science", 0.0))),
		"a budget set before the research is inert")
	for n: ResearchNode in load("res://ResearchTreeData.gd").build():
		rt.force_unlock(str(n.id))
	check(is_equal_approx(g.forecast_horizon_years(), 0.0),
		"and still sees nothing until compute is assigned to it")

	# ── The budget is the decision ──
	# Nothing is forecast for free: a simulation's compute comes out of the same pools research
	# draws on, so pointing thinking at the future costs exactly its share of the tree.
	g._init_compute_alloc()
	g._mark_prod_dirty()
	var science_all: float = float(g._get_total_production().get("science", 0.0))
	for pool: String in g.COMPUTE_POOLS:
		g._on_compute_alloc_changed("asteroid", pool, 1.0)
		g._on_compute_alloc_changed("science", pool, 1.0)
	var science_half: float = float(g._get_total_production().get("science", 0.0))
	check(absf(science_half / maxf(science_all, 1.0) - 0.5) < 0.01,
		"an even split costs research exactly half: %.3f" % (
			science_half / maxf(science_all, 1.0)))
	# Science's floor holds however the weights are set.
	for pool: String in g.COMPUTE_POOLS:
		g._on_compute_alloc_changed("science", pool, 0.0)
	check(float(g._get_total_production().get("science", 0.0)) > 0.0,
		"research never stops entirely")
	var shares: Dictionary = g.compute_shares()
	check(float((shares["science"] as Dictionary)["human"]) >= 1.0 - g.FORECAST_MAX_SHARE - 1e-9,
		"science keeps its floor of every pool")

	# ── Each simulation is budgeted on its own ──
	g._init_compute_alloc()
	for pool: String in g.COMPUTE_POOLS:
		g._on_compute_alloc_changed("asteroid", pool, 1.0)
	g._mark_prod_dirty()
	check(g.forecast_equilibrium_years("asteroid") > 0.0, "the funded simulation has a horizon")
	check(is_equal_approx(g.forecast_equilibrium_years("pandemic"), 0.0),
		"an unfunded one has none")
	check(is_equal_approx(g.forecast_equilibrium_years("nuclear"), 0.0), "nor does the third")

	# ── The curve: four times the compute, twice the sight ──
	g._init_compute_alloc()
	for pool: String in g.COMPUTE_POOLS:
		g._on_compute_alloc_changed("asteroid", pool, 1.0)
		g._on_compute_alloc_changed("science", pool, 9.0)
	var h_low: float = g.forecast_equilibrium_years("asteroid")
	var c_low: float = g.track_compute("asteroid")
	g._init_compute_alloc()
	for pool: String in g.COMPUTE_POOLS:
		g._on_compute_alloc_changed("asteroid", pool, 4.0)
		g._on_compute_alloc_changed("science", pool, 6.0)
	var h_high: float = g.forecast_equilibrium_years("asteroid")
	var c_high: float = g.track_compute("asteroid")
	check(absf(c_high / maxf(c_low, 1e-9) - 4.0) < 0.02,
		"four times the weight is four times the compute: %.3f" % (c_high / c_low))
	check(absf(h_high / maxf(h_low, 1e-9) - 2.0) < 0.02,
		"and buys exactly twice the sight: %.3f" % (h_high / h_low))
	check(is_equal_approx(g.forecast_cost_flops(h_high) / c_high, 1.0),
		"the cost function inverts the horizon")
	check(is_equal_approx(
		g.forecast_cost_flops(2.0 * h_high) / g.forecast_cost_flops(h_high), 4.0),
		"twice the horizon costs four times the compute")

	# ── Foresight accumulates, and closes when it is not paid for ──
	g.foresight_frontier["asteroid"] = float(g.year)
	var settle: float = g.forecast_equilibrium_years("asteroid")
	var walk := func(years: int) -> void:
		for _y in range(years):
			for _d in range(365):
				g._advance_foresight(1.0)
			g.year += 1
	var h_seq: Array = []
	for _step in range(4):
		walk.call(1)
		h_seq.append(g.forecast_horizon_years("asteroid"))
	check(float(h_seq[0]) > 0.0, "a funded simulation starts seeing")
	check(float(h_seq[1]) > float(h_seq[0]) and float(h_seq[2]) > float(h_seq[1]),
		"and sees further the longer it is funded: %s" % str(h_seq))
	check(float(h_seq[3]) <= settle + 1e-6,
		"never past where that budget settles: %.3f vs %.3f" % [float(h_seq[3]), settle])
	# The frontier is absolute, so cutting the budget closes the horizon at a year per year as
	# the present walks towards it — nothing has to take it away.  The weights are zeroed
	# directly rather than through _init_compute_alloc, which also resets the frontiers (it is
	# what a NEW RUN does) and would throw away the very stock under test.
	for pool: String in g.COMPUTE_POOLS:
		g._on_compute_alloc_changed("asteroid", pool, 0.0)
	g._mark_prod_dirty()
	var h_cut: float = g.forecast_horizon_years("asteroid")
	walk.call(3)
	check(absf((h_cut - g.forecast_horizon_years("asteroid")) - 3.0) < 1e-6,
		"an unpaid horizon closes a year per year: %.4f" % (
			h_cut - g.forecast_horizon_years("asteroid")))

	# ── More machines really do buy more sight ──
	g._init_compute_alloc()
	for pool: String in g.COMPUTE_POOLS:
		g._on_compute_alloc_changed("asteroid", pool, 1.0)
	var before_h: float = g.forecast_equilibrium_years("asteroid")
	var arr: Array = g.planet_buildings.get("earth", [])
	for i in 2000:
		arr.append("AI Research Hub III")
	g.planet_buildings["earth"] = arr
	g._mark_prod_dirty(); g._recompute_production_cache()
	for _i in range(4): await process_frame
	check(g.forecast_equilibrium_years("asteroid") > before_h * 1.5,
		"building compute extends the horizon: %.0f -> %.0f yr" % [
			before_h, g.forecast_equilibrium_years("asteroid")])
	check(g.forecast_equilibrium_years("asteroid") <= g.FORECAST_LYAPUNOV_YEARS,
		"and it never exceeds the Lyapunov wall")
	# Open every frontier wide for the prediction checks below, which are about whether the
	# forecast is TRUE rather than about how far it reaches.
	for t: String in g.FORECAST_TRACKS:
		g.foresight_frontier[t] = float(g.year) + g.forecast_equilibrium_years("asteroid")

	# ── Nothing is predicted that cannot be seen ──
	# Impacts are scheduled 60 000-400 000 years apart, so at this horizon the next one is
	# beyond sight and must NOT appear.  Foresight that reported it anyway would be free.
	check(int(g._next_impact_year) > g.year + int(g.forecast_horizon_years()),
		"the next impact is beyond the horizon in a fresh run")
	for e in g.forecast_events():
		check(str(e["kind"]) != "asteroid", "so no impact is claimed")

	# ── The forecast is TRUE ──
	# Put one inside the horizon — which is the state any run is in after its first impact —
	# and check the prediction against what the simulation actually does at that year.
	# Several worlds to hit, or "the forecast named the right one" is vacuous: a fresh run has
	# only Earth, and any roll at all picks it.
	for w in ["mars", "venus", "luna", "mercury"]:
		if not g.colonized_planets.has(w):
			g.colonized_planets.append(w)
			g.world_pop[w] = 1.0e6
	check(g._impact_targets().size() >= 4,
		"there are several worlds an impact could strike: %d" % g._impact_targets().size())
	g._next_impact_year = g.year + 300
	var predicted: Dictionary = {}
	for e in g.forecast_events():
		if str(e["kind"]) == "asteroid":
			predicted = e
			break
	check(not predicted.is_empty(), "an impact is predicted within the horizon")
	if not predicted.is_empty():
		var py: int = int(predicted["year"])
		check(py >= g.year, "and it is in the future: %d vs %d" % [py, g.year])
		# What the forecast SAID — read off the card, not recomputed here.  Recomputing it would
		# only prove the rolls agree with themselves; the claim under test is that the forecast
		# reports them.
		var want_tgt: String = str(predicted.get("target", ""))
		var want_kill: float = float(predicted.get("kill_frac", -1.0))
		check(want_tgt != "" and want_kill >= 0.0, "the card carries its figures as data")
		# What the simulation does when it gets there.
		g.year = py
		g._impact_cooldown_ms = 0
		g._pending_threat = {}
		g._check_asteroid_impact()
		var got: Dictionary = g._pending_threat
		check(not got.is_empty(), "the impact actually happens in the predicted year")
		check(str(got.get("target", "")) == want_tgt,
			"on the predicted world: %s vs %s" % [str(got.get("target", "")), want_tgt])
		check(is_equal_approx(float(got.get("kill_frac", -1.0)), want_kill),
			"with the predicted toll: %s vs %s" % [str(got.get("kill_frac", -1.0)), str(want_kill)])
		check(str(predicted["title"]).contains(g._body_display_name(want_tgt)),
			"and the card named it: %s" % str(predicted["title"]))
		print("predicted year %d, %s, %.1f%% — and that is what happened" % [
			py, want_tgt, want_kill * 100.0])
		root.get_node("/root/SolarSystem").ui_paused = false
		g.get_tree().paused = false

	# ── Asking the forecast must not change the world ──
	# nuclear_probability() reads the arms-strain ratchet; it must never advance it.
	var strain: float = g._arms_strain
	var pop: float = g._total_population()
	for _i in range(5):
		g.forecast_events()
		g.nuclear_probability()
		g.pandemic_probability()
	check(is_equal_approx(g._arms_strain, strain), "forecasting does not ratchet the standoff")
	check(is_equal_approx(g._total_population(), pop), "and kills nobody")

	# ── Everything predicted is inside the horizon, and sorted ──
	var evs: Array = g.forecast_events()
	var limit: int = g.year + int(g.forecast_horizon_years())
	var last: int = -9223372036854775807
	for e in evs:
		check(int(e["year"]) <= limit, "%s is within the horizon" % str(e["title"]))
		check(int(e["year"]) >= last, "events come in order")
		last = int(e["year"])
		check(bool(e.get("forecast", false)) and str(e.get("category", "")) == "warning",
			"and is tagged as a projection")

	print("FAILS: %d" % fails)
	quit()
