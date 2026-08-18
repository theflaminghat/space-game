class_name GalaxyMapPanel
extends Control

## The player's galaxy map: a flat, top-down view of the galactic plane tiled by the same
## hexagonal regions the simulation actually runs on (see Game._region_id).  Because those hexes
## are laid out IN the galactic plane, projecting onto that plane needs no rotation — what you
## see is the real tiling, one hexagon per region, not a stylised abstraction of it.
##
## The grid is always drawn; there is nothing to toggle.  Click a hexagon to select it and a
## panel opens beside the map with that region's stars, settlement and population.
##
## Hover a tile to outline it, click to select it.  WASD or drag to pan · scroll to zoom.

# ── View ──────────────────────────────────────────────────────────────────────
## Half-width shown at zoom 1, in light-years.  The region grid reaches REGION_GRID_RADIUS (26)
## hexes from Sol — 90 000 ly, enough to tile the far rim of the disk — so the default view shows
## the neighbourhood and you pan or zoom out to reach the rest.
const DEFAULT_VIEW_LY: float = 34_000.0
const ZOOM_STEP: float = 1.15
const ZOOM_MIN:  float = 0.25
const ZOOM_MAX:  float = 60.0
## WASD pan speed, as a fraction of the visible half-width per second — so it feels the same
## whether you are looking at the whole galaxy or one region, instead of crawling when zoomed in.
const KEY_PAN_PER_SEC: float = 0.9

## A hexagon is drawn slightly inside its true footprint so neighbours read as separate tiles
## rather than a continuous wash.
const HEX_INSET: float = 0.92

# ── Colours ───────────────────────────────────────────────────────────────────
const COL_BG:        Color = Color(0.03, 0.035, 0.06, 1.0)
const COL_EMPTY:     Color = Color(0.30, 0.36, 0.50)   # tinted by stellar density
const COL_SETTLED:   Color = Color(0.30, 0.90, 0.55)   # tinted by colonised fraction
const COL_EDGE:      Color = Color(0.42, 0.52, 0.72, 0.25)
const COL_SELECTED:  Color = Color(1.00, 0.88, 0.40)
const COL_HOVER:     Color = Color(1.00, 1.00, 1.00)   # white edge under the cursor
const COL_SOL:       Color = Color(1.00, 1.00, 0.70)
const COL_CENTRE:    Color = Color(1.00, 0.82, 0.45)

var _zoom: float = 1.0
var _pan: Vector2 = Vector2.ZERO          # view offset in light-years, in the galactic plane
var _dragging: bool = false
var _last_mouse: Vector2 = Vector2.ZERO
var _drag_moved: bool = false
var _press_pos: Vector2 = Vector2.ZERO
var _font: Font

var _selected: String = ""                # region id, "" = nothing selected
var _hover: String = ""                   # region id under the cursor

# ── Info panel ────────────────────────────────────────────────────────────────
const INFO_W: float = 250.0
const INFO_MARGIN: float = 12.0
var _info: PanelContainer = null
var _info_rows: Dictionary = {}           # label key → value Label
var _info_title: Label = null

## Rows shown for the selected region, in order.
const INFO_ROWS: Array = [
	"Distance from Sol", "Distance from centre", "Stellar density",
	"Stars", "Colonisable systems", "Settled systems", "Population", "Capacity",
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func() -> void:
		if _hover != "":
			_hover = ""
			queue_redraw())
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical   = Control.SIZE_EXPAND_FILL
	clip_contents = true
	_font = ThemeDB.fallback_font
	# NO PanelBackground here.  A Control renders its own _draw() BENEATH its children, so an
	# opaque backing panel would sit on top of the whole map.  _draw() paints COL_BG itself.
	resized.connect(queue_redraw)
	_build_info_panel()
	set_process(true)


## WASD (the same actions the 3-D camera uses — it stands down while this panel is open).
## Polled rather than event-driven so a held key pans smoothly.
func _process(delta: float) -> void:
	if not visible:
		return
	var dir := Vector2.ZERO
	if Input.is_action_pressed("left"):  dir.x -= 1.0
	if Input.is_action_pressed("right"): dir.x += 1.0
	if Input.is_action_pressed("up"):    dir.y += 1.0
	if Input.is_action_pressed("down"):  dir.y -= 1.0
	if dir == Vector2.ZERO:
		return
	# Move by a share of what is on screen, so the pace matches the zoom level.
	var span_ly: float = DEFAULT_VIEW_LY / maxf(_zoom, 0.001)
	_pan += dir.normalized() * span_ly * KEY_PAN_PER_SEC * delta
	queue_redraw()


