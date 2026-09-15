class_name TimelineCanvas
extends Control

## The event cards of the historical timeline.  The axis itself is drawn by TimelineRuler, pinned
## above this canvas's scroll area so it stays in view however far down the cards go; the two share
## the scale and tick functions below, so they cannot disagree.
##
## The axis is the WHOLE of time the run can reach: from the run's first year to the heat death of
## the universe, always, fitted to the panel's width so all of it is on screen at once.  The scale
## is logarithmic in elapsed time — x grows with log10(1 + years since START_YEAR) — so every order
## of magnitude, from the first decade to the hundredth power of ten, gets the same width, and the
## start of the run sits at the left edge rather than being skipped.
##
## Every card hangs directly under its own date and is only as tall as its text.  When cards in one
## stretch of time would overlap, the later ones drop into the first gap beneath that fits them, so
## a busy moment makes the timeline taller instead of pushing cards away from their dates.

## Emitted whenever the card layout or the scale changes, so the ruler can redraw.
signal layout_changed

# ── Scale ──────────────────────────────────────────────────────────────────────
## The run's first year (the game starts on 1 January 1945): the left edge of the axis.
const START_YEAR: int = 1945
## The right edge: heat death, ~10^100 years out, when the last black holes have evaporated and
## nothing is left to do work.  The figure the run-end screen quotes (see VOICE.md).
const HEAT_DEATH_YEAR: float = 1.0e100
const MARGIN_L: float = 40.0
const MARGIN_R: float = 56.0
## Labels are placed every N orders of magnitude, N the smallest of these that keeps labels at
## least LABEL_MIN_PX apart — so they are always evenly spaced, whatever the panel width.
const LABEL_STEPS: Array = [1, 2, 5, 10, 20, 25, 50]
const LABEL_MIN_PX: float = 56.0

# ── Card layout ────────────────────────────────────────────────────────────────
const CARD_W: float = 170.0
const CARD_GAP: float = 10.0      # horizontal space required between neighbouring cards
const ROW_GAP: float = 8.0        # vertical space between a card and the one stacked under it
const TOP_PAD: float = 18.0       # room under the ruler for the connector stubs
const BOTTOM_PAD: float = 16.0
## Lines shown on a card; the full text is in its tooltip.
const TITLE_LINES: int = 2
const DESC_LINES: int = 7
const YEAR_FONT: int = 11
const TITLE_FONT: int = 13
const DESC_FONT: int = 11
const PAD_X: float = 6.0          # text inset inside the card
const PAD_Y: float = 4.0
const BORDER: float = 2.0

const MAX_LIVE_EVENTS := 200
## Card rebuilds are deferred: only while the panel is visible, and at most a few times a second,
## so adding events (even one per frame at fast-forward) never rebuilds the node tree per event.
const REBUILD_SEC := 0.25

## Current in-game year; drives the green "now" marker.
var _current_year: int = START_YEAR
## Game events added at runtime.  Bounded so a deep-time flood of alerts can't grow the rebuild
## cost without limit — the oldest live events fall off; the fixed history events never do.
var _live_events: Array = []
var _live_ids: Dictionary = {}     # id → true, for O(1) duplicate rejection
var _layout_dirty: bool = false
var _rebuild_accum: float = 0.0
## One entry per event, in _all_events() order: { card_x, card_y, card_h, year_x, linked }.
## `linked` is whether the straight drop from the axis to the card's top is clear of other cards.
var _layout: Array = []
var _content_h: float = 0.0        # bottom of the lowest card
var _events: Array = []            # _all_events() as of the last layout
## Width the whole axis is fitted into (the scroll area's visible width), and the scale it gives.
var _fit_width: float = 1600.0
var _px_per_decade: float = 15.0


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rescale()
	_relayout()


# ── Scale (shared with TimelineRuler) ─────────────────────────────────────────

