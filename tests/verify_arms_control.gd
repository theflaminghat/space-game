extends SceneTree

## Arms Control: the fuel cycle, and the only lever on the standoff.
##
## ── What the war model already had ──
##
## `means = military_spending + _nuclear_proliferation()`, where proliferation is the latent
## arsenal of the civilian fission fleet — the fissile material and the expertise a tense world
## can turn to arms. Which left a hole the politics page could not reach: a civilisation that
## built out reactors for their clean, dense energy carried war risk it could not lower at any
## military budget, short of tearing the fleet down. And `_arms_strain`, the standoff's
## compounding carry, had no counter-move at all: spending moves the pressure a check ADDS, never
## how much of the last one is still there.
##
## ── What the policy is ──
##
## Safeguards on the fuel cycle, which is the part no budget reaches, plus a treaty regime that
## unwinds the carry, which is the part nothing reached. It is paid for in matter — inspection is
## people, travel and instruments — and in the research the arms race was producing: the science
## term is written against Military Spending's own bonus, so it cancels the spillover rather than
## taxing science in general, and costs nothing at all at a zero budget.
##
## ── Why it is not a smaller budget in a different hat ──
##
## Cutting the budget lowers TENSION, which safeguards do not touch, and refunds the matter.
## Safeguards cut the LATENT arsenal, which the budget does not touch, and unwind the carry.
## For a reactor-heavy civilisation at the default budget, safeguards are the better of the two at
## the same cost in science; for one with no reactors they do nothing to the means at all. The
## decision is therefore settled by how the civilisation makes its power, which is the point.
##
## And `means` is clamped at 1.0, so a full military budget saturates it alone: safeguards are
## worth most to a civilisation that is not itself armed. Asserted rather than apologised for —
## the description says the policy covers the fuel cycle and not the declared arsenal.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

var _g: Node = null

## Policy state with the named overrides on top of the defaults.
func _pol(over: Dictionary) -> Dictionary:
	var s: Dictionary = PoliticsData.default_state()
	for k: String in over:
		s[k] = over[k]
	return s

## The means to wage a war, at a military budget, a safeguard level and a reactor count.
func _means(mil: float, arms: float, plants: float) -> float:
	_g.policies["military_spending"] = mil
	_g.policies["arms_control"] = arms
	_g._cached_nuclear = plants
	_g._prod_dirty = false
	return _g._nuclear_means()

## The forecast, under the same three knobs and no accumulated standoff.
func _odds(mil: float, arms: float, plants: float) -> float:
	_g._arms_strain = 0.0
	var _m: float = _means(mil, arms, plants)
	return _g.nuclear_probability()


