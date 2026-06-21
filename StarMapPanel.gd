extends Control
class_name StarMapPanel

## A 3D map of nearby stars centred on the Sun, projected orthographically to 2D.
## Drag the mouse to rotate the view about the Sun, scroll to zoom, and click a star
## to select it.  Star positions are real (equatorial cartesian, in light-years).

## Emitted when the player clicks a star (or empty space → "").  Reserved for future
## interstellar-mission targeting.
signal star_selected(star_name: String)

# ── Nearby stars within ~20 ly (real coordinates, light-years, Sun at origin) ──────
const STARS: Array = [
	{"name": "Proxima Centauri", "pos": Vector3(-1.55, -1.18, -3.77), "dist": 4.25, "spectral": "M", "color": Color(1.0, 0.62, 0.46)},
	{"name": "Alpha Centauri A", "pos": Vector3(-1.63, -1.36, -3.81), "dist": 4.37, "spectral": "G", "color": Color(1.0, 0.93, 0.66)},
	{"name": "Alpha Centauri B", "pos": Vector3(-1.63, -1.36, -3.81), "dist": 4.37, "spectral": "K", "color": Color(1.0, 0.8, 0.55)},
	{"name": "Barnard's Star", "pos": Vector3(-0.06, -5.94, 0.49), "dist": 5.96, "spectral": "M", "color": Color(1.0, 0.62, 0.46)},
	{"name": "Wolf 359", "pos": Vector3(-7.50, 2.13, 0.96), "dist": 7.86, "spectral": "M", "color": Color(1.0, 0.62, 0.46)},
	{"name": "Lalande 21185", "pos": Vector3(-6.52, 1.65, 4.88), "dist": 8.31, "spectral": "M", "color": Color(1.0, 0.62, 0.46)},
	{"name": "Sirius", "pos": Vector3(-1.62, 8.13, -2.49), "dist": 8.66, "spectral": "A", "color": Color(0.82, 0.88, 1.0)},
	{"name": "Luyten 726-8", "pos": Vector3(7.54, 3.48, -2.69), "dist": 8.73, "spectral": "M", "color": Color(1.0, 0.62, 0.46)},
	{"name": "Ross 154", "pos": Vector3(1.91, -8.66, -3.92), "dist": 9.69, "spectral": "M", "color": Color(1.0, 0.62, 0.46)},
	{"name": "Ross 248", "pos": Vector3(7.37, -0.58, 7.18), "dist": 10.30, "spectral": "M", "color": Color(1.0, 0.62, 0.46)},
	{"name": "Epsilon Eridani", "pos": Vector3(6.18, 8.28, -1.72), "dist": 10.47, "spectral": "K", "color": Color(1.0, 0.8, 0.55)},
	{"name": "Lacaille 9352", "pos": Vector3(8.46, -2.04, -6.29), "dist": 10.74, "spectral": "M", "color": Color(1.0, 0.62, 0.46)},
	{"name": "Ross 128", "pos": Vector3(-10.98, 0.59, 0.15), "dist": 11.00, "spectral": "M", "color": Color(1.0, 0.62, 0.46)},
	{"name": "61 Cygni", "pos": Vector3(6.47, -6.09, 7.14), "dist": 11.40, "spectral": "K", "color": Color(1.0, 0.8, 0.55)},
	{"name": "Procyon", "pos": Vector3(-4.79, 10.36, 1.04), "dist": 11.46, "spectral": "F", "color": Color(1.0, 1.0, 0.94)},
	{"name": "Epsilon Indi", "pos": Vector3(5.68, -3.17, -9.93), "dist": 11.87, "spectral": "K", "color": Color(1.0, 0.8, 0.55)},
	{"name": "Tau Ceti", "pos": Vector3(10.29, 5.02, -3.27), "dist": 11.91, "spectral": "G", "color": Color(1.0, 0.93, 0.66)},
	{"name": "Gliese 581", "pos": Vector3(-13.03, -15.45, -2.74), "dist": 20.40, "spectral": "M", "color": Color(1.0, 0.62, 0.46)},
]

