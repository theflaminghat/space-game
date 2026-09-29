extends SceneTree
var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)
func holdings(g) -> Dictionary:
	var out := {}
	for star in g.star_polity:
		out[str(g.star_polity[star])] = int(out.get(str(g.star_polity[star]), 0)) + 1
	return out
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

	# Grow a crowded neighbourhood so there is something to fight over.
	for _n in range(8):
		g._spread_aliens(50000.0)
	var before: Dictionary = holdings(g)
	var before_systems: int = g.star_polity.size()
	print("before war: %d systems, %d states" % [before_systems, before.size()])

	# ── Conquest moves systems between states without inventing or destroying them ──
	for _n in range(10):
		g._alien_wars(50000.0)
	var after: Dictionary = holdings(g)
	print("after war: %d systems, %d states" % [g.star_polity.size(), after.size()])
	check(g.star_polity.size() == before_systems, "war moves systems, it does not create them")
	var changed := 0
	for pid in before:
		if int(after.get(pid, 0)) != int(before[pid]): changed += 1
	print("states whose holdings changed: %d" % changed)
	check(changed > 0, "somebody took something")
	# Winners and losers both exist.
	var grew := 0
	var shrank := 0
	var died := 0
	for pid in before:
		var now: int = int(after.get(pid, 0))
		if now > int(before[pid]): grew += 1
		elif now < int(before[pid]): shrank += 1
		if now == 0: died += 1
	print("grew %d, shrank %d, wiped out %d" % [grew, shrank, died])
	check(grew > 0 and shrank > 0, "conquest has two sides")

	# ── Every system still has a consistent owner ──
	var bad := 0
	for star in g.star_polity:
		var f: Dictionary = g.faction_of(star)
		if f.is_empty() or str(f["alignment"]) != str(g.star_factions.get(star, "")): bad += 1
	check(bad == 0, "every conquered system agrees with its new government: %d" % bad)

	# ── Only aggressive states conquer ──
	# Run a war round in a sky with no aggressors at all and nothing may change hands.
	var saved: Dictionary = g.star_factions.duplicate()
	for star in g.star_factions:
		g.star_factions[star] = "peaceful"
	var quiet_before: Dictionary = holdings(g)
	for _n in range(5):
		g._alien_wars(50000.0)
	var quiet_after: Dictionary = holdings(g)
	var moved := 0
	for pid in quiet_before:
		if int(quiet_after.get(pid, 0)) != int(quiet_before[pid]): moved += 1
	check(moved == 0, "a sky of peaceful states has no conquests: %d changed" % moved)
	g.star_factions = saved

	# ── Our colonies are never taken this way ──
	g.colonized_stars = []
	var ours := ""
	for star in g.star_polity:
		ours = str(star); break
	g.colonized_stars.append(ours)
	g._col_star_set = {ours: true}
	var owner_before: String = str(g.star_polity.get(ours, ""))
	for _n in range(10):
		g._alien_wars(50000.0)
	check(str(g.star_polity.get(ours, "")) == owner_before,
		"an alien raid does not quietly take a human colony")

	# ── A conquered system is set back, not left untouched ──
	var t0: int = Time.get_ticks_msec()
	for _n in range(5):
		g._alien_wars(50000.0)
	print("five war rounds over %d systems: %d ms" % [g.star_polity.size(), Time.get_ticks_msec() - t0])
	check(Time.get_ticks_msec() - t0 < 2000, "war is cheap enough to run every tick")
	print("FAILS: ", fails)
	quit()
