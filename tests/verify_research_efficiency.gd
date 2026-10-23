extends SceneTree

## Research is the BUDGET times an efficiency, and the two kinds of thinker have different ones.
##
## This replaced a single "research_speed" boost that multiplied the civilisation's whole compute
## pool.  That was wrong twice over: a better transistor made human beings think faster, and the
## extra thinking went to forecasting and every other simulation as well as to the tree, so a
## research technology silently improved asteroid prediction.
##
## A machine starts worse than a person — a data centre is a very fast idiot — and machine
## learning is the line that closes the gap and then passes it.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _sci(g: Node) -> float:
	g._mark_prod_dirty()
	return float(g._get_total_production().get("science", 0.0))

func _run() -> void:
	seed(20260927)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(40): await process_frame
	var g: Node = current_scene
	var rt: Node = root.get_node("ResearchTree")

	# ── The old boost is gone from the tree entirely ──
	for n: ResearchNode in rt.nodes.values():
		check(not (n.boosts as Dictionary).has("research_speed"),
			"%s no longer grants research_speed" % n.id)

	# ── Two efficiencies, and a machine starts the worse scientist ──
	check(is_equal_approx(g.human_research_efficiency(), g.HUMAN_RESEARCH_EFFICIENCY),
		"a fresh run starts at the base human efficiency")
	check(is_equal_approx(g.ai_research_efficiency(), g.AI_RESEARCH_EFFICIENCY),
		"and the base machine one")
	check(g.ai_research_efficiency() < g.human_research_efficiency(),
		"a machine is worse per FLOP to begin with: %.2f vs %.2f" % [
			g.ai_research_efficiency(), g.human_research_efficiency()])

	# ── Compute itself is no longer inflated by a research technology ──
	# This is the bug the change was for: the old boost grew the pool, so it reached the
	# forecast simulations too.
	var ai_before: float = g.pool_compute("ai")
	var human_before: float = g.pool_compute("human")
	for id: String in ["integrated_circuits", "semiconductor_manufacturing",
			"microprocessors", "high_performance_computing"]:
		rt.force_unlock(id)
	g._mark_prod_dirty()
	check(is_equal_approx(g.pool_compute("human"), human_before),
		"researching the compute lane does not make people think faster")
	check(is_equal_approx(g.pool_compute("ai"), ai_before),
		"nor inflate the machine pool")
	check(g.ai_research_efficiency() > g.AI_RESEARCH_EFFICIENCY,
		"it makes machine research more efficient instead: %.2f" % g.ai_research_efficiency())

	# A forecast budget is untouched by a research technology.
	rt.force_unlock(g.FORECAST_RESEARCH)
	for pool: String in g.COMPUTE_POOLS:
		g._on_compute_alloc_changed("asteroid", pool, 1.0)
	var horizon_before: float = g.forecast_equilibrium_years("asteroid")
	rt.force_unlock("automated_science_systems")
	g._mark_prod_dirty()
	check(absf(g.forecast_equilibrium_years("asteroid") - horizon_before) < 1.0e-6,
		"and a research technology no longer improves asteroid prediction")

	# ── Machine learning tiers, each raising machine efficiency ──
	var ml: ResearchNode = rt.get_research_node("machine_learning_systems")
	check(ml.max_level > 1, "machine learning has tiers: %d" % ml.max_level)
	check(float((ml.boosts as Dictionary).get("ai_research_efficiency", 0.0)) > 0.0,
		"and each raises machine research efficiency")
	check(not (ml.boosts as Dictionary).has("human_research_efficiency"),
		"and not the human one")
	var seq: Array = []
	var crossed_at: int = -1
	var human_at_start: float = g.human_research_efficiency()
	for lv in range(1, ml.max_level + 1):
		rt.force_unlock("machine_learning_systems")
		seq.append(g.ai_research_efficiency())
		if crossed_at < 0 and g.ai_research_efficiency() > human_at_start:
			crossed_at = lv
	check(ml.level == ml.max_level, "all its passes can be taken: %d" % ml.level)
	for i in range(1, seq.size()):
		check(float(seq[i]) > float(seq[i - 1]),
			"pass %d is better than the one before: %s" % [i + 1, str(seq)])
	check(crossed_at > 0,
		"machines overtake people somewhere on that line, at pass %d" % crossed_at)
	check(is_equal_approx(g.human_research_efficiency(), human_at_start),
		"without touching what a person is worth")

	# ── The efficiency multiplies the BUDGET, and only the research budget ──
	g._init_compute_alloc()        # everything on the tree
	g._mark_prod_dirty()
	var all_sci: float = _sci(g)
	check(all_sci > 0.0, "the tree produces science")

	# Same total compute, moved from the machines to the people: with a machine now the better
	# scientist, that must produce LESS.
	check(g.ai_research_efficiency() > g.human_research_efficiency(),
		"machines are the better scientist by now")
	for pool: String in g.COMPUTE_POOLS:
		g._on_compute_alloc_changed("asteroid", pool, 0.0)
	g._on_compute_alloc_changed("science", "human", 1.0)
	g._on_compute_alloc_changed("science", "ai", 0.0)
	g._on_compute_alloc_changed("asteroid", "ai", 1.0)
	var people_only: float = _sci(g)
	g._on_compute_alloc_changed("science", "human", 0.0)
	g._on_compute_alloc_changed("asteroid", "human", 1.0)
	g._on_compute_alloc_changed("science", "ai", 1.0)
	g._on_compute_alloc_changed("asteroid", "ai", 0.0)
	var machines_only: float = _sci(g)
	check(people_only > 0.0 and machines_only > 0.0, "both arrangements produce something")
	# Not a direct comparison of the two totals — the pools are different sizes — but each
	# pool's contribution has to carry its own efficiency, which this pins.
	var sh: Dictionary = g.compute_shares()
	var expect_ai: float = g.pool_compute("ai") * float((sh["science"] as Dictionary)["ai"]) \
		* g.ai_research_efficiency() * g.science_multiplier * g._policy_science_mult() \
		* (1.0 + rt.get_boost("science_production"))
	var expect_human: float = g.pool_compute("human") * float((sh["science"] as Dictionary)["human"]) \
		* g.human_research_efficiency() * g.science_multiplier * g._policy_science_mult() \
		* (1.0 + rt.get_boost("science_production"))
	check(absf(machines_only / maxf(expect_ai + expect_human, 1.0) - 1.0) < 1.0e-6,
		"science is each pool's share times its own efficiency: %s vs %s" % [
			Units.format_si(machines_only, ""), Units.format_si(expect_ai + expect_human, "")])

	# ── And the panel says so ──
	var p = g.sidebar.compute_panel
	g.sidebar.hide_all()
	p.show()
	g.refresh_compute_panel()
	for _i in range(6): await process_frame
	var st: Dictionary = g.compute_panel_state()
	check(absf(float(st["human_efficiency"]) - g.human_research_efficiency()) < 1.0e-9,
		"the panel is told the human efficiency")
	check(absf(float(st["ai_efficiency"]) - g.ai_research_efficiency()) < 1.0e-9,
		"and the machine one")
	check(p._human_lbl.text.contains("research x"),
		"and shows it: '%s'" % p._human_lbl.text)
	check(p._ai_lbl.text.contains("research x"), "for both pools")

	print("FAILS: %d" % fails)
	quit()
