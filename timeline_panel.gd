## TimelinePanel — built entirely in code so no extra .tscn is needed.
## Add this script to a bare Control node in the scene.
extends Control

var _canvas: TimelineCanvas
var _year_label: Label

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index in [
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		accept_event()


func _ready() -> void:
	# Expand to fill whatever space HBoxContainer2 gives us
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical   = Control.SIZE_EXPAND_FILL

	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root_vbox)

	# ── Header bar ────────────────────────────────────────────────────────────
	var header := HBoxContainer.new()
	root_vbox.add_child(header)

	var title_lbl := Label.new()
	title_lbl.text = "Historical Timeline"
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_lbl)

	_year_label = Label.new()
	_year_label.text = "Year: 1945"
	_year_label.add_theme_color_override("font_color", Color(0.20, 0.90, 0.35))
	header.add_child(_year_label)

	# ── Category legend ───────────────────────────────────────────────────────
	# Merge both color palettes so the legend covers game events too.
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 8)
	root_vbox.add_child(legend)

	var all_cat_colors: Dictionary = {}
	for k: String in TimelineEvents.CATEGORY_COLORS:
		all_cat_colors[k] = TimelineEvents.CATEGORY_COLORS[k]
	for k: String in GameEvents.CATEGORY_COLORS:
		all_cat_colors[k] = GameEvents.CATEGORY_COLORS[k]

	for cat_name: String in all_cat_colors:
		var cat_color: Color = all_cat_colors[cat_name]

		var dot := ColorRect.new()
		dot.color = cat_color
		dot.custom_minimum_size = Vector2(12, 12)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		legend.add_child(dot)

		var lbl := Label.new()
		lbl.text = cat_name.capitalize()
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.80, 0.80, 0.85))
		legend.add_child(lbl)

		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(8, 0)
		legend.add_child(spacer)

	# ── Horizontal scroll container ───────────────────────────────────────────
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(scroll)

	_canvas = TimelineCanvas.new()
	scroll.add_child(_canvas)

# ── Public API ────────────────────────────────────────────────────────────────

func set_current_year(year: int) -> void:
	if _year_label:
		_year_label.text = "Year: %d" % year
	if _canvas:
		_canvas.set_current_year(year)

## Add a live game event card to the timeline canvas.
## The dict should contain "year", "title", "desc", and "category".
func add_live_event(ev: Dictionary) -> void:
	if _canvas:
		_canvas.add_event(ev)