func _run() -> void:
	seed(20261110)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	_g = g


	# ── The policy is there, with the other one it argues with ──
	var found: Dictionary = {}
	for p: Dictionary in PoliticsData.POLICIES:
		if str(p["id"]) == "arms_control":
			found = p
	check(not found.is_empty(), "there is an arms_control policy")
	check(str(found.get("category", "")) == "Society",
		"and it sits with Military Spending: %s" % str(found.get("category", "")))
	check(float(found.get("default", -1.0)) == 0.0,
		"starting at nothing, which is where 1945 is: %s" % str(found.get("default")))
	check(PoliticsData.default_state().has("arms_control"), "and a fresh state carries it")


	# ── Paid for in the research the race was producing ──
	# Written against Military Spending's own bonus, so at a full budget and full safeguards the
	# spillover is exactly cancelled: the same science as a civilisation that never raced at all.
	var raced: float = PoliticsData.science_mult(_pol({"military_spending": 50.0, "arms_control": 0.0}))
	var signed_: float = PoliticsData.science_mult(_pol({"military_spending": 50.0, "arms_control": 100.0}))
	var never: float = PoliticsData.science_mult(_pol({"military_spending": 0.0, "arms_control": 0.0}))
	check(signed_ < raced, "safeguards cost the arms race's science: %f vs %f" % [signed_, raced])
	check(is_equal_approx(signed_, never),
		"and cost exactly that and no more: %f vs %f" % [signed_, never])
	# Nothing to lose at a zero budget, which is why it is not a tax on science.
	check(is_equal_approx(
			PoliticsData.science_mult(_pol({"military_spending": 0.0, "arms_control": 100.0})), never),
		"a civilisation that was not racing loses no science to signing")
	# And paid for in matter.
	check(PoliticsData.minerals_mult(_pol({"arms_control": 100.0}))
		< PoliticsData.minerals_mult(_pol({"arms_control": 0.0})),
		"inspection costs matter")


	# ── The fuel cycle, which no budget reaches ──
	var bare: float = _means(0.0, 0.0, 36.0)
	var kept: float = _means(0.0, 100.0, 36.0)
	check(kept < bare, "safeguards cut the latent arsenal: %f vs %f" % [kept, bare])
	check(is_equal_approx(kept, bare * (1.0 - g.ARMS_SAFEGUARD_CUT)),
		"by exactly ARMS_SAFEGUARD_CUT: %f vs %f" % [kept, bare * (1.0 - g.ARMS_SAFEGUARD_CUT)])
	# Safeguards are not disarmament. The material and the expertise stay where they are, so the
	# means cannot be taken to zero by signing for them — only by not having the reactors.
	check(kept > 0.0, "and never to zero: %f" % kept)
	check(is_equal_approx(_means(0.0, 100.0, 0.0), 0.0),
		"a civilisation with no reactors has nothing to safeguard")

	# The limit the description states: a full budget saturates the means on its own.
	var armed: float = _means(50.0, 0.0, 36.0)
	check(is_equal_approx(armed, 1.0), "a full budget is the whole means by itself: %f" % armed)
	check(is_equal_approx(_means(50.0, 100.0, 36.0), armed),
		"so safeguards on the fuel cycle do nothing for a civilisation armed to the teeth")

	# And it is not a disarmament treaty: the rivalry is untouched.
	_g.policies["military_spending"] = 10.0
	_g.policies["arms_control"] = 0.0
	var tension: float = g._geopolitical_tension()
	_g.policies["arms_control"] = 100.0
	check(is_equal_approx(g._geopolitical_tension(), tension),
		"tension is what spreading out and a smaller budget are for, not this")


	# ── The forecast reads the same term the check does ──
	var before: float = _odds(10.0, 0.0, 36.0)
	var after: float = _odds(10.0, 100.0, 36.0)
	check(before > 0.0, "a reactor-heavy single world has odds to lower: %f" % before)
	check(after < before, "and signing lowers them: %f vs %f" % [after, before])


	# ── The standoff unwinds, and this is the only thing that unwinds it ──
	# Driven with no reactors and no budget, so pressure is zero and what is left is the carry.
	# _check_nuclear_war returns after the ratchet in that state, so nothing is rolled.
	for arms: float in [0.0, 100.0]:
		_g._arms_strain = 3.0
		_g.policies["military_spending"] = 0.0
		_g.policies["arms_control"] = arms
		_g._cached_nuclear = 0.0
		_g._prod_dirty = false
		g._next_nuclear_year = g.year
		g._nuclear_cooldown_ms = 0
		g._check_nuclear_war()
		var want: float = 3.0 * g.NUCLEAR_STRAIN_DECAY \
			* (1.0 - g.ARMS_STRAIN_RELIEF * (arms / 100.0))
		check(is_equal_approx(g._arms_strain, want),
			"a standoff of 3.0 carries %f at %d%% safeguards, not %f" % [want, int(arms), g._arms_strain])
	check(g.ARMS_STRAIN_RELIEF > 0.0, "and a treaty regime really does unwind some of it")

	# Asking the forecast what the odds are must still not make them worse, safeguards or not.
	_g._arms_strain = 1.5
	_g.policies["arms_control"] = 60.0
	for _i in range(5):
		g.nuclear_probability()
	check(is_equal_approx(g._arms_strain, 1.5),
		"the forecast does not ratchet the standoff: %f" % g._arms_strain)


	# ── Why it is a different move from a smaller budget ──
	# A reactor-heavy civilisation at the default budget: safeguards beat cutting the budget, and
	# cost the same science — the budget's spillover is lost either way.
	var basis: float = _odds(10.0, 0.0, 36.0)
	var signs: float = _odds(10.0, 100.0, 36.0)
	var cuts: float = _odds(0.0, 0.0, 36.0)
	check(signs < cuts and cuts < basis,
		"safeguards beat disarming a reactor-heavy world: %f vs %f, from %f" % [signs, cuts, basis])
	check(is_equal_approx(
			PoliticsData.science_mult(_pol({"military_spending": 10.0, "arms_control": 100.0})),
			PoliticsData.science_mult(_pol({"military_spending": 0.0, "arms_control": 0.0}))),
		"at the same price in science")

	# And with no reactors it is the other way round: nothing to safeguard, so the budget is the
	# only move. The decision is settled by how the civilisation makes its power.
	check(is_equal_approx(_odds(10.0, 100.0, 0.0), _odds(10.0, 0.0, 0.0)),
		"safeguards do nothing for a world with no reactors")
	check(is_equal_approx(_odds(0.0, 0.0, 0.0), 0.0),
		"while disarming one leaves no means at all")

	print("FAILS: %d" % fails)
	quit()
