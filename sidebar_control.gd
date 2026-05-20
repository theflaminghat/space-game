extends HBoxContainer

@onready var research_tree: Control = $research_tree
@onready var evolution_tree: Control = $EvolutionTreeUI
@onready var planet_info: PanelContainer = $PlanetInfoPage
@onready var statistics: Control = $StatisticsPage
@onready var planet_buttons: VBoxContainer = $planet_buttons_container

func hide_all() -> void:
	research_tree.hide()
	evolution_tree.hide()
	statistics.hide()
	planet_buttons.hide()

func _on_top_view_pressed() -> void:
	hide_all()


func _on_research_pressed() -> void:
	hide_all()
	research_tree.show()


func _on_launches_pressed() -> void:
	hide_all()


func _on_evolution_pressed() -> void:
	hide_all()
	evolution_tree.show()


func _on_statistics_pressed() -> void:
	hide_all()
	statistics.show()

var planet_data = {"name":"earth"}
func _on_planets_pressed() -> void:
	hide_all()
	planet_info.set_planet_info(planet_data)
	planet_buttons.show()
