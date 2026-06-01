extends Node3D

var state = "planet_view"
var set_to_zero = false
var current_planet: Node3D = null
var world_root: Node3D = null
var planets_root: Node3D = null

@onready var child_node: Camera3D = $Camera3D


func move_to_planet(planet_name: String) -> void:
	state = "planet_view"
	set_to_zero = false

	if planets_root == null:
		push_error("planets_root is null")
		return

	var new_planet := planets_root.get_node_or_null(planet_name) as Node3D
	if new_planet == null:
		push_error("Planet not found: " + planet_name)
		return

	current_planet = new_planet

	if get_parent() != new_planet:
		var old_global := global_transform
		get_parent().remove_child(self)
		new_planet.add_child(self)
		global_transform = old_global

	# Put pivot at the planet origin.
	# Scale must be ONE — the planet's world scale is already inherited through
	# the parent chain.  Setting scale = planet.scale here would make the pivot's
	# world scale = planet_scale², shrinking small planets' camera distance to s²
	# (< visual radius for any planet with s < 0.5, e.g. Mercury at 0.38).
	position = Vector3.ZERO
	rotation_degrees = Vector3.ZERO
	scale = Vector3.ONE

	child_node.set_radius(current_planet.scale.x)


func _ready() -> void:
	# Use absolute references based on the current scene tree,
	# not based on this node's current parent.
	world_root = get_tree().current_scene.get_node("WorldRoot") as Node3D
	planets_root = world_root.get_node("Planets") as Node3D

	move_to_planet("earth")


func _process(delta: float) -> void:
	if state == "planet_view":
		if !set_to_zero:
			rotation_degrees = Vector3.ZERO
			set_to_zero = true

		if Input.is_action_pressed("right"):
			rotation_degrees.y += 1
		elif Input.is_action_pressed("left"):
			rotation_degrees.y -= 1
		elif Input.is_action_pressed("up") and rotation_degrees.x > -90:
			rotation_degrees.x -= 1
		elif Input.is_action_pressed("down") and rotation_degrees.x < 90:
			rotation_degrees.x += 1


func _on_sun_button_pressed() -> void:
	move_to_planet("sun")

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

	if get_parent() != world_root:
		var old_global := global_transform
		get_parent().remove_child(self)
		world_root.add_child(self)
		global_transform = old_global

	global_position = Vector3(0, 30, 0)
	rotation_degrees = Vector3(-90, 0, 0)