## Orders of magnitude the axis covers, start to heat death (≈100).
static func span_decades() -> float:
	return log(1.0 + HEAT_DEATH_YEAR - float(START_YEAR)) / log(10.0)


func _rescale() -> void:
	_px_per_decade = maxf(1.0, (_fit_width - MARGIN_L - MARGIN_R) / span_decades())


## Fit the whole axis into `width` px (the visible width of the scroll area).  Called when the
## panel is laid out or resized; a new width re-places every card.
func fit_width(width: float) -> void:
	if width <= 0.0 or absf(width - _fit_width) < 1.0:
		return
	_fit_width = width
	_rescale()
	_relayout()


## Canvas x of a calendar year.
func year_to_x(y: float) -> float:
	var dt: float = maxf(0.0, y - float(START_YEAR))
	return MARGIN_L + log(1.0 + dt) / log(10.0) * _px_per_decade


func axis_end_year() -> float:
	return HEAT_DEATH_YEAR


func axis_end_x() -> float:
	return year_to_x(HEAT_DEATH_YEAR)


func px_per_decade() -> float:
	return _px_per_decade


## Short calendar-year label for card headers and the present marker: the year up to 9999, then
## K / M / B / T / Qa / Qi, then a power of ten.
static func fmt_year(y: float) -> String:
	if y < 10000.0:
		return str(int(y))
	if y >= 1.0e21:
		return pow10_text(int(floor(log(y) / log(10.0))))
	for unit: Array in [[1.0e18, "Qi"], [1.0e15, "Qa"], [1.0e12, "T"], [1.0e9, "B"], [1.0e6, "M"], [1.0e3, "K"]]:
		if y >= float(unit[0]):
			var n: float = y / float(unit[0])
			var txt: String = ("%.2f" % n).rstrip("0").rstrip(".") if n < 100.0 else str(int(round(n)))
			return txt + str(unit[1])
	return str(int(y))


const SUPERSCRIPT: Array = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"]

## "10⁴⁵" for 45.
static func pow10_text(k: int) -> String:
	var sup: String = ""
	for ch in str(k):
		sup += str(SUPERSCRIPT[int(ch)])
	return "10" + sup


## Tick marks along the whole axis: [{year, x, label, text}], in x order.  One tick at every power
## of ten of elapsed years — evenly spaced, since the scale is logarithmic — with a label every N of
## them (N from LABEL_STEPS, the smallest that keeps labels apart).  Labels read in years elapsed
## since the start; the axis begins at the run's first year and ends at heat death.
func ticks() -> Array:
	var out: Array = [{"year": float(START_YEAR), "x": year_to_x(START_YEAR), "label": true,
		"text": str(START_YEAR)}]
	var every: int = int(LABEL_STEPS[LABEL_STEPS.size() - 1])
	for s in LABEL_STEPS:
		if float(s) * _px_per_decade >= LABEL_MIN_PX:
			every = int(s)
			break
	# Tick k sits where log10(1 + elapsed) = k, i.e. 10^k - 1 years in, so the spacing is exact all
	# the way from the start (k = 0 is the start itself, already ticked above).
	var last_k: int = int(round(span_decades()))
	for k in range(1, last_k + 1):
		var y: float = float(START_YEAR) + pow(10.0, k) - 1.0
		var end: bool = k == last_k
		var lab: bool = end or (k > 0 and k % every == 0 and last_k - k >= every / 2.0)
		out.append({"year": y, "x": year_to_x(y), "label": lab,
			"text": "heat death" if end else "%s yr" % pow10_text(k)})
	return out


func current_year() -> int:
	return _current_year


func layout() -> Array:
	return _layout


func events() -> Array:
	return _events


## Colour of an event's category, from whichever palette defines it.
static func cat_color(ev: Dictionary) -> Color:
	var cat: String = ev.get("category", "civilization")
	if GameEvents.CATEGORY_COLORS.has(cat):
		return GameEvents.CATEGORY_COLORS[cat]
	if TimelineEvents.CATEGORY_COLORS.has(cat):
		return TimelineEvents.CATEGORY_COLORS[cat]
	return Color.WHITE


