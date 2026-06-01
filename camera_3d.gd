extends Camera3D
var n = 1.3

func set_radius(radius: float) -> void:
	n = 1
	position = Vector3(0, 0, 1)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_released("zoom in"):
		if n > 1.3:
			position -= Vector3(0, 0, n)
			n -= 0.3
	elif event.is_action_released("zoom out"):
		n += 0.3
		position += Vector3(0, 0, n)
