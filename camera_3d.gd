extends Camera3D

var x_pos
var y_pos
var time
var radius = 5
var offset = 0
var speed = 0.65

func move_to_planet(planet_name:String):
	var planet = get_node("Planets/"+planet_name)
	radius = planet.radius - 0.75
	offset = planet.offset
	speed = planet.speed

func _process(delta):
	time = Time.get_ticks_msec()/1000.0
	x_pos = radius*sin(time*speed+offset)
	y_pos = radius*cos(time*speed+offset)
	position = Vector3(x_pos, 0, y_pos)
	rotation_degrees.y = (time*speed+offset)*(180/3.1415)+180
