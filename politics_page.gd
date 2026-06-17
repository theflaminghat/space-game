## PoliticsPage — built entirely in code; attach to a bare Control node in the scene.
extends Control

signal policy_changed(policy_id: String, value: Variant)

## Maps policy_id → CheckBox or HSlider so load_policies() can update them.
var _controls: Dictionary = {}

## Maps slider policy_id → its numeric value Label / unit suffix, so the readout
## can be set explicitly instead of relying on the value_changed signal (which
## doesn't fire when a loaded value matches the slider's current/stepped value).
var _slider_labels: Dictionary = {}
var _slider_units:  Dictionary = {}

## Live mirror of the current policy values, used to compute the effect summary.
var _state: Dictionary = {}

## Maps effect key → value Label in the "Current Effects" summary.
var _effect_labels: Dictionary = {}

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_build_ui()

# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)

	var outer := MarginContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("margin_left",   10)
	outer.add_theme_constant_override("margin_right",  10)
	outer.add_theme_constant_override("margin_top",    10)
	outer.add_theme_constant_override("margin_bottom", 10)
	scroll.add_child(outer)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	outer.add_child(vbox)

	# Page title
	var title := Label.new()
	title.text = "Politics & Policy"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	vbox.add_child(title)

	# Live effect summary, computed from the current policy state.
	_state = PoliticsData.default_state()
	_build_effects_summary(vbox)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(spacer)

	# One section per category
	for cat: String in PoliticsData.CATEGORIES:
		var cat_policies: Array = []
		for p: Dictionary in PoliticsData.POLICIES:
			if p["category"] == cat:
				cat_policies.append(p)
		if cat_policies.is_empty():
			continue
		_build_category(vbox, cat, cat_policies)

func _build_category(parent: VBoxContainer, cat: String, policies: Array) -> void:
	var cat_color: Color = PoliticsData.CATEGORY_COLORS.get(cat, Color.WHITE)

	# Category header label
	var cat_lbl := Label.new()
	cat_lbl.text = cat.to_upper()
	cat_lbl.add_theme_font_size_override("font_size", 11)
	cat_lbl.add_theme_color_override("font_color", cat_color)
	parent.add_child(cat_lbl)

	# Thin coloured separator
	var sep := HSeparator.new()
	sep.add_theme_color_override("color", cat_color)
	parent.add_child(sep)

	for policy: Dictionary in policies:
		_build_policy_row(parent, policy)

	# Small gap after each category
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	parent.add_child(gap)

func _build_policy_row(parent: VBoxContainer, policy: Dictionary) -> void:
	var pid: String = policy["id"]

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	# Left column: name + description ─────────────────────────────────────────
	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_col)

	var name_lbl := Label.new()
	name_lbl.text = policy["name"]
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	text_col.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = policy["desc"]
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", Color(0.62, 0.62, 0.70))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_col.add_child(desc_lbl)

	# Right column: CheckBox or slider ────────────────────────────────────────
	if policy["type"] == "toggle":
		var cb := CheckBox.new()
		cb.button_pressed = bool(policy["default"])
		cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cb.toggled.connect(func(pressed: bool) -> void:
			_state[pid] = pressed
			_refresh_effects()
			policy_changed.emit(pid, pressed)
		)
		row.add_child(cb)
		_controls[pid] = cb
	else:
		# Vertical stack: value label on top, slider below
		var slider_col := VBoxContainer.new()
		slider_col.custom_minimum_size = Vector2(130, 0)
		slider_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(slider_col)

		var unit: String = policy.get("unit", "")
		var val_lbl := Label.new()
		val_lbl.text = _fmt_slider_value(float(policy["default"]), unit)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val_lbl.add_theme_font_size_override("font_size", 12)
		val_lbl.add_theme_color_override("font_color", Color(0.90, 0.90, 1.0))
		slider_col.add_child(val_lbl)
		_slider_labels[pid] = val_lbl
		_slider_units[pid]  = unit

		var slider := HSlider.new()
		slider.min_value = float(policy["min"])
		slider.max_value = float(policy["max"])
		slider.step      = float(policy["step"])
		slider.value     = float(policy["default"])
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(func(v: float) -> void:
			val_lbl.text = _fmt_slider_value(v, unit)
			_state[pid] = v
			_refresh_effects()
			policy_changed.emit(pid, v)
		)
		slider_col.add_child(slider)
		_controls[pid] = slider

