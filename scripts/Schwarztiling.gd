@tool
extends MeshInstance3D

## SchwarzTiling.gd
##
## Two modes controlled by `show_schwarz_triangles`:
##
##   FALSE (default) — Wythoff dual tiling.
##     The 120 Schwarz triangles are used to generate a Wythoff point per
##     triangle. Coincident points are merged into unique vertices, and the
##     dual polygon around each vertex becomes one hoverable/clickable tile.
##     Moving the Wythoff barycentric point recovers every classical solid.
##
##   TRUE — Raw Schwarz triangle mode.
##     The sphere is shown as exactly 120 identical right triangles
##     (angles 90°, 60°, 36°). Each triangle is its own hoverable tile.
##     The Wythoff preset is ignored in this mode.
##
## Signals:
##   tile_hovered(tile_index, position)
##   tile_unhovered(tile_index)
##   tile_clicked(tile_index, position, button)

signal tile_hovered(tile_index: int, position: Vector3)
signal tile_unhovered(tile_index: int)
signal tile_clicked(tile_index: int, position: Vector3, button: int)

# ── Wythoff presets ───────────────────────────────────────────────────────────

const WYTHOFF_PRESETS := {
	"Icosahedron":                 Vector3(1.0, 0.0, 0.0),
	"Dodecahedron":                Vector3(0.0, 1.0, 0.0),
	"Icosidodecahedron":           Vector3(0.0, 0.0, 1.0),
	"Truncated Icosahedron":       Vector3(0.5, 0.5, 0.0),
	"Truncated Dodecahedron":      Vector3(0.5, 0.0, 0.5),
	"Truncated Icosidodecahedron": Vector3(0.0, 0.5, 0.5),
	"Rhombicosidodecahedron":      Vector3(1.0, 1.0, 1.0),
	"Snub Dodecahedron":           Vector3(0.3, 0.4, 0.3),
}

# ── Exports ───────────────────────────────────────────────────────────────────

## When false: Wythoff dual tiling (classical solids).
## When true:  raw 120 Schwarz triangles — each is a hoverable tile.
@export var show_schwarz_triangles: bool = false:
	set(v): show_schwarz_triangles = v; if is_node_ready() or Engine.is_editor_hint(): _rebuild()

@export_enum(
	"Icosahedron",
	"Dodecahedron",
	"Icosidodecahedron",
	"Truncated Icosahedron",
	"Truncated Dodecahedron",
	"Truncated Icosidodecahedron",
	"Rhombicosidodecahedron",
	"Snub Dodecahedron",
	"Custom"
) var wythoff_preset: int = 0:
	set(v): wythoff_preset = v; if is_node_ready() or Engine.is_editor_hint(): _rebuild()

## Only used when wythoff_preset is "Custom".
## x = weight at p/36° corner, y = at q/60° corner, z = at r/90° corner.
@export var wythoff_custom: Vector3 = Vector3(0.3, 0.4, 0.3):
	set(v): wythoff_custom = v; if is_node_ready() or Engine.is_editor_hint(): _rebuild()

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

@export_range(0.0, 1.0) var tile_alpha: float = 1.0:
	set(v): tile_alpha = v; if is_node_ready() or Engine.is_editor_hint(): _rebuild()

@export var hover_color: Color = Color(1.0, 0.85, 0.1):
	set(v): hover_color = v

@export var highlight_hover: bool = true

# ── Internal state ────────────────────────────────────────────────────────────

# _tile_polys holds whatever is the ACTIVE set of tiles — either the 120
# Schwarz triangles (as Array[Vector3] of 3 verts) or the dual polygons.
var _tile_polys: Array = []
var _hovered_tile: int = -1
var _highlight_nodes: Dictionary = {}

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_rebuild()

# ── Overridable callbacks ─────────────────────────────────────────────────────

func on_tile_hover(tile_index: int, _pos: Vector3) -> void: pass
func on_tile_unhover(tile_index: int) -> void: pass
func on_tile_click(tile_index: int, _pos: Vector3, _btn: int) -> void: pass

