extends Camera3D
var n=1
func set_radius(radius:float):
	n=1
	position = Vector3(0,0,1)

func _process(_delta):
	if Input.is_action_just_released("zoom in"):
		if n>1:
			position -= Vector3(0,0,n)
			n-=0.3
	if Input.is_action_just_released("zoom out"):
		n+=0.3
		position += Vector3(0,0,n)