# ── Public API ────────────────────────────────────────────────────────────────

## Sync all controls to match a saved policy state (e.g. after loading a game).
func load_policies(state: Dictionary) -> void:
	for pid: String in _controls:
		if not state.has(pid):
			continue
		_state[pid] = state[pid]
		var ctrl: Node = _controls[pid]
		if ctrl is CheckBox:
			(ctrl as CheckBox).button_pressed = bool(state[pid])
		elif ctrl is HSlider:
			# Set silently (avoids spurious policy_changed emits during load), then
			# read the snapped value back and update the label explicitly so the
			# number always matches the slider — even when no value_changed fires.
			var slider := ctrl as HSlider
			slider.set_value_no_signal(float(state[pid]))
			_set_slider_label(pid, slider.value)
			_state[pid] = slider.value
	_refresh_effects()

## Update a slider's numeric readout to match a value (with its unit suffix).
func _set_slider_label(pid: String, value: float) -> void:
	if _slider_labels.has(pid):
		(_slider_labels[pid] as Label).text = _fmt_slider_value(value, _slider_units.get(pid, ""))

## Format a slider value with its unit.  Policy sliders use whole-number steps, so
## show them as integers — GDScript's % operator has no %g specifier (using one
## makes the whole format fail and print the literal "%g%s").
func _fmt_slider_value(value: float, unit: String) -> String:
	return "%d%s" % [int(round(value)), unit]

# ── Live effect summary ─────────────────────────────────────────────────────

## Build the "Current Effects" panel that shows the live policy multipliers.
func _build_effects_summary(parent: VBoxContainer) -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.11, 0.15)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)

	var hdr := Label.new()
	hdr.text = "CURRENT EFFECTS"
	hdr.add_theme_font_size_override("font_size", 11)
	hdr.add_theme_color_override("font_color", Color(0.70, 0.80, 0.95))
	box.add_child(hdr)

	var rows: Array = [
		["science",  "Science output"],
		["compute",  "Compute"],
		["minerals", "Matter output"],
		["energy",   "Energy output"],
		["mission",  "Mission time"],
	]
	for r: Array in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		box.add_child(row)

		var name_lbl := Label.new()
		name_lbl.text = r[1]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.add_theme_color_override("font_color", Color(0.80, 0.80, 0.88))
		row.add_child(name_lbl)

		var val_lbl := Label.new()
		val_lbl.add_theme_font_size_override("font_size", 12)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val_lbl)
		_effect_labels[r[0]] = val_lbl

	_refresh_effects()

## Recompute every effect label from the live policy state.
func _refresh_effects() -> void:
	if _effect_labels.is_empty():
		return
	_set_effect("science",  PoliticsData.science_mult(_state),  false)
	_set_effect("compute",  PoliticsData.compute_mult(_state),  false)
	_set_effect("minerals", PoliticsData.minerals_mult(_state), false)
	_set_effect("energy",   PoliticsData.energy_mult(_state),   false)
	# Mission time: a multiplier below 1.0 (shorter) is the beneficial direction.
	_set_effect("mission",  PoliticsData.mission_dur_mult(_state), true)

## Update one effect label's text and colour.  `lower_is_better` flips the
## green/red sense (used for mission time, where shorter is good).
func _set_effect(key: String, m: float, lower_is_better: bool) -> void:
	var lbl: Label = _effect_labels.get(key, null)
	if lbl == null:
		return
	var pct: int = int(round((m - 1.0) * 100.0))
	lbl.text = "×%.2f  (%+d%%)" % [m, pct]
	if pct == 0:
		lbl.add_theme_color_override("font_color", Color(0.72, 0.72, 0.78))
	else:
		var beneficial: bool = (m < 1.0) if lower_is_better else (m > 1.0)
		lbl.add_theme_color_override("font_color",
			Color(0.45, 0.85, 0.55) if beneficial else Color(0.90, 0.55, 0.45))
