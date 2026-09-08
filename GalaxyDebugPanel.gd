class_name GalaxyDebugPanel
extends Control

## Debug view of the galaxy in TRUE (linear) scale — no logarithmic compression.  Reads the
## already-generated galaxy data straight from the main StarMapPanel and renders it to real
## proportion, so the disk, spiral arms, bulge, and Sol's ~26 000 ly offset from the centre all
## appear at their actual relative sizes.  A scale bar + readout report the real distances.
##
## Drag to rotate · scroll to zoom.

var source: StarMapPanel = null   # where the galaxy data is read from

const DEFAULT_VIEW_LY: float = 95000.0   # half-width shown at zoom 1 (the whole galaxy fits)
const ROT_SENS:  float = 0.01
const ZOOM_STEP: float = 1.15
const ZOOM_MIN:  float = 0.15
const ZOOM_MAX:  float = 500.0
## Territory wireframes are hidden until the player's tile spans at least this many pixels.
const TERRITORY_MIN_PX: float = 48.0

var _yaw:   float = 0.6
var _pitch: float = 0.85
var _zoom:  float = 1.0
var _dragging: bool = false
var _last_mouse: Vector2 = Vector2.ZERO
var _font: Font
var _show_stars: bool = true      # render the full star catalogue (toggleable)
var _show_field: bool = true      # render the cosmetic field backdrop (toggleable)
var _show_regions: bool = true    # render the statistical colonisation regions (toggleable)
var _show_clusters: bool = true   # render the colonisable open-cluster shell (toggleable)
var _show_territory: bool = true  # render each cluster's Voronoi territory (toggleable)
## Height of the plane the territory is cut at, in light-years above the tile's mid-plane.  The
## cells are solids and drawing all hundred and forty at once is a thicket; one slice through
## them is an ordinary Voronoi map.  Sliding it is also the only way to SEE that the partition is
## three-dimensional — cells swell, pinch out and vanish as the plane passes their extent.
var _territory_z: float = 0.0
var _clusters_btn: Button = null
var _territory_btn: Button = null
var _territory_slider: HSlider = null
## Cluster name → 0..1 settled, pushed from Game so the ring fill matches the star map.
var _cluster_frac: Dictionary = {}

## Per-cluster colonisation fractions (cluster name → 0..1).
func set_cluster_progress(frac: Dictionary) -> void:
	_cluster_frac = frac
	queue_redraw()
