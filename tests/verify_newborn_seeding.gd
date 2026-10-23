extends SceneTree

## Stars go on forming for the whole run, and a star that forms inside settled space is a system
## that became colonisable with nobody watching: every von Neumann lineage near it retired when
## there was nowhere left to go.  Unless something wakes one, new stars accumulate uncolonised
## forever — which is what the swarm did.  Treated as the same event as a system cleared by
## weapons, because mechanically it is one.

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
	var P = load("res://StarMapPanel.gd")

	# ── The catalogue reports what it admitted ──
	check(P.advance_star_formation(float(g.year)).is_empty(),
		"nothing has formed yet in 1945")
	var born: Array = P.advance_star_formation(5.0e6)
	check(born.size() > 0, "stars form once the clock reaches them: %d" % born.size())
	var names: Dictionary = {}
	for n in born:
		names[str(n)] = true
	check(names.size() == born.size(), "and each is reported once")
	for s: Dictionary in P.all_stars():
		names.erase(str(s["name"]))
	# Everything admitted should be in the catalogue (barring any trimmed out of range).
	check(names.size() < born.size(), "the newborns are in the catalogue")
	check(P.advance_star_formation(5.0e6).is_empty(),
		"and asking again at the same year admits nothing")

	# ── The index over the catalogue is dropped when the catalogue changes ──
	var v0: int = P.catalogue_version()
	g._rebuild_star_grid(P.all_stars())
	check(int(g.get("_star_grid_version")) == P.catalogue_version(),
		"the grid records which catalogue it was built over")
	P.advance_star_formation(2.0e7)
	P.all_stars()
	check(P.catalogue_version() > v0, "forming stars bumps the catalogue revision")
	# The size test this replaced would have kept the stale index whenever the count happened to
	# match, which at the MAX_RESOLVED cap is every time.
	var stale: int = int(g.get("_star_grid_version"))
	g.set("_star_grid_size", P.all_stars().size())
	g._rebuild_star_grid(P.all_stars())
	check(int(g.get("_star_grid_version")) > stale,
		"and a changed revision rebuilds the index even at an unchanged size")

	# ── A newborn is offered to the swarm ──
	for n: ResearchNode in load("res://ResearchTreeData.gd").build():
		rt.force_unlock(str(n.id))
	check(g._vn_unlocked(), "the swarm is available")
	(g.get("_vn_freed") as Array).clear()
	g.year = 3.0e7
	g._advance_star_formation()
	var freed: Array = g.get("_vn_freed")
	check(freed.size() > 0, "newly formed stars are queued for the swarm: %d" % freed.size())
	var newborn: String = ""
	for n in freed:
		if str(n).begins_with("newborn"):
			newborn = str(n); break
	check(newborn != "", "and they are the stars that just formed")

	# ── The nearest colony is woken and sent ──
	# A lineage that retired is exactly the state every colony near a newborn is in.
	var pos: Vector3 = g._star_pos(newborn)
	var neighbour := ""
	var best := INF
	for s: Dictionary in P.all_stars():
		var nm: String = str(s["name"])
		if nm == newborn or g._star_occupied(nm):
			continue
		var d: float = (s["pos"] as Vector3).distance_to(pos)
		if d < best:
			best = d
			neighbour = nm
	check(neighbour != "", "there is a star nearby to hold the colony")
	g._colonize_star(neighbour)
	(g.get("_vn_seeds") as Dictionary).clear()        # retired: nobody is watching
	g.interstellar_missions.clear()
	# A probe costs energy to throw; a fresh run has nowhere near enough for an interstellar
	# launch, and a refusal for lack of fuel would look exactly like the bug under test.
	rt.resources["energy"] = 1.0e40
	(g.get("_vn_freed") as Array).assign([newborn])
	g._vn_wake_near_freed()
	var aimed := false
	var woke := false
	for m in g.interstellar_missions:
		if str(m.get("target", "")) == newborn:
			aimed = true
			check(str(m.get("origin", "")) == neighbour,
				"sent from the nearest colony, not from across the map")
	woke = (g.get("_vn_seeds") as Dictionary).has(neighbour)
	check(aimed, "a probe is launched at the newborn")
	check(woke, "and the colony that sent it is awake again")

	# ── A star already taken is not re-offered ──
	g.interstellar_missions.clear()
	g._colonize_star(newborn)
	(g.get("_vn_freed") as Array).assign([newborn])
	g._vn_wake_near_freed()
	var again := false
	for m in g.interstellar_missions:
		if str(m.get("target", "")) == newborn:
			again = true
	check(not again, "a newborn already colonised is dropped rather than flown at twice")

	print("FAILS: %d" % fails)
	quit()
