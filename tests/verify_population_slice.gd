extends SceneTree

## The population pass is sliced, and that is exact rather than approximate.
##
## At 1x the clock advances four simulated days a second, and growing every world on every one
## of them was most of a late game's frame budget: fifteen thousand worlds at about three
## microseconds each is forty-odd milliseconds a day, four times a second. So a colony is grown
## once per CYCLE of POP_SLICES ticks, with the whole cycle's span at once.
##
## That rests on one property: logistic growth in closed form COMPOSES. k/(1 + (k/p - 1)e^-rt)
## advanced over 8t is what eight steps of t give, so this is the same answer and not a cheaper
## approximation of it — as long as k held across the span, which is why worlds in the solar
## system (whose capacity moves as things are built on them) are still grown every tick.
##
## The weighted sums are accumulated across the cycle, each world contributing on its own tick,
## and published when it closes. So there is no running total to drift: a cycle's figures are a
## complete pass, just spread over eight ticks.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(20261020)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var SD = load("res://stock_data.gd")

	check(g.POP_SLICES >= 2, "the cycle is more than one tick: %d" % g.POP_SLICES)

	# A roster of colonies, all identical so one closed-form figure answers for all of them.
	var N: int = g.POP_SLICES * 25
	var start_pop: float = 1.0e6
	for i in range(N):
		var nm := "slice_%d" % i
		g.colonized_stars.append(nm)
		g._col_star_set[nm] = true
		g._colony_year[nm] = g.year
		g.world_pop[nm] = start_pop
		g._world_stock[nm] = SD.found("standard", "balanced", SD.baseline())

	# ── A full cycle grows every colony exactly one cycle's worth ──
	# Compared against the closed form over the whole span, which is the answer a day-by-day
	# pass is approximating with eight successive floors.
	var k: float = g.COLONY_HABITAT_K * g._pop_cap_mult()
	var r: float = g.POP_GROWTH_PER_YEAR / 365.25 * PoliticsData.pop_growth_mult(g.policies)
	var span: float = float(g.POP_SLICES)
	var want: float = k / (1.0 + (k / start_pop - 1.0) * exp(-r * span))
	for _t in range(g.POP_SLICES):
		g._update_population(1.0)
	var grown: int = 0
	var worst: float = 0.0
	for i in range(N):
		var got: float = float(g.world_pop["slice_%d" % i])
		if got > start_pop:
			grown += 1
		worst = maxf(worst, absf(got - want) / want)
	check(grown == N, "every colony grew over the cycle: %d of %d" % [grown, N])
	check(worst < 1.0e-6,
		"and by exactly one closed-form step of the whole span: worst %.3e off" % worst)

	# ── Not more than once ──
	# A colony grown on every tick would be eight steps ahead, which the composition makes
	# indistinguishable in form but not in size.
	var eight_steps: float = start_pop
	for _s in range(g.POP_SLICES):
		eight_steps = k / (1.0 + (k / eight_steps - 1.0) * exp(-r * float(g.POP_SLICES)))
	check(float(g.world_pop["slice_0"]) < eight_steps * 0.999,
		"no colony was grown every tick: %s vs %s" % [g.world_pop["slice_0"], eight_steps])

	# ── Within a cycle, only a share of the roster moves per tick ──
	# That is the whole point: the work is spread, not merely deferred.
	var before: Array = []
	for i in range(N):
		before.append(float(g.world_pop["slice_%d" % i]))
	g._update_population(1.0)
	var moved: int = 0
	for i in range(N):
		if absf(float(g.world_pop["slice_%d" % i]) - float(before[i])) > 0.5:
			moved += 1
	check(moved > 0, "a tick moves something: %d" % moved)
	check(moved < N / 2, "but only a slice of the roster: %d of %d" % [moved, N])

	# ── The weighted sums are a complete pass, published at the close ──
	# Checked against a sum over every world, which is what they are meant to be.
	# Run on until a cycle has just CLOSED, because that is the claim: the partials are a
	# complete pass the moment every world has contributed. Between closes they lag by up to a
	# cycle, which is asserted separately below.
	for _t2 in range(g.POP_SLICES * 3):
		g._update_population(1.0)
		if g._pop_slice == 0:
			break
	check(g._pop_slice == 0, "a cycle has just closed")
	var want_head: float = 0.0
	var want_c: float = 0.0
	var want_l: float = 0.0
	for w: String in g.world_pop:
		var pop: float = float(g.world_pop[w])
		var st: Dictionary = g.stock_of(w)
		want_head += pop
		want_c += pop * SD.compute_mult_of(st)
		want_l += pop * SD.life_mult_of(st)
	check(absf(float(g.stats["current_population"]) - want_head) < want_head * 1.0e-6,
		"the headcount is every world's: %s vs %s" % [g.stats["current_population"], want_head])
	check(absf(g._pop_weighted_compute - want_c) < want_c * 1.0e-6,
		"and the weighted compute sum: %s vs %s" % [g._pop_weighted_compute, want_c])
	check(want_head > 0.0 and absf(g._pop_weighted_life - want_l / want_head)
			< 1.0e-6, "and the weighted life average")

	# ── Between closes the sums lag, and by a trivial amount ──
	# They are read as a rate of thinking and a span of life, both of which move on geological
	# timescales; being up to one cycle stale is a fraction of a percent and is the price of
	# not re-summing every world every tick.
	var at_close: float = g._pop_weighted_compute
	for _t3 in range(g.POP_SLICES - 1):
		g._update_population(1.0)
	var drift: float = absf(g._pop_weighted_compute - at_close) / maxf(at_close, 1.0)
	check(drift < 0.01, "the mid-cycle lag is under a percent: %.4f%%" % (drift * 100.0))

	# ── Solar-system worlds are grown every tick ──
	# Their capacity moves as things are built on them, and the closed form only composes
	# across a span the capacity held for.
	var e0: float = float(g.world_pop["earth"])
	g._update_population(1.0)
	var e1: float = float(g.world_pop["earth"])
	g._update_population(1.0)
	var e2: float = float(g.world_pop["earth"])
	check(e1 > e0 and e2 > e1,
		"Earth grows on consecutive ticks: %s -> %s -> %s" % [e0, e1, e2])

	print("FAILS: %d" % fails)
	quit()
