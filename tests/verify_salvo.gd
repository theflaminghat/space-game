extends SceneTree

## A salvo is one track on the map, carrying its count.
##
## Every round in a salvo leaves the same year for the same star on the same flight plan, so each
## drew at exactly the same place: ten missiles were ten identical strokes on identical pixels,
## distinguishable from one only as overdraw, and ten times the work for one line.

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
	var sm = g.sidebar.star_map
	for n: ResearchNode in load("res://ResearchTreeData.gd").build():
		rt.force_unlock(str(n.id))
	rt.resources["energy"] = 1.0e40
	g._planet_inv("earth")["Missile"] = 1.0e9
	g._planet_inv("earth")["Berserker"] = 1.0e9
	g._mark_prod_dirty(); g._recompute_production_cache()
	var star := ""
	for s in g.star_factions:
		star = str(s); break
	g._detected_aliens[star] = true
	g.sidebar.show_star_map()
	sm.focus_star(star)
	for _i in range(15): await process_frame

	# ── Ten missiles, one track ──
	g.interstellar_attacks.clear()
	g._on_missile_requested(star, 4.0, 1.0, 10)
	g.refresh_star_map()
	check(g.interstellar_attacks.size() == 10, "ten rounds are still ten rounds in the model")
	check(sm._attacks.size() == 1, "but one track on the map: %d" % sm._attacks.size())
	check(int(sm._attacks[0].get("count", 0)) == 10,
		"carrying the count: %d" % int(sm._attacks[0].get("count", 0)))
	check(str(sm._attacks[0].get("target", "")) == star, "aimed at the right star")

	# ── A second salvo is its own track: different flight, different place on it ──
	g.year += 1
	g._on_missile_requested(star, 4.0, 1.0, 3)
	g.refresh_star_map()
	check(sm._attacks.size() == 2, "a later salvo is a separate track: %d" % sm._attacks.size())
	var counts: Array = []
	for a in sm._attacks:
		counts.append(int(a.get("count", 0)))
	counts.sort()
	check(counts == [3, 10], "each with its own count: %s" % str(counts))

	# ── A different weapon never merges with one ──
	g._on_berserker_requested(star, 4.0, 1.0, 5)
	g.refresh_star_map()
	check(sm._attacks.size() == 3, "berserkers are their own track: %d" % sm._attacks.size())
	var kinds: Dictionary = {}
	for a in sm._attacks:
		kinds[str(a.get("kind", ""))] = true
	check(kinds.has("missile") and kinds.has("berserker"), "both weapons are represented")

	# ── The map still draws, with the labels placed ──
	g.year += 70
	g.refresh_star_map()
	sm.size = Vector2(900, 700)
	for _i in range(15): await process_frame
	check(sm._salvo_label_pos.size() == 3, "one label per track: %d" % sm._salvo_label_pos.size())
	# They must not be written on top of each other — that is what made them unreadable.
	for i in range(sm._salvo_label_pos.size()):
		for j in range(i + 1, sm._salvo_label_pos.size()):
			var d: Vector2 = sm._salvo_label_pos[i] - sm._salvo_label_pos[j]
			check(absf(d.x) >= 22.0 or absf(d.y) >= 11.0,
				"labels %d and %d are clear of each other: %s" % [i, j, str(d)])
	print("tracks %d, labels at %s" % [sm._attacks.size(), str(sm._salvo_label_pos)])

	# ── A single round carries no label ──
	g.interstellar_attacks.clear()
	g._on_missile_requested(star, 4.0, 1.0, 1)
	g.refresh_star_map()
	for _i in range(10): await process_frame
	check(int(sm._attacks[0].get("count", 0)) == 1, "a lone missile counts one")
	check(sm._salvo_label_pos.is_empty(), "and is not labelled: %s" % str(sm._salvo_label_pos))

	# ── Arrival: one event per salvo, telling the truth about it ──
	#
	# Resolving round by round, the first arrival erased the system and every round after it
	# reported striking EMPTY SPACE — ten missiles read as one hit and nine misses. Worse, the
	# popup queue keeps the most RECENT few, so the cards the player saw were the misses.
	g.interstellar_attacks.clear()
	g._pending_event_notifications.clear()
	g._on_missile_requested(star, 4.0, 1.0, 10)
	g._on_berserker_requested(star, 4.0, 1.0, 4)
	g._pending_event_notifications.clear()          # drop the launch cards
	check(g.star_factions.has(star), "the target is defended before the strike")
	g.year = int(float(g.interstellar_attacks[0]["end_year"])) + 1
	g._check_interstellar_attacks()

	var notes: Array = g._pending_event_notifications
	check(notes.size() == 2, "fourteen rounds land as two events, one per weapon: %d" % notes.size())
	check(g.interstellar_attacks.is_empty(), "and nothing is left in flight")
	check(not g.star_factions.has(star), "the system is destroyed")
	var seen: Dictionary = {}
	for n in notes:
		seen[str(n["title"])] = str(n["desc"])
	check(seen.has("Relativistic Impact") and seen.has("Berserker Strike"),
		"both weapons report: %s" % str(seen.keys()))
	for t: String in seen:
		var d: String = seen[t]
		check(not d.contains("empty space"),
			"%s does not claim to have hit empty space: %s" % [t, d])
	check(str(seen.get("Relativistic Impact", "")).contains("10 relativistic missiles"),
		"the missiles report their number: %s" % str(seen.get("Relativistic Impact", "")))
	check(str(seen.get("Berserker Strike", "")).contains("4 berserker swarms"),
		"so do the berserkers: %s" % str(seen.get("Berserker Strike", "")))
	print("arrival: %s" % str(seen.values()))

	# A single round still reads as one, and a salvo into a dead system agrees in number.
	for spec: Array in [[1, false, "The relativistic missile shatters"],
			[1, true, "It strikes empty space"], [6, true, "They strike empty space"]]:
		g.interstellar_attacks.clear()
		g._pending_event_notifications.clear()
		g._on_missile_requested(star, 4.0, 1.0, int(spec[0]))
		g._pending_event_notifications.clear()
		if bool(spec[1]):
			g.star_factions.erase(star)
		else:
			g.star_factions[star] = "aggressive"
		g.year = int(float(g.interstellar_attacks[0]["end_year"])) + 1
		g._check_interstellar_attacks()
		check(g._pending_event_notifications.size() == 1,
			"x%d resolves to one event" % int(spec[0]))
		var desc: String = str(g._pending_event_notifications[0]["desc"])
		check(desc.contains(str(spec[2])), "reads correctly: %s" % desc)

	print("FAILS: %d" % fails)
	quit()
