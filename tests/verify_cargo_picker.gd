extends SceneTree

## The Supply Run's item menu is filed by type.
##
## It was one OptionButton listing the origin's whole inventory by formula, so a developed world
## offered sixty entries in the order "Aerogel, Al, Algae, Al2O3, ..." and the thing worth
## sending was somewhere in the scroll.  CargoPicker shows the same goods under the Inventory
## tab's headings, each a fold, by name, with what the origin holds of each.
##
## It drives a hidden OptionButton rather than replacing it (the LaunchBodyPicker pattern), so
## this checks both halves: what the player sees, and that a pick lands in the model every other
## piece of the panel reads.  Clicks are real mouse events pushed into the popup, because a Tree
## in row mode reports a change of row twice and a heading that toggled on each report opened
## and shut inside a single click — which a programmatic select() alone would not have shown.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _click(win: Window, tree: Tree, it: TreeItem, col: int = 0) -> void:
	var at: Vector2 = tree.position + tree.get_item_area_rect(it, col).get_center()
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = at
		e.global_position = at
		win.push_input(e)
		await process_frame

func _heading(tree: Tree, prefix: String) -> TreeItem:
	var h: TreeItem = tree.get_root().get_first_child()
	while h != null and not h.get_text(0).begins_with(prefix):
		h = h.get_next()
	return h

func _child(head: TreeItem, key: String) -> TreeItem:
	var c: TreeItem = head.get_first_child() if head != null else null
	while c != null and str(c.get_metadata(0)) != key:
		c = c.get_next()
	return c

func _choose(opt: OptionButton, text: String) -> void:
	for i in range(opt.item_count):
		if opt.get_item_text(i) == text:
			opt.select(i)
			opt.item_selected.emit(i)
			return

