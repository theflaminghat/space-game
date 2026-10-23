extends SceneTree

## A research node can be a line of work rather than a single discovery: taken more than once,
## each pass costing more and adding its boosts again.  Not every node — most are one discovery
## and stay that way — and the ones that are repeatable have different numbers of passes.
##
## The load-bearing part is that "known" is the LEVEL, not the state.  Taking a second pass puts
## the node back into RESEARCHING, and if the gates read the state then starting an upgrade would
## close everything the node had opened: boosts to zero, dependents re-locked, buildings gone
## from the build panel until it finished.

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
	var D = load("res://ResearchTreeData.gd")

	# ── Some nodes have levels, most do not, and the counts differ ──
	var repeatable: Array = []
	var single: Array = []
	for n: ResearchNode in rt.nodes.values():
		if n.is_repeatable():
			repeatable.append(n)
		else:
			single.append(n)
	check(repeatable.size() > 0, "some nodes are repeatable: %d" % repeatable.size())
	check(single.size() > repeatable.size(),
		"but most are single discoveries: %d of %d" % [single.size(), rt.nodes.size()])
	var counts: Dictionary = {}
	for n: ResearchNode in repeatable:
		counts[n.max_level] = true
		check(int(D.LEVELS.get(n.id, 0)) == n.max_level,
			"%s takes its count from the table" % n.id)
	check(counts.size() > 1,
		"and they do not all have the same number of levels: %s" % str(counts.keys()))
	for n: ResearchNode in single:
		check(n.max_level == 1, "%s is a one-shot node" % n.id)

	# ── A fresh tree starts at level zero ──
	var r: ResearchNode = rt.get_research_node("radio_astronomy")
	check(r != null and r.max_level == 5, "radio_astronomy has five levels")
	check(r.level == 0, "nothing is researched yet")
	check(not r.is_known(), "so it is not known")
	check(not rt.is_unlocked("radio_astronomy"), "and does not gate anything open")

	# ── Each pass costs more than the last, and adds its boost again ──
	var base: float = float(r.cost.get("science", 0.0))
	check(base > 0.0, "it costs science")
	for lv in range(1, r.max_level + 1):
		var want: float = base * pow(r.level_cost_growth, float(lv - 1))
		check(absf(float(r.cost_for_level(lv).get("science", 0.0)) / want - 1.0) < 1.0e-9,
			"pass %d costs %.1fx the first" % [lv, pow(r.level_cost_growth, float(lv - 1))])
	var per: float = float(r.boosts.get("detection", 0.0))
	check(per > 0.0, "and grants a boost")
	for lv in range(1, r.max_level + 1):
		rt.force_unlock("radio_astronomy")
		check(r.level == lv, "a pass banks a level: %d" % r.level)
		check(rt.is_unlocked("radio_astronomy"), "it is known from the first pass")
		check(absf(rt.get_boost("detection") - per * float(lv)) < 1.0e-9,
			"and the boost is %d passes' worth: %.2f" % [lv, rt.get_boost("detection")])
	check(not r.has_next_level(), "the last pass closes the line")
	rt.force_unlock("radio_astronomy")
	check(r.level == r.max_level, "and it cannot be pushed past its ceiling")
	check(not rt.can_queue("radio_astronomy"), "nor queued again")
	check(not rt.start_research("radio_astronomy"), "nor started again")

	# ── The bill shown is never a pass that does not exist ──
	check(absf(float(r.cost_shown().get("science", 0.0))
		/ float(r.cost_for_level(r.max_level).get("science", 0.0)) - 1.0) < 1.0e-9,
		"a maxed line shows its last pass, not a phantom next one")
	var t: ResearchNode = rt.get_research_node("transistors")
	rt.force_unlock("transistors")
	check(absf(float(t.cost_shown().get("science", 0.0))
		/ float(t.cost.get("science", 0.0)) - 1.0) < 1.0e-9,
		"and an ordinary unlocked node shows what it actually cost")

	# ── Researching an upgrade does not close the gate ──
	# This is the whole reason is_known() exists.
	var p: ResearchNode = rt.get_research_node("predictive_modeling")
	for n2: ResearchNode in rt.nodes.values():
		if n2.id != "predictive_modeling":
			rt.force_unlock(n2.id)
	rt.force_unlock("predictive_modeling")
	check(p.level == 1, "predictive_modeling is at its first pass")
	var boost_before: float = rt.get_boost("science_production")
	# Point some compute at a simulation, or the horizon is zero for want of a budget rather
	# than for want of the research — which would make the check below pass vacuously.
	for pool: String in g.COMPUTE_POOLS:
		g._on_compute_alloc_changed("asteroid", pool, 1.0)
	g._mark_prod_dirty()
	var horizon_before: float = g.forecast_equilibrium_years("asteroid")
	check(horizon_before > 0.0, "the funded simulation has a horizon to lose")
	rt.active_research = null
	check(rt.start_research("predictive_modeling"), "a second pass can be started")
	check(p.state == ResearchNode.State.RESEARCHING, "and it is running")
	check(rt.is_unlocked("predictive_modeling"),
		"the node stays KNOWN while the upgrade runs")
	check(absf(rt.get_boost("science_production") - boost_before) < 1.0e-9,
		"its boost is not withdrawn mid-upgrade")
	g._mark_prod_dirty()
	check(g.forecast_equilibrium_years("asteroid") > 0.0,
		"and what it gated stays open: forecasting still works")
	check(absf(g.forecast_equilibrium_years("asteroid") - horizon_before) < 1.0,
		"unchanged, in fact")

	# Cancelling an upgrade returns the node to what it already was, not to unresearched.
	rt.cancel_research()
	check(p.state == ResearchNode.State.UNLOCKED, "cancelling leaves it unlocked")
	check(p.level == 1, "with the pass it had")
	check(rt.is_unlocked("predictive_modeling"), "and still known")

	# ── A pass is paid for out of science, at the right price ──
	# tick() does nothing while the world clock is paused, which a headless run may well be.
	root.get_node("SolarSystem").paused = false
	root.get_node("SolarSystem").ui_paused = false
	rt.set_research_paused(false)
	rt.active_research = null
	p.level = 1
	p.state = ResearchNode.State.UNLOCKED
	rt.start_research("predictive_modeling")
	var need: float = float(p.cost_for_level(2).get("science", 0.0))
	check(absf(float(p.cost_for_next_level().get("science", 0.0)) / need - 1.0) < 1.0e-9,
		"the running pass is priced as pass two")
	rt.resources["science"] = need * 0.5
	rt.tick(0.0, 1.0)
	check(p.progress > 0.4 and p.progress < 0.6,
		"half the bill is half the progress: %.3f" % p.progress)
	rt.resources["science"] = need
	rt.tick(0.0, 1.0)
	check(p.level == 2, "paying the rest banks the second pass")
	check(p.state == ResearchNode.State.UNLOCKED, "and leaves it unlocked")

	# ── Levels survive a save, and an old save without them still loads ──
	var saved: Dictionary = rt.save_state()
	check(int((saved["nodes"] as Dictionary)["radio_astronomy"]["level"]) == 5,
		"the level is written to the save")
	rt.load_tree(D.build())
	check(rt.get_research_node("radio_astronomy").level == 0, "a reloaded tree is blank")
	rt.load_state(saved)
	check(rt.get_research_node("radio_astronomy").level == 5, "and the level comes back")
	check(absf(rt.get_boost("detection") - per * 5.0) < 1.0e-9,
		"with the boost it was worth")

	# A save from before levels existed records only the state.  Every unlocked node in it was
	# taken once, so it must load as a tree sitting at first pass — not as blind.
	var legacy: Dictionary = {"nodes": {}, "resources": {}, "active_research": "",
		"research_paused": false, "research_queue": []}
	(legacy["nodes"] as Dictionary)["radio_astronomy"] = {
		"state": ResearchNode.State.UNLOCKED, "progress": 1.0}
	(legacy["nodes"] as Dictionary)["transistors"] = {
		"state": ResearchNode.State.LOCKED, "progress": 0.0}
	rt.load_tree(D.build())
	rt.load_state(legacy)
	var lr: ResearchNode = rt.get_research_node("radio_astronomy")
	check(lr.level == 1, "an old save's unlocked node loads at its first pass: %d" % lr.level)
	check(rt.is_unlocked("radio_astronomy"), "and is known")
	check(lr.has_next_level(), "with the rest of the line still to take")
	check(rt.get_research_node("transistors").level == 0, "a locked node stays at zero")

	print("FAILS: %d" % fails)
	quit()
