extends MeshInstance3D

# Rotation speed in radians per second
@export var rotation_speed: Vector3 = Vector3(0, 1, 0) # rotates around Y-axis

func _process(delta: float) -> void:
	# Apply rotation each frame
	rotate_x(rotation_speed.x * delta)
	rotate_y(rotation_speed.y * delta)
	rotate_z(rotation_speed.z * delta)
