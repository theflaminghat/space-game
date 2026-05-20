extends Control

const SAVE_DIR := "user://saves/"
const GAME_SCENE := "res://node_3d.tscn"

@onready var save_list: ItemList = $Panel/VBoxContainer/SaveList
@onready var save_name_input: LineEdit = $Panel/VBoxContainer/SaveNameInput

func _ready() -> void:
	ensure_save_dir()
	refresh_save_list()
	save_list.item_selected.connect(_on_save_selected)

func ensure_save_dir() -> void:
	var user_dir := DirAccess.open("user://")
	if user_dir == null:
		print("Could not open user://")
		return

	if not user_dir.dir_exists("saves"):
		var err := user_dir.make_dir("saves")
		if err != OK:
			print("Failed to create saves dir: ", err)

func refresh_save_list() -> void:
	save_list.clear()

	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		print("Could not open save dir: ", SAVE_DIR)
		print("Actual path: ", ProjectSettings.globalize_path(SAVE_DIR))
		return

	dir.list_dir_begin()
	while true:
		var file_name: String = dir.get_next()
		if file_name == "":
			break

		if dir.current_is_dir():
			continue

		if file_name.ends_with(".json"):
			save_list.add_item(file_name.get_basename())

	dir.list_dir_end()
	
func get_selected_save_path() -> String:
	var selected: PackedInt32Array = save_list.get_selected_items()
	if selected.is_empty():
		return ""

	var slot_name: String = save_list.get_item_text(selected[0])
	return SAVE_DIR + slot_name + ".json"
	
func get_input_save_path() -> String:
	var slot_name := save_name_input.text.strip_edges()

	if slot_name == "":
		return ""

	# Optional: sanitize filename
	slot_name = slot_name.replace("/", "_").replace("\\", "_").replace(":", "_")
	return SAVE_DIR + slot_name + ".json"

func _on_save_selected(index: int) -> void:
	save_name_input.text = save_list.get_item_text(index)
	
func _on_new_game_button_pressed() -> void:
	GameSession.should_load_on_start = false
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_load_game_button_pressed() -> void:
	var path := get_input_save_path()

	# If nothing typed, try selected save
	if path == "":
		path = get_selected_save_path()

	if path == "":
		push_warning("Choose or enter a save name.")
		return

	if not FileAccess.file_exists(path):
		push_warning("Save file does not exist: " + path)
		return

	GameSession.current_save_path = path
	GameSession.should_load_on_start = true

	get_tree().change_scene_to_file(GAME_SCENE)
