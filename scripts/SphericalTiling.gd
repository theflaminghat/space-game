@tool
extends MeshInstance3D

## SphericalTiling.gd
## Attach to a MeshInstance3D. Builds a geodesic sphere tiling with ~N triangles.
##
## Signals:
##   tile_hovered(tile_index: int, position: Vector3)
##   tile_unhovered(tile_index: int)
##   tile_clicked(tile_index: int, position: Vector3, button: int)
##
## Override on_tile_hover / on_tile_click in a subclass, or connect the signals.

# ── Signals ───────────────────────────────────────────────────────────────────

## Emitted when the mouse enters a tile. position is the world-space hit point.
signal tile_hovered(tile_index: int, position: Vector3)
## Emitted when the mouse leaves a tile.
signal tile_unhovered(tile_index: int)
## Emitted on mouse button press over a tile. button is MOUSE_BUTTON_LEFT etc.
signal tile_clicked(tile_index: int, position: Vector3, button: int)

# ── Exports ───────────────────────────────────────────────────────────────────

@export var target_n: int = 80:
	set(v): target_n = v; if is_node_ready() or Engine.is_editor_hint(): _rebuild()

@export var radius: float = 1.0:
	set(v): radius = v; if is_node_ready() or Engine.is_editor_hint(): _rebuild()

@export var face_color: Color = Color(0.3, 0.6, 1.0):
	set(v): face_color = v; if is_node_ready() or Engine.is_editor_hint(): _rebuild()

@export var edge_color: Color = Color(1.0, 1.0, 1.0):
	set(v): edge_color = v; if is_node_ready() or Engine.is_editor_hint(): _rebuild()

@export var show_wireframe: bool = true:
	set(v): show_wireframe = v; if is_node_ready() or Engine.is_editor_hint(): _rebuild()

@export var color_by_face: bool = true:
	set(v): color_by_face = v; if is_node_ready() or Engine.is_editor_hint(): _rebuild()

@export_range(0, 200) var relax_iterations: int = 20:
	set(v): relax_iterations = v; if is_node_ready() or Engine.is_editor_hint(): _rebuild()

## Highlight color shown on the hovered tile.
@export var hover_color: Color = Color(1.0, 0.9, 0.2):
	set(v): hover_color = v

## Whether to visually highlight the hovered tile.
@export var highlight_hover: bool = true

# ── State ─────────────────────────────────────────────────────────────────────

var _hovered_tile: int = -1
# Per-tile override materials indexed by face index.
var _tile_materials: Dictionary = {}
# Stored face data so highlight can update without full rebuild.
var _faces: Array[Vector3i] = []
var _verts: Array[Vector3] = []

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_rebuild()

# ── Public overridable callbacks ──────────────────────────────────────────────

## Override in a subclass to react to hover. Called in addition to the signal.
func on_tile_hover(tile_index: int, position: Vector3) -> void:
	pass

## Override in a subclass to react to unhover.
func on_tile_unhover(tile_index: int) -> void:
	pass

## Override in a subclass to react to click.
func on_tile_click(tile_index: int, position: Vector3, button: int) -> void:
	print("clicked")

# ── Public API ────────────────────────────────────────────────────────────────

func get_triangle_count() -> int:
	return 20 * int(pow(4, _subdivisions_for(target_n)))

## Set a custom material on a specific tile index.
func set_tile_material(tile_index: int, mat: Material) -> void:
	_tile_materials[tile_index] = mat
	_apply_tile_material(tile_index, mat)

## Reset a tile back to the default face material.
func clear_tile_material(tile_index: int) -> void:
	_tile_materials.erase(tile_index)
	_apply_tile_material(tile_index, null)

# ── Subdivision helpers ───────────────────────────────────────────────────────

static func _subdivisions_for(n: int) -> int:
	var s := 0
	while 20 * int(pow(4, s)) < n:
		s += 1
	return s

func _rebuild() -> void:
	if Engine.is_editor_hint():
		return  # skip collision setup in editor; mesh only
	var s := _subdivisions_for(target_n)
	print("SphericalTiling: subdiv=%d  tris=%d" % [s, 20 * int(pow(4, s))])
	_build_all(s)

# ── Icosahedron ───────────────────────────────────────────────────────────────

const _PHI := 1.6180339887498949

