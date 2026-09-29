extends SceneTree

## Clicking a "Signature detected" card takes the player to that star on the star map.
##
## The chain is: _announce carries the star on the notification -> the card is built clickable
## -> TimelineCanvas emits -> TimelinePanel forwards -> Game opens the map and focuses it.
## Each link is checked, then the whole thing is driven by a real click.

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
	var sm = g.sidebar.star_map
	var tl = g.timeline_panel

	# ── The detection names its star ──
	var star: String = ""
	for s in g.star_factions:
		star = str(s)
		break
	check(star != "", "there is a neighbour to detect")
	g._pending_event_notifications.clear()
	g._announce("Signature detected", "A signature resolves at %s." % star,
		"detect_%s_%d" % [star, g.year], {"star": star})
	var notif: Dictionary = g._pending_event_notifications[0]
	check(str(notif.get("star", "")) == star,
		"the event carries its star: '%s'" % str(notif.get("star", "")))
	check(str(notif.get("title", "")) == "Signature detected", "and is the detection card")

	# ── The card is clickable, and only when there is somewhere to go ──
	g.sidebar.timeline_panel.show()
	for _i in range(40): await process_frame
	var canvas: Node = _find_canvas(tl)
	check(canvas != null, "the timeline canvas exists")
	var card: Control = _find_card(canvas, "Signature detected")
	check(card != null, "the detection has a card")
	if card != null:
		check(card.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND,
			"the card invites a click")
		check(card.tooltip_text.contains("star map"), "and says where it goes")
	var plain: Control = _find_card(canvas, "First Atomic Bomb")
	if plain != null:
		check(plain.mouse_default_cursor_shape != Control.CURSOR_POINTING_HAND,
			"a card with no star does not invite one")

	# ── The click takes you there ──
	# Put the map somewhere else entirely first, so arriving at the star is visible as a change.
	sm._yaw = 0.0
	sm._zoom = 1.0
	sm._selected = -1
	sm._selected_cluster = -1
	g.sidebar.hide_all()
	check(not sm.visible, "the star map starts closed")

	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	card.gui_input.emit(ev)
	for _i in range(10): await process_frame

	check(sm.visible, "clicking the card opens the star map")
	check(sm.selected_star() == star,
		"and selects the star: '%s' (wanted '%s')" % [sm.selected_star(), star])
	check(sm._zoom != 1.0, "and zooms to it: %s" % str(sm._zoom))
	print("focused %s | zoom %.2f | yaw %.2f" % [sm.selected_star(), sm._zoom, sm._yaw])

	# ── It is actually ON SCREEN, which is the thing the player asked for ──
	# Zoom and yaw are means; where the star lands is the end. Project it the way _draw does.
	sm.size = Vector2(900, 700)
	var centre: Vector2 = sm.size * 0.5
	var where: Vector2 = sm._project(sm._rel(g._star_pos(star)), sm._view_basis(),
		centre, sm._fit_scale(centre))
	var rect := Rect2(Vector2.ZERO, sm.size)
	check(rect.has_point(where), "the star lands inside the panel: %s in %s" % [str(where), str(sm.size)])
	var from_centre: float = where.distance_to(centre)
	check(from_centre > 40.0,
		"clear of Sol at the centre rather than on top of it: %.0f px out" % from_centre)
	check(from_centre < minf(centre.x, centre.y) * 0.95,
		"and not jammed against the edge: %.0f px out of %.0f" % [
			from_centre, minf(centre.x, centre.y)])
	print("on screen at %s, %.0f px from Sol (panel %s)" % [str(where), from_centre, str(sm.size)])

	# ── Opening it twice does not close it ──
	# The sidebar button toggles; being sent here by something else must not.
	g._on_timeline_star_focus(star)
	for _i in range(5): await process_frame
	check(sm.visible, "being sent there again leaves it open, not toggled shut")

	# ── A name the map cannot resolve still leaves the player at the map ──
	check(not sm.focus_star("no such star"), "an unresolvable name is refused")
	check(sm.selected_star() == star, "and changes nothing")

	print("FAILS: %d" % fails)
	quit()


func _find_canvas(node: Node) -> Node:
	if node.get_class() == "Control" and node.get_script() != null \
			and str(node.get_script().resource_path).ends_with("timeline_canvas.gd"):
		return node
	for c in node.get_children():
		var r: Node = _find_canvas(c)
		if r != null:
			return r
	return null


## The card panel whose title label matches, found by walking the card's own labels.
func _find_card(canvas: Node, title: String) -> Control:
	for card in canvas.get_children():
		if _has_label(card, title):
			return card as Control
	return null


func _has_label(node: Node, text: String) -> bool:
	if node is Label and str((node as Label).text) == text:
		return true
	for c in node.get_children():
		if _has_label(c, text):
			return true
	return false