# ── Layout ────────────────────────────────────────────────────────────────────

## Every event, fixed history and live, oldest first.
func _all_events() -> Array:
	var combined: Array = []
	combined.append_array(TimelineEvents.EVENTS)
	combined.append_array(_live_events)
	combined.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["year"]) < float(b["year"]))
	return combined


## Hang each card under its date, in the highest gap below the axis that it fits without touching
## another card.
func _compute_layout() -> void:
	_events = _all_events()
	_layout.clear()
	var m: Dictionary = _text_metrics()
	var placed: Array = []             # Rect2 of every card placed so far
	_content_h = 0.0
	for ev: Dictionary in _events:
		var yx: float = year_to_x(float(ev["year"]))
		# Centred under its date, but kept inside the fitted width: the axis fills the panel, so
		# a card for the far future would otherwise hang off its right edge.
		var cx: float = clampf(yx - CARD_W * 0.5, 4.0, maxf(4.0, _fit_width - CARD_W - 4.0))
		var h: float = card_height(ev, m)
		# The cards already hanging under this stretch of the axis, top first; walk down past each
		# one this card would touch until a gap tall enough turns up.
		var under: Array = []
		for r: Rect2 in placed:
			if r.position.x < cx + CARD_W + CARD_GAP and cx < r.end.x + CARD_GAP:
				under.append(r)
		under.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.y < b.position.y)
		var y: float = TOP_PAD
		for r: Rect2 in under:
			if r.position.y >= y + h + ROW_GAP:
				break
			y = maxf(y, r.end.y + ROW_GAP)
		placed.append(Rect2(cx, y, CARD_W, h))
		_layout.append({"card_x": cx, "card_y": y, "card_h": h, "year_x": yx, "linked": true})
		_content_h = maxf(_content_h, y + h)
	# A connector runs straight down from the axis to the card's top; draw it only where that path
	# is clear, or it would cross the cards stacked above.
	for i in range(placed.size()):
		var pos: Dictionary = _layout[i]
		var xs: Array = [float(pos["year_x"]), _connector_x(pos)]
		for j in range(placed.size()):
			var r: Rect2 = placed[j]
			if j == i or r.position.y >= float(pos["card_y"]):
				continue
			if xs.any(func(x: float) -> bool: return x >= r.position.x - 2.0 and x <= r.end.x + 2.0):
				pos["linked"] = false
				break
	_update_size()


## Width is the fitted width — the whole axis is on screen, so nothing scrolls sideways; height
## follows the lowest card.
func _update_size() -> void:
	custom_minimum_size = Vector2(_fit_width, maxf(TOP_PAD, _content_h) + BOTTOM_PAD)


## Where a card's connector meets its top edge: under its date, or its nearest top corner when the
## card was pushed in from the panel's edge.
static func _connector_x(pos: Dictionary) -> float:
	return clampf(float(pos["year_x"]), float(pos["card_x"]) + 6.0, float(pos["card_x"]) + CARD_W - 6.0)


# ── Card sizing ───────────────────────────────────────────────────────────────
# A card is exactly as tall as its text, measured with the same font, width and wrapping the card's
# labels use, so cards can be packed before any of them is built.

func _text_metrics() -> Dictionary:
	return {
		"font": get_theme_font("font", "Label"),
		"line_spacing": float(get_theme_constant("line_spacing", "Label")),
		"sep": float(get_theme_constant("separation", "VBoxContainer")),
	}


## Width available to a card's text.
static func text_width() -> float:
	return CARD_W - 2.0 * BORDER - 2.0 * PAD_X


