extends CanvasLayer
class_name Encyclopedia

## In-game encyclopedia.  Toggle with O; Escape, the × button or a click outside the window also
## close it.  Every building, item, recipe, research node, mechanic and console command has a page,
## generated on demand by WikiData from the game's own tables (so a page opened mid-run shows live
## figures — research status, stock on hand, science rate).  Underlined names are links.
##
## Keys typed into any text field (this window's search box, the developer console, a rate entry)
## are left alone, so "o" can still be typed.

const TOGGLE_KEY: Key = KEY_O

var _game: Node = null
var _index: Array = []
var _by_id: Dictionary = {}          # entry id → entry
var _tree_items: Dictionary = {}     # entry id → TreeItem (only those passing the filter)
var _history: Array = []             # ids visited before the current one, for Back
var _current: String = ""
var _syncing: bool = false           # true while the tree selection is set from code

var _tree: Tree
var _text: RichTextLabel
var _search: LineEdit
var _back: Button


func _ready() -> void:
	layer = 95                                  # over the game UI; under the console and menus
	process_mode = Node.PROCESS_MODE_ALWAYS     # readable while the game is paused
	add_to_group("ui_overlay")                  # the 3-D camera and galaxy map stand down while open
	_build_ui()
	visible = false


## Called by Game so pages can read live state.
func setup(game: Node) -> void:
	_game = game


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if visible and key.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
	elif key.keycode == TOGGLE_KEY and not (key.ctrl_pressed or key.alt_pressed or key.meta_pressed) \
			and not _typing():
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


## True while a text field has keyboard focus, so letters belong to it.
func _typing() -> bool:
	var f: Control = get_viewport().gui_get_focus_owner()
	return f != null and f.is_visible_in_tree() and (f is LineEdit or f is TextEdit)


func open(id: String = "") -> void:
	# (Re)built on every open: cheap, and a new run replaces the research tree underneath it.
	_index = WikiData.build_index(_game)
	_by_id.clear()
	for e: Dictionary in _index:
		_by_id[e["id"]] = e
	_populate(_search.text)
	visible = true
	var target: String = id if id != "" else (_current if _current != "" else WikiData.HOME_ID)
	_show(target, false)


func close() -> void:
	visible = false
	if _search.has_focus():
		_search.release_focus()


# ── Navigation ────────────────────────────────────────────────────────────────

func _show(id: String, remember: bool) -> void:
	if id != WikiData.HOME_ID and not _by_id.has(id):
		return
	if remember and _current != "" and _current != id:
		_history.append(_current)
		if _history.size() > 100:
			_history.pop_front()
	_current = id
	if id == WikiData.HOME_ID:
		_text.text = WikiData.home_page(_index)
	else:
		_text.text = WikiData.page(_by_id[id], _game, _index)
	_text.scroll_to_line(0)
	_back.disabled = _history.is_empty()
	_select_in_tree(id)


func _on_back() -> void:
	if _history.is_empty():
		return
	_show(str(_history.pop_back()), false)


func _on_link(meta: Variant) -> void:
	_show(str(meta), true)


func _select_in_tree(id: String) -> void:
	var item: TreeItem = _tree_items.get(id, null)
	if item == null:
		_tree.deselect_all()
		return
	var p: TreeItem = item.get_parent()
	while p != null:
		p.collapsed = false
		p = p.get_parent()
	_syncing = true
	item.select(0)
	_syncing = false
	_tree.scroll_to_item(item)


func _on_tree_selected() -> void:
	if _syncing:
		return
	var item: TreeItem = _tree.get_selected()
	if item == null:
		return
	var id: String = str(item.get_metadata(0))
	if id == "":
		item.collapsed = not item.collapsed    # a category or group: fold it
		item.deselect(0)
		return
	_show(id, true)


# ── Tree ──────────────────────────────────────────────────────────────────────

