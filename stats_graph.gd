## StatsGraph — a custom-drawn line-graph Control.
## Attach to a bare Control node or instantiate in code.
class_name StatsGraph
extends Control

# ── Layout constants ──────────────────────────────────────────────────────────
const PAD_L: float = 48.0   # left  — Y-axis tick labels
const PAD_R: float = 90.0   # right — endpoint value annotations
const PAD_T: float = 16.0   # top
const PAD_B: float = 36.0   # bottom — X-axis year labels

const LINE_W:    float = 2.0
const DOT_R:     float = 4.0
const HOVER_DOT: float = 5.0

const COL_BG:   Color = Color(0.07, 0.08, 0.10)
const COL_GRID: Color = Color(1.0,  1.0,  1.0,  0.06)
const COL_AXIS: Color = Color(0.40, 0.42, 0.50, 0.80)
const COL_CURS: Color = Color(1.0,  1.0,  1.0,  0.25)
const COL_LABL: Color = Color(0.45, 0.47, 0.58)
const COL_EMPTY:Color = Color(0.35, 0.37, 0.45)

## Cap on stored points.  When exceeded, history is halved (every other point kept),
## which bounds memory and per-frame draw cost over very long sessions while keeping
## the full time span visible — deep-time history just gets coarser, not truncated.
const MAX_POINTS: int = 4000

## Parallel arrays — one entry per recorded year.
var history_years: Array[int]   = []
## key → Array[float]   (same length as history_years)
var history_data: Dictionary    = {}

## Ordered list of {key, label, color, type} — drives legend and draw order.
var series_meta: Array          = []
## key → bool
var active: Dictionary          = {}

## Cached per-series min/max so _draw_series and _draw_hover_cursor never do
## O(n) scans during drawing.  Rebuilt whenever a snapshot is pushed or history cleared.
var _cached_vmin: Dictionary = {}   # key → float
var _cached_vmax: Dictionary = {}   # key → float

# ── Hover state ────────────────────────────────────────────────────────────────
var _hover_x: float = -1.0   # screen-space x of mouse; -1 = not hovering

# ── Cached per-draw ───────────────────────────────────────────────────────────
var _px0: float = 0.0
var _px1: float = 0.0
var _py0: float = 0.0
var _py1: float = 0.0

# ── Public API ────────────────────────────────────────────────────────────────

func push_snapshot(year: int, data_dict: Dictionary) -> void:
	history_years.append(year)
	for m: Dictionary in series_meta:
		var key: String = m["key"]
		if not history_data.has(key):
			history_data[key] = []
		var val: float = float(data_dict.get(key, 0.0))
		(history_data[key] as Array).append(val)
		# Update cached min/max incrementally — no full scan needed.
		if not _cached_vmin.has(key):
			_cached_vmin[key] = val
			_cached_vmax[key] = val
		else:
			_cached_vmin[key] = minf(_cached_vmin[key], val)
			_cached_vmax[key] = maxf(_cached_vmax[key], val)
	if history_years.size() > MAX_POINTS:
		_downsample()
	queue_redraw()

## Halve the stored resolution, keeping every other point.  Amortised O(1) per push
## (runs only once every ~MAX_POINTS/2 snapshots).  Cached min/max are left intact —
## they remain valid outer bounds for axis scaling.
func _downsample() -> void:
	var thinned_years: Array[int] = []
	for i in range(0, history_years.size(), 2):
		thinned_years.append(history_years[i])
	history_years = thinned_years
	for key: String in history_data:
		var arr: Array = history_data[key]
		var thinned: Array = []
		for i in range(0, arr.size(), 2):
			thinned.append(arr[i])
		history_data[key] = thinned

func clear_history() -> void:
	history_years.clear()
	for key: String in history_data:
		history_data[key] = []
	_cached_vmin.clear()
	_cached_vmax.clear()
	queue_redraw()

# ── Input ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover_x = (event as InputEventMouseMotion).position.x
		queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover_x = -1.0
		queue_redraw()