var _stars_btn: Button = null
var _field_btn: Button = null
var _regions_btn: Button = null
var _selected_region: String = ""   # id of the region whose info sidebar is open ("" = none)
var _press_pos: Vector2 = Vector2.ZERO
var _drag_moved: bool = false       # distinguishes a click (select) from a drag (rotate)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical   = Control.SIZE_EXPAND_FILL
	clip_contents = true
	_font = ThemeDB.fallback_font
	resized.connect(queue_redraw)

	# Toggle for rendering every star (real + all procedural) over the field backdrop.
	_stars_btn = Button.new()
	_stars_btn.toggle_mode = true
	_stars_btn.button_pressed = true
	_stars_btn.text = "Stars: on"
	_stars_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_stars_btn.offset_left = -118.0
	_stars_btn.offset_right = -12.0
	_stars_btn.offset_top = 10.0
	_stars_btn.offset_bottom = 34.0
	_stars_btn.toggled.connect(func(on: bool) -> void:
		_show_stars = on
		_stars_btn.text = "Stars: on" if on else "Stars: off"
		queue_redraw())
	add_child(_stars_btn)

	# Toggle for the cosmetic field backdrop (the faint sampled galaxy points).
	_field_btn = Button.new()
	_field_btn.toggle_mode = true
	_field_btn.button_pressed = true
	_field_btn.text = "Field: on"
	_field_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_field_btn.offset_left = -118.0
	_field_btn.offset_right = -12.0
	_field_btn.offset_top = 38.0
	_field_btn.offset_bottom = 62.0
	_field_btn.toggled.connect(func(on: bool) -> void:
		_show_field = on
		_field_btn.text = "Field: on" if on else "Field: off"
		queue_redraw())
	add_child(_field_btn)

	# Toggle for the statistical colonisation regions (green coverage overlay).
	_regions_btn = Button.new()
	_regions_btn.toggle_mode = true
	_regions_btn.button_pressed = true
	_regions_btn.text = "Regions: on"
	_regions_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_regions_btn.offset_left = -118.0
	_regions_btn.offset_right = -12.0
	_regions_btn.offset_top = 66.0
	_regions_btn.offset_bottom = 90.0
	_regions_btn.toggled.connect(func(on: bool) -> void:
		_show_regions = on
		_regions_btn.text = "Regions: on" if on else "Regions: off"
		queue_redraw())
	add_child(_regions_btn)

	# Toggle for the colonisable open-cluster shell.
	_clusters_btn = Button.new()
	_clusters_btn.toggle_mode = true
	_clusters_btn.button_pressed = true
	_clusters_btn.text = "Clusters: on"
	_clusters_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_clusters_btn.offset_left = -118.0
	_clusters_btn.offset_right = -12.0
	_clusters_btn.offset_top = 94.0
	_clusters_btn.offset_bottom = 118.0
	_clusters_btn.toggled.connect(func(on: bool) -> void:
		_show_clusters = on
		_clusters_btn.text = "Clusters: on" if on else "Clusters: off"
		queue_redraw())
	add_child(_clusters_btn)

	# Toggle for the Voronoi territories the clusters partition their tile into, and a slider that
	# moves the plane they are cut at.  The button carries the height, so the slider needs no
	# label of its own in a 106-pixel column.
	_territory_btn = Button.new()
	_territory_btn.toggle_mode = true
	_territory_btn.button_pressed = true
	_territory_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_territory_btn.offset_left = -118.0
	_territory_btn.offset_right = -12.0
	_territory_btn.offset_top = 122.0
	_territory_btn.offset_bottom = 146.0
	_territory_btn.toggled.connect(func(on: bool) -> void:
		_show_territory = on
		_update_territory_label()
		queue_redraw())
	add_child(_territory_btn)

	_territory_slider = HSlider.new()
	_territory_slider.min_value = -StarMapPanel.tile_half_height_ly()
	_territory_slider.max_value = StarMapPanel.tile_half_height_ly()
	_territory_slider.step = 25.0
	_territory_slider.value = _territory_z
	_territory_slider.tooltip_text = "Height of the slice through the tile (ly)"
	_territory_slider.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_territory_slider.offset_left = -118.0
	_territory_slider.offset_right = -12.0
	_territory_slider.offset_top = 150.0
	_territory_slider.offset_bottom = 172.0
	_territory_slider.value_changed.connect(func(v: float) -> void:
		_territory_z = v
		_update_territory_label()
		queue_redraw())
	add_child(_territory_slider)
	_update_territory_label()

## Keep the territory button reading as the slider's own label, so the slice height is legible
## without spending another row on a caption.
func _update_territory_label() -> void:
	if _territory_btn == null:
		return
	if not _show_territory:
		_territory_btn.text = "Territory: off"
	else:
		_territory_btn.text = "Slice: %+d ly" % int(round(_territory_z))

# ── View maths (linear — the whole point of this panel) ─────────────────────────

func _view_basis() -> Basis:
	var ca := cos(_yaw);   var sa := sin(_yaw)
	var ce := cos(_pitch); var se := sin(_pitch)
	var right := Vector3(-sa, ca, 0.0)
	var up    := Vector3(-se * ca, -se * sa, ce)
	var fwd   := Vector3(ca * ce, sa * ce, se)
	return Basis(right, up, fwd)

## Pixels per light-year: the whole DEFAULT_VIEW_LY half-width fits the panel at zoom 1.
func _scale_px(center: Vector2) -> float:
	return (minf(center.x, center.y) * 0.9 / DEFAULT_VIEW_LY) * _zoom

## Straight orthographic projection — light-years × pixels-per-ly, no log remap.
func _project(p: Vector3, b: Basis, center: Vector2, s: float) -> Vector2:
	return center + Vector2(p.dot(b.x), -p.dot(b.y)) * s