## Lines `text` wraps to at the card's text width, capped at `max_lines`.
static func _wrapped_lines(text: String, font: Font, font_size: int, max_lines: int) -> int:
	if text == "":
		return 0
	var para := TextParagraph.new()
	para.width = text_width()
	para.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	para.add_string(text, font, font_size)
	return mini(para.get_line_count(), max_lines)


static func _label_h(lines: int, font: Font, font_size: int, line_spacing: float) -> float:
	if lines <= 0:
		return 0.0
	return float(lines) * font.get_height(font_size) + float(lines - 1) * line_spacing


## Height of the card for `ev`: border, year strip, then the padded title and description.
func card_height(ev: Dictionary, m: Dictionary = {}) -> float:
	if m.is_empty():
		m = _text_metrics()
	var font: Font = m["font"]
	var ls: float = m["line_spacing"]
	var sep: float = m["sep"]
	var h: float = 2.0 * BORDER + _label_h(1, font, YEAR_FONT, ls) + sep + 2.0 * PAD_Y
	h += _label_h(_wrapped_lines(str(ev.get("title", "")), font, TITLE_FONT, TITLE_LINES), font, TITLE_FONT, ls)
	var desc_lines: int = _wrapped_lines(str(ev.get("desc", "")), font, DESC_FONT, DESC_LINES)
	if desc_lines > 0:
		h += sep + _label_h(desc_lines, font, DESC_FONT, ls)
	return ceilf(h)


func _relayout() -> void:
	_compute_layout()
	_build_cards()
	queue_redraw()
	layout_changed.emit()


# ── Cards ─────────────────────────────────────────────────────────────────────

func _build_cards() -> void:
	for child in get_children():
		child.queue_free()
	for i in range(_events.size()):
		var pos: Dictionary = _layout[i]
		_make_card(_events[i], float(pos["card_x"]), float(pos["card_y"]), float(pos["card_h"]))


func _make_card(ev: Dictionary, cx: float, cy: float, ch: float) -> void:
	var col: Color = cat_color(ev)

	var panel := PanelContainer.new()
	panel.position = Vector2(cx, cy)
	panel.custom_minimum_size = Vector2(CARD_W, ch)
	panel.size = Vector2(CARD_W, ch)
	panel.clip_contents = true
	# PASS, not STOP: the card shows its tooltip, but the wheel still reaches the canvas and pans.
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.tooltip_text = "%s — %s\n\n%s" % [fmt_year(float(ev["year"])), str(ev.get("title", "")), str(ev.get("desc", ""))]
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.17)
	style.border_color = col
	style.set_border_width_all(int(BORDER))
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(vbox)

	# Coloured header strip with the year.
	var header_pc := PanelContainer.new()
	var hstyle := StyleBoxFlat.new()
	hstyle.bg_color = col.darkened(0.30)
	hstyle.corner_radius_top_left  = 4
	hstyle.corner_radius_top_right = 4
	header_pc.add_theme_stylebox_override("panel", hstyle)
	var year_lbl := Label.new()
	year_lbl.text = fmt_year(float(ev["year"]))
	year_lbl.add_theme_color_override("font_color", Color.WHITE)
	year_lbl.add_theme_font_size_override("font_size", YEAR_FONT)
	header_pc.add_child(year_lbl)
	vbox.add_child(header_pc)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   int(PAD_X))
	margin.add_theme_constant_override("margin_right",  int(PAD_X))
	margin.add_theme_constant_override("margin_top",    int(PAD_Y))
	margin.add_theme_constant_override("margin_bottom", int(PAD_Y))
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(margin)
	var inner := VBoxContainer.new()
	margin.add_child(inner)

	# Title and description are capped at a few lines (card_height() measures the same caps); the
	# tooltip carries all of it.
	var title_lbl := Label.new()
	title_lbl.text = str(ev.get("title", ""))
	title_lbl.add_theme_font_size_override("font_size", TITLE_FONT)
	title_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.max_lines_visible = TITLE_LINES
	title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	inner.add_child(title_lbl)

	var desc: String = str(ev.get("desc", ""))
	if desc != "":
		var desc_lbl := Label.new()
		desc_lbl.text = desc
		desc_lbl.add_theme_font_size_override("font_size", DESC_FONT)
		desc_lbl.add_theme_color_override("font_color", Color(0.70, 0.70, 0.78))
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.max_lines_visible = DESC_LINES
		desc_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		inner.add_child(desc_lbl)

	add_child(panel)


