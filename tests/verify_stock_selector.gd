extends SceneTree

## The launch panel's founding-population selector.
##
## Game owns the order and the panel only asks for it, so what matters is that the two cannot
## drift apart: a refused order must leave the dropdowns where they were rather than showing a
## selection the simulation never accepted, and Game pushing a result back must not echo out
## again as if the player had touched the control.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _colony_mission_index() -> int:
	for i in range(MissionData.MISSION_TYPES.size()):
		if str(MissionData.MISSION_TYPES[i].get("name", "")) == "Colony Ship":
			return i
	return -1

func _run() -> void:
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var SD = load("res://stock_data.gd")
	var p = g.launch_panel
	g.sidebar.hide_all()
	# SHOWN, which the measurements at the end of this file depend on: a hidden Control is never
	# laid out, so its rect is whatever it was last given — and an assertion about overflow run
	# against one of those compares two numbers that mean nothing.  Asking a hidden panel where
	# its children are reported a 76-pixel overflow that was not there.
	p.show()
	g.refresh_launch_panel()
	for _i in range(4): await process_frame

	# ── It exists, and it offers exactly what the data says ──
	check(p._founders_option != null, "there is a founder-group selector")
	check(p._traits_button != null, "and a trait menu")
	var menu: PopupMenu = p._traits_button.get_popup()
	check(p._founders_option.item_count == SD.FOUNDERS.size(),
		"every founder group is offered: %d of %d" % [
			p._founders_option.item_count, SD.FOUNDERS.size()])
	check(menu.item_count == SD.TRAITS.size(),
		"and every trait: %d of %d" % [menu.item_count, SD.TRAITS.size()])
	check(p._founders_ids == SD.founders_ids(), "the ids line up with the rows")
	check(p._trait_ids == SD.trait_ids(), "for both")
	# Checkboxes and not one choice: a stock holds a SET of traits, and a dropdown cannot say
	# that.  This is the assertion that fails if the menu is ever built as plain items.
	for i in range(menu.item_count):
		check(menu.is_item_checkable(i), "trait %d is a checkbox" % i)
		check(menu.get_item_tooltip(i).length() > 20, "and %d says what it trades" % i)
	# Ticking a box must not shut the menu — picking three traits is three clicks.
	check(not menu.hide_on_checkable_item_selection,
		"and the menu stays open while they are ticked")
	for i in range(p._founders_option.item_count):
		check(p._founders_option.get_item_tooltip(i).length() > 20,
			"founder group %d says what it costs" % i)

	# ── Shown only for the mission that carries people ──
	var colony: int = _colony_mission_index()
	check(colony >= 0, "there is a Colony Ship mission")
	for i in range(MissionData.MISSION_TYPES.size()):
		p.mission_option.selected = i
		p._refresh_stock_ui()
		var want: bool = i == colony
		check(p._stock_box.visible == want,
			"%s %s the selector" % [MissionData.MISSION_TYPES[i]["name"],
				"shows" if want else "hides"])
	p.mission_option.selected = colony
	p._refresh_stock_ui()

	# ── A sequence nobody holds cannot be ticked ──
	# Greyed rather than silently snapping back, which would read as a bug.
	g._push_colony_stock()
	for i in range(menu.item_count):
		check(menu.is_item_disabled(i),
			"with an empty archive and no Synthetic Biology, %s cannot be ordered"
				% str(p._trait_ids[i]))
	root.get_node("ResearchTree").force_unlock("synthetic_biology")
	g._push_colony_stock()
	for i in range(menu.item_count):
		check(not menu.is_item_disabled(i),
			"once a sequence can be written, %s is live" % str(p._trait_ids[i]))

	# ── The controls show what the simulation holds ──
	check(g.set_colony_stock("broad", ["longevity"]) == "",
		"set an order behind the panel's back")
	g._push_colony_stock()
	check(str(p._founders_ids[p._founders_option.selected]) == "broad",
		"a push moves the founder dropdown")
	check(menu.is_item_checked(p._trait_ids.find("longevity")),
		"and ticks the trait the order carries")
	check(p._traits_button.text.find("Extended") >= 0,
		"with the button naming it: %s" % p._traits_button.text)
	# Past one it counts instead, because three names do not fit a 400px column — but the
	# tooltip still says which three, or the count is all the player ever gets.
	g.set_colony_stock("broad", ["longevity", "high_intelligence"])
	g._push_colony_stock()
	check(p._traits_button.text.find("2") >= 0,
		"two ticked reads as a count: %s" % p._traits_button.text)
	check(p._traits_button.tooltip_text.find("Extended") >= 0
			and p._traits_button.tooltip_text.find("Intelligence") >= 0,
		"with both named in the tooltip: %s" % p._traits_button.tooltip_text)
	g.set_colony_stock("broad", ["longevity"])
	g._push_colony_stock()
	check(p._stock_effects.text.find("founders") >= 0,
		"and the readout says what is aboard: %s" % p._stock_effects.text)

	# ── A push does not echo back out as a player action ──
	# Without the guard this is an infinite loop between the panel and Game, and the symptom
	# would be a selector that fights the player rather than an obvious crash.
	var emitted: Array = []
	p.colony_stock_changed.connect(func(f: String, t: Array): emitted.append([f, t]))
	g._push_colony_stock()
	check(emitted.is_empty(), "pushing the order back emits nothing: %s" % str(emitted))

	# ── Choosing in the panel reaches the simulation ──
	var minimal_i: int = p._founders_ids.find("minimal")
	p._founders_option.selected = minimal_i
	p._emit_stock()
	check(str(g.colony_stock["founders"]) == "minimal",
		"picking a founder group sets the order: %s" % str(g.colony_stock))
	check((g.colony_stock["traits"] as Array) == ["longevity"],
		"and leaves the traits alone")
	check(emitted.size() == 1, "exactly one request went out: %s" % str(emitted))

	# ── Ticking a trait in the menu reaches the simulation ──
	var clever_i: int = p._trait_ids.find("high_intelligence")
	menu.id_pressed.emit(clever_i)
	check((g.colony_stock["traits"] as Array).has("high_intelligence"),
		"ticking one adds it: %s" % str(g.colony_stock["traits"]))
	check((g.colony_stock["traits"] as Array).has("longevity"),
		"without dropping what was already ticked")
	menu.id_pressed.emit(clever_i)
	check(not (g.colony_stock["traits"] as Array).has("high_intelligence"),
		"and unticking takes it off again: %s" % str(g.colony_stock["traits"]))
	# A fourth is refused by Game, and the panel is pushed back to what was accepted rather
	# than being left showing an order the simulation does not have.
	g.set_colony_stock("minimal", SD.trait_ids().slice(0, SD.MAX_TRAITS))
	g._push_colony_stock()
	var spare: String = str(SD.trait_ids()[SD.MAX_TRAITS])
	menu.id_pressed.emit(p._trait_ids.find(spare))
	check((g.colony_stock["traits"] as Array).size() == SD.MAX_TRAITS,
		"a fourth trait is refused: %s" % str(g.colony_stock["traits"]))
	check(not menu.is_item_checked(p._trait_ids.find(spare)),
		"and the box it was ticked in comes back off")

	# ── The cost follows the group ──
	# A bigger founding population is more to lift, and that has to be visible before launch or
	# the choice is free and "broad" is simply correct.
	g.set_colony_stock("minimal", [])
	g._push_colony_stock()
	var cheap: int = p._mission_rockets(colony)
	g.set_colony_stock("broad", [])
	g._push_colony_stock()
	var dear: int = p._mission_rockets(colony)
	check(dear > cheap, "a broad group costs more vehicles: %d vs %d" % [dear, cheap])
	# And only for the mission that carries anybody.
	var probe: int = -1
	for i in range(MissionData.MISSION_TYPES.size()):
		if str(MissionData.MISSION_TYPES[i].get("name", "")) == "Research Probe":
			probe = i
	if probe >= 0:
		g.set_colony_stock("minimal", [])
		g._push_colony_stock()
		var probe_cheap: int = p._mission_rockets(probe)
		g.set_colony_stock("broad", [])
		g._push_colony_stock()
		check(p._mission_rockets(probe) == probe_cheap,
			"a probe carries nobody and costs the same either way")

	# ── Both injected editors are in the form, not past the launch list ──
	# add_child appends to the end of the panel's VBox, which is after the launch button and the
	# active-launch list — where the cargo manifest sat unseen until this was noticed.  Each has
	# to be moved up, and the cheap way to say so is that both come before the launch button.
	var vbox: Control = p.get_node("MarginContainer/VBoxContainer")
	check(p._stock_box.get_parent() == vbox, "the selector is in the form column")
	check(p._cargo_box.get_parent() == vbox, "and so is the cargo manifest")
	check(p._stock_box.get_index() < p.launch_button.get_index(),
		"the selector comes before the launch button: %d vs %d" % [
			p._stock_box.get_index(), p.launch_button.get_index()])
	check(p._cargo_box.get_index() < p.launch_button.get_index(),
		"and so does the cargo manifest: %d vs %d" % [
			p._cargo_box.get_index(), p.launch_button.get_index()])
	# And neither spills out of the panel.  Measured rather than eyeballed, because a panel that
	# sits flush against the window edge looks exactly like one whose last control is cut off —
	# the rects tell the two apart and a screenshot does not.
	p.mission_option.selected = colony
	p._refresh_stock_ui()
	p._refresh_cargo()
	await process_frame
	await process_frame
	# The cargo manifest is held to the same rule: it shares the column, so a row of its that
	# pushes the panel open widens every other row with it.
	p.mission_option.selected = p._cargo_mission_index() if p.has_method("_cargo_mission_index") else colony
	for i in range(MissionData.MISSION_TYPES.size()):
		if bool(MissionData.MISSION_TYPES[i].get("cargo", false)):
			p.mission_option.selected = i
	p._refresh_stock_ui()
	p._refresh_cargo()
	await process_frame
	await process_frame
	for child in p._cargo_box.get_children():
		var cc: Control = child as Control
		if cc == null or not cc.visible:
			continue
		check(cc.get_global_rect().end.x <= vbox.get_global_rect().end.x + 0.5,
			"cargo %s stays inside the panel: %.1f vs %.1f" % [cc.get_class(),
				cc.get_global_rect().end.x, vbox.get_global_rect().end.x])
	p.mission_option.selected = colony
	p._refresh_stock_ui()
	p._refresh_cargo()
	await process_frame
	await process_frame
	for box: Control in [p._stock_box]:
		for child in box.get_children():
			var c: Control = child as Control
			if c == null or not c.visible:
				continue
			check(c.get_global_rect().end.x <= vbox.get_global_rect().end.x + 0.5,
				"%s stays inside the panel: %.1f vs %.1f" % [c.get_class(),
					c.get_global_rect().end.x, vbox.get_global_rect().end.x])

	print("FAILS: %d" % fails)
	quit()
