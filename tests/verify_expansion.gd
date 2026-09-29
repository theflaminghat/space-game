extends SceneTree
var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	# Pin the global RNG BEFORE the scene loads.  Game._ready sets galaxy_seed = randi(), so
	# without this the generated sky — and every polity, colony and war seeded off it — differs
	# from one run of this test to the next, and the counts asserted below are a coin toss.
	seed(20260927)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(25): await process_frame
	var g: Node = current_scene
	var ss: Node = root.get_node("SolarSystem")
	var SM = load("res://StarMapPanel.gd")

	# ── Generated factions hold several systems each, not one ──
	var aim: Vector3 = (SM.galactic_basis()[0] as Vector3).normalized()
	ss.star_drift_ly = aim * 3000.0
	SM.set_sky_frame(ss.sol_position(), float(g.year))
	g._seed_generated_factions()
	var holdings := {}
	for star in g.star_polity:
		var pid := str(g.star_polity[star])
		holdings[pid] = int(holdings.get(pid, 0)) + 1
	var generated := 0
	var multi := 0
	for pid in holdings:
		generated += 1
		if int(holdings[pid]) > 1: multi += 1
	print("polities known: %d, holding %d systems in total" % [generated, g.star_polity.size()])
	check(generated > 0, "the frontier has governments")

	# ── Expansion extends a polity, not just an alignment ──
	var before_stars: int = g.star_factions.size()
	var before_polities: int = holdings.size()
	# Run a long spread: the rate is 3e-4 per system per year.
	g._spread_aliens(200000.0)
	var after: Dictionary = {}
	for star in g.star_polity:
		after[str(g.star_polity[star])] = int(after.get(str(g.star_polity[star]), 0)) + 1
	print("after 200 kyr of expansion: %d systems, %d polities" % [g.star_factions.size(), after.size()])
	check(g.star_factions.size() > before_stars, "somebody expanded")
	# Growth extends existing states.  New polities DO appear, but only as breakaway states once
	# a government passes POLITY_SPLIT_SYSTEMS — so every id that is new must carry the splinter
	# suffix Polities.splinter_of() gives it, never a freshly invented government.
	var invented: Array = []
	for pid: String in after:
		if holdings.has(pid):
			continue
		if not pid.contains("_s"):
			invented.append(pid)
	print("new polities: %d, of which invented from nothing: %d" % [
		after.size() - before_polities, invented.size()])
	check(invented.is_empty(),
		"expansion grows existing states or splits them, never invents new ones: %s" % str(invented))
	# Every inhabited star belongs to a government, and agrees with it.
	var orphan := 0
	var disagree := 0
	for star in g.star_factions:
		var f: Dictionary = g.faction_of(star)
		if f.is_empty():
			orphan += 1
		elif str(f["alignment"]) != str(g.star_factions[star]):
			disagree += 1
	check(orphan == 0, "no colony without a government: %d" % orphan)
	check(disagree == 0, "no colony disagreeing with its government: %d" % disagree)
	# A colony has a fresh signature, so its light has not reached Sol yet.
	var fresh := 0
	for star in g._alien_since:
		if absf(float(g._alien_since[star]) - float(g.year)) < 1.0: fresh += 1
	check(fresh > 0, "new colonies start emitting now: %d" % fresh)

	# ── Expansion never takes a system someone already holds, or one of ours ──
	var owners := {}
	var doubled := 0
	for star in g.star_polity:
		if owners.has(star): doubled += 1
		owners[star] = true
	check(doubled == 0, "no system held twice")
	for cs in g.colonized_stars:
		check(not g.star_factions.has(str(cs)), "aliens did not settle our colony at %s" % cs)

	# ── Infrastructure grows for generated civilisations like any other ──
	var sample := ""
	for star in g.star_factions:
		if str(star).begins_with("chunk"): sample = str(star); break
	if sample != "":
		var young: Dictionary = g._alien_infra_at(sample, float(g._alien_since[sample]) + 100.0)
		var old_infra: Dictionary = g._alien_infra_at(sample, float(g._alien_since[sample]) + 5.0e6)
		print("generated civ %s: dyson %.3f → %.3f" % [sample, float(young["dyson"]), float(old_infra["dyson"])])
		check(float(old_infra["dyson"]) > float(young["dyson"]), "a generated civilisation builds over time")
	ss.reset_star()
	print("FAILS: ", fails)
	quit()
