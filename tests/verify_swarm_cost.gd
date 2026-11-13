extends SceneTree

## The sandbox runs about as fast as a new game, not at a quarter of the speed.
##
## It ran at 27 fps from the moment it was unpaused.  Its swarm is built arrays — four thousand
## structures on the Sun — and the swarm's panel count was taken by walking that roster entry by
## entry.  _swarm_power() needs the count, _combine_production() needs the power, and every read
## of compute or production goes through _combine_production, so the walk ran about a dozen
## times a frame: 2.5 ms a time, thirty of a frame's thirty-seven.  The lifters and the core
## mixers walked it again for their own ratings, and every production rebuild once more,
## whichever world it was rebuilding for.
##
## They all read the production cache's per-kind tally now (_planet_tally), which costs what the
## Sun has KINDS of, not what it has entries.  So besides the frame itself this checks that the
## count off the tally is the roster's count, clean cache or dirty, and that none of these costs
## grows when the roster does.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _ms(f: Callable, n: int = 20) -> float:
	f.call()                       # warm: the first call can rebuild a cache
	var t0 := Time.get_ticks_usec()
	for _i in range(n):
		f.call()
	return float(Time.get_ticks_usec() - t0) / 1000.0 / n

## The Sun's panels counted entry by entry: what the tally has to agree with.
func _walked(g: Node) -> int:
	var n: int = 0
	for b in (g.planet_buildings.get("sun", []) as Array):
		n += int(g._swarm_panels_of(str(b)))
	return n

## One simulation slice, with whatever paused it cleared first.  An event card pauses the game,
## and a paused _process returns at once — a frame measured that way is measuring nothing.
func _slice(g: Node, ss: Node) -> void:
	ss.paused = false
	ss.ui_paused = false
	paused = false
	g._process(0.016)

