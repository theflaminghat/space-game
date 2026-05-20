extends Node3D

var x_pos
var y_pos
var time=0
var radius = 1
var offset = 0
var speed = 0.65
var state = "planet_view"
var set_to_zero = false

@onready var child_node = $Camera3D

func move_to_planet(planet_name:String):
	state = "planet_view"
	var current_planet = get_node("../Planets/"+planet_name)
	radius = current_planet.orbit_radius
	offset = current_planet.orbit_offset
	speed = current_planet.speed
	scale = current_planet.scale
	child_node.set_radius(scale[0])
	
func _ready():
	move_to_planet("earth")

func _process(delta):
	time += delta
	if state=="planet_view":
		if !set_to_zero:
			rotation_degrees = Vector3(0,0,0)
			set_to_zero = true
		var angle = time * speed + offset
		
		position = Vector3(
			radius * sin(angle),
			0.0,
			radius * cos(angle)
		)
		if Input.is_action_pressed("right"):
			rotation_degrees += Vector3(0,1,0)
		elif Input.is_action_pressed("left"):
			rotation_degrees += Vector3(0,-1,0)
		elif Input.is_action_pressed("up") and rotation_degrees[0]>-90:
			rotation_degrees += Vector3(-1,0,0)
		elif Input.is_action_pressed("down") and rotation_degrees[0]<90:
			rotation_degrees += Vector3(1,0,0)


func _on_mercury_button_pressed() -> void:
	move_to_planet("mercury")


func _on_venus_button_pressed() -> void:
	move_to_planet("venus")


func _on_earth_button_pressed() -> void:
	move_to_planet("earth")


func _on_mars_button_pressed() -> void:
	move_to_planet("mars")


func _on_jupiter_button_pressed() -> void:
	move_to_planet("jupiter")


func _on_saturn_button_pressed() -> void:
	move_to_planet("saturn")


func _on_uranus_button_pressed() -> void:
	move_to_planet("uranus")


func _on_neptune_button_pressed() -> void:
	move_to_planet("neptune")


func _on_top_view_pressed() -> void:
	state = "top_view"
	self.position = Vector3(0,30,0)
	rotation_degrees = Vector3(-90,0,0)
