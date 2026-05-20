@tool
extends MeshInstance3D

## FloretTiling.gd
## Spherical floret pentagon tessellation.
##
## Construction:
##   1. Subdivide an icosahedron s times  → triangular mesh
##   2. Place a snub point inside each triangle (barycentric t, t, 1-2t)
##   3. Build the dual: each original vertex → one floret pentagon
##      whose corners are the snub points of its surrounding triangles
##   4. Project all points onto the sphere
##
## Face count = 12 pentagons (from icosahedron vertices, degree-5)
##            + 10 * 4^s * 2  hexagon-pentagons (degree-6 vertices)
## Visually these all look like irregular pentagons in a flower pattern.
##
## Signals:
##   tile_hovered(tile_index, position)
##   tile_unhovered(tile_index)
##   tile_clicked(tile_index, position, button)

# ── Signals ───────────────────────────────────────────────────────────────────

signal tile_hovered(tile_index: int, position: Vector3)
signal tile_unhovered(tile_index: int)
signal tile_clicked(tile_index: int, position: Vector3, button: int)

# ── Exports ───────────────────────────────────────────────────────────────────

## Subdivision level. Face count ≈ 10 * 4^s + 2.
@export_range(0, 4) var subdivisions: int = 2:
	set(v): subdivisions = v; if is_node_ready() or Engine.is_editor_hint(): _rebuild()

@export var radius: float = 1.0:
	set(v): radius = v; if is_node_ready() or Engine.is_editor_hint(): _rebuild()

## Snub offset — how far the snub point is rotated inside each triangle.
## 0.25 = classic floret look. 0.333 = centroid (no rotation, hexagonal).
@export_range(0.15, 0.45) var snub_t: float = 0.25:
	set(v): snub_t = v; if is_node_ready() or Engine.is_editor_hint(): _rebuild()

@export var face_color: Color = Color(0.3, 0.6, 1.0):
	set(v): face_color = v; if is_node_ready() or Engine.is_editor_hint(): _rebuild()

@export var edge_color: Color = Color(1.0, 1.0, 1.0):
	set(v): edge_color = v; if is_node_ready() or Engine.is_editor_hint(): _rebuild()

@export var show_wireframe: bool = true:
	set(v): show_wireframe = v; if is_node_ready() or Engine.is_editor_hint(): _rebuild()

@export var color_by_face: bool = true:
	set(v): color_by_face = v; if is_node_ready() or Engine.is_editor_hint(): _rebuild()

@export var hover_color: Color = Color(1.0, 0.85, 0.1):
	set(v): hover_color = v

@export var highlight_hover: bool = true

# ── Internal state ────────────────────────────────────────────────────────────

var _hovered_tile: int = -1
# Each floret face is a polygon: Array of Vector3 (already on sphere surface)
var _floret_polys: Array = []   # Array[Array[Vector3]]

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_rebuild()

# ── Overridable callbacks ─────────────────────────────────────────────────────

func on_tile_hover(tile_index: int, position: Vector3) -> void: pass
func on_tile_unhover(tile_index: int) -> void: pass
func on_tile_click(tile_index: int, position: Vector3, button: int) -> void: pass

# ── Public API ────────────────────────────────────────────────────────────────

func get_tile_count() -> int:
	return _floret_polys.size()

# ── Icosahedron base ──────────────────────────────────────────────────────────

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

# ── Geodesic subdivision ──────────────────────────────────────────────────────

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

# ── Floret construction ───────────────────────────────────────────────────────

## For each triangle, compute the snub point: a weighted-and-rotated interior
## point projected back to the sphere. The snub_t parameter controls how much
## the point is biased toward one vertex (creating the floret asymmetry).
## Returns: Array[Vector3], one snub point per face, same indexing as faces.
static func _snub_points(verts: Array[Vector3], faces: Array[Vector3i], t: float) -> Array[Vector3]:
	var snubs: Array[Vector3] = []
	var u := t
	var v := t
	var w := 1.0 - 2.0 * t   # barycentric coords sum to 1
	for f in faces:
		var p := verts[f.x] * u + verts[f.y] * v + verts[f.z] * w
		snubs.append(p.normalized())
	return snubs

