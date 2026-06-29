extends Control

const SAVE_DIR  := "user://saves/"
const GAME_SCENE := "res://node_3d.tscn"

@onready var _load_panel: PanelContainer = $LoadPanel
@onready var _save_list:  ItemList       = $LoadPanel/MarginContainer/VBoxContainer/SaveList
@onready var _save_input: LineEdit       = $LoadPanel/MarginContainer/VBoxContainer/SaveNameInput
@onready var _settings:   CanvasLayer    = $SettingsMenu


func _ready() -> void:
	_ensure_save_dir()
	# Make the god-mode sandbox slot available if it isn't already (non-destructive —
	# never overwrites an existing file, so a player can save over the slot if they want).
	if not FileAccess.file_exists(SandboxSave.SAVE_PATH):
		SandboxSave.write()
	_refresh_save_list()


func _ensure_save_dir() -> void:
	var user_dir := DirAccess.open("user://")
	if user_dir == null:
		return
	if not user_dir.dir_exists("saves"):
		user_dir.make_dir("saves")


func _refresh_save_list() -> void:
	_save_list.clear()
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var file_name: String = dir.get_next()
		if file_name == "":
			break
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			_save_list.add_item(file_name.get_basename())
	dir.list_dir_end()


func _on_save_selected(index: int) -> void:
	_save_input.text = _save_list.get_item_text(index)


func _on_new_game_button_pressed() -> void:
	GameSession.should_load_on_start = false
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_load_game_button_pressed() -> void:
	_load_panel.visible = true


func _on_load_confirm_pressed() -> void:
	var slot := _save_input.text.strip_edges()
	if slot == "":
		var sel: PackedInt32Array = _save_list.get_selected_items()
		if not sel.is_empty():
			slot = _save_list.get_item_text(sel[0])
	if slot == "":
		push_warning("Choose or enter a save name.")
		return
	slot = slot.replace("/", "_").replace("\\", "_").replace(":", "_")
	var path := SAVE_DIR + slot + ".json"
	if not FileAccess.file_exists(path):
		push_warning("Save file does not exist: " + path)
		return
	GameSession.current_save_path = path
	GameSession.should_load_on_start = true
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_cancel_pressed() -> void:
	_load_panel.visible = false


func _on_settings_button_pressed() -> void:
	_settings.visible = true


func _on_quit_button_pressed() -> void:
	get_tree().quit()
