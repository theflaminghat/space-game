extends Control
class_name EvolutionTreeControl

signal node_selected(node_id: String)

const NODE_SIZE: Vector2 = Vector2(170, 72)
const LINE_WIDTH: float = 3.0

const COLOR_BG: Color = Color(0.08, 0.09, 0.11)
const COLOR_GRID: Color = Color(1, 1, 1, 0.04)
const COLOR_LINE: Color = Color(0.75, 0.8, 0.9, 0.35)
const COLOR_LINE_HIGHLIGHT: Color = Color(0.9, 0.95, 1.0, 0.85)

const COLOR_LOCKED: Color = Color(0.20, 0.22, 0.26)
const COLOR_AVAILABLE: Color = Color(0.20, 0.34, 0.52)
const COLOR_UNLOCKED: Color = Color(0.18, 0.48, 0.26)
const COLOR_SELECTED: Color = Color(0.78, 0.68, 0.22)
const COLOR_TEXT: Color = Color(0.95, 0.97, 1.0)
const COLOR_SUBTEXT: Color = Color(0.82, 0.86, 0.92)

var tree_data: Dictionary = {}
var unlocked: Dictionary = {}
var selected_id: String = ""
var hovered_id: String = ""

var _node_rects: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()

func load_tree(data: Dictionary, unlocked_map: Dictionary = {}) -> void:
	tree_data = data.duplicate(true)
	unlocked = unlocked_map.duplicate(true)
	_rebuild_bounds()
	queue_redraw()

func set_unlocked_map(unlocked_map: Dictionary) -> void:
	unlocked = unlocked_map.duplicate(true)
	queue_redraw()

func unlock_node(node_id: String) -> void:
	unlocked[node_id] = true
	queue_redraw()

func is_unlocked(node_id: String) -> bool:
	return bool(unlocked.get(node_id, false))

func is_available(node_id: String) -> bool:
	if not tree_data.has(node_id):
		return false
	if is_unlocked(node_id):
		return false

	var node: Dictionary = tree_data[node_id]
	var parents: Array = node.get("parents", [])
	for p: Variant in parents:
		if not is_unlocked(str(p)):
			return false
	return true

func _rebuild_bounds() -> void:
	var max_x: float = 1200.0
	var max_y: float = 800.0

	for key: Variant in tree_data.keys():
		var node: Dictionary = tree_data[key]
		var pos: Vector2 = node.get("pos", Vector2.ZERO)
		max_x = max(max_x, pos.x + NODE_SIZE.x + 120.0)
		max_y = max(max_y, pos.y + NODE_SIZE.y + 120.0)

	custom_minimum_size = Vector2(max_x, max_y)
	size = custom_minimum_size

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BG, true)
	_draw_grid()
	_node_rects.clear()
	_draw_connections()
	_draw_nodes()

func _draw_grid() -> void:
	var step: float = 100.0
	var x: float = 0.0
	while x <= size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), COLOR_GRID, 1.0)
		x += step

	var y: float = 0.0
	while y <= size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), COLOR_GRID, 1.0)
		y += step

func _draw_connections() -> void:
	for key: Variant in tree_data.keys():
		var node_id: String = str(key)
		var node: Dictionary = tree_data[node_id]
		var pos: Vector2 = node.get("pos", Vector2.ZERO)

		for parent_v: Variant in node.get("parents", []):
			var parent_id: String = str(parent_v)
			if not tree_data.has(parent_id):
				continue

			var parent: Dictionary = tree_data[parent_id]
			var parent_pos: Vector2 = parent.get("pos", Vector2.ZERO)

			var start: Vector2 = parent_pos + Vector2(NODE_SIZE.x, NODE_SIZE.y * 0.5)
			var end: Vector2 = pos + Vector2(0, NODE_SIZE.y * 0.5)
			var mid_x: float = (start.x + end.x) * 0.5

			var highlight: bool = (
				hovered_id == node_id
				or hovered_id == parent_id
				or selected_id == node_id
				or selected_id == parent_id
			)

			var line_color: Color = COLOR_LINE_HIGHLIGHT if highlight else COLOR_LINE

			draw_polyline(
				PackedVector2Array([
					start,
					Vector2(mid_x, start.y),
					Vector2(mid_x, end.y),
					end
				]),
				line_color,
				LINE_WIDTH,
				true
			)

func _draw_nodes() -> void:
	var title_font: Font = get_theme_default_font()
	var title_size: int = 15
	var sub_size: int = 12

	for key: Variant in tree_data.keys():
		var node_id: String = str(key)
		var node: Dictionary = tree_data[node_id]
		var pos: Vector2 = node.get("pos", Vector2.ZERO)
		var rect: Rect2 = Rect2(pos, NODE_SIZE)
		_node_rects[node_id] = rect

		var base_color: Color = COLOR_LOCKED
		if is_unlocked(node_id):
			base_color = COLOR_UNLOCKED
		elif is_available(node_id):
			base_color = COLOR_AVAILABLE

		if node_id == selected_id:
			base_color = base_color.lerp(COLOR_SELECTED, 0.45)
		elif node_id == hovered_id:
			base_color = base_color.lightened(0.12)

		_draw_node_box(rect, base_color)

		var title: String = str(node.get("name", node_id))
		var subtitle: String = str(node.get("subtitle", ""))

		draw_string(
			title_font,
			rect.position + Vector2(12, 24),
			title,
			HORIZONTAL_ALIGNMENT_LEFT,
			rect.size.x - 24.0,
			title_size,
			COLOR_TEXT
		)

		if subtitle != "":
			draw_string(
				title_font,
				rect.position + Vector2(12, 48),
				subtitle,
				HORIZONTAL_ALIGNMENT_LEFT,
				rect.size.x - 24.0,
				sub_size,
				COLOR_SUBTEXT
			)

func _draw_node_box(rect: Rect2, color: Color) -> void:
	draw_rect(rect, color, true)
	draw_rect(rect, Color(1, 1, 1, 0.12), false, 2.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mouse_pos: Vector2 = event.position
		var found: String = ""

		for key: Variant in _node_rects.keys():
			var id: String = str(key)
			if (_node_rects[id] as Rect2).has_point(mouse_pos):
				found = id
				break

		if hovered_id != found:
			hovered_id = found
			_update_tooltip()
			queue_redraw()

	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			for key: Variant in _node_rects.keys():
				var id: String = str(key)
				if (_node_rects[id] as Rect2).has_point(event.position):
					selected_id = id
					node_selected.emit(id)
					queue_redraw()
					return

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		hovered_id = ""
		_update_tooltip()
		queue_redraw()

func _update_tooltip() -> void:
	if hovered_id == "" or not tree_data.has(hovered_id):
		tooltip_text = ""
		return

	var node: Dictionary = tree_data[hovered_id]
	var parents_text: String = ""
	var parents: Array = node.get("parents", [])

	if not parents.is_empty():
		var names: PackedStringArray = PackedStringArray()
		for p: Variant in parents:
			names.append(str(p))
		parents_text = "\nParents: " + ", ".join(names)

	var status: String = "Locked"
	if is_unlocked(hovered_id):
		status = "Unlocked"
	elif is_available(hovered_id):
		status = "Available"

	tooltip_text = "%s\n%s\nStatus: %s%s" % [
		str(node.get("name", hovered_id)),
		str(node.get("description", "")),
		status,
		parents_text
	]