# ── Drawing ─────────────────────────────────────────────────────────────────────

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.05, 1.0))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.4, 0.5, 0.7, 0.25), false, 1.0)
	var center: Vector2 = size * 0.5
	if source == null:
		draw_string(_font, Vector2(14, 26), "Galaxy debug — no data source",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.6, 0.6))
		return
	var b := _view_basis()
	var s := _scale_px(center)

	# Field stars — the faint cosmetic backdrop, at actual positions with no compression.
	if _show_field:
		for fs: Dictionary in source.galaxy_field():
			var sp := _project(fs["pos"], b, center, s)
			if sp.x < -4.0 or sp.y < -4.0 or sp.x > size.x + 4.0 or sp.y > size.y + 4.0:
				continue
			var col: Color = fs["col"]
			draw_rect(Rect2(sp - Vector2(1.1, 1.1) * 0.5, Vector2(1.1, 1.1)), Color(col.r, col.g, col.b, 0.6))

	# Region grid surrounding the player: each hexagonal-prism tile near Sol drawn as a hexagon,
	# washed by stellar density (a faint grey-blue showing the disk) with colonised tiles in green.
	if _show_regions:
		var game := get_tree().current_scene
		if game and game.has_method("galaxy_region_grid"):
			var hex_r: float = float(game.galaxy_region_cell_ly())    # circumradius (ly)
			var pax: Array = game.galaxy_region_plane_axes()          # galactic axes [gx, gy, gz]
			var gx: Vector3 = pax[0]
			var gy: Vector3 = pax[1]
			var gz: Vector3 = pax[2]
			var half_h: Vector3 = gz * (float(game.galaxy_region_height_ly()) * 0.5)  # ± prism height
			var cull_px: float = hex_r * s + 4.0
			# Unit hex corner offsets (flat-top) in the galactic plane, reused per tile.
			var corner: Array = []
			for i in range(6):
				var a := deg_to_rad(60.0 * float(i))
				corner.append(gx * (hex_r * cos(a)) + gy * (hex_r * sin(a)))
			for rg: Dictionary in game.galaxy_region_grid():
				var c: Vector3 = rg["center"]
				var csp := _project(c, b, center, s)
				if csp.x < -cull_px or csp.y < -cull_px or csp.x > size.x + cull_px or csp.y > size.y + cull_px:
					continue
				# Top and bottom hex faces of the tall prism (extruded along the galactic pole).
				var top := PackedVector2Array()
				var bot := PackedVector2Array()
				for i in range(6):
					top.append(_project(c + (corner[i] as Vector3) + half_h, b, center, s))
					bot.append(_project(c + (corner[i] as Vector3) - half_h, b, center, s))
				var dens: float = clampf(float(rg["density"]), 0.0, 1.0)
				var f: float = float(rg["frac"])
				var sel: bool = str(rg["id"]) == _selected_region
				# Fill the top face; vertical edges + bottom outline convey the prism's height.
				draw_colored_polygon(top, Color(0.40, 0.52, 0.72, 0.04 + 0.10 * dens))  # density wash
				if f > 0.0:
					draw_colored_polygon(top, Color(0.35, 0.95, 0.55, 0.15 + 0.45 * f))  # colonised overlay
				if sel:
					draw_colored_polygon(top, Color(1.0, 0.85, 0.35, 0.14))              # selection tint
				for i in range(6):
					draw_line(top[i], bot[i], Color(0.45, 0.60, 0.85, 0.08), 1.0)        # vertical edge
				top.append(top[0])
				bot.append(bot[0])
				draw_polyline(bot, Color(0.45, 0.60, 0.85, 0.08), 1.0)                   # bottom outline
				if sel:
					draw_polyline(top, Color(1.0, 0.9, 0.45, 0.95), 2.0)                 # highlighted tile
				else:
					draw_polyline(top, Color(0.45, 0.60, 0.85, 0.20), 1.0)               # top outline
				# Label each tile with its star count once it's big enough on screen to read.
				if hex_r * s >= 30.0:
					var stars: float = float(rg.get("stars", 0.0))
					var txt: String = Units.format_si(stars, "") + "★"
					var tw: float = _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
					draw_string(_font, csp - Vector2(tw * 0.5, -3.0), txt,
						HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
						Color(0.75, 0.82, 0.95, 0.55 + 0.4 * clampf(f, 0.0, 1.0)))

	# Individual stars — real + procedural — but ONLY those inside the player's zone (the
	# observation range).  Beyond it the galaxy is represented by the statistical regions above,
	# each carrying its own star count, so no procedural stars are drawn out there.
	if _show_stars:
		for st: Dictionary in StarMapPanel.all_stars():
			var stp := _project(st["pos"], b, center, s)
			if stp.x < -2.0 or stp.y < -2.0 or stp.x > size.x + 2.0 or stp.y > size.y + 2.0:
				continue
			var sc: Color = st["color"]
			draw_rect(Rect2(stp - Vector2(1.6, 1.6) * 0.5, Vector2(1.6, 1.6)), Color(sc.r, sc.g, sc.b, 0.95))

	# Open clusters — the colonisable shell just past the individual-star horizon.  Drawn as
	# rings rather than points because a cluster is hundreds to thousands of stars, and filled
	# in proportion to how much of it has been settled, so the outward campaign is legible in
	# true scale alongside everything else.
	if _show_clusters:
		# Territory first, so the cluster rings sit on top of it.  Each cluster owns the part of
		# its tile nearer to it than to any other seed — a convex 3D cell — and what is drawn is
		# one PLANE through that partition, at the height the slider is set to.  A slice is an
		# ordinary Voronoi map, which is readable; all hundred and forty solids at once is not.
		# Sliding the plane is also the only way to see that the partition has depth: cells swell,
		# pinch out and disappear as the height passes their extent, and the count in the readout
		# moves with it.
		#
		# Skipped entirely until the tile is worth more than a few dozen pixels: at galaxy zoom the
		# whole partition collapses onto Sol and reads as a smudge.
		var tile_px: float = 2.0 * StarMapPanel.HEX_SIZE * s
		if _show_territory and tile_px > TERRITORY_MIN_PX:
			var cl_all: Array = StarMapPanel.star_clusters()
			for cell: Dictionary in StarMapPanel.cluster_slice(_territory_z):
				var ci: int = int(cell["index"])
				if ci < 0 or ci >= cl_all.size():
					continue
				var cl: Dictionary = cl_all[ci]
				var home_cell: bool = bool(cl.get("is_home", false))
				var tc: Color = Color(1.0, 0.90, 0.62) if home_cell else (cl["color"] as Color)
				# A settled cluster takes the same green its ring does, so the campaign's reach
				# reads off the territory map and not just off the dots.
				var taken: float = clampf(float(_cluster_frac.get(str(cl["name"]), 0.0)), 0.0, 1.0)
				if taken > 0.0:
					tc = tc.lerp(Color(0.40, 0.95, 0.55), 0.35 + 0.65 * taken)
				var ring: PackedVector3Array = cell["poly"]
				var scr := PackedVector2Array()
				for wp: Vector3 in ring:
					scr.append(_project(wp, b, center, s))
				if scr.size() < 3:
					continue
				var fill_a: float = 0.20 if home_cell else 0.10
				var edge_a: float = 0.75 if home_cell else 0.45
				draw_colored_polygon(scr, Color(tc.r, tc.g, tc.b, fill_a))
				var loop := scr.duplicate()
				loop.append(scr[0])
				draw_polyline(loop, Color(tc.r, tc.g, tc.b, edge_a), 1.0)
				# The cell's full volume, once its footprint is wide enough to carry the text —
				# the territory is the solid, and this face of it is only a section.
				var vol: float = float(cl.get("volume", 0.0))
				var foot: float = sqrt(maxf(float(cell["area"]), 0.0)) * s
				if vol > 0.0 and foot > 46.0:
					var lp := _project(cl["pos"] as Vector3, b, center, s)
					draw_string(_font, lp + Vector2(6.0, -6.0), "%s ly³" % Units.format_si(vol, ""),
						HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(tc.r, tc.g, tc.b, 0.85))
		for cl: Dictionary in StarMapPanel.star_clusters():
			if bool(cl.get("is_home", false)):
				continue      # the home seed sits on Sol; its ring would just cover the Sun
			var cp := _project(cl["pos"], b, center, s)
			if cp.x < -6.0 or cp.y < -6.0 or cp.x > size.x + 6.0 or cp.y > size.y + 6.0:
				continue
			var cc: Color = cl["color"]
			# Radius carries the star count, so a rich cluster reads as a bigger object.
			var frac_stars: float = clampf(
				(float(cl["stars"]) - 250.0) / 5750.0, 0.0, 1.0)
			var rad: float = lerpf(2.0, 5.0, frac_stars)
			var settled: float = clampf(float(_cluster_frac.get(str(cl["name"]), 0.0)), 0.0, 1.0)
			if settled > 0.0:
				# Filled wedge = the share taken, drawn from 12 o'clock so partial progress reads.
				draw_circle(cp, rad, Color(0.35, 0.90, 0.55, 0.30 + 0.55 * settled))
			draw_arc(cp, rad, 0.0, TAU, 18, Color(cc.r, cc.g, cc.b, 0.85), 1.0, true)

	# Named clusters/nebulae — tiny at galaxy scale, but positioned correctly.
	for m: Dictionary in source.galaxy_landmarks():
		var msp := _project(m["pos"], b, center, s)
		var mc: Color = m["color"]
		draw_circle(msp, 2.0, Color(mc.r, mc.g, mc.b, 0.85))

	# The galactic centre and Sol, marked, so the true offset is legible.
	var gc_sp := _project(source.galaxy_center(), b, center, s)
	draw_circle(gc_sp, 4.0, Color(1.0, 0.82, 0.45))
	draw_arc(gc_sp, 9.0, 0.0, TAU, 24, Color(1.0, 0.82, 0.45, 0.5), 1.0, true)
	draw_string(_font, gc_sp + Vector2(7.0, -4.0), "Galactic Centre",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.86, 0.6))
	var sol_sp := _project(Vector3.ZERO, b, center, s)
	draw_circle(sol_sp, 3.0, Color(1.0, 1.0, 0.65))
	draw_string(_font, sol_sp + Vector2(6.0, -4.0), "Sol",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 1.0, 0.7))

	_draw_scale_bar(s)

	# Header + live scale readout — this is a debug view, so surface the real numbers.
	draw_string(_font, Vector2(14, 24), "Galaxy — linear scale (debug)",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.95, 1.0))
	var view_ly: float = DEFAULT_VIEW_LY / _zoom
	draw_string(_font, Vector2(14, 44),
		"View half-width %s ly  ·  %s ly/px  ·  zoom ×%.2f" % [
			Units.format_si(view_ly, ""), Units.format_si(1.0 / maxf(s, 1e-9), ""), _zoom],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.62, 0.72, 0.88))
	var star_txt: String = "%d stars in zone" % StarMapPanel.all_stars().size() if _show_stars else "stars off"
	var settled_cl: int = 0
	var total_cl: int = 0
	for cl: Dictionary in StarMapPanel.star_clusters():
		if bool(cl.get("is_home", false)):
			continue          # counted as territory, not as a target
		total_cl += 1
		if float(_cluster_frac.get(str(cl["name"]), 0.0)) > 0.0:
			settled_cl += 1
	var cluster_txt: String = "%d clusters, %d touched" % [
		total_cl, settled_cl] if _show_clusters else "clusters off"
	if _show_clusters and _show_territory:
		# The cells tile the prism exactly, so the volume is always the whole region; the count is
		# how many of them the current slice actually passes through.
		cluster_txt += ", %s ly³ in %d cells (%d cut at %+d ly)  ·  seed %d" % [
			Units.format_si(StarMapPanel.tile_volume_ly3(), ""),
			StarMapPanel.star_clusters().size(),
			StarMapPanel.cluster_slice(_territory_z).size(), int(round(_territory_z)),
			StarMapPanel.galaxy_seed()]
	var field_txt: String = "field %d" % source.galaxy_field().size() if _show_field else "field off"
	var region_txt: String = "regions off"
	if _show_regions:
		var g := get_tree().current_scene
		region_txt = "%d colonised regions" % (g.galaxy_regions_data().size() if g and g.has_method("galaxy_regions_data") else 0)
	draw_string(_font, Vector2(14, 60),
		"%s  ·  %s  ·  %s  ·  %s  ·  click a region · drag rotate · scroll zoom" % [
			field_txt, star_txt, cluster_txt, region_txt],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.62, 0.75))

	# Selected-region info sidebar (only while a region is picked and regions are shown).
	if _show_regions and _selected_region != "":
		var gr := get_tree().current_scene
		if gr and gr.has_method("galaxy_region_info"):
			_draw_region_sidebar(gr.galaxy_region_info(_selected_region))