const ROT_SENS:  float = 0.01    # radians of rotation per pixel dragged
const MIN_PITCH: float = -1.45   # ~ ±83° — stop short of gimbal flip at the poles
const MAX_PITCH: float =  1.45
const ZOOM_STEP: float = 1.12
const ZOOM_MIN:  float = 0.4
const ZOOM_MAX:  float = 6.0
const PICK_PX:   float = 16.0    # click tolerance for selecting a star

const BG_COLOR:    Color = Color(0.03, 0.04, 0.08, 0.96)
const RING_COLOR:  Color = Color(0.30, 0.45, 0.65, 0.20)
const RING_LABEL:  Color = Color(0.42, 0.56, 0.78, 0.55)
const DROP_COLOR:  Color = Color(0.45, 0.60, 0.85, 0.12)

var _yaw:   float = 0.6
var _pitch: float = 0.5
var _zoom:  float = 1.0
var _selected: int = -1

var _dragging:   bool = false
var _drag_moved: bool = false
var _last_mouse: Vector2 = Vector2.ZERO

var _font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_font = ThemeDB.fallback_font
	resized.connect(queue_redraw)

# ── Public API ────────────────────────────────────────────────────────────────

## Name of the currently selected star, or "" if none.
func selected_star() -> String:
	return str(STARS[_selected]["name"]) if _selected >= 0 else ""

# ── Projection ────────────────────────────────────────────────────────────────

## Orbit-camera basis from azimuth (_yaw) and elevation (_pitch), with the star
## coordinate Z axis as "up".  Dragging horizontally spins the map about that
## vertical axis like a turntable; dragging vertically raises/lowers the viewpoint.
func _view_basis() -> Basis:
	var ca := cos(_yaw);   var sa := sin(_yaw)
	var ce := cos(_pitch); var se := sin(_pitch)
	var right := Vector3(-sa, ca, 0.0)                 # screen → world right (in XY plane)
	var up    := Vector3(-se * ca, -se * sa, ce)       # screen up (world Z when level)
	var fwd   := Vector3(ca * ce, sa * ce, se)         # toward the viewer (depth)
	return Basis(right, up, fwd)

func _max_dist() -> float:
	var m: float = 1.0
	for s: Dictionary in STARS:
		m = maxf(m, float(s["dist"]))
	return m

## Pixels per light-year so the farthest star fits the panel with a margin.
func _fit_scale(center: Vector2) -> float:
	return (minf(center.x, center.y) * 0.86 / _max_dist()) * _zoom

## Orthographic projection of a world point onto the camera's right/up axes.
func _project(p: Vector3, b: Basis, center: Vector2, scale: float) -> Vector2:
	return center + Vector2(p.dot(b.x), -p.dot(b.y)) * scale

## Signed depth along the view axis (larger = nearer the viewer).
func _depth(p: Vector3, b: Basis) -> float:
	return p.dot(b.z)