# ── Drawing ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	var w := size.x
	var h := size.y
	_px0 = PAD_L
	_px1 = w - PAD_R
	_py0 = PAD_T
	_py1 = h - PAD_B

	# Background
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)

	if history_years.size() < 2:
		var font := ThemeDB.fallback_font
		var msg  := "Waiting for data — returns each year."
		draw_string(font, Vector2(_px0 + 16, (_py0 + _py1) * 0.5 + 6),
			msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COL_EMPTY)
		_draw_axes()
		return

	_draw_grid()
	_draw_axes()
	_draw_series()
	if _hover_x >= _px0 and _hover_x <= _px1:
		_draw_hover_cursor()

func _draw_grid() -> void:
	var font := ThemeDB.fallback_font
	var pw   := _px1 - _px0
	var ph   := _py1 - _py0

	# Horizontal grid (0 / 25 / 50 / 75 / 100 %)
	for i in range(5):
		var t:  float = float(i) / 4.0
		var gy: float = _py1 - t * ph
		draw_line(Vector2(_px0, gy), Vector2(_px1, gy), COL_GRID, 1.0)
		var pct: String = "%d%%" % int(t * 100)
		draw_string(font, Vector2(2, gy + 5), pct,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_LABL)

	# Vertical grid (year ticks)
	var n := history_years.size()
	var year_min: int = history_years[0]
	var year_max: int = history_years[n - 1]
	var span: float   = maxf(float(year_max - year_min), 1.0)

	var step: int = _tick_step(year_max - year_min)
	var t_year: int = int(ceil(year_min / float(step))) * step
	while t_year <= year_max:
		var tx: float = _px0 + (t_year - year_min) / span * pw
		draw_line(Vector2(tx, _py0), Vector2(tx, _py1), COL_GRID, 1.0)
		draw_string(font, Vector2(tx - 14, _py1 + 18), _fmt_year(t_year),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_LABL)
		t_year += step

func _draw_axes() -> void:
	draw_line(Vector2(_px0, _py0), Vector2(_px0, _py1), COL_AXIS, 1.5)
	draw_line(Vector2(_px0, _py1), Vector2(_px1, _py1), COL_AXIS, 1.5)

func _draw_series() -> void:
	var n: int       = history_years.size()
	var year_min: int = history_years[0]
	var year_max: int = history_years[n - 1]
	var span: float   = maxf(float(year_max - year_min), 1.0)
	var pw: float     = _px1 - _px0
	var ph: float     = _py1 - _py0
	var font := ThemeDB.fallback_font

	# Stack endpoint labels vertically so they don't collide
	var endpoint_slots: Array = []   # y positions already used

	for m: Dictionary in series_meta:
		var key: String    = m["key"]
		if not active.get(key, true):
			continue
		var data: Array = history_data.get(key, [])
		if data.size() < 2:
			continue

		var col: Color   = m["color"]
		var type: String = m.get("type", "float")

		# Per-series min/max normalization — from cache, never a per-draw O(n) scan.
		var vmin: float = _cached_vmin.get(key, 0.0)
		var vmax: float = _cached_vmax.get(key, 0.0)
		if vmax <= vmin:
			vmax = vmin + 1.0   # constant series → draw at baseline

		# Build polyline
		var pts := PackedVector2Array()
		for i in range(min(n, data.size())):
			var yr: int   = history_years[i]
			var val: float = float(data[i])
			var tx: float  = _px0 + (yr - year_min) / span * pw
			var ny: float  = (val - vmin) / (vmax - vmin)
			var ty: float  = _py1 - ny * ph
			pts.append(Vector2(tx, ty))

		draw_polyline(pts, col, LINE_W, true)

		# Endpoint dot
		var ep: Vector2 = pts[pts.size() - 1]
		draw_circle(ep, DOT_R, col)

		# Endpoint value label (right margin) — nudge down if slot taken
		var lbl_y: float = ep.y
		for used_y: float in endpoint_slots:
			if absf(lbl_y - used_y) < 14:
				lbl_y = used_y + 14
		endpoint_slots.append(lbl_y)

		var last_val: float = float(data[data.size() - 1])
		var val_str: String = _fmt(last_val, type)
		draw_string(font, Vector2(_px1 + 4, lbl_y + 5),
			val_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)