# ── Public API ────────────────────────────────────────────────────────────────

func get_tile_count() -> int:
	return _tile_polys.size()

# ─────────────────────────────────────────────────────────────────────────────
# Geometry — Icosahedron + Schwarz triangles
# ─────────────────────────────────────────────────────────────────────────────

const _PHI := 1.6180339887498949

static func _icosahedron() -> Array:
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
	for v in raw: verts.append(v.normalized())
	var faces: Array[Vector3i] = [
		Vector3i(0,11,5),  Vector3i(0,5,1),   Vector3i(0,1,7),   Vector3i(0,7,10),  Vector3i(0,10,11),
		Vector3i(1,5,9),   Vector3i(5,11,4),  Vector3i(11,10,2), Vector3i(10,7,6),  Vector3i(7,1,8),
		Vector3i(3,9,4),   Vector3i(3,4,2),   Vector3i(3,2,6),   Vector3i(3,6,8),   Vector3i(3,8,9),
		Vector3i(4,9,5),   Vector3i(2,4,11),  Vector3i(6,2,10),  Vector3i(8,6,7),   Vector3i(9,8,1),
	]
	return [verts, faces]

## Build 120 Schwarz triangles. Each is [p, q, r]: Array of three Vector3
## on the unit sphere. p=36°, q=60°, r=90° corner.
static func _build_schwarz_triangles() -> Array:
	var base := _icosahedron()
	var verts: Array[Vector3] = base[0]
	var faces: Array[Vector3i] = base[1]
	var tris := []
	for face in faces:
		var v0: Vector3 = verts[face.x]
		var v1: Vector3 = verts[face.y]
		var v2: Vector3 = verts[face.z]
		var q: Vector3  = (v0 + v1 + v2).normalized()
		var r01: Vector3 = (v0 + v1).normalized()
		var r12: Vector3 = (v1 + v2).normalized()
		var r20: Vector3 = (v2 + v0).normalized()
		# 6 Schwarz triangles per icosahedron face.
		# Ensure each triangle winds counter-clockwise when viewed from outside
		# the sphere by checking the face normal against the centroid direction.
		for tri in [[v0,q,r01],[v1,q,r01],[v1,q,r12],[v2,q,r12],[v2,q,r20],[v0,q,r20]]:
			var a: Vector3 = tri[0]; var b: Vector3 = tri[1]; var c: Vector3 = tri[2]
			var normal := (b - a).cross(c - a)
			var center := (a + b + c) / 3.0
			if normal.dot(center) < 0.0:
				tris.append([a, c, b])  # flip winding
			else:
				tris.append(tri)
	return tris  # 120 entries

# ─────────────────────────────────────────────────────────────────────────────
# Geometry — Wythoff dual polygons
# ─────────────────────────────────────────────────────────────────────────────

static func _wythoff_point(tri: Array, bary: Vector3) -> Vector3:
	var p: Vector3 = tri[0]
	var q: Vector3 = tri[1]
	var r: Vector3 = tri[2]
	var s := bary.x + bary.y + bary.z
	if s < 0.0001: return p
	return (p * bary.x + q * bary.y + r * bary.z).normalized()

const _MERGE_DIST := 0.0001

static func _merge_points(pts: Array[Vector3]) -> Array:
	var unique: Array[Vector3] = []
	var mapping: Array[int] = []
	mapping.resize(pts.size())
	for i in range(pts.size()):
		var found := -1
		for j in range(unique.size()):
			if pts[i].distance_to(unique[j]) < _MERGE_DIST:
				found = j; break
		if found == -1:
			found = unique.size()
			unique.append(pts[i])
		mapping[i] = found
	return [unique, mapping]