func _run() -> void:
	seed(20261112)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(40): await process_frame
	var g: Node = current_scene
	var us: Node = root.get_node("UISound")
	var cd: Script = load("res://compound_data.gd")
	var cp: Script = load("res://cargo_picker.gd")

	# Something in every heading, and amounts that are easy to recognise.
	var inv: Dictionary = g._planet_inv("earth")
	var stocked := {"Wheat": 2.0e9, "Fe2O3": 3.0e9, "Al": 4.0e9, "Steel": 5.0e9,
		"Plastic": 6.0e9, "Microchip": 7.0e9, "Rocket": 8.0e9}
	for k: String in stocked:
		inv[k] = stocked[k]

	g.sidebar.hide_all()
	g.launch_panel.show()
	g.refresh_launch_panel()
	for _i in range(4): await process_frame
	var lp = g.launch_panel
	_choose(lp.mission_option, "Supply Run")
	for _i in range(4): await process_frame

	# ── The picker stands where the list was, and the list is still the model ──
	var picker = lp._cargo_picker
	check(picker != null, "the launch panel has a cargo picker")
	if picker == null:
		print("FAILS: %d" % fails); quit(); return
	check(picker.is_visible_in_tree(), "it is what the player sees")
	check(not lp._cargo_pick.visible, "the flat list is hidden behind it")
	check(picker.option == lp._cargo_pick, "and it drives that list")
	var offered: Array = []
	for i in range(lp._cargo_pick.item_count):
		offered.append(lp._cargo_pick.get_item_text(i))
	for k: String in stocked:
		check(offered.has(k), "%s is on offer" % k)

	# ── Filed by type, under the Inventory tab's headings, in its order ──
	picker.emit_signal("pressed")
	for _i in range(4): await process_frame
	var tree: Tree = picker._tree
	var win: Window = picker._popup
	check(win.visible, "the menu opens")
	var heads: Array = []
	var seen: Dictionary = {}
	var h: TreeItem = tree.get_root().get_first_child()
	while h != null:
		heads.append(h.get_text(0))
		var c: TreeItem = h.get_first_child()
		var prev_name: String = ""
		while c != null:
			var key: String = str(c.get_metadata(0))
			seen[key] = int(seen.get(key, 0)) + 1
			var cat: String = str(cd.CATEGORIES.get(key, "raw"))
			check(h.get_text(0).begins_with(str(cd.CATEGORY_LABELS[cat])),
				"%s is under %s, not %s" % [key, cd.CATEGORY_LABELS[cat], h.get_text(0)])
			check(c.get_text(0) == str(cd.NAMES.get(key, key)),
				"%s goes by its name: '%s'" % [key, c.get_text(0)])
			check(prev_name.naturalnocasecmp_to(c.get_text(0)) <= 0,
				"by name within a heading: %s after %s" % [c.get_text(0), prev_name])
			prev_name = c.get_text(0)
			c = c.get_next()
		h = h.get_next()
	print("headings: ", heads)
	check(heads.size() == cd.CATEGORY_ORDER.size(), "a heading for each type held: %d" % heads.size())
	var last: int = -1
	for t: String in heads:
		var at: int = -1
		for i in range(cd.CATEGORY_ORDER.size()):
			if t.begins_with(str(cd.CATEGORY_LABELS[cd.CATEGORY_ORDER[i]])):
				at = i
		check(at > last, "headings in the Inventory's order: %s" % t)
		last = at
	for i in range(lp._cargo_pick.item_count):
		var k: String = lp._cargo_pick.get_item_text(i)
		check(int(seen.get(k, 0)) == 1, "%s is listed exactly once: %d" % [k, int(seen.get(k, 0))])

	var refined: TreeItem = _heading(tree, "Refined")
	var steel: TreeItem = _child(refined, "Steel")
	check(steel != null and steel.get_text(1) == Units.format_si(stocked["Steel"], "g"),
		"each entry shows what the origin holds: '%s'" % (steel.get_text(1) if steel else "-"))

	# ── Only the heading holding the current pick is open ──
	var cur_cat: String = str(cd.CATEGORIES.get(picker.selected_key(), "raw"))
	var open: Array = []
	h = tree.get_root().get_first_child()
	while h != null:
		if not h.collapsed:
			open.append(h.get_text(0))
		h = h.get_next()
	check(open.size() == 1 and str(open[0]).begins_with(str(cd.CATEGORY_LABELS[cur_cat])),
		"only the current pick's heading opens: %s" % str(open))

	# ── A heading folds once per click, wherever on it the click lands ──
	# A missing heading fails the run here rather than crashing it further down: a script error
	# aborts _run before quit(), which hangs the harness until its timeout.
	var made: TreeItem = _heading(tree, "Manufactured")
	var food: TreeItem = _heading(tree, "Food")
	check(made != null and food != null, "the headings this test clicks are there")
	if made == null or food == null:
		print("FAILS: %d" % fails); quit(); return
	var was: bool = made.collapsed
	var moves0: int = int(us.plays["move"])
	await _click(win, tree, made)
	for _i in range(2): await process_frame
	check(made.collapsed != was, "a click on the heading opens it")
	await _click(win, tree, made)
	for _i in range(2): await process_frame
	check(made.collapsed == was, "a second click shuts it again")
	await _click(win, tree, made)
	for _i in range(2): await process_frame
	check(made.collapsed != was, "and a third opens it: it is not stuck on either")
	check(int(us.plays["move"]) - moves0 == 3, "one MOVE per fold: %d" % (int(us.plays["move"]) - moves0))
	check(win.visible, "folding does not close the menu")
	# The arrow folds it too — the Tree does that one itself — and sounds the same.
	var food_was: bool = food.collapsed
	moves0 = int(us.plays["move"])
	var arrow: Rect2 = tree.get_item_area_rect(food, 0)
	var at_arrow: Vector2 = tree.position + Vector2(arrow.position.x + 6.0, arrow.get_center().y)
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = at_arrow
		e.global_position = at_arrow
		win.push_input(e)
		await process_frame
	check(food.collapsed != food_was, "the fold arrow works")
	check(int(us.plays["move"]) - moves0 == 1, "and makes the same one sound: %d"
		% (int(us.plays["move"]) - moves0))
	food.collapsed = food_was

	# ── A pick lands in the model, closes the menu, and sounds like a menu pick ──
	var chip: TreeItem = _child(made, "Microchip")
	check(chip != null, "Microchip is under Manufactured Goods")
	if chip == null:
		print("FAILS: %d" % fails); quit(); return
	var sel0: int = int(us.plays["select"])
	await _click(win, tree, chip, 1)       # on the holding, not the name: the row is one target
	for _i in range(3): await process_frame
	check(lp._cargo_pick.get_item_text(lp._cargo_pick.selected) == "Microchip",
		"the pick is the list's selection: %s" % lp._cargo_pick.get_item_text(lp._cargo_pick.selected))
	check(not win.visible, "and the menu closes")
	check(int(us.plays["select"]) - sel0 == 1, "with one SELECT: %d" % (int(us.plays["select"]) - sel0))
	check(picker.text.begins_with(str(cd.NAMES["Microchip"])), "the button says so: '%s'" % picker.text)

	# Choosing what is already chosen closes the menu and clicks, as any dropdown does.  It used to
	# do nothing at all: the click changes no highlight, and the handler listened for one.
	picker.emit_signal("pressed")
	for _i in range(4): await process_frame
	var again: TreeItem = _child(_heading(tree, "Manufactured"), "Microchip")
	check(again != null and again.is_selected(0), "the current pick is highlighted on opening")
	sel0 = int(us.plays["select"])
	await _click(win, tree, again)
	for _i in range(3): await process_frame
	check(not win.visible, "re-choosing it closes the menu")
	check(int(us.plays["select"]) - sel0 == 1, "with a SELECT: %d" % (int(us.plays["select"]) - sel0))

	# Moving the highlight is not choosing: arrow keys walk the list and leave the menu open.
	picker.emit_signal("pressed")
	for _i in range(4): await process_frame
	var key_down := InputEventKey.new()
	key_down.keycode = KEY_DOWN
	key_down.physical_keycode = KEY_DOWN
	key_down.pressed = true
	tree.grab_focus()
	win.push_input(key_down)
	for _i in range(3): await process_frame
	check(win.visible, "an arrow key moves the highlight without picking")
	check(lp._cargo_pick.get_item_text(lp._cargo_pick.selected) == "Microchip",
		"and the pick is unchanged: %s" % lp._cargo_pick.get_item_text(lp._cargo_pick.selected))
	win.hide()
	for _i in range(2): await process_frame

	# And the rest of the panel reads it: Add ships what was picked, listed by name.
	lp._cargo_amt.text = "1G"
	lp._on_cargo_add()
	check(is_equal_approx(float(lp._manifest.get("Microchip", 0.0)), 1.0e9),
		"Add ships the picked good: %s" % str(lp._manifest))

	# The hold lists by name too — checked with something whose name is not its formula.
	picker.emit_signal("pressed")
	for _i in range(4): await process_frame
	var raw_head: TreeItem = _heading(tree, "Raw")
	raw_head.collapsed = false
	await process_frame
	var hem: TreeItem = _child(raw_head, "Fe2O3")
	check(hem != null and hem.get_text(0) == str(cd.NAMES["Fe2O3"]), "Fe2O3 is listed as Hematite")
	if hem != null:
		await _click(win, tree, hem)
		for _i in range(3): await process_frame
		lp._cargo_amt.text = "1G"
		lp._on_cargo_add()
		for _i in range(2): await process_frame
	var rows: Array = []
	for r in lp._cargo_list.get_children():
		if not r.is_queued_for_deletion():
			rows.append((r.get_child(0) as Label).text)
	print("hold rows: ", rows)
	var named: bool = false
	for t: String in rows:
		named = named or t.ends_with(str(cd.NAMES["Fe2O3"]))
	check(named, "the hold lists it by name, not formula: %s" % str(rows))

	# ── A lone heading opens itself; an empty world says so ──
	for k: String in inv.keys():
		inv.erase(k)
	inv["Steel"] = 1.0e9
	inv["Al"] = 1.0e9
	g.refresh_launch_panel()
	lp._refresh_cargo()
	for _i in range(3): await process_frame
	picker.emit_signal("pressed")
	for _i in range(3): await process_frame
	var only: TreeItem = tree.get_root().get_first_child()
	check(only != null and only.get_next() == null, "one type held, one heading")
	check(only != null and not only.collapsed, "and it is open, holding the current pick")
	win.hide()
	inv.clear()
	g.refresh_launch_panel()
	lp._refresh_cargo()
	for _i in range(3): await process_frame
	check(lp._cargo_pick.item_count == 0, "nothing holdable at the origin")
	check(picker.text.begins_with("Nothing here to ship"), "and the button says so: '%s'" % picker.text)

	# ── Picking a body clicks like every other dropdown in the panel ──
	var tp = lp._target_picker
	tp.emit_signal("pressed")
	for _i in range(3): await process_frame
	var body: TreeItem = tp._tree.get_root().get_first_child().get_next()
	sel0 = int(us.plays["select"])
	await _click(tp._popup, tp._tree, body)
	for _i in range(3): await process_frame
	check(int(us.plays["select"]) - sel0 == 1,
		"a body pick plays SELECT, as the OptionButton it replaced did: %d" % (int(us.plays["select"]) - sel0))

	# ── The standing Supply Run rule has the same menu ──
	for k: String in stocked:
		inv[k] = stocked[k]
	g.launch_panel.hide()
	var ap = g.sidebar.automation_panel
	g.sidebar.hide_all()
	ap.show()
	ap.set_launch_stock(g._build_launch_stock())
	_choose(ap._l_mission, "Supply Run")
	for _i in range(4): await process_frame
	var rp = ap._l_cargo_picker
	check(rp != null and rp.get_script() == cp, "the automation rule has a cargo picker too")
	if rp != null:
		check(not ap._l_cargo_pick.visible and rp.option == ap._l_cargo_pick,
			"standing in for its flat list")
		rp.emit_signal("pressed")
		for _i in range(3): await process_frame
		var rhead: TreeItem = _heading(rp._tree, "Refined")
		var rsteel: TreeItem = _child(rhead, "Steel")
		check(rsteel != null, "filed the same way")
		if rsteel != null:
			rhead.collapsed = false          # an item under a shut heading has nowhere to click
			await process_frame
			await _click(rp._popup, rp._tree, rsteel)
			for _i in range(3): await process_frame
			check(ap._l_cargo_pick.get_item_text(ap._l_cargo_pick.selected) == "Steel",
				"and a pick lands in the rule's list")

	print("FAILS: %d" % fails)
	quit()
