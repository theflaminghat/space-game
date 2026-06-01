extends CanvasLayer

var showing = true

func _input(event):
	if event.is_action_pressed("escape"):
		self.visible = showing
		showing = not showing

func _on_quit_to_menu_pressed() -> void:
	# Reset all pause flags before leaving so the start menu isn't frozen.
	SolarSystem.paused     = false
	SolarSystem.ui_paused  = false
	get_tree().paused      = false
	get_tree().change_scene_to_file("res://start_menu.tscn")
