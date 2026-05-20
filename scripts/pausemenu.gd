extends CanvasLayer

var showing = true

func _input(event):
	if event.is_action_pressed("escape"):
		self.visible = showing
		get_tree().paused = showing
		showing = not showing
