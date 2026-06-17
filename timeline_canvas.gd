class_name TimelineCanvas
extends Control

# ── Scale constants ────────────────────────────────────────────────────────────
## Linear zone: 1940 … LOG_CUTOFF_YEAR at PX_PER_YEAR pixels/year.
const START_YEAR      := 1940
const LOG_CUTOFF_YEAR := 2_500      # switch to log scale after this year
const PX_PER_YEAR     := 8.0
## Logarithmic zone: 200 px per decade (10× jump) beyond LOG_CUTOFF_YEAR.
const LOG_SCALE_PX    := 200.0

# ── Layout constants ───────────────────────────────────────────────────────────
const MARGIN_L     := 40.0
const TIMELINE_Y   := 240
const CARD_W       := 160
const CARD_H       := 200
const CARD_Y_ABOVE := 16
const CARD_Y_BELOW := 266
const CANVAS_H     := 480
const CARD_GAP     := 10

## Current in-game year; drives the green "now" marker.
var _current_year: int = 1945

## Game events added at runtime (each dict must contain a "year" key).
var _live_events: Array = []

## Pre-computed card positions so _draw() and _build_cards() stay in sync.
## Each element: { card_x, card_y, year_x, above }
var _layout: Array = []

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	custom_minimum_size.y = CANVAS_H
	_compute_layout()
	_build_cards()

# ── Scale helpers ─────────────────────────────────────────────────────────────

## Maps a calendar year to a canvas x-position using a hybrid linear/log scale.
## Years ≤ LOG_CUTOFF_YEAR use 8 px/year; years beyond use 200 px per decade.
## This keeps near-future events readable while fitting billions of years on screen.
func _year_to_x(y: int) -> float:
	if y <= LOG_CUTOFF_YEAR:
		return MARGIN_L + float(y - START_YEAR) * PX_PER_YEAR
	else:
		var base_x := MARGIN_L + float(LOG_CUTOFF_YEAR - START_YEAR) * PX_PER_YEAR
		var decades := log(float(y) / float(LOG_CUTOFF_YEAR)) / log(10.0)
		return base_x + decades * LOG_SCALE_PX

## Short human-readable year label used in card headers and ruler ticks.
func _fmt_year(y: int) -> String:
	if y >= 1_000_000_000:
		return "%.2fB" % (float(y) / 1_000_000_000.0)
	if y >= 1_000_000:
		return "%.1fM" % (float(y) / 1_000_000.0)
	if y >= 10_000:
		return "%.1fK" % (float(y) / 1_000.0)
	return str(y)

## Returns the category color from whichever palette defines it.
func _cat_color(ev: Dictionary) -> Color:
	var cat: String = ev.get("category", "civilization")
	if GameEvents.CATEGORY_COLORS.has(cat):
		return GameEvents.CATEGORY_COLORS[cat]
	if TimelineEvents.CATEGORY_COLORS.has(cat):
		return TimelineEvents.CATEGORY_COLORS[cat]
	return Color.WHITE

# ── Event list ────────────────────────────────────────────────────────────────

## Returns all events (static history + live game events) sorted by year.
func _all_events() -> Array:
	var combined: Array = []
	combined.append_array(TimelineEvents.EVENTS)
	combined.append_array(_live_events)
	combined.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["year"]) < int(b["year"]))
	return combined

# ── Layout computation ────────────────────────────────────────────────────────

func _compute_layout() -> void:
	_layout.clear()
	var above_next: float = 0.0
	var below_next: float = 0.0

	var all_ev := _all_events()
	# Canvas right edge: whichever is larger — the default end year or the last event.
	var max_year := LOG_CUTOFF_YEAR
	for ev in all_ev:
		max_year = max(max_year, int(ev["year"]))
	var max_x: float = _year_to_x(max_year) + MARGIN_L

	for i in range(all_ev.size()):
		var ev: Dictionary = all_ev[i]
		var year_x := _year_to_x(int(ev["year"]))
		var above: bool = (i % 2 == 0)
		var card_x: float

		if above:
			card_x = max(year_x - CARD_W * 0.5, above_next)
			above_next = card_x + CARD_W + CARD_GAP
		else:
			card_x = max(year_x - CARD_W * 0.5, below_next)
			below_next = card_x + CARD_W + CARD_GAP

		_layout.append({
			"card_x": card_x,
			"card_y": float(CARD_Y_ABOVE) if above else float(CARD_Y_BELOW),
			"year_x": year_x,
			"above":  above,
		})
		max_x = max(max_x, card_x + CARD_W + MARGIN_L)

	custom_minimum_size.x = max_x