# ── Drawing ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	draw_rect(full, BG_COLOR)
	draw_rect(full, Color(0.4, 0.5, 0.7, 0.25), false, 1.0)

	var center: Vector2 = size * 0.5
	var b := _view_basis()
	var scale := _fit_scale(center)
	var maxd := _max_dist()

	# Reference rings lying in the star XY plane — they tilt into ellipses as you
	# rotate, giving the otherwise-flat projection a clear sense of 3D orientation.
	for r_ly: int in [5, 10, 15, 20]:
		if float(r_ly) > maxd + 2.0:
			continue
		var pts := PackedVector2Array()
		for i in range(65):
			var a := TAU * float(i) / 64.0
			pts.append(_project(Vector3(cos(a), sin(a), 0.0) * float(r_ly), b, center, scale))
		draw_polyline(pts, RING_COLOR, 1.0, true)
		draw_string(_font, _project(Vector3(float(r_ly), 0.0, 0.0), b, center, scale) + Vector2(3, -3),
			"%d ly" % r_ly, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, RING_LABEL)

	# Stars, far-to-near so nearer ones overlap on top.
	var order: Array = range(STARS.size())
	order.sort_custom(func(i: int, j: int) -> bool:
		return _depth(STARS[i]["pos"], b) < _depth(STARS[j]["pos"], b))

	for i: int in order:
		var s: Dictionary = STARS[i]
		var p: Vector3 = s["pos"]
		var sp := _project(p, b, center, scale)
		# Drop line to the reference plane conveys the star's height above/below it.
		var foot := _project(Vector3(p.x, p.y, 0.0), b, center, scale)
		draw_line(foot, sp, DROP_COLOR, 1.0)
		draw_circle(foot, 1.5, DROP_COLOR)

		var near := clampf(_depth(p, b) / maxd * 0.5 + 0.5, 0.0, 1.0)
		var rad := lerpf(3.0, 6.5, near)
		var col: Color = s["color"]
		if i == _selected:
			draw_circle(sp, rad + 6.0, Color(1.0, 1.0, 1.0, 0.22))
			draw_arc(sp, rad + 6.0, 0.0, TAU, 40, Color(0.9, 0.95, 1.0, 0.9), 1.5, true)
		draw_circle(sp, rad + 2.0, Color(col.r, col.g, col.b, 0.22))   # glow
		draw_circle(sp, rad, col)
		draw_string(_font, sp + Vector2(rad + 4.0, 4.0), str(s["name"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(0.88, 0.93, 1.0, 0.95) if i == _selected else Color(0.78, 0.84, 0.96, 0.6))

	# The Sun, fixed at the centre of the map.
	draw_circle(center, 10.0, Color(1.0, 0.85, 0.3, 0.22))
	draw_circle(center, 5.5, Color(1.0, 0.9, 0.42))
	draw_string(_font, center + Vector2(9, -6), "Sol", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.92, 0.6))

	# Title + controls hint.
	draw_string(_font, Vector2(14, 24), "Star Map", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.9, 0.95, 1.0))
	draw_string(_font, Vector2(14, 42), "Drag to rotate  ·  scroll to zoom  ·  click a star to select",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.68, 0.8))

	# Selected-star info box.
	if _selected >= 0:
		var s: Dictionary = STARS[_selected]
		var lines: Array = [str(s["name"]),
			"%.2f light-years" % float(s["dist"]),
			"Spectral type %s" % str(s["spectral"])]
		var box := Rect2(Vector2(12, size.y - (16.0 * lines.size() + 16.0) - 12.0),
			Vector2(248, 16.0 * lines.size() + 16.0))
		draw_rect(box, Color(0.06, 0.08, 0.14, 0.92))
		draw_rect(box, Color(0.4, 0.55, 0.8, 0.5), false, 1.0)
		for li in range(lines.size()):
			draw_string(_font, box.position + Vector2(10, 19 + li * 16), str(lines[li]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12 if li == 0 else 11,
				Color(0.92, 0.96, 1.0) if li == 0 else Color(0.7, 0.78, 0.9))

# ── Input ─────────────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_dragging = true
					_drag_moved = false
					_last_mouse = mb.position
				else:
					if _dragging and not _drag_moved:
						_try_select(mb.position)
					_dragging = false
				accept_event()
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom = clampf(_zoom * ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
					queue_redraw()
					accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom = clampf(_zoom / ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
					queue_redraw()
					accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		var d := mm.position - _last_mouse
		_last_mouse = mm.position
		if d.length() > 1.5:
			_drag_moved = true
		_yaw -= d.x * ROT_SENS
		_pitch = clampf(_pitch + d.y * ROT_SENS, MIN_PITCH, MAX_PITCH)
		queue_redraw()
		accept_event()

## Pick the nearest projected star to the click, within PICK_PX pixels.
func _try_select(mouse: Vector2) -> void:
	var center: Vector2 = size * 0.5
	var b := _view_basis()
	var scale := _fit_scale(center)
	var best: int = -1
	var best_d: float = PICK_PX
	for i in range(STARS.size()):
		var dd := _project(STARS[i]["pos"], b, center, scale).distance_to(mouse)
		if dd < best_d:
			best_d = dd
			best = i
	_selected = best
	queue_redraw()
	star_selected.emit(selected_star())
