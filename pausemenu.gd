extends CanvasLayer

var showing = true


func _ready() -> void:
	# Both ways out of the run. Save and Settings open a panel instead, so they keep the
	# ordinary navigation sound.
	UISound.mark($VBoxContainer/quit_to_menu, UISound.BACK)
	UISound.mark($VBoxContainer/quit, UISound.BACK)


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
