extends SceneTree

## Compute spent on medicine, and what it is worth.
##
## The epidemiology track buys two things and both of them are about the outbreak NOT happening:
## the year it is due, and surveillance that holds the odds down. Nothing anywhere touched the
## TOLL — so a civilisation could see the plague coming, cut its chances by two thirds, and then
## lose four fifths of everyone alive with no move available. The asteroid has a laser, the war
## has a treaty, the machines have alignment; the plague had a date.
##
## What is asserted here is the shape of the answer rather than its numbers: that it is a stock
## and not a slider position, that it saturates short of a cure, that it is the only term in the
## toll anybody paid for, and that what it delivers in the meantime is a share of what the TREE
## knows rather than a way around learning any of it.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(20261111)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(40): await process_frame
	var g: Node = current_scene
	var rt: Node = root.get_node("ResearchTree")

	# ── Gated on its own node, not on the forecast's ──
	#
	# The share-out used to have ONE gate over everything that was not the tree, because
	# everything that was not the tree was a forecast. Medicine arrives somewhere else entirely,
	# so a civilisation with bioinformatics and no predictive modelling has to be able to spend
	# on it — and the reverse.
	check(not rt.is_unlocked(g.MEDICINE_RESEARCH), "medicine starts locked")
	check(not rt.is_unlocked(g.FORECAST_RESEARCH), "and so does forecasting")
	for pool: String in g.COMPUTE_POOLS:
		g._on_compute_alloc_changed("medicine", pool, 1.0)
	g._mark_prod_dirty()
	var shares: Dictionary = g.compute_shares()
	check(is_equal_approx(float((shares["medicine"] as Dictionary)["human"]), 0.0),
		"a budget set before the research is inert: %f" % float(
			(shares["medicine"] as Dictionary)["human"]))
	check(is_equal_approx(g.cure_equilibrium(), 0.0), "and buys no capacity")

	# ── What it delivers is a PRODUCT, and the tree's knowledge is one of its factors ──
	#
	# Asserted here, where a 1945 civilisation has none of the medical branch — including the
	# node that gates this very track, which is one of them. However much capacity is standing,
	# a civilisation that knows no medicine has nothing to deliver.
	for id: String in g.MEDICAL_RESEARCH:
		check(not rt.is_unlocked(id), "%s is not researched yet" % id)
	check(is_equal_approx(g._curable_years(), 0.0),
		"with no medicine known there is nothing to deliver: %f" % g._curable_years())
	g._cure_capacity = 1.0
	var le_blind: float = g._life_expectancy()
	g._cure_capacity = 0.0
	check(is_equal_approx(g._life_expectancy(), le_blind),
		"so a full capacity buys no years at all: %f vs %f" % [g._life_expectancy(), le_blind])

	rt.force_unlock(g.MEDICINE_RESEARCH)
	check(not rt.is_unlocked(g.FORECAST_RESEARCH),
		"forecasting is still locked, so this is medicine's own gate")
	g._mark_prod_dirty()
	shares = g.compute_shares()
	check(float((shares["medicine"] as Dictionary)["human"]) > 0.0,
		"the medicine track is funded without any forecasting research: %f" % float(
			(shares["medicine"] as Dictionary)["human"]))
	check(float((shares["science"] as Dictionary)["human"]) >= 1.0 - g.FORECAST_MAX_SHARE - 1e-9,
		"and science keeps its floor all the same: %f" % float(
			(shares["science"] as Dictionary)["human"]))
	# The forecast tracks are still inert, pointed at or not: one gate each.
	for pool: String in g.COMPUTE_POOLS:
		g._on_compute_alloc_changed("asteroid", pool, 1.0)
	g._mark_prod_dirty()
	shares = g.compute_shares()
	check(is_equal_approx(float((shares["asteroid"] as Dictionary)["human"]), 0.0),
		"a forecast track is still inert: %f" % float((shares["asteroid"] as Dictionary)["human"]))
	# And an inert track takes nothing away from the one that works: asteroid and medicine carry
	# the same weight here, so if the locked one were still in the division medicine would be
	# left with half of what it should have.
	var med_share: float = float((shares["medicine"] as Dictionary)["human"])
	var sci_share: float = float((shares["science"] as Dictionary)["human"])
	check(absf(med_share - (1.0 - sci_share)) < 1e-6,
		"medicine has everything not left with the tree: %f of %f" % [
			med_share, 1.0 - sci_share])

	# ── A stock, not a slider position ──
	#
	# Nobody answers an engineered pathogen in the week it arrives, and the schedule is visible:
	# an effect that could be bought on the spot could be bought the year before a forecast
	# outbreak and sold the year after it.
	g._cure_capacity = 0.0
	var settles: float = g.cure_equilibrium()
	check(settles > 0.05, "a full budget settles somewhere worth having: %f" % settles)

	# ── Saturating: there is no budget that buys a cure ──
	#
	# Asserted against the curve rather than against this civilisation's budget, because a 1945
	# budget is nowhere near the ceiling and a run's compute climbs five orders of magnitude
	# past it. Anything linear is either nothing at the start or everything by the middle.
	var half: float = g.MEDICINE_HALF_FLOPS
	check(absf(g.cure_capacity_at(half) - 0.5) < 1e-6,
		"the half-point is halfway: %f" % g.cure_capacity_at(half))
	check(g.cure_capacity_at(half * 1.0e6) < 1.0,
		"a million times that is still short of a cure: %.6f" % g.cure_capacity_at(half * 1.0e6))
	check(g.cure_capacity_at(half * 2.0) - g.cure_capacity_at(half)
			< g.cure_capacity_at(half) * 0.5,
		"and doubling a budget buys less than the first half of it did: %f then %f" % [
			g.cure_capacity_at(half), g.cure_capacity_at(half * 2.0)])
	check(settles < 1.0, "so what this one settles at is short of one: %f" % settles)
	g._advance_cure_capacity(1.0)
	var after_day: float = g._cure_capacity
	check(after_day > 0.0, "a day of it is not nothing: %f" % after_day)
	check(after_day < settles * 0.01,
		"but it is nowhere near what the budget settles at: %f of %f" % [after_day, settles])
	# Decades to build. 25 years is one e-folding, so a little under two thirds of the way.
	g._cure_capacity = 0.0
	g._advance_cure_capacity(25.0 * 365.25)
	check(absf(g._cure_capacity - settles * 0.632) < settles * 0.02,
		"a working lifetime of it gets most of the way: %f of %f" % [g._cure_capacity, settles])
	# A fast-forward slice can be millions of years wide. It has to LAND on the equilibrium.
	g._advance_cure_capacity(1.0e9)
	check(absf(g._cure_capacity - settles) < 1.0e-6,
		"and a deep fast-forward lands on it rather than past it: %f vs %f" % [
			g._cure_capacity, settles])

	# ── And it drains ──
	for pool: String in g.COMPUTE_POOLS:
		g._on_compute_alloc_changed("medicine", pool, 0.0)
	g._mark_prod_dirty()
	check(is_equal_approx(g.cure_equilibrium(), 0.0), "an unfunded track settles at nothing")
	var held: float = g._cure_capacity
	g._advance_cure_capacity(25.0 * 365.25)
	check(g._cure_capacity < held * 0.4,
		"what is not paid for goes stale: %f -> %f" % [held, g._cure_capacity])

	# ── The only term in the toll that anybody chose ──
	#
	# Measured by running the same outbreak twice. The kill roll is a pure function of the year,
	# so the two runs differ in nothing but what was standing when it arrived.
	for pool: String in g.COMPUTE_POOLS:
		g._on_compute_alloc_changed("medicine", pool, 1.0)
	g._mark_prod_dirty()
	var before: Dictionary = g.world_pop.duplicate(true)
	var pop0: float = 0.0
	for w: String in before:
		pop0 += float(before[w])
	check(pop0 > 0.0, "there is somebody to lose: %f" % pop0)

	g._cure_capacity = 0.0
	g._trigger_pandemic()
	var bare: float = pop0 - _alive(g)
	g.world_pop = before.duplicate(true)

	g._cure_capacity = 1.0
	check(absf(g.cure_toll_cut() - g.MEDICINE_TOLL_MAX) < 1e-6,
		"full capacity answers the most it ever can: %f" % g.cure_toll_cut())
	g._trigger_pandemic()
	var answered: float = pop0 - _alive(g)
	g.world_pop = before.duplicate(true)

	check(bare > 0.0, "the bare outbreak kills: %s" % str(bare))
	check(answered < bare, "medicine takes something off it: %s vs %s" % [answered, bare])
	check(absf(answered - bare * (1.0 - g.MEDICINE_TOLL_MAX)) <= maxf(bare * 0.01, 2.0),
		"and takes off exactly what it claims — %d%%: %s vs %s" % [
			int(round(g.MEDICINE_TOLL_MAX * 100.0)), answered, bare])
	check(answered > 0.0,
		"a plague is never answered away entirely: %s left of %s" % [answered, bare])

	# ── And what it is worth rises with what the tree knows ──
	#
	# A multiplier on the research rather than a bonus beside it: compute searches the space the
	# tree opened, so it can never be a way around opening it.
	rt.force_unlock("modern_medicine")
	g._cure_capacity = 0.0          # the toll section above left it standing
	var le_bare: float = g._life_expectancy()
	g._cure_capacity = 1.0
	var le_cured: float = g._life_expectancy()
	check(le_cured > le_bare, "once medicine knows something, the budget delivers it: %f vs %f" % [
		le_cured, le_bare])
	var want: float = g.MEDICINE_LE_SHARE * g._curable_years() * g._pop_weighted_life
	check(absf((le_cured - le_bare) - want) < 0.05,
		"by its share of what is known: %f vs %f" % [le_cured - le_bare, want])

	# Uploaded minds are not a disease anybody cures, and their 5000 years would swamp the page.
	var known: float = g._curable_years()
	rt.force_unlock("post_biological_transition")
	check(absf(g._curable_years() - known) < 1e-6,
		"the upload is left out of it: %f vs %f" % [g._curable_years(), known])

	# ── The warning says where BOTH decisions stand ──
	#
	# A plague card that gave only the odds was half a warning: whether it happens and what it
	# costs come out of two different budgets, and the second one was invisible.
	for n: ResearchNode in load("res://ResearchTreeData.gd").build():
		rt.force_unlock(str(n.id))
	# Far enough ahead to reach a scheduled outbreak: plagues are 800-2500 years apart and a
	# 1945 budget settles at a horizon of thirty. The frontier is a stock, so it is set here
	# rather than integrated — how it got there is _advance_foresight's business, not this
	# test's — and the machines are pushed to make the odds worth reporting.
	g._ai_capability = 1.0
	g.foresight_frontier["pandemic"] = float(g.year) + 60000.0
	g._cure_capacity = 0.0
	var cards: Array = _plague_cards(g)
	check(cards.size() > 0, "the forecast carries a plague card: %d" % cards.size())
	for c: Dictionary in cards:
		check(str(c.get("desc", "")).contains("Nothing is standing against it"),
			"with nothing standing it says so: %s" % str(c.get("desc", "")).right(60))
	g._cure_capacity = 1.0
	cards = _plague_cards(g)
	check(cards.size() > 0, "and still carries one: %d" % cards.size())
	for c: Dictionary in cards:
		check(str(c.get("desc", "")).contains("answer %d%%" % int(round(
				g.cure_toll_cut() * 100.0))),
			"and with medicine standing it says how much: %s" % str(c.get("desc", "")).right(60))

	print("FAILS: %d" % fails)
	quit()


## Every plague warning the forecast is currently carrying.
func _plague_cards(g: Node) -> Array:
	var out: Array = []
	for e: Dictionary in g.forecast_events():
		if str(e.get("kind", "")) == "pandemic":
			out.append(e)
	return out


## Everybody alive on the worlds a plague reaches.
func _alive(g: Node) -> float:
	var n: float = 0.0
	for w: String in g.world_pop:
		n += float(g.world_pop[w])
	return n
