extends Camera3D

## The orbit camera's distance from the focused body, in the pivot's local units (1 = the closest
## framing, about 2× the body's radius — see camera_pivot.gd).
##
## Zoom is kept as a whole number of steps out from the closest framing, and the distance is worked
## out from that count, so zooming out and back in any number of times always returns to exactly
## the same distances.  Each step out is 0.3 longer than the one before: 1, 2.3, 3.9, 5.8, 8.0, …
const MIN_DIST: float = 1.0

var _zoom_steps: int = 0


static func distance_for(steps: int) -> float:
	return MIN_DIST + float(steps) + 0.15 * float(steps) * float(steps + 1)


## Reset to the closest framing; called whenever the camera moves to a new body.
func set_radius(_radius: float) -> void:
	_zoom_steps = 0
	_apply_zoom()


func _apply_zoom() -> void:
	position = Vector3(0, 0, distance_for(_zoom_steps))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_released("zoom in"):
		if _zoom_steps > 0:
			_zoom_steps -= 1
			_apply_zoom()
	elif event.is_action_released("zoom out"):
		_zoom_steps += 1
		_apply_zoom()