func _run() -> void:
	seed(20261112)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(40): await process_frame
	var g: Node = current_scene
	var ss: Node = root.get_node("SolarSystem")

	# ── A new game's slice, the yardstick ──
	var s0: float = g.entropy_exported
	var base: float = _ms(func() -> void: _slice(g, ss))
	check(g.entropy_exported > s0, "the new game's slices really ran the simulation")

	var SB = load("res://sandbox_save.gd")
	SB.write()
	g.load_game(SB.SAVE_PATH)
	for _i in range(5): await process_frame
	var sun: Array = g.planet_buildings["sun"]
	check(sun.size() > 2000, "the sandbox Sun carries its thousands: %d" % sun.size())

	# ── The sandbox's slice ──
	s0 = g.entropy_exported
	var sbx: float = _ms(func() -> void: _slice(g, ss))
	print("slice: new game %.3f ms, sandbox %.3f ms" % [base, sbx])
	check(g.entropy_exported > s0, "the sandbox's slices really ran the simulation")
	# It was 34 ms against 1.  The sandbox has far more going on than a new game, so it may cost
	# a few times as much; it may not cost thirty.
	check(sbx < base * 10.0, "a sandbox slice costs a few new-game slices, not thirty: %.3f vs %.3f ms"
		% [sbx, base])

	# ── The count off the tally is the roster's count ──
	g._recompute_production_cache()
	check(not g._prod_dirty, "the cache is clean")
	check(g._swarm_built() == _walked(g), "clean: %d panels, the roster says %d"
		% [g._swarm_built(), _walked(g)])
	var was: int = g._swarm_built()
	g._on_demolish_requested("sun", "Swarm Collector Array", 1)
	check(g._swarm_built() == was - 1 and g._swarm_built() == _walked(g),
		"a demolition takes one out: %d, was %d, the roster says %d" % [g._swarm_built(), was, _walked(g)])
	# The other path: a roster changed and the cache marked dirty but not yet rebuilt.  The tally
	# from before the change must not be what answers.  (The demolition above rebuilds before it
	# returns, so it never reaches this.)
	sun.remove_at(sun.rfind("Swarm Collector Array"))
	g._mark_prod_dirty("sun")
	check(g._prod_dirty, "the cache is dirty")
	check(g._swarm_built() == was - 2 and g._swarm_built() == _walked(g),
		"dirty, before any rebuild: %d, the roster says %d" % [g._swarm_built(), _walked(g)])
	g._recompute_production_cache()
	check(g._swarm_built() == _walked(g), "and clean again: %d, the roster says %d"
		% [g._swarm_built(), _walked(g)])
	# And the changes nobody announces.  The cache is clean, and the roster moves under it anyway:
	# load_game replaces every roster and reads the swarm count long before it marks anything
	# dirty, and plenty of tests set a roster by hand.
	# Replaced wholesale at the same length, so only the list's identity gives it away.
	check(not g._prod_dirty, "the cache is clean again")
	var swapped: Array = sun.duplicate()
	swapped[swapped.find("Swarm Collector Array")] = "Orbital Vault"
	g.planet_buildings["sun"] = swapped
	sun = swapped
	check(g._swarm_built() == _walked(g) and g._swarm_built() == was - 3,
		"a roster replaced at the same length, unannounced: %d, the roster says %d"
			% [g._swarm_built(), _walked(g)])
	g._recompute_production_cache()
	# Grown in place, which only its length gives away.
	sun.append("Swarm Collector Array")
	check(g._swarm_built() == _walked(g) and g._swarm_built() == was - 2,
		"a roster appended to in place, unannounced: %d, the roster says %d"
			% [g._swarm_built(), _walked(g)])
	g._mark_prod_dirty("sun")
	g._recompute_production_cache()
	# The rebuild's own swarm share is the swarm as it stands after the demolition.
	var e: float = 0.0
	for p: String in g._prod_planet:
		e += float(g._prod_planet[p]["energy"])
	check(is_equal_approx(g._bld_energy, e + g._swarm_power()),
		"the rebuilt grid carries the swarm as it now stands: %s vs %s + %s"
			% [str(g._bld_energy), str(e), str(g._swarm_power())])

	# ── And none of it grows with the roster ──
	var t_power: float = _ms(func() -> void: g._swarm_power())
	var t_lift: float = _ms(func() -> void: g._sun_structure_total("star_lift_power"))
	var t_rebuild: float = _ms(func() -> void:
		g._mark_prod_dirty("earth")
		g._recompute_production_cache(), 10)
	# Ten times the roster, in a kind it already holds, so the tally has as many kinds to walk
	# as before and only the entry count changes.
	var extra: String = "Orbital Vault"
	check(sun.has(extra), "the Sun holds some %s to multiply" % extra)
	for _i in range(sun.size() * 9):
		sun.append(extra)
	g._mark_prod_dirty("sun")
	g._recompute_production_cache()
	var t_power10: float = _ms(func() -> void: g._swarm_power())
	var t_lift10: float = _ms(func() -> void: g._sun_structure_total("star_lift_power"))
	var t_rebuild10: float = _ms(func() -> void:
		g._mark_prod_dirty("earth")
		g._recompute_production_cache(), 10)
	print("at %d and %d entries: swarm power %.4f / %.4f ms, lift rating %.4f / %.4f ms, Earth rebuild %.3f / %.3f ms"
		% [sun.size() / 10, sun.size(), t_power, t_power10, t_lift, t_lift10, t_rebuild, t_rebuild10])
	check(t_power10 < maxf(t_power * 2.5, 0.05),
		"the swarm's power costs the same at ten times the roster: %.4f vs %.4f ms" % [t_power10, t_power])
	check(t_lift10 < maxf(t_lift * 2.5, 0.05),
		"and so does a Sun rating: %.4f vs %.4f ms" % [t_lift10, t_lift])
	# Tighter, because Earth's own share of its rebuild is the same at both sizes and dilutes the
	# ratio: counting the Sun once per rebuild shows up here as about three times, not ten.
	check(t_rebuild10 < maxf(t_rebuild * 1.6, 0.3),
		"and rebuilding another world does not count the Sun: %.3f vs %.3f ms" % [t_rebuild10, t_rebuild])

	print("FAILS: %d" % fails)
	quit()
