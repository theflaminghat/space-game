extends Control

var showing: bool = false

const NODE_W: float = 200.0
const NODE_H: float = 56.0
const TIER_GAP_X: float = 220.0
const NODE_GAP_Y: float = 90.0

const TREE_LEFT_PAD: float = 40.0
const TREE_TOP_PAD: float = 90.0
const TREE_RIGHT_PAD: float = 360.0   # extra right scroll room so the last column
									  # can be panned out from under the info panel
const TREE_BOTTOM_PAD: float = 40.0

const INFO_PANEL_W: float = 260.0
const INFO_PANEL_MARGIN_R: float = 48.0   # inset from the right edge
const INFO_PANEL_GAP: float = 64

const LINE_STUB: float = 18.0
const LINE_WIDTH: float = 2.0

const PAN_STEP: int = 80

var _scroll: ScrollContainer
var _tree_container: Control
var _conn_layer: Control
var _tooltip: PanelContainer
var _tooltip_title: Label
var _tooltip_desc: Label
var _tooltip_cost: Label
var _info_panel: PanelContainer
var _info_title: Label
var _info_desc: Label
var _info_unlocks: Label
var _info_cost: Label
var _info_boosts: Label
var _progress_bar: ProgressBar
var _research_btn: Button

var _tooltip_boosts: Label

var _node_rects: Dictionary = {}
var _node_controls: Dictionary = {}
var _queue_labels: Dictionary = {}
var _selected_id: String = ""
var _tooltip_timer: Timer
var _hovered_node_id: String = ""
var _hovered_button: Button = null
var _tooltip_ready: bool = false
var _tooltip_margin: Vector2 = Vector2(16, 16)

var _drag_panning: bool = false
var _drag_last_mouse_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_scene()

	ResearchTree.node_state_changed.connect(_on_node_state_changed)
	ResearchTree.research_completed.connect(_on_research_completed)
	ResearchTree.queue_changed.connect(_update_queue_labels)

	if ResearchTree.nodes.is_empty():
		ResearchTree.resources = {
			"science": 9999.0,
			"minerals": 9999.0,
			"energy": 9999.0
		}
		ResearchTree.load_tree(ResearchTreeData.build())

	_populate_tree()


func _process(delta: float) -> void:
	ResearchTree.tick(delta)
	_update_progress_bar()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton

		# Always swallow wheel input while the mouse is over the tech tree
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP \
		or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN \
		or mb.button_index == MOUSE_BUTTON_WHEEL_LEFT \
		or mb.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
			if mb.shift_pressed:
				if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
					_scroll.scroll_horizontal = max(_scroll.scroll_horizontal - PAN_STEP, 0)
				elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
					_scroll.scroll_horizontal += PAN_STEP
				elif mb.button_index == MOUSE_BUTTON_WHEEL_LEFT:
					_scroll.scroll_horizontal = max(_scroll.scroll_horizontal - PAN_STEP, 0)
				elif mb.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
					_scroll.scroll_horizontal += PAN_STEP
			else:
				# Optional: normal wheel also pans horizontally since vertical scrolling is disabled
				if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
					_scroll.scroll_horizontal = max(_scroll.scroll_horizontal - PAN_STEP, 0)
				elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
					_scroll.scroll_horizontal += PAN_STEP
				elif mb.button_index == MOUSE_BUTTON_WHEEL_LEFT:
					_scroll.scroll_horizontal = max(_scroll.scroll_horizontal - PAN_STEP, 0)
				elif mb.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
					_scroll.scroll_horizontal += PAN_STEP

			accept_event()
			get_viewport().set_input_as_handled()
			return

		# Middle mouse drag panning
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_drag_panning = true
				_drag_last_mouse_pos = mb.position
			else:
				_drag_panning = false

			accept_event()
			get_viewport().set_input_as_handled()
			return

	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion

		if _drag_panning:
			var delta: Vector2 = mm.position - _drag_last_mouse_pos
			_scroll.scroll_horizontal = max(_scroll.scroll_horizontal - int(delta.x), 0)
			_drag_last_mouse_pos = mm.position
			accept_event()
			get_viewport().set_input_as_handled()
			return