# ── Card construction ─────────────────────────────────────────────────────────

func _build_cards() -> void:
	for child in get_children():
		child.queue_free()

	var all_ev := _all_events()
	for i in range(all_ev.size()):
		var ev: Dictionary  = all_ev[i]
		var pos: Dictionary = _layout[i]
		_make_card(ev, pos["card_x"], pos["card_y"])

func _make_card(ev: Dictionary, cx: float, cy: float) -> void:
	var cat_color: Color = _cat_color(ev)

	# Outer panel ──────────────────────────────────────────────────────────────
	var panel := PanelContainer.new()
	panel.position = Vector2(cx, cy)
	panel.custom_minimum_size = Vector2(CARD_W, CARD_H)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.17)
	style.border_color = cat_color
	style.set_border_width_all(2)
	style.corner_radius_top_left     = 4
	style.corner_radius_top_right    = 4
	style.corner_radius_bottom_left  = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)

	# Coloured header strip ────────────────────────────────────────────────────
	var header_pc := PanelContainer.new()
	var hstyle := StyleBoxFlat.new()
	hstyle.bg_color = cat_color.darkened(0.30)
	hstyle.corner_radius_top_left    = 4
	hstyle.corner_radius_top_right   = 4
	header_pc.add_theme_stylebox_override("panel", hstyle)

	var year_lbl := Label.new()
	year_lbl.text = _fmt_year(int(ev["year"]))
	year_lbl.add_theme_color_override("font_color", Color.WHITE)
	year_lbl.add_theme_font_size_override("font_size", 11)
	header_pc.add_child(year_lbl)
	vbox.add_child(header_pc)

	# Inner margin ─────────────────────────────────────────────────────────────
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   6)
	margin.add_theme_constant_override("margin_right",  6)
	margin.add_theme_constant_override("margin_top",    4)
	margin.add_theme_constant_override("margin_bottom", 4)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(margin)

	var inner := VBoxContainer.new()
	margin.add_child(inner)

	# Title ────────────────────────────────────────────────────────────────────
	var title_lbl := Label.new()
	title_lbl.text = ev["title"]
	title_lbl.add_theme_font_size_override("font_size", 13)
	title_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(title_lbl)

	# Description ──────────────────────────────────────────────────────────────
	var desc_lbl := Label.new()
	desc_lbl.text = ev["desc"]
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", Color(0.70, 0.70, 0.78))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(desc_lbl)

	add_child(panel)

# ── Custom drawing (ruler + connectors + now-marker) ─────────────────────────