static func _base_icosahedron() -> Array:
	var t := _PHI
	var raw := [
		Vector3(-1,  t,  0), Vector3( 1,  t,  0),
		Vector3(-1, -t,  0), Vector3( 1, -t,  0),
		Vector3( 0, -1,  t), Vector3( 0,  1,  t),
		Vector3( 0, -1, -t), Vector3( 0,  1, -t),
		Vector3( t,  0, -1), Vector3( t,  0,  1),
		Vector3(-t,  0, -1), Vector3(-t,  0,  1),
	]
	var verts: Array[Vector3] = []
	for v in raw:
		verts.append(v.normalized())
	var faces: Array[Vector3i] = [
		Vector3i(0,11, 5), Vector3i(0, 5, 1), Vector3i(0, 1, 7), Vector3i(0, 7,10), Vector3i(0,10,11),
		Vector3i(1, 5, 9), Vector3i(5,11, 4), Vector3i(11,10, 2), Vector3i(10, 7, 6), Vector3i(7, 1, 8),
		Vector3i(3, 9, 4), Vector3i(3, 4, 2), Vector3i(3, 2, 6), Vector3i(3, 6, 8), Vector3i(3, 8, 9),
		Vector3i(4, 9, 5), Vector3i(2, 4,11), Vector3i(6, 2,10), Vector3i(8, 6, 7), Vector3i(9, 8, 1),
	]
	return [verts, faces]

static func _subdivide(verts: Array[Vector3], faces: Array[Vector3i]) -> Array:
	var cache := {}
	var new_faces: Array[Vector3i] = []
	for f in faces:
		var a := f.x; var b := f.y; var c := f.z
		var ab := _mid(verts, cache, a, b)
		var bc := _mid(verts, cache, b, c)
		var ca := _mid(verts, cache, c, a)
		new_faces.append(Vector3i(a,  ab, ca))
		new_faces.append(Vector3i(b,  bc, ab))
		new_faces.append(Vector3i(c,  ca, bc))
		new_faces.append(Vector3i(ab, bc, ca))
	return [verts, new_faces]

static func _mid(verts: Array[Vector3], cache: Dictionary, i: int, j: int) -> int:
	var key := Vector2i(min(i,j), max(i,j))
	if cache.has(key): return cache[key]
	var m := ((verts[i] + verts[j]) * 0.5).normalized()
	var idx := verts.size()
	verts.append(m)
	cache[key] = idx
	return idx

static func _relax(verts: Array[Vector3], faces: Array[Vector3i], iterations: int) -> Array[Vector3]:
	var n := verts.size()
	var adj: Array = []
	adj.resize(n)
	for i in range(n):
		adj[i] = {}
	for f in faces:
		adj[f.x][f.y] = true; adj[f.x][f.z] = true
		adj[f.y][f.x] = true; adj[f.y][f.z] = true
		adj[f.z][f.x] = true; adj[f.z][f.y] = true
	for _iter in range(iterations):
		var new_verts: Array[Vector3] = []
		new_verts.resize(n)
		for i in range(n):
			var neighbours: Array = adj[i].keys()
			if neighbours.is_empty():
				new_verts[i] = verts[i]; continue
			var centroid := Vector3.ZERO
			for nb in neighbours:
				centroid += verts[nb]
			new_verts[i] = centroid.normalized()
		verts = new_verts
	return verts

# ── Build mesh + colliders ────────────────────────────────────────────────────

func _build_all(subdivisions: int) -> void:
	# Clear old Area3D children
	for child in get_children():
		child.queue_free()
	_tile_materials.clear()
	_hovered_tile = -1

	var base := _base_icosahedron()
	var verts: Array[Vector3] = base[0]
	var faces: Array[Vector3i] = base[1]

	for _i in range(subdivisions):
		var result := _subdivide(verts, faces)
		verts = result[0]; faces = result[1]

	if relax_iterations > 0:
		verts = _relax(verts, faces, relax_iterations)

	for i in range(verts.size()):
		verts[i] *= radius

	_verts = verts
	_faces = faces

	mesh = _build_mesh(verts, faces)
	_build_colliders(verts, faces)

func _build_mesh(verts: Array[Vector3], faces: Array[Vector3i]) -> ArrayMesh:
	var positions := PackedVector3Array()
	var normals   := PackedVector3Array()
	var colors    := PackedColorArray()

	for fi in range(faces.size()):
		var f := faces[fi]
		var v0 := verts[f.x]; var v1 := verts[f.y]; var v2 := verts[f.z]
		var col := Color.from_hsv(float(fi) / float(faces.size()), 0.65, 0.95) if color_by_face else face_color
		positions.append(v0); normals.append(v0.normalized()); colors.append(col)
		positions.append(v1); normals.append(v1.normalized()); colors.append(col)
		positions.append(v2); normals.append(v2.normalized()); colors.append(col)

	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR]  = colors

	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	arr_mesh.surface_set_material(0, mat)

	if show_wireframe:
		var lpos := PackedVector3Array(); var lcol := PackedColorArray()
		var nudge := 1.002
		for f in faces:
			var v0 := verts[f.x]*nudge; var v1 := verts[f.y]*nudge; var v2 := verts[f.z]*nudge
			lpos.append(v0); lcol.append(edge_color)
			lpos.append(v1); lcol.append(edge_color)
			lpos.append(v1); lcol.append(edge_color)
			lpos.append(v2); lcol.append(edge_color)
			lpos.append(v2); lcol.append(edge_color)
			lpos.append(v0); lcol.append(edge_color)
		var la := []; la.resize(Mesh.ARRAY_MAX)
		la[Mesh.ARRAY_VERTEX] = lpos; la[Mesh.ARRAY_COLOR] = lcol
		arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, la)
		var wm := StandardMaterial3D.new()
		wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		wm.vertex_color_use_as_albedo = true
		arr_mesh.surface_set_material(1, wm)

	return arr_mesh

