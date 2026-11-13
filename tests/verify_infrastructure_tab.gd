extends SceneTree

## Opening the Infrastructure tab does not freeze the game.
##
## It took about two seconds, and it was two things.  Text with a symbol the UI font lacks made
## Godot search the system's fonts for every label (verify_ui_font.gd has that half).  And the
## list built every level of every building — some 3 200 controls — for a tab that opens with all
## of them folded away.  A card's levels are built the first time it is opened now, so the list
## costs its headers and nothing else until somebody looks inside one.
##
## Which moves the risk: apply_counts patched rows it assumed every level had, and decided a
## rebuild was due by counting them against the catalogue.  With cards unopened that count never
## matches, so the guard would have rebuilt the whole list on every refresh — the original
## stutter, four times a second.  So this checks the list stays put across refreshes, that an
## unopened card's header still moves, and that a card opened late comes up current.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c

## The card for one building family, found by its toggle's text.
func _card(bp: Node, base: String) -> Node:
	for n: Node in bp.build_list.get_children():
		if n is VBoxContainer and n.get_child_count() > 0 and n.get_child(0).get_child_count() > 0:
			var t: Node = n.get_child(0).get_child(0)
			if t is Button and (t as Button).text.ends_with("  " + base):
				return n
	return null

func _run() -> void:
	seed(20261112)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(40): await process_frame
	var g: Node = current_scene
	var bp = g.build_panel
	g.current_planet = "earth"
	g._planet_tabs.visible = true
	g._planet_tabs.current_tab = bp.get_index()
	g._refresh_planet_tabs()
	for _i in range(3): await process_frame

	# ── The list is headers until a card is opened ──
	var families: int = bp._families.size()
	var nodes: int = _count(bp.build_list)
	print("%d families, %d controls in the list" % [families, nodes])
	check(families > 20, "the catalogue is all there: %d families" % families)
	check(nodes < families * 10, "and costs its headers, not its levels: %d controls for %d cards"
		% [nodes, families])
	check(bp._rows.is_empty(), "no level has been built yet: %d rows" % bp._rows.size())

	# Pick a family that stands on Earth from the start, so its count can move.
	var base: String = ""
	for b: String in bp._families:
		var tiers: Array = bp._families[b]["tiers"]
		if int((tiers[0] as Dictionary).get("count", 0)) > 0:
			base = b
			break
	check(base != "", "a family with buildings standing on Earth")
	if base == "":
		print("FAILS: %d" % fails); quit(); return
	var card: Node = _card(bp, base)
	check(card != null, "its card is in the list")
	if card == null:
		print("FAILS: %d" % fails); quit(); return
	var body: Control = card.get_child(1)
	var toggle: Button = card.get_child(0).get_child(0)
	check(not body.visible and body.get_child(0).get_child_count() == 0,
		"its body is folded and empty")

	# ── A refresh that changes nothing structural does not rebuild ──
	var before: Array = bp.build_list.get_children()
	bp.apply_counts(g._get_catalog_for_display())
	check(bp.build_list.get_children() == before,
		"a refresh with every card shut patches in place rather than rebuilding")
	if bp.build_list.get_children() != before:
		print("FAILS: %d" % fails); quit(); return    # the cards below were freed with the old list

	# ── An unopened card's header still follows the roster ──
	var tier0: String = str((bp._families[base]["tiers"][0] as Dictionary)["name"])
	var total_lbl: Label = bp._families[base]["total"]
	var was_total: int = int(total_lbl.text)
	(g.planet_buildings["earth"] as Array).append(tier0)
	g._mark_prod_dirty("earth")
	bp.apply_counts(g._get_catalog_for_display())
	check(int(total_lbl.text) == was_total + 1, "the shut card's total moves: %s, was %d"
		% [total_lbl.text, was_total])
	check(bp.build_list.get_children() == before, "still without a rebuild")

	# ── A card opened late comes up current, not as the list was built ──
	toggle.emit_signal("pressed")
	await process_frame
	check(body.visible, "opening the card shows it")
	check(bp._rows.has(tier0), "and builds its levels: %s" % str(bp._rows.keys()))
	if bp._rows.has(tier0):
		# The Active slider's ceiling is the level's standing count when the level is built (a
		# single-level card's own count label is hidden and blank; the header carries the number).
		var asl: HSlider = bp._rows[tier0]["active_slider"]
		var want: int = g._count_building("earth", tier0)
		check(asl != null and int(asl.max_value) == want,
			"with today's count, %d, not the one the list was built with: %s"
				% [want, str(asl.max_value) if asl else "no slider"])
	var grown: int = _count(bp.build_list)
	check(grown > nodes, "the levels cost their controls only once opened: %d → %d" % [nodes, grown])

	# Shutting and reopening reuses what was built.
	var row_before: Variant = bp._rows.get(tier0)
	toggle.emit_signal("pressed")
	toggle.emit_signal("pressed")
	await process_frame
	check(_count(bp.build_list) == grown, "reopening builds nothing twice")
	check(bp._rows.get(tier0) == row_before, "and keeps the same row")

	# ── An opened card is patched in place, as before ──
	(g.planet_buildings["earth"] as Array).append(tier0)
	g._mark_prod_dirty("earth")
	bp.apply_counts(g._get_catalog_for_display())
	if bp._rows.has(tier0):
		var asl2: HSlider = bp._rows[tier0]["active_slider"]
		check(asl2 != null and int(asl2.max_value) == g._count_building("earth", tier0),
			"an opened card is patched in place: %s" % (str(asl2.max_value) if asl2 else "no slider"))
	check(bp.build_list.get_children() == before, "with the list still standing")

	# ── A change of shape still rebuilds ──
	var cat: Array = g._get_catalog_for_display()
	var reshaped: Array = cat.duplicate(true)
	var flip: Dictionary = reshaped[0]
	flip["available"] = not bool(flip.get("available", true))
	bp.apply_counts(reshaped)
	check(bp.build_list.get_children() != before, "a level turning available rebuilds the list")

	print("FAILS: %d" % fails)
	quit()
