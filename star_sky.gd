extends Node3D

## The night sky of the 3-D solar system, drawn from the game's own star catalogue instead of a
## photograph.
##
## It used to be a PanoramaSkyMaterial over my_image.png: a fixed picture of somebody else's sky,
## which said nothing true about where the player is and could not change when the Sun moved.
## The catalogue the star map already keeps IS a sky — real positions for the named stars,
## procedurally placed ones filling the home cell — so this projects it onto a shell around the
## camera and lets the two views agree with each other.
##
## What that buys beyond looking right: a Shkadov-driven Sun carries its neighbourhood with it,
## StarMapPanel.set_sky_frame re-derives the catalogue from the new position, and the constellations
## overhead change with it.  Nothing here has to know that; it rebuilds whenever the catalogue's
## revision moves.
##
## Deliberately NO class_name: a freshly added global class is not in the project's class cache
## until the editor reimports, so a headless run cannot resolve it.  Game loads it by path.

## How far out the shell sits.  Beyond everything in the solar system (Neptune is ~110 units from
## the Sun on the log-radial scale) and inside the camera's far plane, so ordinary depth sorting
## puts the stars behind the planets with no depth tricks.
const SKY_RADIUS: float = 6000.0
## Far plane the camera needs for a shell at that radius, with room for the camera's own offset
## from the origin.
const CAMERA_FAR: float = 16000.0

## Apparent size of the faintest and brightest stars at SKY_RADIUS, in world units.
const SIZE_MIN: float = 12.0
const SIZE_MAX: float = 58.0
## Brightness floor, so the faintest stars are present but barely.
const ALPHA_MIN: float = 0.22
const ALPHA_MAX: float = 1.0
## Apparent-brightness range the size and alpha ramps span, in decades.  Beyond this the ramp is
## clamped: Sirius should be the brightest thing up there, not a thousand times the size of
## everything else.
const BRIGHT_DECADES: float = 6.0

var _mm: MultiMesh = null
var _mmi: MultiMeshInstance3D = null
var _built_version: int = -1


func _ready() -> void:
	_build()


## Keep the shell centred on the viewer, so a star is always SKY_RADIUS away however far the
## camera has travelled from the Sun — which is what makes it read as a sky rather than as a
## very large sphere the player could fly to.  Orientation is deliberately NOT copied: the stars
## hold still in world space while the camera turns, which is the whole point of them.
func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		global_position = cam.global_position
		if cam.far < CAMERA_FAR:
			cam.far = CAMERA_FAR
	# Checked every frame, not on a timer: it is one integer compare, and _build only runs when
	# the catalogue has actually changed.  On a timer the sky spent up to a second showing the
	# sixty hand-catalogued stars that exist before the procedural field is generated.
	if StarMapPanel.catalogue_version() != _built_version:
		_build()


## Where every star goes, as [{dir, size, color}] — the whole derivation, with nothing in it
## that touches the rendering server.
##
## Separated from _build so it can be checked at all: under --headless the renderer is a dummy
## and MultiMesh instance data is not stored, so reading transforms back out of the shell tells
## you nothing about whether they were right going in.
##
## Apparent brightness is L / d², with L from the main-sequence mass-luminosity relation the rest
## of the game uses.  The ramp is scaled to the brightest star actually in the catalogue rather
## than to a guessed constant, and clamped to BRIGHT_DECADES below it — Sirius should be the
## brightest thing up there, not a thousand times the size of everything else.
func star_points() -> Array:
	var out: Array = []
	var apps: PackedFloat32Array = PackedFloat32Array()
	var brightest: float = 0.0
	for s: Dictionary in StarMapPanel.all_stars():
		var p: Vector3 = s["pos"]
		var d: float = p.length()
		if d < 1.0e-4:
			continue                      # Sol itself; it is drawn as a body, not as a point
		var m: float = maxf(float(s.get("mass", 1.0)), 0.02)
		var app: float = pow(m, StarModel.LUMINOSITY_EXP) / (d * d)
		out.append({"dir": p / d, "color": s.get("color", Color.WHITE)})
		apps.append(app)
		brightest = maxf(brightest, app)
	if out.is_empty() or brightest <= 0.0:
		return []
	var top: float = log(brightest) / log(10.0)
	for i in range(out.size()):
		# Position on the ramp: decades below the brightest star, clamped.
		var decades: float = top - log(maxf(apps[i], 1.0e-30)) / log(10.0)
		var t: float = 1.0 - clampf(decades / BRIGHT_DECADES, 0.0, 1.0)
		var e: Dictionary = out[i]
		e["size"] = lerpf(SIZE_MIN, SIZE_MAX, t * t)
		var c: Color = e["color"]
		e["color"] = Color(c.r, c.g, c.b, lerpf(ALPHA_MIN, ALPHA_MAX, t))
	return out


## Lay one quad per catalogued star on the shell, in its real direction.
func _build() -> void:
	_built_version = StarMapPanel.catalogue_version()
	var pts: Array = star_points()
	if _mm == null:
		_mm = MultiMesh.new()
		_mm.transform_format = MultiMesh.TRANSFORM_3D
		_mm.use_colors = true
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		_mm.mesh = quad
		_mmi = MultiMeshInstance3D.new()
		_mmi.name = "StarShell"
		_mmi.multimesh = _mm
		_mmi.material_override = _make_material()
		_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Sized at the shell, so the sky is never culled by its own bounds as the camera moves.
		var e: float = SKY_RADIUS + SIZE_MAX
		_mmi.custom_aabb = AABB(Vector3(-e, -e, -e), Vector3(e * 2.0, e * 2.0, e * 2.0))
		add_child(_mmi)
	_mm.instance_count = pts.size()
	_mm.visible_instance_count = pts.size()
	for i in range(pts.size()):
		var p: Dictionary = pts[i]
		var sz: float = float(p["size"])
		_mm.set_instance_transform(i, Transform3D(
			Basis.IDENTITY.scaled(Vector3(sz, sz, sz)),
			(p["dir"] as Vector3) * SKY_RADIUS))
		_mm.set_instance_color(i, p["color"])


## Unshaded, billboarded, additively blended points.  Additive because stars ADD light to the
## background rather than covering it, so overlapping ones brighten instead of flattening into
## one disc, and the dark blue behind them shows through the faint ones.
func _make_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.disable_receive_shadows = true
	m.albedo_texture = _point_texture()
	# Drawn before anything else in the transparent pass, and writing no depth, so planets and
	# craft always sit in front of the sky whatever order they are submitted in.
	m.render_priority = -128
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


## A soft round point: opaque in the middle, falling to nothing at the rim, so a star reads as a
## glow rather than as a square.
static var _tex: ImageTexture = null
static func _point_texture() -> ImageTexture:
	if _tex != null:
		return _tex
	var n: int = 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBAF)
	var c: float = float(n - 1) * 0.5
	for y in range(n):
		for x in range(n):
			var r: float = Vector2(float(x) - c, float(y) - c).length() / c
			var a: float = clampf(1.0 - r, 0.0, 1.0)
			a = a * a * a                       # tight core, long faint skirt
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_tex = ImageTexture.create_from_image(img)
	return _tex