func _build_scene() -> void:
	_scroll = ScrollContainer.new()
	_scroll.anchor_left = 0.0
	_scroll.anchor_top = 0.0
	_scroll.anchor_right = 1.0
	_scroll.anchor_bottom = 1.0
	_scroll.offset_left = 0.0
	_scroll.offset_top = 0.0
	_scroll.offset_right = 0.0   # tree fills the full width; info panel floats on top
	_scroll.offset_bottom = 0.0
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	add_child(_scroll)

	_tree_container = Control.new()
	_tree_container.name = "TreeContainer"
	_tree_container.custom_minimum_size = Vector2(1200, 700)
	_scroll.add_child(_tree_container)

	_tooltip = PanelContainer.new()
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.z_index = 20
	_tooltip.visible = false
	_tooltip.position = Vector2(-10000, -10000)
	add_child(_tooltip)

	var tt_box: VBoxContainer = VBoxContainer.new()
	tt_box.add_theme_constant_override("separation", 4)
	_tooltip.add_child(tt_box)

	_tooltip_title = _make_label("", true)
	_tooltip_desc = _make_label("", false, true)
	_tooltip_cost = _make_label("")
	_tooltip_boosts = _make_label("")
	_tooltip_boosts.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22))
	tt_box.add_child(_tooltip_title)
	tt_box.add_child(_tooltip_desc)
	tt_box.add_child(_tooltip_cost)
	tt_box.add_child(_tooltip_boosts)

	_tooltip_timer = Timer.new()
	_tooltip_timer.wait_time = 0.08
	_tooltip_timer.one_shot = true
	_tooltip_timer.timeout.connect(_try_hide_tooltip)
	add_child(_tooltip_timer)

	# Info panel floats on the right (z_index 10) over the full-width tree, inset
	# slightly from the edge by INFO_PANEL_MARGIN_R.
	_info_panel = PanelContainer.new()
	_info_panel.custom_minimum_size = Vector2(INFO_PANEL_W, 0)
	_info_panel.anchor_left = 1.0
	_info_panel.anchor_right = 1.0
	_info_panel.anchor_top = 0.0
	_info_panel.anchor_bottom = 0.0
	_info_panel.offset_left = -(INFO_PANEL_W + INFO_PANEL_MARGIN_R)
	_info_panel.offset_right = -INFO_PANEL_MARGIN_R
	_info_panel.offset_top = 8.0
	_info_panel.z_index = 10
	add_child(_info_panel)

	var info_box: VBoxContainer = VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 8)
	_info_panel.add_child(info_box)

	_info_title = _make_label("", true)
	_info_desc = _make_label("", false, true)
	_info_cost = _make_label("")
	_info_boosts = _make_label("")
	_info_boosts.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22))

	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0
	_progress_bar.max_value = 100
	_progress_bar.value = 0
	_progress_bar.custom_minimum_size = Vector2(0, 18)

	_research_btn = Button.new()
	_research_btn.text = "Add to Queue"
	_research_btn.pressed.connect(_on_research_button_pressed)

	_info_unlocks = _make_label("", false, true)
	_info_unlocks.add_theme_color_override("font_color", Color(0.70, 0.85, 1.00))
	_info_unlocks.add_theme_font_size_override("font_size", 12)

	info_box.add_child(_info_title)
	info_box.add_child(_info_desc)
	info_box.add_child(_info_unlocks)
	info_box.add_child(_info_cost)
	info_box.add_child(_info_boosts)
	info_box.add_child(_progress_bar)
	info_box.add_child(_research_btn)

	_info_panel.hide()


func _make_label(txt: String, bold: bool = false, do_wrap: bool = false) -> Label:
	var l: Label = Label.new()
	l.text = txt
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if do_wrap else TextServer.AUTOWRAP_OFF
	if bold:
		l.add_theme_font_size_override("font_size", 15)
	return l