func _build_colliders(verts: Array[Vector3], faces: Array[Vector3i]) -> void:
	## One Area3D + ConvexPolygonShape3D per tile.
	## The Area3D's name encodes the face index so we can recover it in callbacks.
	for fi in range(faces.size()):
		var f := faces[fi]
		var v0 := verts[f.x]; var v1 := verts[f.y]; var v2 := verts[f.z]

		var area := Area3D.new()
		area.name = "Tile_%d" % fi
		area.input_ray_pickable = true
		area.collision_layer = 1
		area.collision_mask  = 1

		var cshape := CollisionShape3D.new()
		var shape  := ConvexPolygonShape3D.new()
		# Add the centroid as a 4th point so the shape has volume
		var centroid := ((v0 + v1 + v2) / 3.0).normalized() * radius * 0.98
		shape.points = PackedVector3Array([v0, v1, v2, centroid])
		cshape.shape = shape

		area.add_child(cshape)
		add_child(area)

		# Connect signals — capture fi by value via Callable.bind()
		area.mouse_entered.connect(_on_tile_mouse_entered.bind(fi))
		area.mouse_exited.connect(_on_tile_mouse_exited.bind(fi))
		area.input_event.connect(_on_tile_input_event.bind(fi))

# ── Input callbacks ───────────────────────────────────────────────────────────

func _on_tile_mouse_entered(tile_index: int) -> void:
	if _hovered_tile == tile_index:
		return
	if _hovered_tile != -1:
		_clear_hover(_hovered_tile)
	_hovered_tile = tile_index

	if highlight_hover:
		_set_tile_highlight(tile_index, hover_color)

	var pos := _tile_centroid(tile_index)
	tile_hovered.emit(tile_index, pos)
	on_tile_hover(tile_index, pos)

func _on_tile_mouse_exited(tile_index: int) -> void:
	if _hovered_tile == tile_index:
		_clear_hover(tile_index)
		_hovered_tile = -1
	tile_unhovered.emit(tile_index)
	on_tile_unhover(tile_index)

func _on_tile_input_event(_camera: Node, event: InputEvent, pos: Vector3, _normal: Vector3, _shape: int, tile_index: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		tile_clicked.emit(tile_index, pos, event.button_index)
		on_tile_click(tile_index, pos, event.button_index)

# ── Highlight helpers ─────────────────────────────────────────────────────────

func _tile_centroid(tile_index: int) -> Vector3:
	var f := _faces[tile_index]
	return (_verts[f.x] + _verts[f.y] + _verts[f.z]) / 3.0

func _set_tile_highlight(tile_index: int, color: Color) -> void:
	# Each face occupies 3 consecutive vertices in surface 0.
	# We swap the surface material for a flat-colored override on that range
	# by using a per-face mesh on a MeshInstance3D overlay child.
	var existing := get_node_or_null("_highlight_%d" % tile_index)
	if existing:
		existing.queue_free()

	var f := _faces[tile_index]
	var v0 := _verts[f.x]; var v1 := _verts[f.y]; var v2 := _verts[f.z]
	var nudge := 1.003

	var positions := PackedVector3Array([v0*nudge, v1*nudge, v2*nudge])
	var normals   := PackedVector3Array([v0.normalized(), v1.normalized(), v2.normalized()])
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals

	var hm := ArrayMesh.new()
	hm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.surface_set_material(0, mat)

	var mi := MeshInstance3D.new()
	mi.name = "_highlight_%d" % tile_index
	mi.mesh = hm
	add_child(mi)

func _clear_hover(tile_index: int) -> void:
	var existing := get_node_or_null("_highlight_%d" % tile_index)
	if existing:
		existing.queue_free()

func _apply_tile_material(_tile_index: int, _mat: Material) -> void:
	# Reserved for future per-tile persistent material overrides.
	pass