static func _build_dual_polygons(
		unique_verts: Array[Vector3],
		tri_to_vert: Array[int],
		schwarz_tris: Array) -> Array:

	var n_verts := unique_verts.size()
	var vert_tris: Array = []
	vert_tris.resize(n_verts)
	for i in range(n_verts): vert_tris[i] = []
	for ti in range(tri_to_vert.size()):
		vert_tris[tri_to_vert[ti]].append(ti)

	var polys := []
	for vi in range(n_verts):
		var ring: Array = vert_tris[vi]
		if ring.size() < 3: continue
		var center: Vector3 = unique_verts[vi]
		var corners: Array[Vector3] = []
		for ti in ring:
			var tri: Array = schwarz_tris[ti]
			var c: Vector3 = ((tri[0] as Vector3) + (tri[1] as Vector3) + (tri[2] as Vector3)).normalized()
			corners.append(c)
		# Sort angularly in the tangent plane at center
		var up := Vector3.UP if abs(center.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		var tx := center.cross(up).normalized()
		var ty := center.cross(tx).normalized()
		corners.sort_custom(func(a: Vector3, b: Vector3) -> bool:
			var da := a - center; var db := b - center
			return atan2(da.dot(ty), da.dot(tx)) < atan2(db.dot(ty), db.dot(tx))
		)
		polys.append(corners)
	return polys

# ─────────────────────────────────────────────────────────────────────────────
# Rebuild pipeline
# ─────────────────────────────────────────────────────────────────────────────

func _get_bary() -> Vector3:
	var keys := WYTHOFF_PRESETS.keys()
	if wythoff_preset < keys.size():
		return WYTHOFF_PRESETS[keys[wythoff_preset]]
	return wythoff_custom if wythoff_custom.length() > 0.001 else Vector3(0.333, 0.333, 0.334)

func _rebuild() -> void:
	for child in get_children(): child.queue_free()
	_tile_polys.clear()
	_hovered_tile = -1
	_highlight_nodes.clear()

	var schwarz_tris := _build_schwarz_triangles()

	if show_schwarz_triangles:
		# ── Mode A: 120 Schwarz triangles are the tiles ───────────────────────
		for tri in schwarz_tris:
			var poly: Array[Vector3] = []
			poly.append((tri[0] as Vector3) * radius)
			poly.append((tri[1] as Vector3) * radius)
			poly.append((tri[2] as Vector3) * radius)
			_tile_polys.append(poly)
		print("SchwarzTiling: 120 Schwarz triangles")
	else:
		# ── Mode B: Wythoff dual polygons are the tiles ───────────────────────
		var bary := _get_bary()
		var wythoff_pts: Array[Vector3] = []
		for tri in schwarz_tris:
			wythoff_pts.append(_wythoff_point(tri, bary))

		var merged := _merge_points(wythoff_pts)
		var unique_verts: Array[Vector3] = merged[0]
		var tri_to_vert: Array[int]      = merged[1]

		var polys := _build_dual_polygons(unique_verts, tri_to_vert, schwarz_tris)
		for pi in range(polys.size()):
			var poly: Array = polys[pi]
			for vi in range(poly.size()):
				poly[vi] = (poly[vi] as Vector3) * radius
		_tile_polys = polys
		var keys := WYTHOFF_PRESETS.keys()
		var name: String = keys[wythoff_preset] if wythoff_preset < keys.size() else "Custom"
		print("SchwarzTiling: %d dual tiles (%s)" % [_tile_polys.size(), name])

	mesh = _build_mesh()
	if not Engine.is_editor_hint():
		_build_colliders()

# ─────────────────────────────────────────────────────────────────────────────
# Mesh
# ─────────────────────────────────────────────────────────────────────────────

func _build_mesh() -> ArrayMesh:
	var positions := PackedVector3Array()
	var normals   := PackedVector3Array()
	var colors    := PackedColorArray()
	var total: int = _tile_polys.size()

	for fi in range(total):
		var poly: Array = _tile_polys[fi]
		var col := Color.from_hsv(float(fi) / float(total), 0.65, 0.95) if color_by_face else face_color
		col.a = 0
		var n: int = poly.size()
		# Fan triangulation from vertex 0
		for i in range(1, n - 1):
			var v0: Vector3 = poly[0]
			var v1: Vector3 = poly[i]
			var v2: Vector3 = poly[i + 1]
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
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	arr_mesh.surface_set_material(0, mat)

	if show_wireframe:
		var lpos := PackedVector3Array()
		var lcol := PackedColorArray()
		var nudge := 1.002
		for poly in _tile_polys:
			var n: int = poly.size()
			for i in range(n):
				var a: Vector3 = (poly[i]           as Vector3) * nudge
				var b: Vector3 = (poly[(i+1) % n]   as Vector3) * nudge
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

# ─────────────────────────────────────────────────────────────────────────────
# Colliders
# ─────────────────────────────────────────────────────────────────────────────

func _build_colliders() -> void:
	for fi in range(_tile_polys.size()):
		var poly: Array = _tile_polys[fi]

		var centroid := Vector3.ZERO
		for p in poly: centroid += p as Vector3
		centroid = (centroid / poly.size()).normalized() * radius * 0.97

		var pts := PackedVector3Array()
		for p in poly: pts.append(p as Vector3)
		pts.append(centroid)

		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		var cshape := CollisionShape3D.new()
		cshape.shape = shape

		var area := Area3D.new()
		area.name = "Tile_%d" % fi
		area.input_ray_pickable = true
		area.collision_layer = 1
		area.collision_mask  = 1
		area.add_child(cshape)
		add_child(area)

		area.mouse_entered.connect(_on_tile_entered.bind(fi))
		area.mouse_exited.connect(_on_tile_exited.bind(fi))
		area.input_event.connect(_on_tile_input.bind(fi))

# ─────────────────────────────────────────────────────────────────────────────
# Input callbacks
# ─────────────────────────────────────────────────────────────────────────────

func _on_tile_entered(tile_index: int) -> void:
	if _hovered_tile == tile_index: return
	if _hovered_tile != -1: _clear_highlight(_hovered_tile)
	_hovered_tile = tile_index
	if highlight_hover: _set_highlight(tile_index, hover_color)
	var pos := _poly_centroid(tile_index)
	tile_hovered.emit(tile_index, pos)
	on_tile_hover(tile_index, pos)

func _on_tile_exited(tile_index: int) -> void:
	if _hovered_tile == tile_index:
		_clear_highlight(tile_index)
		_hovered_tile = -1
	tile_unhovered.emit(tile_index)
	on_tile_unhover(tile_index)

func _on_tile_input(_camera: Node, event: InputEvent, pos: Vector3, _normal: Vector3, _shape: int, tile_index: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		tile_clicked.emit(tile_index, pos, event.button_index)
		on_tile_click(tile_index, pos, event.button_index)

# ─────────────────────────────────────────────────────────────────────────────
# Highlight
# ─────────────────────────────────────────────────────────────────────────────

func _poly_centroid(tile_index: int) -> Vector3:
	var poly: Array = _tile_polys[tile_index]
	var c := Vector3.ZERO
	for p in poly: c += p as Vector3
	return c / poly.size()

func _set_highlight(tile_index: int, color: Color) -> void:
	_clear_highlight(tile_index)
	var poly: Array = _tile_polys[tile_index]
	var nudge := 1.003
	var n: int = poly.size()
	var positions := PackedVector3Array()
	var normals   := PackedVector3Array()
	for i in range(1, n - 1):
		var v0: Vector3 = (poly[0]     as Vector3) * nudge
		var v1: Vector3 = (poly[i]     as Vector3) * nudge
		var v2: Vector3 = (poly[i + 1] as Vector3) * nudge
		positions.append(v0); normals.append(v0.normalized())
		positions.append(v1); normals.append(v1.normalized())
		positions.append(v2); normals.append(v2.normalized())
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	var hm := ArrayMesh.new()
	hm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.albedo_color.a = tile_alpha
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	hm.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = hm
	add_child(mi)
	_highlight_nodes[tile_index] = mi

func _clear_highlight(tile_index: int) -> void:
	if _highlight_nodes.has(tile_index):
		_highlight_nodes[tile_index].queue_free()
		_highlight_nodes.erase(tile_index)