func _draw_hover_cursor() -> void:
	var n: int        = history_years.size()
	var year_min: int = history_years[0]
	var year_max: int = history_years[n - 1]
	var span: float   = maxf(float(year_max - year_min), 1.0)
	var pw: float     = _px1 - _px0
	var ph: float     = _py1 - _py0
	var font := ThemeDB.fallback_font

	# Vertical cursor
	draw_line(Vector2(_hover_x, _py0), Vector2(_hover_x, _py1), COL_CURS, 1.0)

	# Nearest year index
	var t_frac: float = (_hover_x - _px0) / pw
	var hover_year: int = int(year_min + t_frac * span)
	var best_i: int = 0
	for i in range(n):
		if absi(history_years[i] - hover_year) < absi(history_years[best_i] - hover_year):
			best_i = i
	var snapped_x: float = _px0 + (history_years[best_i] - year_min) / span * pw

	# Year label
	draw_string(font, Vector2(snapped_x - 14, _py1 + 18),
		_fmt_year(history_years[best_i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)

	# Dots + values at this index for each active series
	for m: Dictionary in series_meta:
		var key: String = m["key"]
		if not active.get(key, true):
			continue
		var data: Array = history_data.get(key, [])
		if best_i >= data.size():
			continue

		var vmin: float = _cached_vmin.get(key, 0.0)
		var vmax: float = _cached_vmax.get(key, 0.0)
		if vmax <= vmin: vmax = vmin + 1.0

		var val: float  = float(data[best_i])
		var ny:  float  = (val - vmin) / (vmax - vmin)
		var ty:  float  = _py1 - ny * ph
		var col: Color  = m["color"]

		draw_circle(Vector2(snapped_x, ty), HOVER_DOT, col)
		draw_string(font, Vector2(snapped_x + 8, ty + 5),
			_fmt(val, str(m.get("type", "float"))),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)

# ── Helpers ───────────────────────────────────────────────────────────────────

## Returns a tick interval that keeps the number of X-axis ticks to ≤ 8.
## Works across the full range from a few years to 10 billion years.
func _tick_step(span: int) -> int:
	# Target ≤ 8 ticks by finding the smallest "round" step >= span/8.
	var raw: float = float(span) / 8.0
	# Round up to 1, 2, or 5 × a power of 10.
	var mag: float = pow(10.0, floor(log(raw) / log(10.0)))
	for mult in [1, 2, 5, 10]:
		var candidate: int = int(mag * mult)
		if candidate >= int(raw):
			return maxi(candidate, 1)
	return maxi(int(mag * 10), 1)

## Compact year label for X-axis — keeps ticks readable at any timescale.
func _fmt_year(y: int) -> String:
	var v := float(y)
	if absf(v) >= 1.0e9: return "%.2fB" % (v / 1.0e9)
	if absf(v) >= 1.0e6: return "%.1fM" % (v / 1.0e6)
	if absf(v) >= 1.0e3: return "%.1fK" % (v / 1.0e3)
	return str(y)

func _fmt(val: float, type: String) -> String:
	match type:
		"percent":
			var p := val if val > 1.0 else val * 100.0
			return "%.1f%%" % p
		"int":
			var v := int(val)
			if absf(val) >= 1e12: return "%.1fT" % (val / 1e12)
			if absf(val) >= 1e9:  return "%.1fB" % (val / 1e9)
			if absf(val) >= 1e6:  return "%.1fM" % (val / 1e6)
			if absf(val) >= 1e3:  return "%.1fK" % (val / 1e3)
			return str(v)
		_:
			return Units.format_si_verbose(val, "")
