extends PanelContainer

## Extraction tab of the merged planet panel.  Mining doesn't have to take whatever the ground
## gives: this is where the player points the operation at named deposits, deciding what share of
## its throughput goes to each compound in the crust.
##
## The allocation always sums to 100%.  Raising one compound takes the difference proportionally
## out of the others, so the panel enforces the real constraint — a finite mining fleet — rather
## than letting the player simply have more of everything.
##
## Feeds Game.set_extraction_focus; Game._extract_layer then splits mine yield by these weights
## instead of by crustal abundance.

signal focus_changed(planet: String, weights: Dictionary)

var _list:   VBoxContainer = null
var _header: Label = null
var _reset:  Button = null

var _planet: String = ""
## compound → 0..1 share of mining throughput.  Always normalised to sum to 1.
var _weights: Dictionary = {}
var _sliders: Dictionary = {}   # compound → HSlider
var _values:  Dictionary = {}   # compound → Label (percentage + yield)
var _mine_rate: float = 0.0
## Set while a slider is being rebalanced programmatically, so the value_changed signals that
## the rebalance itself emits don't recurse back into another rebalance.
var _rebalancing: bool = false

## Swallow scroll-wheel so hovering this tab doesn't zoom the 3-D camera behind it.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index in [
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		accept_event()

func _ready() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var title_row := HBoxContainer.new()
	var title := Label.new()
	title.text = "Extraction"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	_reset = Button.new()
	_reset.text = "Match crust"
	_reset.add_theme_font_size_override("font_size", 11)
	_reset.tooltip_text = "Clear the allocation and take whatever the ground gives, by natural abundance"
	_reset.pressed.connect(_on_reset_pressed)
	title_row.add_child(_reset)
	vbox.add_child(title_row)

	_header = Label.new()
	_header.add_theme_font_size_override("font_size", 11)
	_header.add_theme_color_override("font_color", Color(0.62, 0.70, 0.84))
	_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_header)
	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)

## Push a world's extraction picture (Game.extraction_data output).  Rebuilds the rows when the
## body changes; otherwise just refreshes the yield figures so dragging stays smooth.
func set_extraction(planet: String, data: Dictionary) -> void:
	_mine_rate = float(data.get("mine_rate", 0.0))
	var rows: Array = data.get("rows", [])
	if planet != _planet:
		_planet = planet
		_weights = {}
		for row: Dictionary in rows:
			_weights[str(row["compound"])] = float(row["weight"])
		_normalise()
		_rebuild(rows)
	_refresh_labels()

## Rebuild one slider row per crust compound.
func _rebuild(rows: Array) -> void:
	_sliders.clear()
	_values.clear()
	for child in _list.get_children():
		child.queue_free()

	# Richest first — the compounds worth arguing over are at the top.
	var sorted: Array = rows.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["abundance"]) > float(b["abundance"]))

	for row: Dictionary in sorted:
		var compound: String = str(row["compound"])
		var line := VBoxContainer.new()
		line.add_theme_constant_override("separation", 0)

		var head := HBoxContainer.new()
		var name_lbl := Label.new()
		name_lbl.text = CompoundData.NAMES.get(compound, compound)
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.tooltip_text = "%s — %.3f%% of this world's crust" % [
			compound, float(row["abundance"]) * 100.0]
		head.add_child(name_lbl)

		var val := Label.new()
		val.add_theme_font_size_override("font_size", 11)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.add_theme_color_override("font_color", Color(0.85, 0.90, 0.70))
		head.add_child(val)
		line.add_child(head)
		_values[compound] = val

		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 100.0
		slider.step = 0.5
		slider.value = float(_weights.get(compound, 0.0)) * 100.0
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(_on_slider_changed.bind(compound))
		line.add_child(slider)
		_sliders[compound] = slider

		_list.add_child(line)

## One compound was dragged: give it what it asked for and take the difference proportionally
## out of everything else, so the allocation still sums to 100%.
func _on_slider_changed(value: float, compound: String) -> void:
	if _rebalancing:
		return
	var want: float = clampf(value / 100.0, 0.0, 1.0)
	var others: float = 0.0
	for c: String in _weights:
		if c != compound:
			others += float(_weights[c])
	var remaining: float = 1.0 - want
	if others > 0.0:
		# Scale the rest down (or up) to fill exactly what's left.
		var k: float = remaining / others
		for c: String in _weights:
			if c != compound:
				_weights[c] = float(_weights[c]) * k
	elif _weights.size() > 1:
		# Everything else was at zero — spread the remainder evenly rather than losing it.
		var each: float = remaining / float(_weights.size() - 1)
		for c: String in _weights:
			if c != compound:
				_weights[c] = each
	_weights[compound] = want
	_push_sliders()
	_refresh_labels()
	focus_changed.emit(_planet, _weights)

## Write the current weights back into the sliders without re-triggering the rebalance.
func _push_sliders() -> void:
	_rebalancing = true
	for c: String in _sliders:
		(_sliders[c] as HSlider).value = float(_weights.get(c, 0.0)) * 100.0
	_rebalancing = false

## Normalise the allocation so it sums to exactly 1.
func _normalise() -> void:
	var total: float = 0.0
	for c: String in _weights:
		total += float(_weights[c])
	if total <= 0.0:
		return
	for c: String in _weights:
		_weights[c] = float(_weights[c]) / total

## Refresh each row's "share → yield" readout against the world's current mining throughput.
func _refresh_labels() -> void:
	for c: String in _values:
		var share: float = float(_weights.get(c, 0.0))
		(_values[c] as Label).text = "%.1f%%   %s/day" % [
			share * 100.0, Units.format_si(share * _mine_rate, "g")]
	if _header:
		_header.text = "Share of this world's %s/day mining throughput sent to each deposit. Raising one takes the difference from the rest." \
			% Units.format_si(_mine_rate, "g")

## Drop the allocation and go back to taking whatever the ground gives.
func _on_reset_pressed() -> void:
	if _planet == "":
		return
	focus_changed.emit(_planet, {})
	_planet = ""   # force a rebuild from crustal abundance on the next push