## The selection readout: hidden until a region is picked, then filled from Game.galaxy_region_info.
func _build_info_panel() -> void:
	_info = PanelContainer.new()
	_info.custom_minimum_size = Vector2(INFO_W, 0)
	_info.anchor_left = 1.0
	_info.anchor_right = 1.0
	_info.offset_left = -(INFO_W + INFO_MARGIN)
	_info.offset_right = -INFO_MARGIN
	_info.offset_top = INFO_MARGIN
	_info.visible = false
	add_child(_info)

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	_info.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	margin.add_child(col)

	_info_title = Label.new()
	_info_title.add_theme_font_size_override("font_size", 14)
	_info_title.add_theme_color_override("font_color", COL_SELECTED)
	col.add_child(_info_title)
	col.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 1)
	col.add_child(grid)
	for key: String in INFO_ROWS:
		var k := Label.new()
		k.text = key
		k.add_theme_font_size_override("font_size", 11)
		k.add_theme_color_override("font_color", Color(0.62, 0.70, 0.84))
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(k)
		var v := Label.new()
		v.text = "-"
		v.add_theme_font_size_override("font_size", 11)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(v)
		_info_rows[key] = v

	var hint := Label.new()
	hint.text = "Click another region to inspect it."
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.50, 0.56, 0.68))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)


# ── View maths ────────────────────────────────────────────────────────────────

## Pixels per light-year at the current zoom.
func _scale_px() -> float:
	return (minf(size.x, size.y) * 0.5 * 0.92 / DEFAULT_VIEW_LY) * _zoom

## A point in the galactic plane (already reduced to 2-D light-year coordinates) → screen.
func _to_screen(p: Vector2, s: float) -> Vector2:
	return size * 0.5 + (p - _pan) * Vector2(s, -s)   # +y is galactic north, so flip for screen

## Reduce a Sol-relative 3-D position to 2-D coordinates in the galactic plane.
func _plane(p: Vector3, gx: Vector3, gy: Vector3) -> Vector2:
	return Vector2(p.dot(gx), p.dot(gy))


# ── Drawing ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
	var game := get_tree().current_scene
	if game == null or not game.has_method("galaxy_region_grid"):
		draw_string(_font, Vector2(14, 26), "Galaxy map — no data source",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.6, 0.6))
		return

	var s: float = _scale_px()
	var hex_r: float = float(game.galaxy_region_cell_ly())
	var pax: Array = game.galaxy_region_plane_axes()
	var gx: Vector3 = pax[0]
	var gy: Vector3 = pax[1]
	var r_px: float = hex_r * s
	var cull: float = r_px + 4.0

	# Flat-top hex corner offsets, computed once and reused for every tile.
	var corners: Array = []
	for i in range(6):
		var a := deg_to_rad(60.0 * float(i))
		corners.append(Vector2(cos(a), sin(a)) * (r_px * HEX_INSET))

	for rg: Dictionary in game.galaxy_region_grid():
		var p := _to_screen(_plane(rg["center"] as Vector3, gx, gy), s)
		if p.x < -cull or p.y < -cull or p.x > size.x + cull or p.y > size.y + cull:
			continue
		var poly := PackedVector2Array()
		for c: Vector2 in corners:
			poly.append(p + Vector2(c.x, -c.y))   # screen y is inverted

		var dens: float = clampf(float(rg["density"]), 0.0, 1.0)
		var frac: float = clampf(float(rg["frac"]), 0.0, 1.0)
		var rid: String = str(rg["id"])
		var sel: bool = rid == _selected
		var hov: bool = rid == _hover

		# Unsettled regions read as the galaxy's stellar density; settled ones go green in
		# proportion to how much of the region humanity actually holds.
		draw_colored_polygon(poly, Color(COL_EMPTY.r, COL_EMPTY.g, COL_EMPTY.b, 0.10 + 0.35 * dens))
		if frac > 0.0:
			draw_colored_polygon(poly,
				Color(COL_SETTLED.r, COL_SETTLED.g, COL_SETTLED.b, 0.20 + 0.55 * frac))
		var outline := poly.duplicate()
		outline.append(poly[0])
		if sel:
			draw_polyline(outline, COL_SELECTED, 2.0)
		elif hov:
			draw_polyline(outline, COL_HOVER, 2.0)
		else:
			draw_polyline(outline, COL_EDGE, 1.0)

	# Landmarks: Sol at the origin, and the galactic centre it orbits.
	var sol := _to_screen(Vector2.ZERO, s)
	draw_circle(sol, 3.5, COL_SOL)
	draw_string(_font, sol + Vector2(7, -4), "Sol", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_SOL)
	if game.has_method("galaxy_region_info"):
		var gc := _to_screen(_plane((gx * StarMapPanel.SOL_GC_LY), gx, gy), s)
		draw_circle(gc, 4.0, COL_CENTRE)
		draw_arc(gc, 10.0, 0.0, TAU, 24, Color(COL_CENTRE.r, COL_CENTRE.g, COL_CENTRE.b, 0.5), 1.0, true)
		draw_string(_font, gc + Vector2(8, -4), "Galactic Centre",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_CENTRE)

	_draw_scale_bar(s)
	draw_string(_font, Vector2(14, 24), "Galaxy", HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
		Color(0.90, 0.95, 1.0))
	draw_string(_font, Vector2(14, 42),
		"%s ly across · click a region · WASD or drag to pan · scroll zoom" % Units.format_si(
			DEFAULT_VIEW_LY * 2.0 / _zoom, ""),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.62, 0.75))