# ── Drawing (behind the cards) ─────────────────────────────────────────────────

func _draw() -> void:
	var h: float = maxf(size.y, custom_minimum_size.y)
	# Faint scale lines at every labelled tick, so a card many rows down still reads against
	# the axis above it.
	for t: Dictionary in ticks():
		if bool(t["label"]):
			draw_line(Vector2(float(t["x"]), 0.0), Vector2(float(t["x"]), h),
				Color(0.45, 0.47, 0.60, 0.10), 1.0)
	# Connectors: straight down from the ruler at the event's own year, to the top of its card.  A
	# card pushed in from the edge doesn't sit under its date, so the line bends onto its nearest
	# top corner.  Only cards with a clear path get one: a line to a card stacked under others would
	# run behind them.  Stacked cards sit under their date anyway, their header gives the year, and
	# every event keeps its dot and stub on the axis.
	for i in range(_layout.size()):
		var pos: Dictionary = _layout[i]
		if not bool(pos["linked"]):
			continue
		var c: Color = cat_color(_events[i])
		var col := Color(c.r, c.g, c.b, 0.45)
		var yx: float = float(pos["year_x"])
		var cy: float = float(pos["card_y"])
		var cx: float = _connector_x(pos)
		if is_equal_approx(cx, yx):
			draw_line(Vector2(yx, 0.0), Vector2(yx, cy), col, 1.5)
		else:
			draw_line(Vector2(yx, 0.0), Vector2(yx, cy - 8.0), col, 1.5)
			draw_line(Vector2(yx, cy - 8.0), Vector2(cx, cy), col, 1.5)
	# The present.
	var cur_x: float = year_to_x(_current_year)
	draw_line(Vector2(cur_x, 0.0), Vector2(cur_x, h), Color(0.20, 0.90, 0.35, 0.55), 2.0)


## The whole axis is on screen, so the mouse wheel scrolls down through the rows of cards.
func _gui_input(event: InputEvent) -> void:
	var scroll := get_parent() as ScrollContainer
	if scroll == null or not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not (mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]):
		return
	if mb.pressed:
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll.scroll_vertical -= 120
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			scroll.scroll_vertical += 120
	accept_event()


# ── Public API ────────────────────────────────────────────────────────────────

## Add a live game event.  The dict must contain at least "year", "title", "desc" and "category".
## Duplicate ids are ignored.  O(1); the (bounded) card tree is rebuilt lazily in _process, only
## while the panel is visible.
func add_event(ev: Dictionary) -> void:
	var ev_id: String = ev.get("id", "")
	if ev_id != "":
		if _live_ids.has(ev_id):
			return
		_live_ids[ev_id] = true
	_live_events.append(ev)
	if _live_events.size() > MAX_LIVE_EVENTS:
		var dropped: Dictionary = _live_events.pop_front()
		var did: String = dropped.get("id", "")
		if did != "":
			_live_ids.erase(did)
	_layout_dirty = true


func _process(delta: float) -> void:
	if not _layout_dirty or not is_visible_in_tree():
		return
	_rebuild_accum += delta
	if _rebuild_accum >= REBUILD_SEC:
		_rebuild_accum = 0.0
		_layout_dirty = false
		_relayout()


## The axis is fixed (start to heat death), so a new year only moves the present marker: a redraw,
## never a rebuild of the cards.
func set_current_year(y: int) -> void:
	_current_year = y
	queue_redraw()
	layout_changed.emit()