func _populate_tree() -> void:
	for child: Node in _tree_container.get_children():
		child.queue_free()

	_node_rects.clear()
	_node_controls.clear()
	_queue_labels.clear()

	var min_x: float = 999999.0
	var min_y: float = 999999.0
	var max_x: float = -999999.0
	var max_y: float = -999999.0

	# First pass: find bounds from the actual tech tree positions
	for node_value: Variant in ResearchTree.nodes.values():
		var node: ResearchNode = node_value as ResearchNode
		var pos: Vector2 = node.position

		min_x = min(min_x, pos.x)
		min_y = min(min_y, pos.y)
		max_x = max(max_x, pos.x + NODE_W)
		max_y = max(max_y, pos.y + NODE_H)

	# Keep everything inside positive UI space with padding
	var shift: Vector2 = Vector2.ZERO
	if min_x < TREE_LEFT_PAD:
		shift.x = TREE_LEFT_PAD - min_x
	if min_y < TREE_TOP_PAD:
		shift.y = TREE_TOP_PAD - min_y

	# Second pass: create buttons using the stored positions
	for node_value: Variant in ResearchTree.nodes.values():
		var node: ResearchNode = node_value as ResearchNode
		var pos: Vector2 = node.position + shift
		_create_node_button(node, pos)

	var canvas_width: float = max_x + shift.x + TREE_RIGHT_PAD
	var canvas_height: float = max(600.0, max_y + shift.y + TREE_BOTTOM_PAD)

	_tree_container.custom_minimum_size = Vector2(canvas_width, canvas_height)
	_tree_container.size = Vector2(canvas_width, canvas_height)

	if _conn_layer != null and is_instance_valid(_conn_layer):
		_conn_layer.queue_free()

	_conn_layer = Control.new()
	_conn_layer.name = "ConnectionLayer"
	_conn_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_conn_layer.position = Vector2.ZERO
	_conn_layer.size = Vector2(canvas_width, canvas_height)
	_tree_container.add_child(_conn_layer)
	_tree_container.move_child(_conn_layer, 0)
	_conn_layer.draw.connect(_draw_connections)
	_conn_layer.queue_redraw()

	call_deferred("_reset_scroll_position")


func _reset_scroll_position() -> void:
	if _scroll != null:
		_scroll.scroll_horizontal = 0
		_scroll.scroll_vertical = 0


func _create_node_button(node: ResearchNode, pos: Vector2) -> void:
	var btn: Button = Button.new()
	btn.custom_minimum_size = Vector2(NODE_W, NODE_H)
	btn.position = pos
	btn.size = Vector2(NODE_W, NODE_H)
	btn.text = node.display_name
	btn.clip_text = true

	_style_button(btn, node)

	btn.pressed.connect(_on_node_pressed.bind(node.id))
	btn.mouse_entered.connect(_on_node_hovered.bind(node.id, btn))
	btn.mouse_exited.connect(_on_node_unhovered.bind(node.id, btn))

	# Queue-position badge: small label anchored to top-right of the button
	var queue_label := Label.new()
	queue_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_label.anchor_left  = 1.0
	queue_label.anchor_right  = 1.0
	queue_label.anchor_top    = 0.0
	queue_label.anchor_bottom = 0.0
	queue_label.offset_left   = -24.0
	queue_label.offset_right  = -3.0
	queue_label.offset_top    = 3.0
	queue_label.offset_bottom = 21.0
	queue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	queue_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	queue_label.add_theme_font_size_override("font_size", 11)
	queue_label.z_index = 10
	queue_label.visible = false
	var badge_bg := StyleBoxFlat.new()
	badge_bg.bg_color = Color(0.0, 0.0, 0.0, 0.78)
	badge_bg.set_corner_radius_all(4)
	queue_label.add_theme_stylebox_override("normal", badge_bg)
	btn.add_child(queue_label)
	_queue_labels[node.id] = queue_label

	_tree_container.add_child(btn)
	_node_controls[node.id] = btn
	_node_rects[node.id] = Rect2(pos, Vector2(NODE_W, NODE_H))


func _style_button(btn: Button, node: ResearchNode) -> void:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.set_corner_radius_all(6)
	s.set_border_width_all(2)

	match node.state:
		ResearchNode.State.LOCKED:
			s.bg_color = Color(0.14, 0.14, 0.14)
			s.border_color = Color(0.28, 0.28, 0.28)
			btn.modulate = Color(0.62, 0.62, 0.62)

		ResearchNode.State.AVAILABLE:
			s.bg_color = Color(0.12, 0.38, 0.70)
			s.border_color = Color(0.55, 0.82, 1.0)
			btn.modulate = Color.WHITE

		ResearchNode.State.RESEARCHING:
			s.bg_color = Color(0.45, 0.30, 0.02)
			s.border_color = Color(1.0, 0.82, 0.18)
			btn.modulate = Color.WHITE

		ResearchNode.State.UNLOCKED:
			s.bg_color = Color(0.06, 0.34, 0.14)
			s.border_color = Color(0.25, 0.90, 0.45)
			btn.modulate = Color.WHITE

	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", s)
	btn.add_theme_stylebox_override("pressed", s)
	btn.add_theme_stylebox_override("focus", s)


