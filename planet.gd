class_name planet extends MeshInstance3D

var x_pos
var y_pos
var time
@export var radius = 1
@export var offset = 0
@export var speed = 1.0



func _process(delta):
	time = Time.get_ticks_msec()/1000.0
	x_pos = radius*sin(time*speed+offset)
	y_pos = radius*cos(time*speed+offset)
	position = Vector3(x_pos, 0, y_pos)
