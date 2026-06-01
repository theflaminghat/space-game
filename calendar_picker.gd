class_name CalendarPicker
extends VBoxContainer

## Emitted when the player clicks a valid day cell.
signal date_selected(year: int, month: int, day: int)

const MONTH_NAMES: Array[String] = [
	"January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December"
]
const DOW_HEADERS: Array[String] = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

# ── View state ────────────────────────────────────────────────────────────────
var _view_year:  int = 2026
var _view_month: int = 1   # 1-indexed

# ── Selected date ─────────────────────────────────────────────────────────────
var _sel_year:  int = 2026
var _sel_month: int = 1
var _sel_day:   int = 1

# ── Minimum selectable date (game's current date) ─────────────────────────────
var _min_year:  int = 2026
var _min_month: int = 1
var _min_day:   int = 1

# ── UI refs ───────────────────────────────────────────────────────────────────
var _header_label: Label
var _day_btns:     Array = []   # 42 Button nodes (6 weeks × 7 days)

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	custom_minimum_size = Vector2(252, 0)
	add_theme_constant_override("separation", 3)
	_build_ui()
	_refresh_grid()


func _build_ui() -> void:
	# ── Month navigation header ───────────────────────────────────────────────
	var header := HBoxContainer.new()

	var prev_btn := Button.new()
	prev_btn.text        = "<"
	prev_btn.flat        = true
	prev_btn.custom_minimum_size = Vector2(26, 26)
	prev_btn.pressed.connect(_on_prev_month)
	header.add_child(prev_btn)

	_header_label = Label.new()
	_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_label.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	_header_label.add_theme_font_size_override("font_size", 13)
	header.add_child(_header_label)

	var next_btn := Button.new()
	next_btn.text        = ">"
	next_btn.flat        = true
	next_btn.custom_minimum_size = Vector2(26, 26)
	next_btn.pressed.connect(_on_next_month)
	header.add_child(next_btn)

	add_child(header)

	# ── Day grid ──────────────────────────────────────────────────────────────
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)

	# Day-of-week labels
	for h: String in DOW_HEADERS:
		var lbl := Label.new()
		lbl.text                     = h
		lbl.horizontal_alignment     = HORIZONTAL_ALIGNMENT_CENTER
		lbl.custom_minimum_size      = Vector2(32, 18)
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.modulate                 = Color(0.65, 0.65, 0.65)
		grid.add_child(lbl)

	# 6 weeks × 7 days = 42 buttons
	for i: int in range(42):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(32, 28)
		btn.add_theme_font_size_override("font_size", 12)
		btn.flat = true
		btn.pressed.connect(_on_day_pressed.bind(i))
		grid.add_child(btn)
		_day_btns.append(btn)

	add_child(grid)


func _refresh_grid() -> void:
	_header_label.text = "%s  %d" % [MONTH_NAMES[_view_month - 1], _view_year]

	# Monday-first column offset for the 1st of the month
	var dow:    int = _day_of_week(_view_year, _view_month, 1)
	var offset: int = (dow + 6) % 7   # 0=Mon … 6=Sun → col 0…6
	var days_total: int = _days_in_month(_view_year, _view_month)

	for i: int in range(42):
		var btn: Button = _day_btns[i] as Button
		var day: int    = i - offset + 1

		if day < 1 or day > days_total:
			btn.text     = ""
			btn.disabled = true
			btn.modulate = Color(1, 1, 1, 0)
			continue

		var before_min: bool = _date_before(
			_view_year, _view_month, day,
			_min_year,  _min_month,  _min_day
		)
		var is_sel: bool = (
			_view_year  == _sel_year  and
			_view_month == _sel_month and
			day         == _sel_day
		)

		btn.text     = str(day)
		btn.disabled = before_min
		btn.modulate = (
			Color(0.35, 0.70, 1.00)  if is_sel      else
			Color(0.40, 0.40, 0.40)  if before_min  else
			Color(1.00, 1.00, 1.00)
		)