## Build vertex→face adjacency: for each vertex index, which face indices
## touch it, in sorted angular order around that vertex.
static func _vertex_face_rings(
		verts: Array[Vector3],
		faces: Array[Vector3i]) -> Array:
	var n := verts.size()
	# raw adjacency lists
	var rings: Array = []
	rings.resize(n)
	for i in range(n):
		rings[i] = []

	for fi in range(faces.size()):
		var f := faces[fi]
		rings[f.x].append(fi)
		rings[f.y].append(fi)
		rings[f.z].append(fi)

	# Sort each ring angularly around its vertex so the polygon winds correctly
	for vi in range(n):
		var ring: Array = rings[vi]
		if ring.size() < 3:
			continue
		var center := verts[vi]
		# Build a local 2D frame tangent to the sphere at center
		var up := Vector3.UP if abs(center.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		var tx := center.cross(up).normalized()
		var ty := center.cross(tx).normalized()
		# Sort by angle in this tangent plane
		ring.sort_custom(func(a_idx, b_idx):
			var ca := _face_centroid_static(verts, faces[a_idx])
			var cb := _face_centroid_static(verts, faces[b_idx])
			var da := ca - center
			var db := cb - center
			var ang_a := atan2(da.dot(ty), da.dot(tx))
			var ang_b := atan2(db.dot(ty), db.dot(tx))
			return ang_a < ang_b
		)

	return rings

static func _face_centroid_static(verts: Array[Vector3], f: Vector3i) -> Vector3:
	return (verts[f.x] + verts[f.y] + verts[f.z]) / 3.0

# ── Rebuild pipeline ──────────────────────────────────────────────────────────

func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_hovered_tile = -1
	_floret_polys.clear()

	# 1. Build subdivided icosahedron
	var base := _base_icosahedron()
	var verts: Array[Vector3] = base[0]
	var faces: Array[Vector3i] = base[1]

	for _i in range(subdivisions):
		var r := _subdivide(verts, faces)
		verts = r[0]; faces = r[1]

	# 2. Compute one snub point per triangle face
	var snubs := _snub_points(verts, faces, snub_t)

	# 3. For each vertex, gather its surrounding snub points in angular order
	#    → that ordered ring of snub points IS the floret pentagon for that vertex
	var rings := _vertex_face_rings(verts, faces)

	for vi in range(verts.size()):
		var ring: Array = rings[vi]
		if ring.size() < 3:
			continue
		var poly: Array[Vector3] = []
		for fi in ring:
			poly.append(snubs[fi] * radius)
		_floret_polys.append(poly)

	# 4. Build mesh and colliders
	mesh = _build_mesh()
	if not Engine.is_editor_hint():
		_build_colliders()

# ── Mesh building ─────────────────────────────────────────────────────────────

## Triangulate a convex polygon (fan from first vertex) and append to arrays.
static func _append_polygon(
		poly: Array,
		color: Color,
		positions: PackedVector3Array,
		normals: PackedVector3Array,
		colors: PackedColorArray) -> void:
	var n: int = poly.size()
	for i in range(1, n - 1):
		var v0: Vector3 = poly[0]
		var v1: Vector3 = poly[i]
		var v2: Vector3 = poly[i + 1]
		positions.append(v0); normals.append(v0.normalized()); colors.append(color)
		positions.append(v1); normals.append(v1.normalized()); colors.append(color)
		positions.append(v2); normals.append(v2.normalized()); colors.append(color)

func _build_mesh() -> ArrayMesh:
	var positions := PackedVector3Array()
	var normals   := PackedVector3Array()
	var colors    := PackedColorArray()

	var total := _floret_polys.size()
	for fi in range(total):
		var poly: Array = _floret_polys[fi]
		var col := Color.from_hsv(float(fi) / float(total), 0.65, 0.95) if color_by_face else face_color
		_append_polygon(poly, col, positions, normals, colors)

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
		var lpos := PackedVector3Array()
		var lcol := PackedColorArray()
		var nudge := 1.002
		for poly in _floret_polys:
			var n: int = poly.size()
			for i in range(n):
				var a: Vector3 = poly[i] * nudge
				var b: Vector3 = poly[(i + 1) % n] * nudge
				lpos.append(a); lcol.append(edge_color)
				lpos.append(b); lcol.append(edge_color)
		var la := []; la.resize(Mesh.ARRAY_MAX)
		la[Mesh.ARRAY_VERTEX] = lpos; la[Mesh.ARRAY_COLOR] = lcol
		arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, la)
		var wm := StandardMaterial3D.new()
		wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		wm.vertex_color_use_as_albedo = true
		arr_mesh.surface_set_material(1, wm)

	return arr_mesh