func _draw_connections() -> void:
	for node_value: Variant in ResearchTree.nodes.values():
		var node: ResearchNode = node_value as ResearchNode

		for child_id_value: Variant in node.unlocks:
			var child_id: String = child_id_value as String

			if not _node_rects.has(node.id) or not _node_rects.has(child_id):
				continue

			var from_rect: Rect2 = _node_rects[node.id] as Rect2
			var to_rect: Rect2 = _node_rects[child_id] as Rect2

			var start: Vector2 = from_rect.position + Vector2(from_rect.size.x, from_rect.size.y * 0.5)
			var end: Vector2 = to_rect.position + Vector2(0.0, to_rect.size.y * 0.5)

			var child_node: ResearchNode = ResearchTree.get_research_node(child_id)
			var col: Color = Color(0.33, 0.33, 0.33)

			if child_node.state == ResearchNode.State.UNLOCKED:
				# Both ends done — full green
				col = Color(0.35, 0.92, 0.50, 0.90)
			elif child_node.state == ResearchNode.State.RESEARCHING:
				col = Color(1.0, 0.78, 0.20, 0.95)
			elif child_node.state == ResearchNode.State.AVAILABLE:
				col = Color(0.45, 0.78, 1.0, 0.95)
			elif node.state == ResearchNode.State.UNLOCKED:
				# Parent is done but child still needs other prerequisites —
				# dim green so the line lights up along the numerical_methods
				# path even when the child is waiting on a second prerequisite.
				col = Color(0.25, 0.65, 0.35, 0.65)

			_draw_elbow_connection(start, end, col, LINE_WIDTH)


func _draw_elbow_connection(start: Vector2, end: Vector2, col: Color, width: float) -> void:
	var start_stub_x: float = start.x + LINE_STUB
	var end_stub_x: float = end.x - LINE_STUB
	var lane_x: float = (start_stub_x + end_stub_x) * 0.5

	if lane_x <= start.x + 4.0:
		lane_x = start.x + 24.0
	if lane_x >= end.x - 4.0:
		lane_x = end.x - 24.0

	var p1: Vector2 = start
	var p2: Vector2 = Vector2(start_stub_x, start.y)
	var p3: Vector2 = Vector2(lane_x, start.y)
	var p4: Vector2 = Vector2(lane_x, end.y)
	var p5: Vector2 = Vector2(end_stub_x, end.y)
	var p6: Vector2 = end

	_conn_layer.draw_line(p1, p2, col, width)
	_conn_layer.draw_line(p2, p3, col, width)
	_conn_layer.draw_line(p3, p4, col, width)
	_conn_layer.draw_line(p4, p5, col, width)
	_conn_layer.draw_line(p5, p6, col, width)


func _on_node_pressed(node_id: String) -> void:
	_selected_id = node_id
	var node: ResearchNode = ResearchTree.get_research_node(node_id)
	if node == null:
		return

	_info_title.text = node.display_name
	_info_desc.text = node.description
	var unlocks_text: String = _format_unlocks(node)
	_info_unlocks.text = unlocks_text
	_info_unlocks.visible = not unlocks_text.is_empty()
	_info_cost.text = _format_cost(node.cost)
	_info_boosts.text = _format_boosts(node.boosts)
	_info_boosts.visible = not node.boosts.is_empty()
	_progress_bar.value = node.progress * 100.0
	_progress_bar.visible = node.state == ResearchNode.State.RESEARCHING

	var is_active: bool = ResearchTree.active_research != null \
		and ResearchTree.active_research.id == node_id
	var queue_pos: int = ResearchTree.research_queue.find(node_id)
	var in_queue: bool = queue_pos >= 0

	match node.state:
		ResearchNode.State.LOCKED:
			_research_btn.text = "Locked"
			_research_btn.disabled = true
		ResearchNode.State.AVAILABLE:
			_research_btn.text = "Add to Queue"
			_research_btn.disabled = false
		ResearchNode.State.RESEARCHING:
			_research_btn.text = "Cancel Research"
			_research_btn.disabled = false
		ResearchNode.State.UNLOCKED:
			_research_btn.text = "Unlocked ✓"
			_research_btn.disabled = true

	if in_queue:
		_research_btn.text = "Remove from Queue (#%d)" % (queue_pos + 2)
		_research_btn.disabled = false

	_info_panel.show()