# ── Input handlers ────────────────────────────────────────────────────────────

func _on_day_pressed(idx: int) -> void:
	var dow:    int = _day_of_week(_view_year, _view_month, 1)
	var offset: int = (dow + 6) % 7
	var day:    int = idx - offset + 1

	if day < 1 or day > _days_in_month(_view_year, _view_month):
		return
	if _date_before(_view_year, _view_month, day, _min_year, _min_month, _min_day):
		return

	_sel_year  = _view_year
	_sel_month = _view_month
	_sel_day   = day
	_refresh_grid()
	date_selected.emit(_sel_year, _sel_month, _sel_day)


func _on_prev_month() -> void:
	_view_month -= 1
	if _view_month < 1:
		_view_month = 12
		_view_year  -= 1
	# Don't navigate before the minimum month
	if _date_before(_view_year, _view_month, 1, _min_year, _min_month, 1):
		_view_year  = _min_year
		_view_month = _min_month
	_refresh_grid()


func _on_next_month() -> void:
	_view_month += 1
	if _view_month > 12:
		_view_month = 1
		_view_year  += 1
	_refresh_grid()

# ── Public API ────────────────────────────────────────────────────────────────

## Call this whenever the game date advances so the calendar enforces the new
## minimum and snaps the selected date forward if it fell behind.
func set_min_date(y: int, m: int, d: int) -> void:
	_min_year  = y
	_min_month = m
	_min_day   = d

	# Snap view to min month if currently before it
	if _date_before(_view_year, _view_month, 1, _min_year, _min_month, 1):
		_view_year  = _min_year
		_view_month = _min_month

	# Snap selection to min date if it fell behind
	if _date_before(_sel_year, _sel_month, _sel_day, _min_year, _min_month, _min_day):
		_sel_year  = _min_year
		_sel_month = _min_month
		_sel_day   = _min_day
		date_selected.emit(_sel_year, _sel_month, _sel_day)

	_refresh_grid()


func get_selected_year()  -> int: return _sel_year
func get_selected_month() -> int: return _sel_month   # 1-indexed
func get_selected_day()   -> int: return _sel_day


## Returns the number of days from (from_y, from_m, from_d) to the selected
## date.  Always >= 0 (clamped, since selection can't be before min date).
func get_offset_days(from_year: int, from_month: int, from_day: int) -> int:
	var diff: int = _to_jdn(_sel_year, _sel_month, _sel_day) \
	              - _to_jdn(from_year,  from_month,  from_day)
	return maxi(diff, 0)


## Formatted as "YYYY-MM-DD".
func get_selected_label() -> String:
	return "%04d-%02d-%02d" % [_sel_year, _sel_month, _sel_day]

# ── Date math helpers ─────────────────────────────────────────────────────────

func _days_in_month(y: int, m: int) -> int:
	var days: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if m == 2 and ((y % 4 == 0 and y % 100 != 0) or y % 400 == 0):
		return 29
	return days[m - 1]


## Tomohiko Sakamoto algorithm — returns 0=Sunday, 1=Monday … 6=Saturday.
func _day_of_week(y: int, m: int, d: int) -> int:
	var t: Array[int] = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
	var yy: int = y
	if m < 3:
		yy -= 1
	return (yy + yy / 4 - yy / 100 + yy / 400 + t[m - 1] + d) % 7


func _date_before(ay: int, am: int, ad: int, by: int, bm: int, bd: int) -> bool:
	if ay != by: return ay < by
	if am != bm: return am < bm
	return ad < bd


## Julian Day Number — used only for offset arithmetic.
func _to_jdn(y: int, m: int, d: int) -> int:
	var a:  int = (14 - m) / 12
	var yy: int = y + 4800 - a
	var mm: int = m + 12 * a - 3
	return d + (153 * mm + 2) / 5 + 365 * yy + yy / 4 - yy / 100 + yy / 400 - 32045
