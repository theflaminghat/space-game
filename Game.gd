extends Node

const SCIENCE_INCOME := 10.0
const MINERAL_INCOME := 5.0
const ENERGY_INCOME  := 3.0

var year: int = 2026
var month: int = 0
var day: int = 0
var time_accum: float = 0.0
var days_per_month: Array[int] = [31,28,31,30,31,30,31,31,30,31,30,31]
var stats := {
	"year": 2026,
	"current_population": 8000000000,
	"ai_autonomy": 0.2,
	"existential_risk": 0.12,
	"colony_count": 0
}

@onready var science_label: Label = $main_ui/VBoxContainer3/HBoxContainer/ScienceLabel
@onready var research_ui: Control = $main_ui/VBoxContainer3/HBoxContainer2/research_tree
@onready var time_label: Label = $main_ui/VBoxContainer3/HBoxContainer/time
@onready var statistics_page: Control = $main_ui/VBoxContainer3/HBoxContainer2/StatisticsPage
@onready var sattelite: Node3D = $WorldRoot/Planets/earth/Node3D

func is_leap(y: int) -> bool:
	return (y % 4 == 0 and y % 100 != 0) or (y % 400 == 0)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("escape"):
		SolarSystem.toggle_ui_pause()
		get_tree().paused = SolarSystem.ui_paused

	if event.is_action_pressed("pause"):
		SolarSystem.toggle_pause()
		get_viewport().set_input_as_handled()
		
func start_new_game() -> void:
	ResearchTree.load_tree(ResearchTreeData.build())
	ResearchTree.resources = {
		"science": 0.0,
		"minerals": 0.0,
		"energy": 0.0
	}

	year = 2026
	month = 0
	day = 0
	time_accum = 0.0

func _ready() -> void:
	if not ResearchTree.research_completed.is_connected(_on_research_completed):
		ResearchTree.research_completed.connect(_on_research_completed)

	if GameSession.should_load_on_start and GameSession.current_save_path != "":
		load_game(GameSession.current_save_path)
	else:
		start_new_game()

	_update_hud()

func _process(delta: float) -> void:
	if SolarSystem.paused or SolarSystem.ui_paused:
		return

	time_accum += delta

	while time_accum >= SolarSystem.seconds_per_day:
		time_accum -= SolarSystem.seconds_per_day
		advance_day()

	ResearchTree.resources["science"] = ResearchTree.resources.get("science", 0.0) + SCIENCE_INCOME * delta
	ResearchTree.resources["minerals"] = ResearchTree.resources.get("minerals", 0.0) + MINERAL_INCOME * delta
	ResearchTree.resources["energy"] = ResearchTree.resources.get("energy", 0.0) + ENERGY_INCOME * delta

	statistics_page.set_stats(stats)

	_update_hud()

func advance_day() -> void:
	day += 1

	var dim: int = days_per_month[month]
	if month == 1 and is_leap(year):
		dim = 29

	if day >= dim:
		day = 0
		month += 1
		if month >= 12:
			month = 0
			year += 1

func _on_research_completed(node: ResearchNode) -> void:
	print("[ExampleGame] Unlocked: %s" % node.display_name)

func save_game(path: String = "") -> void:
	if path == "":
		path = GameSession.current_save_path

	if path == "":
		path = "user://saves/default.json"

	var data: Dictionary = {
		"research": ResearchTree.save_state(),
		"year": year,
		"month": month,
		"day": day
	}

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		print("Saved to %s" % path)

func load_game(path: String = "") -> void:
	if path == "":
		path = GameSession.current_save_path

	if path == "":
		return

	if not FileAccess.file_exists(path):
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return

	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary:
		return

	var data: Dictionary = parsed

	ResearchTree.load_tree(ResearchTreeData.build())

	if data.has("research") and data["research"] is Dictionary:
		ResearchTree.load_state(data["research"])

	year = int(data.get("year", 2026))
	month = int(data.get("month", 0))
	day = int(data.get("day", 0))

	print("Loaded from %s" % path)

func _update_hud() -> void:
	if time_label:
		time_label.text = str(year) + " : " + str(month + 1) + " : " + str(day + 1)

	if science_label:
		science_label.text = (
			"Science: %d  |  Minerals: %d  |  Energy: %d" % [
				int(ResearchTree.resources.get("science", 0)),
				int(ResearchTree.resources.get("minerals", 0)),
				int(ResearchTree.resources.get("energy", 0))
			]
		)

func _on_save_pressed() -> void:
	save_game()

func _on_low_speed_pressed() -> void:
	SolarSystem.seconds_per_day = 0.2

func _on_medium_speed_pressed() -> void:
	SolarSystem.seconds_per_day = 0.1

func _on_high_speed_pressed() -> void:
	SolarSystem.seconds_per_day = 0.05
