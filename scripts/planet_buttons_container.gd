extends VBoxContainer


var showing = false

func _on_planets_pressed() -> void:
	if !showing:
		self.visible = true
	else:
		self.visible = false
	showing = !showing
