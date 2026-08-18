extends Node3D

var state = "planet_view"
var set_to_zero = false
var current_planet: Node3D = null
var world_root: Node3D = null
var planets_root: Node3D = null

@onready var child_node: Camera3D = $Camera3D

## Camera rotation speed in degrees per second.  Scaled by frame delta so the feel
## is identical at any frame rate (a fixed per-frame step made it faster on
## higher-FPS displays).
const ROT_SPEED: float = 60.0


func move_to_planet(planet_name: String) -> void:
	if planets_root == null:
		push_error("planets_root is null")
		return
	var new_planet := planets_root.get_node_or_null(planet_name) as Node3D
	if new_planet == null:
		push_error("Planet not found: " + planet_name)
		return
	focus_node(new_planet)

## Reparent the pivot onto ANY body (planet, moon, or the sun) so the camera orbits it.
## Works for nested bodies (a planet's moon) because the pivot keeps local scale ONE and
## inherits the target's world scale through the parent chain — the camera sits one
## local unit out, which frames each body at ~2× its radius regardless of absolute size.
func focus_node(target: Node3D) -> void:
	state = "planet_view"
	set_to_zero = false
	if target == null:
		return

	current_planet = target

	if get_parent() != target:
		var old_global := global_transform
		get_parent().remove_child(self)
		target.add_child(self)
		global_transform = old_global

	# Put pivot at the body origin.  Scale must be ONE — the body's world scale is already
	# inherited through the parent chain (setting it to the body's scale would square it).
	position = Vector3.ZERO
	rotation_degrees = Vector3.ZERO
	scale = Vector3.ONE

	child_node.set_radius(1.0)


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

		# WASD is shared with the galaxy map's panning, and Input.is_action_pressed polls raw
		# device state — a panel can't consume it.  So the camera simply stands down whenever a
		# full-area panel is covering the view.
		if _ui_panel_open():
			return
		var step: float = ROT_SPEED * delta
		if Input.is_action_pressed("right"):
			rotation_degrees.y += step
		elif Input.is_action_pressed("left"):
			rotation_degrees.y -= step
		elif Input.is_action_pressed("up") and rotation_degrees.x > -90:
			rotation_degrees.x -= step
		elif Input.is_action_pressed("down") and rotation_degrees.x < 90:
			rotation_degrees.x += step


## True while one of the sidebar's full-area panels is open, so keyboard input belongs to it
## rather than to the camera behind it.
func _ui_panel_open() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	var sidebar := scene.get_node_or_null("main_ui/VBoxContainer3/HBoxContainer2")
	if sidebar == null:
		return false
	for child in sidebar.get_children():
		if child is Control and child.visible and child.name != "sidebar":
			return true
	return false
