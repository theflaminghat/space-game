extends Control

## Screen-space hover/click picker for the 3-D solar view.  Each frame it projects every
## selectable body (planets, moons, the Sun, and the asteroid belt's hub) to the screen, finds
## the one under the cursor, draws a white ring around it, and — on left-click over empty 3-D
## space — puts the camera pivot on that body.  Failing a body, the asteroid belt's whole band
## is a target too, outlined by its two edges.  Screen-space (not physics ray-casting) so it works
## for bodies with no colliders, including the MultiMesh-free cosmetic moons.

## Smallest clickable screen radius (px) so distant, tiny moons stay easy to hover.
const MIN_HIT_PX: float = 7.0
## Ring is drawn this many pixels outside the body's apparent edge.
const RING_PAD_PX: float = 5.0
## How many points trace the silhouette.  32 is smooth at any on-screen size a body reaches.
const SILHOUETTE_SEGMENTS: int = 32
const RING_COLOR: Color = Color(1.0, 1.0, 1.0, 0.9)
const RING_WIDTH: float = 2.0

var _planets_root: Node3D = null
var _hover_body: Node3D = null
## The hovered body's projected silhouette, in screen space.  A sphere only projects to a
## CIRCLE when it is dead centre; anywhere else perspective turns it into an ellipse that grows
## and leans as it approaches the edge of the view.  Tracking the real projected outline means
## the ring matches the body wherever it sits, instead of a circle that is too small and the
## wrong shape near the edges.
var _hover_poly: PackedVector2Array = PackedVector2Array()
## When the cursor is over an asteroid belt's band rather than a body, its two projected edges
## (polylines) — the belt is outlined as the band it is, not as a sphere.
var _hover_band: Array = []


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
	_hover_band = []
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
		var poly: PackedVector2Array = _silhouette(cam, body)
		if poly.is_empty():
			continue
		if not _poly_hit(poly, cam.unproject_position(wp), mouse):
			continue
		var depth: float = cam.global_position.distance_to(wp)
		if depth < best_depth:
			best_depth = depth
			_hover_body = body
			_hover_poly = poly
	if _hover_body != null:
		return
	# No body under the cursor: is it over an asteroid belt?  The belt is a band, not a sphere,
	# so it is hit-tested as the annulus it occupies in the orbital plane — anywhere on it
	# selects it.  Bodies always win, because they are discrete targets drawn in front of it.
	for child in _planets_root.get_children():
		if child is AsteroidBelt and (child as AsteroidBelt).band_hit(cam, mouse) < INF:
			_hover_body = child
			_hover_band = (child as AsteroidBelt).band_outline(cam)
			return


## Is the cursor over this body?  Inside the projected outline, or — for a body too small to
## comfortably hit — within MIN_HIT_PX of its centre, so distant moons stay clickable.
func _poly_hit(poly: PackedVector2Array, centre: Vector2, mouse: Vector2) -> bool:
	if mouse.distance_to(centre) <= MIN_HIT_PX:
		return true
	return Geometry2D.is_point_in_polygon(mouse, poly)


## World-space radius of a body, including its scale.
func _world_radius(body: Node3D) -> float:
	var r: float = 0.5
	if body is MeshInstance3D and (body as MeshInstance3D).mesh != null:
		r = (body as MeshInstance3D).mesh.get_aabb().size.x * 0.5
	return r * body.global_transform.basis.get_scale().x


## The body's silhouette as seen from the camera, projected to screen space.
##
## The tangent lines from the camera touch a sphere on a circle — NOT on its equator.  That
## circle sits at distance d - r^2/d with radius r*sqrt(d^2 - r^2)/d.  Projecting points around
## it reproduces exactly what the renderer draws, including the elliptical stretch off-axis,
## so the ring can never disagree with the body.
func _silhouette(cam: Camera3D, body: Node3D) -> PackedVector2Array:
	var out := PackedVector2Array()
	var r: float = _world_radius(body)
	var to_c: Vector3 = body.global_position - cam.global_position
	var d: float = to_c.length()
	if r <= 0.0 or d <= r:
		return out                      # camera at or inside the body — nothing sensible to outline
	var axis: Vector3 = to_c / d
	var ring_d: float = d - (r * r) / d
	var ring_r: float = r * sqrt(maxf(d * d - r * r, 0.0)) / d
	var ring_c: Vector3 = cam.global_position + axis * ring_d
	# Any two axes perpendicular to the view direction will do; guard the degenerate case where
	# the body sits straight up or down from the camera.
	var u: Vector3 = axis.cross(Vector3.UP)
	if u.length_squared() < 1e-8:
		u = axis.cross(Vector3.RIGHT)
	u = u.normalized()
	var v: Vector3 = axis.cross(u).normalized()
	for i in range(SILHOUETTE_SEGMENTS):
		var a: float = TAU * float(i) / float(SILHOUETTE_SEGMENTS)
		var wp: Vector3 = ring_c + (u * cos(a) + v * sin(a)) * ring_r
		if cam.is_position_behind(wp):
			return PackedVector2Array()   # straddling the camera plane — a projected ring would tear
		out.append(cam.unproject_position(wp))
	return out


## Push every point of an outline away from its centroid, so the ring sits a constant number of
## PIXELS outside the body regardless of how the projection has stretched it.
func _padded(poly: PackedVector2Array, pad: float) -> PackedVector2Array:
	if poly.is_empty():
		return poly
	var centroid := Vector2.ZERO
	for pt: Vector2 in poly:
		centroid += pt
	centroid /= float(poly.size())
	var out := PackedVector2Array()
	for pt: Vector2 in poly:
		var dir: Vector2 = pt - centroid
		out.append(pt + (dir.normalized() * pad if dir.length() > 0.001 else Vector2.ZERO))
	return out


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



func _draw() -> void:
	if _hover_body == null:
		return
	if not _hover_band.is_empty():
		for line: PackedVector2Array in _hover_band:
			draw_polyline(line, RING_COLOR, RING_WIDTH, true)
		return
	if _hover_poly.size() < 3:
		return
	var ring: PackedVector2Array = _padded(_hover_poly, RING_PAD_PX)
	ring.append(ring[0])                      # close the loop
	draw_polyline(ring, RING_COLOR, RING_WIDTH, true)


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
