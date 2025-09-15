extends CanvasLayer

var show = true

func _input(event):
	if event.is_action_pressed("escape"):
		self.visible = show
		show = not show