func _on_node_hovered(node_id: String, btn: Button) -> void:
	var node: ResearchNode = ResearchTree.get_research_node(node_id)
	if node == null:
		return

	_hovered_node_id = node_id
	_hovered_button = btn
	_tooltip_timer.stop()
	_tooltip_ready = false

	_tooltip_title.text = node.display_name
	_tooltip_desc.text = node.description
	_tooltip_cost.text = _format_cost(node.cost)
	_tooltip_boosts.text = _format_boosts(node.boosts)
	_tooltip_boosts.visible = not node.boosts.is_empty()

	_tooltip.position = Vector2(-10000, -10000)
	_tooltip.visible = true

	call_deferred("_finalize_tooltip_show", node_id, btn)


func _finalize_tooltip_show(node_id: String, btn: Button) -> void:
	await get_tree().process_frame

	if _hovered_node_id != node_id:
		return
	if btn == null or not is_instance_valid(btn):
		return

	var min_size: Vector2 = _tooltip.get_combined_minimum_size()
	_tooltip.size = min_size
	_tooltip_ready = true
	_update_tooltip_position()


func _on_node_unhovered(node_id: String, btn: Button) -> void:
	if _hovered_node_id == node_id and _hovered_button == btn:
		_tooltip_timer.start()


func _on_research_button_pressed() -> void:
	if _selected_id.is_empty():
		return

	var node: ResearchNode = ResearchTree.get_research_node(_selected_id)
	if node == null:
		return

	var is_active: bool = ResearchTree.active_research != null \
		and ResearchTree.active_research.id == _selected_id
	var in_queue: bool = ResearchTree.research_queue.has(_selected_id)

	if is_active:
		ResearchTree.cancel_research()
	elif in_queue:
		ResearchTree.remove_from_queue(_selected_id)
	elif node.state == ResearchNode.State.AVAILABLE:
		ResearchTree.start_research(_selected_id)

	_on_node_pressed(_selected_id)


func _on_node_state_changed(node: ResearchNode) -> void:
	if _node_controls.has(node.id):
		var btn: Button = _node_controls[node.id] as Button
		_style_button(btn, node)

	if _conn_layer != null and is_instance_valid(_conn_layer):
		_conn_layer.queue_redraw()

	if _selected_id == node.id:
		_on_node_pressed(node.id)

	_update_queue_labels()

	if node.state == ResearchNode.State.AVAILABLE and _node_controls.has(node.id):
		var btn_available: Button = _node_controls[node.id] as Button
		var tw: Tween = create_tween()
		tw.tween_property(btn_available, "scale", Vector2(1.05, 1.05), 0.10)
		tw.tween_property(btn_available, "scale", Vector2.ONE, 0.12)


func _on_research_completed(node: ResearchNode) -> void:
	if not _node_controls.has(node.id):
		return

	var btn: Button = _node_controls[node.id] as Button
	var tw: Tween = create_tween()
	tw.tween_property(btn, "modulate", Color(0.6, 1.6, 0.8), 0.15)
	tw.tween_property(btn, "modulate", Color.WHITE, 0.35)


func _update_progress_bar() -> void:
	if ResearchTree.active_research == null or _selected_id.is_empty():
		return

	if _selected_id == ResearchTree.active_research.id:
		_progress_bar.value = ResearchTree.active_research.progress * 100.0

	if _conn_layer != null and is_instance_valid(_conn_layer):
		_conn_layer.queue_redraw()


func _update_tooltip_position() -> void:
	if not _tooltip.visible or not _tooltip_ready:
		return
	if _hovered_button == null or not is_instance_valid(_hovered_button):
		return

	var mouse_pos: Vector2 = get_local_mouse_position()
	var tip_pos: Vector2 = mouse_pos + _tooltip_margin
	var tooltip_size: Vector2 = _tooltip.size

	var right_limit: float = size.x - tooltip_size.x - 8.0
	if _info_panel.visible:
		# Panel is right-anchored — keep the tooltip to the left of it.
		var info_left: float = _info_panel.get_global_rect().position.x - global_position.x
		right_limit = min(right_limit, info_left - tooltip_size.x - 8.0)

	tip_pos.x = clamp(tip_pos.x, 4.0, max(4.0, right_limit))
	tip_pos.y = clamp(tip_pos.y, 4.0, max(4.0, size.y - tooltip_size.y - 4.0))

	_tooltip.position = tip_pos


