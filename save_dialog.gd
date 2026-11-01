class_name SaveDialog
extends CanvasLayer

## Naming a save.
##
## Saving already worked; it just had nothing to say and nowhere to put the answer. Pressing
## Save wrote `user://saves/default.json` without asking, so every run that had not been loaded
## from a named slot overwrote the same file, and there was no way to keep two games at once or
## to tell which one you were in.
##
## Game is the authority, as it is for every other panel here: this emits `save_requested` and
## shows whatever comes back from `set_result`. It never writes a file itself, so what the
## dialog reports and what is on disk cannot disagree.
##
## PROCESS_MODE_ALWAYS, because the pause menu it opens from is itself only reachable with the
## tree paused — a dialog that cannot be clicked would be worse than no dialog.

## The player pressed Save with this name. Game sanitises and writes; see Game._on_save_requested.
signal save_requested(slot: String)

const SAVE_DIR: String = "user://saves/"

## A slot name reduced to something that can be a filename.
##
## The same three characters StartMenu strips, and deliberately the same rule: a name saved here
## has to be a name that menu can find again, and two sanitisers that drift apart would produce
## saves the player cannot load.
static func sanitise(slot: String) -> String:
	return slot.strip_edges().replace("/", "_").replace("\\", "_").replace(":", "_")


## Where a named slot lives, or "" if the name is not usable.
static func slot_path(slot: String) -> String:
	var clean: String = sanitise(slot)
	if clean == "":
		return ""
	return SAVE_DIR + clean + ".json"


## Every save already on disk, by name, sorted.
static func existing_slots() -> Array:
	var out: Array = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	while true:
		var f: String = dir.get_next()
		if f == "":
			break
		if not dir.current_is_dir() and f.ends_with(".json"):
			out.append(f.get_basename())
	dir.list_dir_end()
	out.sort()
	return out


var _name_edit: LineEdit = null
var _list: ItemList = null
var _status: Label = null
var _save_btn: Button = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 128                      # above the pause menu that opens it
	hide()

	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP   # nothing behind it is clickable
	add_child(shade)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(440, 420)
	add_child(panel)

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	margin.add_child(vb)

	var title := Label.new()
	title.text = "Save game"
	title.add_theme_font_size_override("font_size", 18)
	vb.add_child(title)

	var hint := Label.new()
	hint.text = "Name this save, or pick one below to overwrite."
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(0.72, 0.76, 0.84)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hint)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Save name"
	_name_edit.text_changed.connect(func(_t: String) -> void: _refresh_state())
	# Enter saves, which is what a one-field dialog should do.
	_name_edit.text_submitted.connect(func(_t: String) -> void: _on_save())
	vb.add_child(_name_edit)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(0, 180)
	_list.item_selected.connect(func(i: int) -> void:
		_name_edit.text = _list.get_item_text(i)
		_refresh_state())
	vb.add_child(_list)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 11)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_status)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(close)
	row.add_child(cancel)
	_save_btn = Button.new()
	_save_btn.text = "Save"
	_save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_btn.pressed.connect(_on_save)
	row.add_child(_save_btn)


## Show the dialog, with `default_name` filled in and ready to be typed over.
func open(default_name: String) -> void:
	_list.clear()
	for slot: String in existing_slots():
		_list.add_item(slot)
	_name_edit.text = default_name
	_status.text = ""
	show()
	_name_edit.grab_focus()
	_name_edit.select_all()
	_refresh_state()


func close() -> void:
	hide()


## Whether the name is usable, and whether using it would replace something.
func _refresh_state() -> void:
	var clean: String = sanitise(_name_edit.text)
	_save_btn.disabled = clean == ""
	if clean == "":
		_status.text = "Enter a name."
		_status.modulate = Color(0.85, 0.70, 0.45)
		return
	if FileAccess.file_exists(slot_path(clean)):
		_status.text = "\"%s\" already exists — saving replaces it." % clean
		_status.modulate = Color(0.92, 0.78, 0.45)
	else:
		_status.text = "Will be saved as \"%s\"." % clean
		_status.modulate = Color(0.70, 0.80, 0.95)


func _on_save() -> void:
	var clean: String = sanitise(_name_edit.text)
	if clean == "":
		_refresh_state()
		return
	save_requested.emit(clean)


## Game reports what actually happened to the file.  A failure leaves the dialog OPEN, so the
## player can try another name rather than being told nothing and assuming it worked.
func set_result(ok: bool, message: String) -> void:
	_status.text = message
	_status.modulate = Color(0.55, 0.85, 0.60) if ok else Color(0.95, 0.50, 0.40)
	if ok:
		close()
