extends HBoxContainer

@onready var research_tree: Control = $research_tree
@onready var evolution_tree: Control = $EvolutionTreeUI
@onready var statistics: Control = $StatisticsPage
@onready var timeline_panel: Control = $TimelinePanel
@onready var politics_page: Control = $PoliticsPage
@onready var planet_info_page: PanelContainer = $"../../PlanetInfoPage"
@onready var build_panel: PanelContainer = $"../../BuildPanel"
@onready var launch_panel: PanelContainer = $"../../LaunchPanel"
@onready var production_panel: PanelContainer = $"../../ProductionPanel"

func hide_all() -> void:
	research_tree.hide()
	evolution_tree.hide()
	statistics.hide()
	timeline_panel.hide()
	politics_page.hide()
	planet_info_page.hide()
	build_panel.hide()
	launch_panel.hide()
	production_panel.hide()


func _on_research_pressed() -> void:
	hide_all()
	research_tree.show()


func _on_launches_pressed() -> void:
	hide_all()
	launch_panel.show()
	# Let Game set the date, default origin, and launch-infrastructure discounts.
	var game := get_tree().current_scene
	if game and game.has_method("refresh_launch_panel"):
		game.refresh_launch_panel()


func _on_evolution_pressed() -> void:
	hide_all()
	evolution_tree.show()


func _on_statistics_pressed() -> void:
	hide_all()
	statistics.show()


func _on_timeline_pressed() -> void:
	hide_all()
	timeline_panel.show()


func _on_politics_pressed() -> void:
	hide_all()
	politics_page.show()


func _on_production_pressed() -> void:
	hide_all()
	production_panel.show()