# ── Colliders ─────────────────────────────────────────────────────────────────

func _build_colliders() -> void:
	for fi in range(_floret_polys.size()):
		var poly: Array = _floret_polys[fi]

		var area := Area3D.new()
		area.name = "Tile_%d" % fi
		area.input_ray_pickable = true
		area.collision_layer = 1
		area.collision_mask  = 1

		var cshape := CollisionShape3D.new()
		var shape  := ConvexPolygonShape3D.new()
		# Include an inner centroid point so the shape has volume
		var centroid := Vector3.ZERO
		for p in poly: centroid += p
		centroid = (centroid / poly.size()).normalized() * radius * 0.97
		var pts := PackedVector3Array()
		for p in poly: pts.append(p)
		pts.append(centroid)
		shape.points = pts
		cshape.shape = shape

		area.add_child(cshape)
		add_child(area)

		area.mouse_entered.connect(_on_tile_mouse_entered.bind(fi))
		area.mouse_exited.connect(_on_tile_mouse_exited.bind(fi))
		area.input_event.connect(_on_tile_input_event.bind(fi))

# ── Input callbacks ───────────────────────────────────────────────────────────

func _on_tile_mouse_entered(tile_index: int) -> void:
	if _hovered_tile == tile_index: return
	if _hovered_tile != -1: _clear_highlight(_hovered_tile)
	_hovered_tile = tile_index
	if highlight_hover: _set_highlight(tile_index, hover_color)
	var pos := _poly_centroid(tile_index)
	tile_hovered.emit(tile_index, pos)
	on_tile_hover(tile_index, pos)

func _on_tile_mouse_exited(tile_index: int) -> void:
	if _hovered_tile == tile_index:
		_clear_highlight(tile_index)
		_hovered_tile = -1
	tile_unhovered.emit(tile_index)
	on_tile_unhover(tile_index)

func _on_tile_input_event(_camera: Node, event: InputEvent, pos: Vector3, _normal: Vector3, _shape: int, tile_index: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		tile_clicked.emit(tile_index, pos, event.button_index)
		on_tile_click(tile_index, pos, event.button_index)

# ── Highlight ─────────────────────────────────────────────────────────────────

func _poly_centroid(tile_index: int) -> Vector3:
	var poly: Array = _floret_polys[tile_index]
	var c := Vector3.ZERO
	for p in poly: c += p
	return c / poly.size()

func _set_highlight(tile_index: int, color: Color) -> void:
	_clear_highlight(tile_index)
	var poly: Array = _floret_polys[tile_index]
	var nudge := 1.003

	var positions := PackedVector3Array()
	var normals   := PackedVector3Array()
	var n: int = poly.size()
	for i in range(1, n - 1):
		var v0: Vector3 = poly[0]     * nudge
		var v1: Vector3 = poly[i]     * nudge
		var v2: Vector3 = poly[i + 1] * nudge
		positions.append(v0); normals.append(v0.normalized())
		positions.append(v1); normals.append(v1.normalized())
		positions.append(v2); normals.append(v2.normalized())

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
	mi.name = "_hl_%d" % tile_index
	mi.mesh = hm
	add_child(mi)

func _clear_highlight(tile_index: int) -> void:
	var n := get_node_or_null("_hl_%d" % tile_index)
	if n: n.queue_free()
