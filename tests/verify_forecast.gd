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
	# A share set before the research exists must not quietly tax science for nothing.
	g.compute_forecast_share = 0.5
	g._mark_prod_dirty()
	check(is_equal_approx(g.forecast_compute_share(), 0.0),
		"a share set before the research is inert: %s" % str(g.forecast_compute_share()))
	g.compute_forecast_share = 0.0
	g._mark_prod_dirty()
	for n: ResearchNode in load("res://ResearchTreeData.gd").build():
		rt.force_unlock(str(n.id))
	check(is_equal_approx(g.forecast_horizon_years(), 0.0),
		"and still sees nothing until compute is assigned to it")

	# ── The split is the decision ──
	# Nothing is forecast for free: the horizon comes out of the same pool research draws on.
	g.compute_forecast_share = 0.0
	g._mark_prod_dirty()
	var science_all: float = float(g._get_total_production().get("science", 0.0))
	g.compute_forecast_share = 0.5
	g._mark_prod_dirty()
	var science_half: float = float(g._get_total_production().get("science", 0.0))
	check(g.forecast_horizon_years() > 0.0, "assigning compute opens a horizon")
	check(absf(science_half / maxf(science_all, 1.0) - 0.5) < 0.01,
		"and costs research exactly its share: %.3f" % (science_half / maxf(science_all, 1.0)))
	# Four times the assigned compute must buy twice the sight.
	g.compute_forecast_share = 0.1
	var h_low: float = g.forecast_horizon_years()
	g.compute_forecast_share = 0.4
	check(absf(g.forecast_horizon_years() / maxf(h_low, 1e-9) - 2.0) < 0.02,
		"four times the share, twice the horizon: %.3f" % (g.forecast_horizon_years() / h_low))
	check(g.forecast_compute_share() <= g.FORECAST_MAX_SHARE,
		"and it can never take all of the thinking")
	g.compute_forecast_share = 0.9
	g._mark_prod_dirty()
	check(float(g._get_total_production().get("science", 0.0)) > 0.0,
		"so research never stops entirely")
	g.compute_forecast_share = 0.5
	g._mark_prod_dirty()

	# ── The curve ──
	# Cost goes as the square of the horizon, so horizon goes as the square root of compute:
	# four times the compute must buy exactly twice the sight.
	var h0: float = g.forecast_horizon_years()
	# The cost inverts the horizon against the ASSIGNED compute, which is what buys it — not
	# the civilisation's whole pool.
	var c0: float = g.forecast_compute()
	check(is_equal_approx(g.forecast_cost_flops(h0) / c0, 1.0),
		"the cost function inverts the horizon: %s vs %s" % [
			str(g.forecast_cost_flops(h0)), str(c0)])
	check(is_equal_approx(g.forecast_cost_flops(2.0 * h0) / g.forecast_cost_flops(h0), 4.0),
		"twice the horizon costs four times the compute: %.3f" % (
			g.forecast_cost_flops(2.0 * h0) / g.forecast_cost_flops(h0)))
	check(g.forecast_horizon_years() <= g.FORECAST_LYAPUNOV_YEARS,
		"and it never exceeds the Lyapunov wall")

	# More compute really does buy more sight.
	var before_h: float = g.forecast_horizon_years()
	var arr: Array = g.planet_buildings.get("earth", [])
	for i in 2000:
		arr.append("AI Research Hub III")
	g.planet_buildings["earth"] = arr
	g._mark_prod_dirty(); g._recompute_production_cache()
	for _i in range(4): await process_frame
	check(g.forecast_horizon_years() > before_h * 1.5,
		"building compute extends the horizon: %.0f -> %.0f yr" % [
			before_h, g.forecast_horizon_years()])
	print("horizon %.0f yr on %s" % [g.forecast_horizon_years(),
		Units.format_si(g._get_compute_rate(), "FLOP/s")])

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