func _draw() -> void:
	if _layout.is_empty():
		return

	var w: float = custom_minimum_size.x
	var font      := ThemeDB.fallback_font
	var font_size := 11

	# Timeline bar ─────────────────────────────────────────────────────────────
	draw_line(
		Vector2(MARGIN_L, TIMELINE_Y),
		Vector2(w - MARGIN_L, TIMELINE_Y),
		Color(0.50, 0.50, 0.62, 0.9),
		2.0
	)

	# ── Linear tick marks (START_YEAR … LOG_CUTOFF_YEAR, every 50 / major 100) ─
	var y_start := int(ceil(float(START_YEAR) / 50.0)) * 50
	var y_tick  := y_start
	while y_tick <= LOG_CUTOFF_YEAR:
		var tx: float = _year_to_x(y_tick)
		var major: bool = (y_tick % 100 == 0)
		var th: float = 14.0 if major else 6.0
		draw_line(
			Vector2(tx, TIMELINE_Y - th),
			Vector2(tx, TIMELINE_Y + th),
			Color(0.55, 0.55, 0.65, 0.85),
			1.5 if major else 1.0
		)
		if major:
			draw_string(font, Vector2(tx - 18, TIMELINE_Y + 26),
				str(y_tick), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
				Color(0.60, 0.60, 0.72))
		y_tick += 50

	# ── Log-scale zone: separator + landmark decade ticks ─────────────────────
	var has_log_events := false
	for ev in _live_events:
		if int(ev["year"]) > LOG_CUTOFF_YEAR:
			has_log_events = true
			break

	if has_log_events:
		# Vertical separator at the scale-change boundary
		var sep_x := _year_to_x(LOG_CUTOFF_YEAR)
		draw_line(Vector2(sep_x, 0), Vector2(sep_x, CANVAS_H),
			Color(0.40, 0.40, 0.55, 0.50), 1.0)
		draw_string(font, Vector2(sep_x + 4, TIMELINE_Y + 42),
			"log scale →", HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
			Color(0.42, 0.42, 0.52))

		# Decade tick marks up to the furthest event year
		var far_year := LOG_CUTOFF_YEAR
		for ev in _live_events:
			far_year = max(far_year, int(ev["year"]))
		var decade_ticks: Array[int] = [
			10_000, 100_000, 1_000_000, 10_000_000,
			100_000_000, 1_000_000_000, 10_000_000_000,
		]
		for lt: int in decade_ticks:
			if lt > far_year:
				break
			var tx: float = _year_to_x(lt)
			draw_line(Vector2(tx, TIMELINE_Y - 14), Vector2(tx, TIMELINE_Y + 14),
				Color(0.55, 0.55, 0.65, 0.85), 1.5)
			draw_string(font, Vector2(tx - 18, TIMELINE_Y + 26),
				_fmt_year(lt), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
				Color(0.60, 0.60, 0.72))

	# ── Connector lines + category dots ───────────────────────────────────────
	var all_ev := _all_events()
	for i in range(_layout.size()):
		var pos: Dictionary = _layout[i]
		var ev: Dictionary  = all_ev[i]
		var cat_color: Color = _cat_color(ev)

		# Dot at the true year position on the bar
		var dot_x: float = float(pos["year_x"])
		draw_circle(Vector2(dot_x, TIMELINE_Y), 5.0, cat_color)

		# Connector from card edge to bar dot
		var card_cx: float = float(pos["card_x"]) + CARD_W * 0.5
		var conn_y: float
		if bool(pos["above"]):
			conn_y = CARD_Y_ABOVE + CARD_H
		else:
			conn_y = CARD_Y_BELOW
		draw_line(
			Vector2(card_cx, conn_y),
			Vector2(dot_x, float(TIMELINE_Y)),
			Color(cat_color.r, cat_color.g, cat_color.b, 0.45),
			1.5
		)

	# ── Current-year green marker ──────────────────────────────────────────────
	var cur_x: float = _year_to_x(_current_year)
	draw_line(Vector2(cur_x, 0), Vector2(cur_x, CANVAS_H),
		Color(0.20, 0.90, 0.35, 0.65), 2.0)
	draw_string(font, Vector2(cur_x + 4, 14), _fmt_year(_current_year),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.20, 0.90, 0.35))

# ── Public API ────────────────────────────────────────────────────────────────

## Add a live game event to the timeline.  The dict must contain at least
## "year", "title", "desc", and "category".  Duplicate IDs are ignored.
func add_event(ev: Dictionary) -> void:
	var ev_id: String = ev.get("id", "")
	if ev_id != "":
		for existing: Dictionary in _live_events:
			if existing.get("id", "") == ev_id:
				return   # already on the timeline
	_live_events.append(ev)
	_compute_layout()
	_build_cards()
	queue_redraw()

func set_current_year(y: int) -> void:
	_current_year = y
	queue_redraw()
