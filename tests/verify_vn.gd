extends SceneTree

## Von Neumann probes have to propagate THROUGH the stars, not fill in the bubble around home.
##
## They used to search StarMapPanel.all_stars(), which is the sky as resolved from Sol: bounded
## by the telescopes and trimmed to the nearest MAX_RESOLVED to Sol.  So a colony four hundred
## light-years out could only send probes to stars visible from Earth, and the swarm saturated
## the observation range and stopped there — the frontier sat at 434 ly against a 467 ly range
## for fourteen thousand years while it worked through all six thousand resolved stars.

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
	for _i in range(30): await process_frame
	var g: Node = current_scene
	var rt: Node = root.get_node("ResearchTree")
	var SM = load("res://StarMapPanel.gd")

	for n: ResearchNode in load("res://ResearchTreeData.gd").build():
		rt.force_unlock(str(n.id))
	rt.resources["energy"] = 1.0e40
	check(g._vn_unlocked(), "autonomous colonisation is available")
	var reach: float = SM.observation_range()

	# ── A colony beyond the telescopes can still find somewhere to go ──
	# This is the failure itself: ask for targets from a position further out than Sol can see.
	var far := Vector3(0, 0, reach * 3.0)
	var targets: Array = g._nearest_uncolonised(far, 2, INF, false)
	check(targets.size() == 2, "a colony past the observation range has targets: %s" % str(targets))
	var worst := 0.0
	for t in targets:
		worst = maxf(worst, far.distance_to(g._star_pos(str(t))))
	check(worst < g.VN_SURVEY_LY * 1.5,
		"and they are its OWN neighbours, not stars back home: furthest %.0f ly away" % worst)
	for t in targets:
		check(g._star_pos(str(t)).length() > reach,
			"%s lies beyond what Sol resolves" % str(t))

	# ── Run the swarm and watch the frontier move ──
	var first: Array = g._nearest_uncolonised(Vector3.ZERO, 1, INF, false)
	check(not first.is_empty(), "there is a first target to seed from")
	g._vn_launch(str(first[0]), Vector3.ZERO, {"mission": "colonize"}, "")
	var marks: Array = []
	for block in range(4):
		for _i in range(1500):
			g.year += 1
			rt.resources["energy"] = 1.0e40
			g._check_interstellar_arrivals()
		var frontier := 0.0
		for cs in g.colonized_stars:
			frontier = maxf(frontier, g._star_pos(str(cs)).length())
		marks.append(frontier)
	print("frontier over 6000 years: %s ly" % str(marks))
	print("settled %d stars, %d regions, %d lineages" % [
		g.colonized_stars.size(), g._regions.size(), g._vn_seeds.size()])

	check(marks[3] > reach,
		"the swarm gets past the observation range: %.0f ly vs %.0f" % [marks[3], reach])
	check(marks[3] > marks[1],
		"and is still moving outward late on: %.0f -> %.0f ly" % [marks[1], marks[3]])
	# It should not run away past the boundary where individual worlds give way to regions.
	check(marks[3] <= g.DETAILED_RADIUS_LY + 1.0,
		"without overshooting the detailed radius: %.0f ly" % marks[3])

	# ── No cap on how many probes may be in flight ──
	# There used to be one (VN_MAX_INFLIGHT, twelve), and it was the whole throughput of the
	# swarm however large it grew: expansion ran flat instead of compounding, and a colony that
	# arrived while those twelve were out launched nothing and was never revisited.
	check(not ("VN_MAX_INFLIGHT" in g), "the population cap is gone")
	var peak: int = 0
	for _b in range(6):
		for _i in range(400):
			g.year += 1
			rt.resources["energy"] = 1.0e40
			g._check_interstellar_arrivals()
		peak = maxi(peak, g._vn_inflight())
	check(peak > 100, "far more than a dozen probes fly at once: peak %d" % peak)
	print("peak probes in flight: %d ; %d colonies" % [peak, g.colonized_stars.size()])

	# ── The queue keeps working with nothing in flight ──
	# Working it only on the way out of the arrival loop meant a swarm with no probes currently
	# aloft never sent another: no arrival to trigger a launch, no launch to make an arrival.
	g.interstellar_missions.clear()
	g._vn_pending.append(str(g.colonized_stars[0]))
	var before_missions: int = g.interstellar_missions.size()
	g.year += 1
	g._check_interstellar_arrivals()
	check(g.interstellar_missions.size() > before_missions,
		"a swarm with nothing in flight still launches: %d" % g.interstellar_missions.size())

	# ── An enclosed lineage retires instead of being searched forever ──
	# Built deliberately rather than waited for: take one colony and claim everything its own
	# search can reach, until it can reach nothing.  Then it is enclosed by construction, and
	# whether it retires is a fact about the code rather than about how the run happened to go.
	var subject: String = str(g.colonized_stars[0])
	var er: Dictionary = g._enroute_targets()
	for _round in range(200):
		var reachable: Array = g._nearest_uncolonised(g._star_pos(subject), 8, INF, false, er)
		if reachable.is_empty():
			break
		for r in reachable:
			g._colonize_star(str(r))
	check(g._nearest_uncolonised(g._star_pos(subject), 1, INF, false, er).is_empty(),
		"the subject lineage now has nowhere to go")
	g._vn_seeds[subject] = true
	# Only this one in the queue: tens of thousands are already waiting from the run above, and
	# the time budget means a handful are worked per pass — appended at the back, the subject
	# would not be reached for thousands of passes and the test would prove nothing.
	g._vn_pending.clear()
	g._vn_head = 0
	g._vn_pending.append(subject)
	var had: bool = g._vn_seeds.has(subject)
	# Work the queue directly: a whole tick also lands arrivals, and every arrival founds a
	# colony that becomes a new seed, so the count moves for reasons that are not this.
	g._vn_work_queue()
	check(had and not g._vn_seeds.has(subject),
		"an enclosed lineage is retired, not retried forever")
	print("enclosed lineage %s retired: %s" % [subject, str(not g._vn_seeds.has(subject))])

	# ── A cleared system goes to the colony nearest it ──
	# Occupation reverses even though colonisation does not: our own weapons empty a system, and
	# it becomes colonisable again.  Every colony near it retired long before that, back when the
	# system was somebody else's and there was nowhere else to go — so without waking one, the
	# nearest lineage still awake was out on the frontier and it flew hundreds of light-years
	# past closer colonies to take it.
	var victim := ""
	var vd := INF
	for st in g.star_factions.keys():
		var d: float = g._star_pos(str(st)).length()
		if d < vd:
			vd = d
			victim = str(st)
	if victim != "":
		var vpos: Vector3 = g._star_pos(victim)
		var nearest := ""
		var nd := INF
		for cs in g.colonized_stars:
			var d2: float = g._star_pos(str(cs)).distance_to(vpos)
			if d2 < nd:
				nd = d2
				nearest = str(cs)
		check(nearest != "", "there is a colony near the system we are about to clear")
		# Clear it exactly as a strike does.
		g.star_factions.erase(victim)
		g._vn_freed.clear()
		g._vn_freed.append(victim)
		g.year += 1
		g._check_interstellar_arrivals()
		var claimer := ""
		for m2 in g.interstellar_missions:
			if str(m2.get("target", "")) == victim:
				claimer = str(m2.get("origin", ""))
				break
		check(claimer != "", "the cleared system is claimed at once")
		check(claimer == nearest,
			"and by the colony nearest it (%s at %.1f ly), not one across the map (got %s)" % [
				nearest, nd, claimer])
		# NOT "and stays awake".  Having taken the freed system it usually has nowhere else to
		# go — it is in the settled interior, which is why it was asleep — so the work queue
		# retires it again in the same tick, correctly.  Expansion continues from the system it
		# just claimed, once the probe arrives there; the probe is already in flight and does not
		# depend on its sender staying awake.
		var in_flight := false
		for m3 in g.interstellar_missions:
			if str(m3.get("target", "")) == victim and str(m3.get("origin", "")) == nearest:
				in_flight = true
		check(in_flight, "and the probe is genuinely under way from it")

	print("FAILS: %d" % fails)
	quit()
