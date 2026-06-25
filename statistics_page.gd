## StatisticsPage — graph-based statistics view.
## Replaces the old scrollable-sections layout with a StatsGraph and toggle buttons.
extends Control

const GRAPH_METRICS: Array = [
	{"key": "current_population", "label": "Population",  "color": Color(0.3,  0.7,  1.0),  "type": "int"},
	{"key": "compute_rate",       "label": "Compute",     "color": Color(0.9,  0.8,  0.2),  "type": "float"},
	{"key": "science",            "label": "Science",     "color": Color(0.4,  0.9,  0.6),  "type": "float"},
	{"key": "minerals",           "label": "Minerals",    "color": Color(0.9,  0.5,  0.2),  "type": "float"},
	{"key": "energy",             "label": "Energy",      "color": Color(0.9,  0.9,  0.3),  "type": "float"},
	{"key": "colony_count",       "label": "Colonies",    "color": Color(0.5,  0.9,  0.8),  "type": "int"},
	{"key": "life_expectancy",    "label": "Life Expectancy", "color": Color(0.95, 0.6,  0.75), "type": "int"},
]

var _stats: Dictionary = {}
var _graph: StatsGraph   = null
var _year_label: Label   = null
## key → Button
var _toggle_buttons: Dictionary = {}

# ── Lifecycle ─────────────────────────────────────────────────────────────────

## Swallow mouse-wheel events so scrolling over this panel doesn't zoom the
## solar-system camera behind it.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index in [
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		accept_event()

func _ready() -> void:
	_build_ui()

# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	# ── Header ────────────────────────────────────────────────────────────────
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 36)
	root.add_child(header)

	var title := Label.new()
	title.text = "Statistics"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_year_label = Label.new()
	_year_label.text = "Year 2026"
	_year_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_year_label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
	header.add_child(_year_label)

	# ── Series toggle buttons ─────────────────────────────────────────────────
	var toggle_flow := HFlowContainer.new()
	toggle_flow.add_theme_constant_override("h_separation", 5)
	toggle_flow.add_theme_constant_override("v_separation", 4)
	root.add_child(toggle_flow)

	for m: Dictionary in GRAPH_METRICS:
		var key: String = m["key"]
		var col: Color  = m["color"]

		var btn := Button.new()
		btn.text       = str(m["label"])
		btn.toggle_mode = true
		btn.button_pressed = true
		btn.custom_minimum_size = Vector2(108, 44)
		btn.add_theme_font_size_override("font_size", 11)
		btn.add_theme_color_override("font_color",         col)
		btn.add_theme_color_override("font_pressed_color", Color.WHITE)
		btn.add_theme_color_override("font_hover_color",   col.lightened(0.25))
		btn.toggled.connect(_on_series_toggled.bind(key))
		toggle_flow.add_child(btn)
		_toggle_buttons[key] = btn

	# ── Graph ─────────────────────────────────────────────────────────────────
	_graph = StatsGraph.new()
	_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	root.add_child(_graph)

	# Register every metric with the graph (series_meta drives draw order + legend)
	for m: Dictionary in GRAPH_METRICS:
		_graph.series_meta.append(m.duplicate())
		_graph.active[str(m["key"])] = true

# ── Public API ────────────────────────────────────────────────────────────────

## Called every frame from Game.gd with the latest stat snapshot.
## Updates the year label and button value annotations; does NOT add a history point.
func set_stats(new_stats: Dictionary) -> void:
	_stats = new_stats.duplicate(true)

	if _year_label:
		_year_label.text = "Year %d" % int(_stats.get("year", 2026))

	# Update each toggle button to show the current live value
	for m: Dictionary in GRAPH_METRICS:
		var key: String = m["key"]
		var btn: Button = _toggle_buttons.get(key) as Button
		if btn == null:
			continue
		var val: float = float(_stats.get(key, 0.0))
		var fmt: String = _fmt_val(val, str(m["type"]))
		btn.text = "%s\n%s" % [str(m["label"]), fmt]

## Called once per in-game year from Game.gd — records a permanent history point.
func push_snapshot(snap_year: int, data_dict: Dictionary) -> void:
	if _graph != null:
		_graph.push_snapshot(snap_year, data_dict)

## Clear all recorded history — call when starting a fresh game.
func clear_history() -> void:
	if _graph != null:
		_graph.clear_history()

## The live history graph, so the extinction screen can mirror it.
func get_graph() -> StatsGraph:
	return _graph

# ── Save / load ───────────────────────────────────────────────────────────────

func get_save_data() -> Dictionary:
	if _graph == null:
		return {}
	return {
		"years":   _graph.history_years.duplicate(),
		"history": _graph.history_data.duplicate(true),
	}

func load_save_data(saved: Dictionary) -> void:
	if _graph == null:
		return
	_graph.history_years.clear()
	for v: Variant in saved.get("years", []) as Array:
		_graph.history_years.append(int(v))

	_graph.history_data.clear()
	_graph._cached_vmin.clear()
	_graph._cached_vmax.clear()
	var raw: Dictionary = saved.get("history", {}) as Dictionary
	for k: Variant in raw.keys():
		var key: String = str(k)
		var arr: Array  = []
		var vmin := INF
		var vmax := -INF
		for v2: Variant in (raw[k] as Array):
			var fv: float = float(v2)
			arr.append(fv)
			vmin = minf(vmin, fv)
			vmax = maxf(vmax, fv)
		_graph.history_data[key]  = arr
		_graph._cached_vmin[key] = vmin if vmin != INF else 0.0
		_graph._cached_vmax[key] = vmax if vmax != -INF else 0.0

	_graph.queue_redraw()

# ── Internals ─────────────────────────────────────────────────────────────────

func _on_series_toggled(pressed: bool, key: String) -> void:
	if _graph:
		_graph.active[key] = pressed
		_graph.queue_redraw()

func _fmt_val(val: float, type: String) -> String:
	match type:
		"percent":
			var p: float = val if val > 1.0 else val * 100.0
			return "%.1f%%" % p
		"int":
			if absf(val) >= 1e12: return "%.1fT" % (val / 1e12)
			if absf(val) >= 1e9:  return "%.1fB" % (val / 1e9)
			if absf(val) >= 1e6:  return "%.1fM" % (val / 1e6)
			if absf(val) >= 1e3:  return "%.1fK" % (val / 1e3)
			return str(int(val))
		_:
			return Units.format_si_verbose(val, "")
