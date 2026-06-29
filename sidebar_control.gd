class_name SidebarControl
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

## Star map and automation panels are created in code (no scene node needed) and live
## beside the other full-area panels in this HBoxContainer.
var star_map: StarMapPanel = null
var automation_panel: AutomationPanel = null
## The cloned "automation" sidebar button, hidden until Industrial AI is researched.
var automation_button: Button = null

func _ready() -> void:
	star_map = StarMapPanel.new()
	star_map.hide()
	# Fills the available panel area (right of the sidebar buttons), like the other panels.
	add_child(star_map)
	_add_cloned_button("star_map", "star map", _on_starmap_pressed)

	automation_panel = AutomationPanel.new()
	automation_panel.hide()
	add_child(automation_panel)
	automation_button = _add_cloned_button("automation", "automation", _on_automation_pressed)
	# Hidden by default; Game reveals it via set_automation_locked() once Industrial AI lands.
	if automation_button:
		automation_button.hide()

## Clone an existing sidebar button so the new one inherits its theme/size, then
## repoint it at the given handler.  Returns the new button (or null).
func _add_cloned_button(node_name: String, label: String, handler: Callable) -> Button:
	var src := get_node_or_null("sidebar/research") as Button
	if src == null:
		return null
	var btn: Button = src.duplicate()
	btn.name = node_name
	btn.text = label
	for conn in btn.pressed.get_connections():
		btn.pressed.disconnect(conn["callable"])
	btn.pressed.connect(handler)
	get_node("sidebar").add_child(btn)
	return btn

## Show/hide the Automation button (and close the panel if it's locked while open).
func set_automation_locked(locked: bool) -> void:
	if automation_button:
		automation_button.visible = not locked
	if locked and automation_panel and automation_panel.visible:
		automation_panel.hide()

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
	if star_map:
		star_map.hide()
	if automation_panel:
		automation_panel.hide()


## Toggle a panel: if it's already open, close everything (return to the default view);
## otherwise hide the others and open it.  Returns true when the panel is now shown.
func _toggle_panel(panel: Control) -> bool:
	var was_visible: bool = panel != null and panel.visible
	hide_all()
	if was_visible:
		return false
	if panel:
		panel.show()
	return true


func _on_research_pressed() -> void:
	_toggle_panel(research_tree)


func _on_launches_pressed() -> void:
	if _toggle_panel(launch_panel):
		# Let Game set the date, default origin, and launch-infrastructure discounts.
		var game := get_tree().current_scene
		if game and game.has_method("refresh_launch_panel"):
			game.refresh_launch_panel()


func _on_evolution_pressed() -> void:
	_toggle_panel(evolution_tree)


func _on_statistics_pressed() -> void:
	_toggle_panel(statistics)


func _on_timeline_pressed() -> void:
	_toggle_panel(timeline_panel)


func _on_politics_pressed() -> void:
	_toggle_panel(politics_page)


func _on_production_pressed() -> void:
	_toggle_panel(production_panel)


func _on_starmap_pressed() -> void:
	if _toggle_panel(star_map):
		var game := get_tree().current_scene
		if game and game.has_method("refresh_star_map"):
			game.refresh_star_map()


func _on_automation_pressed() -> void:
	if _toggle_panel(automation_panel):
		# Refresh dropdowns/stock context if Game wants to (e.g. available fuels).
		var game := get_tree().current_scene
		if game and game.has_method("refresh_automation_panel"):
			game.refresh_automation_panel()
