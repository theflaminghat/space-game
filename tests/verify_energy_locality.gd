extends SceneTree

## A colony's probes are built with a colony's star.
##
## _vn_launch charged ResearchTree.resources["energy"] whoever launched — so a probe assembled
## four hundred light-years out, by a colony that may already have declared for itself, came out
## of Sol's reserve in the same instant it left. The line below the charge already knew better:
## it records `from_star` precisely because "a replicated probe leaves the colony that built it,
## which is halfway across the map from Sol".
##
## That contradicted the rest of the design and nothing else. The audit that found it is worth
## keeping: of the twenty-odd places energy is spent, every other one is the player acting from
## the solar system — a launch, a laser, a message, a trade's freight — and those correctly bill
## the home grid. Production was already solar-only, because an interstellar colony has no
## planet_buildings entry to contribute one.
##
## ── The size of it ──
##
## A probe costs 16.2 MJ against a starting STORAGE CAP of 301 TJ: eighteen million probes. The
## charge was never a brake. What paces replication is _vn_work_queue's round-robin and time
## budget, which this does not touch. Asserted below, because "we removed a cost" invites the
## question of what it was holding back, and the answer is nothing.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(20261103)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var SM = load("res://StarMapPanel.gd")
	var rt: Node = root.get_node("ResearchTree")
	var ss: Node = root.get_node("SolarSystem")
	rt.force_unlock("relativistic_navigation")
	rt.force_unlock("self_replicating_industry")

	var names: Array = []
	for s in SM.all_stars():
		names.append(str((s as Dictionary)["name"]))
		if names.size() >= 8:
			break
	check(names.size() >= 8, "stars to aim at: %d" % names.size())


	# ── A colony's probe does not touch the home reserve ──
	var colony: String = str(names[0])
	g._colonize_star(colony)
	rt.resources["energy"] = 5.0e12
	var before: float = float(rt.resources.get("energy", 0.0))
	var sent: bool = g._vn_launch(str(names[1]), g._star_pos(colony), {}, colony)
	check(sent, "the colony launches")
	check(absf(float(rt.resources.get("energy", 0.0)) - before) < 1.0,
		"and Sol's reserve is untouched: %s -> %s" % [
			str(before), str(rt.resources.get("energy", 0.0))])

	# A colony with the home reserve at ZERO still launches — the clearest statement of the
	# rule: its star is not Sol's grid.
	rt.resources["energy"] = 0.0
	check(g._vn_launch(str(names[2]), g._star_pos(colony), {}, colony),
		"a colony launches with the home grid empty")
	check(float(rt.resources.get("energy", 0.0)) <= 0.0,
		"without borrowing against it: %s" % str(rt.resources.get("energy", 0.0)))

	# And a colony that has already SECEDED is the case that makes it obvious.
	g._secede_colony(colony)
	rt.resources["energy"] = 0.0
	check(g._vn_launch(str(names[3]), g._star_pos(colony), {}, colony),
		"a seceded colony's swarm keeps going")
	check(float(rt.resources.get("energy", 0.0)) <= 0.0,
		"still on nobody else's grid: %s" % str(rt.resources.get("energy", 0.0)))


	# ── A launch FROM THE SOLAR SYSTEM still bills the home grid ──
	# This is locality, not "probes are free".
	rt.resources["energy"] = 5.0e12
	var home_before: float = float(rt.resources.get("energy", 0.0))
	check(g._vn_launch(str(names[4]), ss.sol_position(), {}, ""),
		"a launch from home goes")
	check(float(rt.resources.get("energy", 0.0)) < home_before,
		"and is paid for here: %s -> %s" % [
			str(home_before), str(rt.resources.get("energy", 0.0))])
	# And is refused when the grid cannot cover it.
	rt.resources["energy"] = 0.0
	check(not g._vn_launch(str(names[5]), ss.sol_position(), {}, ""),
		"an unaffordable launch from home is refused")


	# ── The charge was never a brake ──
	# Stated as a measurement, because removing a cost invites the question of what it held back.
	var plan: Dictionary = SM.plan_flight(10.0, g.VN_GAMMA, g.VN_ACCEL)
	var probe_cost: float = float(plan["energy"]) * DoctrineData.mission_mass_frac("colonize")
	var cap: float = float(g._cached_storage_caps.get("energy", 0.0))
	check(probe_cost > 0.0, "a probe does cost something: %s" % str(probe_cost))
	check(cap / maxf(probe_cost, 1.0) > 1.0e5,
		"but the STARTING storage cap alone covers a hundred thousand of them: %.0f" % [
			cap / maxf(probe_cost, 1.0)])


	# ── The player's own first probe still earns We Are Bob ──
	# _on_vn_probe_requested builds its mission itself and never calls _vn_launch, so moving the
	# hook into _vn_launch had quietly stopped the hand-launched probe — the one the achievement
	# is actually named for — from earning it.
	g.achievements_earned = {}
	rt.resources["energy"] = 1.0e14
	g._add_stockpile("VNProbe", 10.0, "earth")
	g._on_vn_probe_requested(str(names[6]), g.VN_GAMMA, g.VN_ACCEL, "colonize", g.contact_doctrine)
	check(g.achievements_earned.has("we_are_bob"),
		"the probe the player sends by hand earns it: %s" % str(g.achievements_earned.keys()))
	# And so does a replicated one, which is the other path.
	g.achievements_earned = {}
	g._vn_launch(str(names[7]), g._star_pos(colony), {}, colony)
	check(g.achievements_earned.has("we_are_bob"), "and so does a replicated one")

	print("FAILS: %d" % fails)
	quit()
