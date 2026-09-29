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
	var P = load("res://polities.gd")
	var SM = load("res://StarMapPanel.gd")
	var seed_a := 4242

	# ── Determinism, and the two layers being different sizes ──
	var p1 := Vector3(1200, -300, 800)
	check(P.race_at(p1, seed_a)["id"] == P.race_at(p1, seed_a)["id"], "a place has one race")
	check(P.faction_at(p1, seed_a)["id"] == P.faction_at(p1, seed_a)["id"], "and one polity")
	check(P.race_at(p1, seed_a)["id"] != P.race_at(p1, seed_a + 1)["id"], "another galaxy, another race")
	# A step inside the race cell but across a faction boundary: same species, different state.
	var p2: Vector3 = p1 + Vector3(P.FACTION_CELL_LY, 0, 0)
	var r1: Dictionary = P.race_at(p1, seed_a)
	var r2: Dictionary = P.race_at(p2, seed_a)
	var f1: Dictionary = P.faction_at(p1, seed_a)
	var f2: Dictionary = P.faction_at(p2, seed_a)
	print("at A: %s of the %s" % [f1["name"], f1["race_name"]])
	print("at B (%d ly on): %s of the %s" % [int(P.FACTION_CELL_LY), f2["name"], f2["race_name"]])
	check(r1["id"] == r2["id"], "still the same race a faction-cell away")
	check(f1["id"] != f2["id"], "but a different polity")
	check(str(f1["race_name"]) == str(r1["name"]), "a faction carries its race's name")
	# Far enough and the species changes too.
	var far: Vector3 = p1 + Vector3(P.RACE_CELL_LY * 2.0, 0, 0)
	check(str(P.race_at(far, seed_a)["id"]) != str(r1["id"]), "a different part of the galaxy is a different species")

	# ── Names ──
	var race_names := {}
	var faction_names := {}
	var hostile := 0
	var n := 0
	for x in range(0, 12):
		for z in range(0, 12):
			var pos := Vector3(x * P.RACE_CELL_LY, 0, z * P.RACE_CELL_LY)
			race_names[str(P.race_at(pos, seed_a)["name"])] = true
			for k in range(3):
				var fpos: Vector3 = pos + Vector3(k * P.FACTION_CELL_LY, 0, 0)
				var f: Dictionary = P.faction_at(fpos, seed_a)
				faction_names[str(f["name"])] = true
				n += 1
				if str(f["alignment"]) == "aggressive": hostile += 1
	print("144 race cells → %d distinct species names; %d polities → %d distinct names" % [
		race_names.size(), n, faction_names.size()])
	check(race_names.size() > 60, "species names are varied: %d" % race_names.size())
	check(faction_names.size() > n / 2, "polity names are varied: %d of %d" % [faction_names.size(), n])
	check(absf(float(hostile) / float(n) - 0.5) < 0.12, "half of them are armed: %.2f" % (float(hostile) / float(n)))
	# A polity's name says which it is.
	var sample_h := ""
	var sample_p := ""
	for x in range(40):
		var f: Dictionary = P.faction_at(Vector3(x * P.FACTION_CELL_LY, 0, 0), seed_a)
		if str(f["alignment"]) == "aggressive" and sample_h == "": sample_h = str(f["name"])
		if str(f["alignment"]) == "peaceful" and sample_p == "": sample_p = str(f["name"])
	print("hostile example: %s | peaceful example: %s" % [sample_h, sample_p])

	# ── The original neighbours have identities ──
	var named := 0
	for star in g.star_factions:
		if not str(g.faction_of(star).get("name", "")).is_empty(): named += 1
	print("starting neighbours: %d, all named: %s" % [g.star_factions.size(), named == g.star_factions.size()])
	check(named == g.star_factions.size() and named > 0, "every starting neighbour is a named polity")
	# The setup's hostile count is still honoured — and it counts POLITIES, not systems.  One
	# government commonly holds several stars, so counting armed systems overcounts it; that
	# conflation is the bug the polity layer was built to remove.
	var hostile_polities := {}
	var armed_systems := 0
	for star in g.star_factions:
		if str(g.star_factions[star]) != "aggressive":
			continue
		armed_systems += 1
		hostile_polities[str(g.faction_of(star).get("id", star))] = true
	var want: int = int(root.get_node("GameSession").choice("neighbours").get("hostile", 3))
	print("armed: %d systems held by %d polities; the setup asked for %d" % [
		armed_systems, hostile_polities.size(), want])
	check(hostile_polities.size() == want,
		"the setup screen's hostile count is kept, in polities: %d vs %d" % [
			hostile_polities.size(), want])

	# ── Generated stars out in new sky get inhabitants ──
	var aim: Vector3 = (SM.galactic_basis()[0] as Vector3).normalized()
	ss.star_drift_ly = aim * 3000.0
	SM.set_sky_frame(ss.sol_position(), float(g.year))
	g._seed_generated_factions()
	var gen_civ := 0
	var races_out := {}
	var factions_out := {}
	for s in SM.all_stars():
		if not bool(s.get("civ", false)):
			continue
		var nm := str(s["name"])
		if not g.star_factions.has(nm):
			continue
		gen_civ += 1
		var f: Dictionary = g.faction_of(nm)
		races_out[str(f.get("race_name", ""))] = true
		factions_out[str(f.get("name", ""))] = true
	print("3000 ly out: %d inhabited systems, %d species, %d polities" % [
		gen_civ, races_out.size(), factions_out.size()])
	check(gen_civ > 0, "the frontier is inhabited")
	check(not races_out.has(""), "every one has a species")
	check(factions_out.size() >= races_out.size(), "a species can hold several polities")

	# ── Save/load keeps them ──
	g.save_game("user://saves/polity.json")
	var before: Dictionary = g.star_polity.duplicate()
	var fname: String = str(g.faction_of(before.keys()[0]).get("name", ""))
	g.star_polity = {}
	g._factions = {}
	g.load_game("user://saves/polity.json")
	check(g.star_polity.size() == before.size(), "holdings survive a save: %d" % g.star_polity.size())
	check(str(g.faction_of(before.keys()[0]).get("name", "")) == fname, "and keep their names")
	ss.reset_star()
	print("FAILS: ", fails)
	quit()