## Info sidebar for the selected region: a docked panel on the left listing the tile's location,
## stellar content, and colonisation state, drawn straight (matches this panel's debug aesthetic).
func _draw_region_sidebar(info: Dictionary) -> void:
	var pad: float = 12.0
	var w: float = 236.0
	var x: float = pad
	var y: float = 84.0
	var rows: Array = [
		["Region", str(info.get("id", "—"))],
		["Distance from Sol", "%s ly" % Units.format_si(float(info.get("dist_sol_ly", 0.0)), "")],
		["Distance from centre", "%s ly" % Units.format_si(float(info.get("dist_gc_ly", 0.0)), "")],
		["Stellar density", "%.3f" % float(info.get("density", 0.0))],
		["Stars", "%s" % Units.format_si(float(info.get("stars", 0.0)), "")],
		["Colonisable systems", "%s" % Units.format_si(float(info.get("colonizable", 0.0)), "")],
		["Colonised systems", "%s  (%.0f%%)" % [
			Units.format_si(float(info.get("colonized", 0.0)), ""), 100.0 * float(info.get("frac", 0.0))]],
		["Population", "%s" % Units.format_si(float(info.get("population", 0.0)), "")],
		["Capacity", "%s" % Units.format_si(float(info.get("capacity", 0.0)), "")],
	]
	var h: float = 44.0 + float(rows.size()) * 20.0
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), Color(0.05, 0.06, 0.10, 0.92))
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), Color(1.0, 0.9, 0.45, 0.55), false, 1.0)
	draw_string(_font, Vector2(x + 12.0, y + 22.0), "Region detail",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.92, 0.6))
	var ry: float = y + 44.0
	for row: Array in rows:
		draw_string(_font, Vector2(x + 12.0, ry), str(row[0]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.62, 0.70, 0.84))
		draw_string(_font, Vector2(x + 12.0, ry), str(row[1]),
			HORIZONTAL_ALIGNMENT_RIGHT, w - 24.0, 11, Color(0.90, 0.94, 1.0))
		ry += 20.0