## A calibrated bar rounded to a 1/2/5×10ⁿ length, so distances read off the map directly.
func _draw_scale_bar(s: float) -> void:
	if s <= 0.0:
		return
	var raw: float = 130.0 / s
	var mag: float = pow(10.0, floor(log(raw) / log(10.0)))
	var norm: float = raw / mag
	var nice: float = 1.0 if norm < 1.5 else (2.0 if norm < 3.5 else (5.0 if norm < 7.5 else 10.0))
	var bar_ly: float = nice * mag
	var bar_px: float = bar_ly * s
	var y: float = size.y - 22.0
	var x0: float = 16.0
	var c := Color(0.9, 0.95, 1.0, 0.85)
	draw_line(Vector2(x0, y), Vector2(x0 + bar_px, y), c, 2.0)
	draw_line(Vector2(x0, y - 4), Vector2(x0, y + 4), c, 2.0)
	draw_line(Vector2(x0 + bar_px, y - 4), Vector2(x0 + bar_px, y + 4), c, 2.0)
	draw_string(_font, Vector2(x0, y - 8), "%s ly" % Units.format_si(bar_ly, ""),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, c)


# ── Interaction ───────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_dragging = true
					_drag_moved = false
					_last_mouse = mb.position
					_press_pos = mb.position
				else:
					_dragging = false
					# A press that never became a drag is a click: select (or clear).
					if not _drag_moved:
						_selected = _pick_region(mb.position)
						_refresh_info()
						queue_redraw()
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
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT:
				accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			var d: Vector2 = mm.position - _last_mouse
			_last_mouse = mm.position
			if (mm.position - _press_pos).length() > 4.0:
				_drag_moved = true
			var s: float = _scale_px()
			if s > 0.0:
				_pan -= Vector2(d.x, -d.y) / s   # drag moves the map with the cursor
			queue_redraw()
			accept_event()
		else:
			# Only repaint when the tile under the cursor actually changes — picking runs over
			# every drawn region, and mouse motion fires far more often than the hover changes.
			var h: String = _pick_region(mm.position)
			if h != _hover:
				_hover = h
				queue_redraw()


## Which region is under a screen point — nearest tile centre within its footprint, or "".
func _pick_region(pos: Vector2) -> String:
	var game := get_tree().current_scene
	if game == null or not game.has_method("galaxy_region_grid"):
		return ""
	var s: float = _scale_px()
	var pax: Array = game.galaxy_region_plane_axes()
	var gx: Vector3 = pax[0]
	var gy: Vector3 = pax[1]
	var reach: float = float(game.galaxy_region_cell_ly()) * s
	var best: String = ""
	var best_d: float = reach
	for rg: Dictionary in game.galaxy_region_grid():
		var p := _to_screen(_plane(rg["center"] as Vector3, gx, gy), s)
		var d: float = (p - pos).length()
		if d < best_d:
			best_d = d
			best = str(rg["id"])
	return best


## Fill the info panel from the selected region, or hide it when nothing is selected.
func _refresh_info() -> void:
	if _info == null:
		return
	var game := get_tree().current_scene
	if _selected == "" or game == null or not game.has_method("galaxy_region_info"):
		_info.visible = false
		return
	var d: Dictionary = game.galaxy_region_info(_selected)
	_info_title.text = "Region %s" % str(d.get("id", "?"))
	var frac: float = float(d.get("frac", 0.0))
	_set_row("Distance from Sol",   "%s ly" % Units.format_si(float(d.get("dist_sol_ly", 0.0)), ""))
	_set_row("Distance from centre", "%s ly" % Units.format_si(float(d.get("dist_gc_ly", 0.0)), ""))
	_set_row("Stellar density",     "%.3f" % float(d.get("density", 0.0)))
	_set_row("Stars",               Units.format_si(float(d.get("stars", 0.0)), ""))
	_set_row("Colonisable systems", Units.format_si(float(d.get("colonizable", 0.0)), ""))
	_set_row("Settled systems", "%s  (%.0f%%)" % [
		Units.format_si(float(d.get("colonized", 0.0)), ""), frac * 100.0])
	_set_row("Population",          Units.format_si(float(d.get("population", 0.0)), ""))
	_set_row("Capacity",            Units.format_si(float(d.get("capacity", 0.0)), ""))
	_info.visible = true


func _set_row(key: String, value: String) -> void:
	if _info_rows.has(key):
		(_info_rows[key] as Label).text = value


## Called by Game/sidebar when the panel is opened, so a region selected earlier shows current
## figures rather than whatever they were when it was last looked at.
func refresh() -> void:
	_refresh_info()
	queue_redraw()
