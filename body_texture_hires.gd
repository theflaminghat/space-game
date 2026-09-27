class_name BodyTextureHires
extends Node

## Gives the SELECTED body a surface map at twice the resolution, and takes it away again when
## the player looks at something else.
##
## The maps are SVG, so there is no fixed "native" size to be stuck with: the same file can be
## rasterised at any resolution, and the imported 2048×1024 is only the size chosen for every
## body at once.  A body the player has selected is the one filling the screen, so it gets
## 4096×2048 — and only it, so the extra ~43 MB is paid once rather than thirteen times.
##
## Rasterising at that size takes 90–230 ms depending on the file, which would be a visible
## hitch on every click, so it happens on a worker thread and is swapped in when it is ready.  If
## the player moves on first the result is simply dropped.

## How much sharper the selected body gets, against its imported size.
const SCALE: int = 2
## Ceiling on the rasterised width, in case a future map is authored much larger.
const MAX_WIDTH: int = 8192

## The body currently holding a high-resolution map, and the texture it had before.
var _node: MeshInstance3D = null
var _base_tex: Texture2D = null
## Guards against a slow rasterise landing after the player has moved on.
var _request: int = 0


## Give `node` a doubled map, restoring whatever the last selection had.  Safe to call with null
## (nothing selected) or with a body that has no SVG map — it simply restores and stops.
func select(node: MeshInstance3D) -> void:
	if node == _node:
		return
	_restore()
	_request += 1
	if node == null:
		return
	var mat := _shader_material(node)
	if mat == null:
		return
	var tex: Texture2D = mat.get_shader_parameter("albedo_tex") as Texture2D
	if tex == null or not str(tex.resource_path).ends_with(".svg"):
		return       # a flat-coloured body, or a map that is not vector: nothing to sharpen
	var target: int = mini(tex.get_width() * SCALE, MAX_WIDTH)
	if target <= tex.get_width():
		return       # already at the ceiling: leave it be rather than book it as sharpened
	_node = node
	_base_tex = tex
	var path: String = str(tex.resource_path)
	var token: int = _request
	# The rasterise and its mipmaps are the slow part and touch nothing in the tree, so they run
	# on a worker; only the finished Image comes back to the main thread.
	WorkerThreadPool.add_task(func() -> void:
		var img: Image = _rasterize(path, target)
		_apply.call_deferred(token, img))


## Put the selected body back on its imported map.
func _restore() -> void:
	if _node != null and is_instance_valid(_node) and _base_tex != null:
		var mat := _shader_material(_node)
		if mat != null:
			mat.set_shader_parameter("albedo_tex", _base_tex)
	_node = null
	_base_tex = null


## Rasterise an SVG to `target` pixels wide, with mipmaps, exactly as the importer would.
## Runs on a worker thread: no scene access, no engine singletons beyond file reading.
static func _rasterize(path: String, target: int) -> Image:
	var text: String = FileAccess.get_file_as_string(path)
	if text == "":
		return null
	# The file's own width decides the scale that lands on `target` pixels.
	var intrinsic: float = _intrinsic_width(text)
	if intrinsic <= 0.0:
		return null
	var img := Image.new()
	if img.load_svg_from_string(text, float(target) / intrinsic) != OK:
		return null
	img.generate_mipmaps()
	return img


## The width an SVG declares in its header, which is what its coordinates are in.
static func _intrinsic_width(svg_text: String) -> float:
	var re := RegEx.create_from_string('width="([0-9.]+)"')
	var m := re.search(svg_text)
	return float(m.get_string(1)) if m != null else 0.0


## Swap the finished map in, unless the player has since selected something else.
func _apply(token: int, img: Image) -> void:
	if token != _request or img == null or _node == null or not is_instance_valid(_node):
		return
	var mat := _shader_material(_node)
	if mat == null:
		return
	mat.set_shader_parameter("albedo_tex", ImageTexture.create_from_image(img))


## The body's polar-blur material, wherever it hangs: planets carry it as an override, moons as
## a surface override.
static func _shader_material(node: MeshInstance3D) -> ShaderMaterial:
	if node == null:
		return null
	var mat := node.material_override as ShaderMaterial
	if mat == null:
		mat = node.get_surface_override_material(0) as ShaderMaterial
	return mat


## Width of the map the selected body is currently showing — for tests and the panel.
func current_width() -> int:
	var mat := _shader_material(_node)
	if mat == null:
		return 0
	var tex: Texture2D = mat.get_shader_parameter("albedo_tex") as Texture2D
	return tex.get_width() if tex != null else 0