## A calibrated scale bar (rounded to a 1/2/5×10ⁿ length near 130 px) so the true scale reads off.
func _draw_scale_bar(s: float) -> void:
	if s <= 0.0:
		return
	var raw_ly: float = 130.0 / s
	var mag: float = pow(10.0, floor(log(raw_ly) / log(10.0)))
	var norm: float = raw_ly / mag
	var nice: float = 1.0 if norm < 1.5 else (2.0 if norm < 3.5 else (5.0 if norm < 7.5 else 10.0))
	var bar_ly: float = nice * mag
	var bar_px: float = bar_ly * s
	var y: float = size.y - 22.0
	var x0: float = 16.0
	var c := Color(0.9, 0.95, 1.0, 0.9)
	draw_line(Vector2(x0, y), Vector2(x0 + bar_px, y), c, 2.0)
	draw_line(Vector2(x0, y - 4.0), Vector2(x0, y + 4.0), c, 2.0)
	draw_line(Vector2(x0 + bar_px, y - 4.0), Vector2(x0 + bar_px, y + 4.0), c, 2.0)
	draw_string(_font, Vector2(x0, y - 8.0), "%s ly" % Units.format_si(bar_ly, ""),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, c)

# ── Input ───────────────────────────────────────────────────────────────────────

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
					# A press that didn't turn into a drag is a click — select/deselect a region.
					if not _drag_moved:
						_selected_region = _pick_region(mb.position)
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
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		var d := mm.position - _last_mouse
		_last_mouse = mm.position
		if (mm.position - _press_pos).length() > 4.0:
			_drag_moved = true   # it's a rotate, not a click
		_yaw -= d.x * ROT_SENS
		_pitch = clampf(_pitch + d.y * ROT_SENS, -1.45, 1.45)
		queue_redraw()
		accept_event()

## Which region tile (id) is under a screen point — nearest projected centre within its hex
## footprint, or "" if the click missed every drawn tile.  Uses the same projection as _draw.
func _pick_region(pos: Vector2) -> String:
	if not _show_regions or source == null:
		return ""
	var game := get_tree().current_scene
	if game == null or not game.has_method("galaxy_region_grid"):
		return ""
	var center: Vector2 = size * 0.5
	var b := _view_basis()
	var s := _scale_px(center)
	var reach: float = float(game.galaxy_region_cell_ly()) * s   # hex circumradius in px
	var best: String = ""
	var best_d: float = reach
	for rg: Dictionary in game.galaxy_region_grid():
		var sp := _project(rg["center"] as Vector3, b, center, s)
		var dpx: float = (sp - pos).length()
		if dpx < best_d:
			best_d = dpx
			best = str(rg["id"])
	return best
