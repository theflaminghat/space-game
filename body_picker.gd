extends Control

## Screen-space hover/click picker for the 3-D solar view.  Each frame it projects every
## selectable body (planets, moons, and the Sun) to the screen, finds the one under the
## cursor, draws a white ring around it, and — on left-click over empty 3-D space —
## puts the camera pivot on that body.  Screen-space (not physics ray-casting) so it works
## for bodies with no colliders, including the MultiMesh-free cosmetic moons.

## Smallest clickable screen radius (px) so distant, tiny moons stay easy to hover.
const MIN_HIT_PX: float = 7.0
## Ring is drawn this many pixels outside the body's apparent edge.
const RING_PAD_PX: float = 5.0
const RING_COLOR: Color = Color(1.0, 1.0, 1.0, 0.9)
const RING_WIDTH: float = 2.0

var _planets_root: Node3D = null
var _hover_body: Node3D = null
var _hover_center: Vector2 = Vector2.ZERO
var _hover_radius: float = 0.0


func _ready() -> void:
	# Full-viewport, never blocks input — clicks fall through to _unhandled_input so the
	# UI panels (which mark events handled) always get first refusal.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scene := get_tree().current_scene
	if scene:
		_planets_root = scene.get_node_or_null("WorldRoot/Planets") as Node3D


func _process(_delta: float) -> void:
	var prev: Node3D = _hover_body
	_update_hover()
	if _hover_body != prev or _hover_body != null:
		queue_redraw()


## Find the selectable body whose screen disc is under the cursor (closest to it on ties).
func _update_hover() -> void:
	_hover_body = null
	if _planets_root == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var mouse: Vector2 = get_viewport().get_mouse_position()
	# Among every body whose screen disc is under the cursor, pick the one CLOSEST TO THE CAMERA
	# — the front-most, visible one — so a body sitting behind another is never highlighted
	# through it.  (Depth by centre distance, not cursor proximity.)
	var best_depth: float = INF
	for body in _selectable_bodies():
		if not body.visible:
			continue
		var wp: Vector3 = body.global_position
		if cam.is_position_behind(wp):
			continue
		var center: Vector2 = cam.unproject_position(wp)
		var srad: float = _screen_radius(cam, body, wp, center)
		if mouse.distance_to(center) > srad:
			continue   # cursor isn't over this body's disc
		var depth: float = cam.global_position.distance_to(wp)
		if depth < best_depth:
			best_depth = depth
			_hover_body = body
			_hover_center = center
			_hover_radius = srad


## All bodies the player can target: every planet/star under Planets, plus their moons.
func _selectable_bodies() -> Array:
	var out: Array = []
	for child in _planets_root.get_children():
		if child is Planet:
			out.append(child)
			for sub in (child as Node).get_children():
				if sub is MeshInstance3D and "_moon_" in (sub as Node).name:
					out.append(sub)
	return out


## Apparent radius of `body` in pixels (projected from a point on its surface).
func _screen_radius(cam: Camera3D, body: Node3D, center_world: Vector3, _center_px: Vector2) -> float:
	var world_r: float = 0.5
	if body is MeshInstance3D and (body as MeshInstance3D).mesh != null:
		world_r = (body as MeshInstance3D).mesh.get_aabb().size.x * 0.5
	world_r *= body.global_transform.basis.get_scale().x
	# Use the sphere's TRUE silhouette angular size (asin r/d) rather than projecting an
	# off-axis surface point — the latter badly underestimates the outline up close, which
	# is why the ring looked too small when zoomed in.
	var d: float = cam.global_position.distance_to(center_world)
	if d <= world_r:
		return 100000.0   # camera inside/at the body → ring fills the screen
	var theta: float = asin(clampf(world_r / d, 0.0, 0.9999))
	var vp_h: float = get_viewport().get_visible_rect().size.y
	var fov_v: float = deg_to_rad(cam.fov)   # Camera3D.fov is the vertical FOV (KEEP_HEIGHT)
	var px: float = (vp_h * 0.5) * tan(theta) / tan(fov_v * 0.5)
	return maxf(MIN_HIT_PX, px)


func _draw() -> void:
	if _hover_body == null:
		return
	draw_arc(_hover_center, _hover_radius + RING_PAD_PX, 0.0, TAU, 48,
		RING_COLOR, RING_WIDTH, true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if _hover_body != null:
			var cam := get_viewport().get_camera_3d()
			var pivot := cam.get_parent() if cam else null
			if pivot and pivot.has_method("focus_node"):
				pivot.focus_node(_hover_body)
			# Also open the body's info + build panels (planets AND moons); Game gates
			# access, so an unreached body just gets the camera move.
			var game := get_tree().current_scene
			if game and game.has_method("select_planet"):
				game.select_planet(str(_hover_body.name))
			accept_event()
