class_name TimelineRuler
extends Control

## The axis of the historical timeline, pinned at the top of the panel above the scrolling cards.
## It shows the whole of time the run can reach — from the run's first year to heat death — fitted
## to the panel's width.  Scale, ticks and event positions all come from TimelineCanvas, so the two
## always agree.
##
## Three rows, so nothing overlaps: the present marker's label on top, tick labels beneath it, and
## the axis itself at the bottom, where the event dots sit and their connectors drop into the cards.

const HEIGHT: float = 64.0
const NOW_Y: float = 14.0          # baseline of the present marker's label
const LABEL_Y: float = 34.0        # baseline of the tick labels
const BAR_Y: float = 48.0          # the axis line; the stubs below it continue into the canvas

var canvas: TimelineCanvas = null
var scroll: ScrollContainer = null


func _ready() -> void:
	custom_minimum_size.y = HEIGHT
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func _draw() -> void:
	if canvas == null:
		return
	var font := ThemeDB.fallback_font
	var w: float = size.x
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.08, 0.12, 0.95))

	# The axis, from the start of the run to heat death.
	var x0: float = canvas.year_to_x(TimelineCanvas.START_YEAR)
	var x1: float = canvas.axis_end_x()
	draw_line(Vector2(x0, BAR_Y), Vector2(x1, BAR_Y), Color(0.50, 0.50, 0.62, 0.9), 2.0)

	# One tick per power of ten, evenly spaced; labels on the regular subset TimelineCanvas picks.
	# Each label is centred on its tick, except the first and last, which are held inside the panel.
	for t: Dictionary in canvas.ticks():
		var x: float = float(t["x"])
		var lab: bool = bool(t["label"])
		var th: float = 7.0 if lab else 3.0
		draw_line(Vector2(x, BAR_Y - th), Vector2(x, BAR_Y + th),
			Color(0.60, 0.60, 0.72, 0.9 if lab else 0.45), 1.5 if lab else 1.0)
		if lab:
			var txt: String = str(t["text"])
			var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			var lx: float = clampf(x - tw * 0.5, 2.0, w - tw - 2.0)
			draw_string(font, Vector2(lx, LABEL_Y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				Color(0.66, 0.68, 0.80))

	# Each event: a dot on the axis and a stub down into the card area beneath.
	var lay: Array = canvas.layout()
	var evs: Array = canvas.events()
	for i in range(mini(lay.size(), evs.size())):
		var x: float = float((lay[i] as Dictionary)["year_x"])
		var c: Color = TimelineCanvas.cat_color(evs[i])
		draw_line(Vector2(x, BAR_Y), Vector2(x, HEIGHT), Color(c.r, c.g, c.b, 0.45), 1.5)
		draw_circle(Vector2(x, BAR_Y), 4.0, c)

	# The present, labelled on its own row.
	var cx: float = canvas.year_to_x(canvas.current_year())
	draw_line(Vector2(cx, NOW_Y + 4.0), Vector2(cx, HEIGHT), Color(0.20, 0.90, 0.35, 0.65), 2.0)
	var now: String = TimelineCanvas.fmt_year(float(canvas.current_year()))
	var nw: float = font.get_string_size(now, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(font, Vector2(clampf(cx - nw * 0.5, 2.0, w - nw - 2.0), NOW_Y), now,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.20, 0.90, 0.35))


## The wheel over the axis scrolls the cards beneath it.
func _gui_input(event: InputEvent) -> void:
	if scroll == null or not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		if mb.pressed:
			scroll.scroll_vertical -= 120
		accept_event()
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if mb.pressed:
			scroll.scroll_vertical += 120
		accept_event()