func _try_hide_tooltip() -> void:
	var mouse_pos: Vector2 = get_local_mouse_position()
	var over_tooltip: bool = false

	if _tooltip.visible and _tooltip_ready:
		over_tooltip = Rect2(_tooltip.position, _tooltip.size).has_point(mouse_pos)

	var over_hovered_button: bool = false
	if _hovered_button != null and is_instance_valid(_hovered_button):
		var local_pos: Vector2 = _hovered_button.global_position - global_position
		var rect: Rect2 = Rect2(local_pos, _hovered_button.size)
		over_hovered_button = rect.has_point(mouse_pos)

	if over_tooltip or over_hovered_button:
		return

	_hovered_node_id = ""
	_hovered_button = null
	_tooltip_ready = false
	_tooltip.visible = false
	_tooltip.position = Vector2(-10000, -10000)


func _update_queue_labels() -> void:
	for nid_v: Variant in _queue_labels.keys():
		var lbl: Label = _queue_labels[nid_v as String] as Label
		lbl.visible = false
		lbl.text = ""

	if ResearchTree.active_research != null:
		var aid: String = ResearchTree.active_research.id
		if _queue_labels.has(aid):
			var lbl: Label = _queue_labels[aid] as Label
			lbl.text = "1"
			lbl.visible = true

	for i: int in range(ResearchTree.research_queue.size()):
		var qid: String = ResearchTree.research_queue[i] as String
		if _queue_labels.has(qid):
			var lbl: Label = _queue_labels[qid] as Label
			lbl.text = str(i + 2)
			lbl.visible = true


func _format_boosts(boosts: Dictionary) -> String:
	if boosts.is_empty():
		return ""
	var label_map: Dictionary = {
		"research_speed":    "Research Speed",
		"matter_production": "Matter Output",
		"energy_production": "Energy Output",
		"science_production":"Compute Output",
	}
	var parts: Array[String] = []
	for key_v: Variant in boosts.keys():
		var key: String = key_v as String
		var label: String = label_map.get(key, key.capitalize())
		parts.append("%s +%d%%" % [label, int(float(boosts[key]) * 100.0)])
	return "Unlocks: " + "  |  ".join(parts)


func _format_unlocks(node: ResearchNode) -> String:
	var lines: Array[String] = []

	# Child research nodes this node directly unlocks
	if not node.unlocks.is_empty():
		lines.append("Enables research:")
		for child_id_v: Variant in node.unlocks:
			var child_id: String = child_id_v as String
			var child: ResearchNode = ResearchTree.get_research_node(child_id)
			if child != null:
				lines.append("  • " + child.display_name)

	# Buildings gated behind this node
	var buildings: Array[String] = []
	for bname_v: Variant in BuildingUnlocks.BUILDING_UNLOCK_REQUIREMENTS.keys():
		var bname: String = bname_v as String
		var req: String = BuildingUnlocks.BUILDING_UNLOCK_REQUIREMENTS[bname] as String
		if req == node.id:
			buildings.append(bname)
	if not buildings.is_empty():
		if not lines.is_empty():
			lines.append("")
		lines.append("Enables buildings:")
		for b: String in buildings:
			lines.append("  • " + b)

	return "\n".join(lines)


func _format_cost(cost: Dictionary) -> String:
	if cost.is_empty():
		return "Free"

	# Costs are production-scaled (science can reach ~1e29), so format with SI
	# prefixes instead of printing a raw 30-digit integer.
	const UNITS := {"science": "FLOP", "energy": "J", "minerals": "g"}
	var total: float = 0.0
	var parts: Array[String] = []
	for key_value: Variant in cost.keys():
		var k: String = key_value as String
		var v: float = float(cost[k])
		total += v
		if v > 0.0:
			parts.append("%s: %s" % [k.capitalize(), Units.format_si(v, UNITS.get(k, ""))])

	if total <= 0.0:
		return "Free"
	return "  |  ".join(parts)


func _on_research_pressed() -> void:
	if not showing:
		self.visible = true
	else:
		self.visible = false
	showing = not showing