## Rebuild the entry list, keeping only entries matching every word of `filter`.  With a filter
## everything is expanded; without one, categories start folded so the list reads as a contents.
func _populate(filter: String) -> void:
	var words: PackedStringArray = filter.strip_edges().to_lower().split(" ", false)
	_tree.clear()
	_tree_items.clear()
	var root: TreeItem = _tree.create_item()
	var home: TreeItem = _tree.create_item(root)
	home.set_text(0, "Overview")
	home.set_metadata(0, WikiData.HOME_ID)
	_tree_items[WikiData.HOME_ID] = home
	var current_cat: String = str((_by_id.get(_current, {}) as Dictionary).get("cat", ""))
	for cat: String in WikiData.CATEGORIES:
		var matches: Array = []
		for e: Dictionary in _index:
			if e["cat"] == cat and _matches(e, words):
				matches.append(e)
		if matches.is_empty():
			continue
		var cat_item: TreeItem = _tree.create_item(root)
		cat_item.set_text(0, "%s (%d)" % [cat, matches.size()])
		cat_item.set_metadata(0, "")
		cat_item.set_custom_color(0, Color(0.62, 0.76, 1.0))
		cat_item.collapsed = words.is_empty() and cat != current_cat
		var groups: Dictionary = {}
		for e: Dictionary in matches:
			var parent: TreeItem = cat_item
			var g: String = str(e["group"])
			if g != "":
				if not groups.has(g):
					var gi: TreeItem = _tree.create_item(cat_item)
					gi.set_text(0, g)
					gi.set_metadata(0, "")
					gi.set_custom_color(0, Color(0.70, 0.74, 0.82))
					gi.collapsed = false
					groups[g] = gi
				parent = groups[g]
			var leaf: TreeItem = _tree.create_item(parent)
			leaf.set_text(0, str(e["title"]))
			leaf.set_metadata(0, str(e["id"]))
			_tree_items[str(e["id"])] = leaf
	_select_in_tree(_current)


func _matches(e: Dictionary, words: PackedStringArray) -> bool:
	for w: String in words:
		if str(e["search"]).find(w) < 0:
			return false
	return true


func _on_search(text: String) -> void:
	_populate(text)
	# Jump to the single hit, so typing a full name opens it.
	var leaves: Array = []
	for id: String in _tree_items:
		if id != WikiData.HOME_ID:
			leaves.append(id)
	if leaves.size() == 1:
		_show(str(leaves[0]), true)


# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Dim everything behind, swallow its clicks and scrolls, and close on a click outside.
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			close())
	root.add_child(backdrop)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.07
	panel.anchor_right = 0.93
	panel.anchor_top = 0.06
	panel.anchor_bottom = 0.94
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.10, 0.98)
	sb.border_color = Color(0.35, 0.45, 0.65)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	var title := Label.new()
	title.text = "Encyclopedia"
	title.add_theme_font_size_override("font_size", 22)
	head.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_search = LineEdit.new()
	_search.placeholder_text = "Search…"
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(320, 0)
	_search.text_changed.connect(_on_search)
	head.add_child(_search)
	_back = Button.new()
	_back.text = "◀ Back"
	_back.disabled = true
	_back.pressed.connect(_on_back)
	head.add_child(_back)
	var home := Button.new()
	home.text = "Overview"
	home.pressed.connect(func() -> void: _show(WikiData.HOME_ID, true))
	head.add_child(home)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.custom_minimum_size = Vector2(36, 0)
	close_btn.pressed.connect(close)
	head.add_child(close_btn)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(split)
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.custom_minimum_size = Vector2(340, 0)
	_tree.item_selected.connect(_on_tree_selected)
	split.add_child(_tree)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.selection_enabled = true
	_text.scroll_active = true
	_text.meta_underlined = true
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("normal_font_size", 15)
	_text.add_theme_font_size_override("bold_font_size", 15)
	_text.add_theme_font_size_override("mono_font_size", 14)
	_text.meta_clicked.connect(_on_link)
	split.add_child(_text)

	var hint := Label.new()
	hint.text = "O or Esc to close  ·  underlined names are links  ·  the simulation keeps running while this is open"
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(0.60, 0.66, 0.78)
	col.add_child(hint)
