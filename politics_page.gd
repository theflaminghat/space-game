## PoliticsPage — built entirely in code; attach to a bare Control node in the scene.
extends Control

signal policy_changed(policy_id: String, value: Variant)

## Maps policy_id → CheckBox or HSlider so load_policies() can update them.
var _controls: Dictionary = {}

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
		val_lbl.text = "%g%s" % [policy["default"], unit]
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val_lbl.add_theme_font_size_override("font_size", 12)
		val_lbl.add_theme_color_override("font_color", Color(0.90, 0.90, 1.0))
		slider_col.add_child(val_lbl)

		var slider := HSlider.new()
		slider.min_value = float(policy["min"])
		slider.max_value = float(policy["max"])
		slider.step      = float(policy["step"])
		slider.value     = float(policy["default"])
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(func(v: float) -> void:
			val_lbl.text = "%g%s" % [v, unit]
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
		var ctrl: Node = _controls[pid]
		if ctrl is CheckBox:
			(ctrl as CheckBox).button_pressed = bool(state[pid])
		elif ctrl is HSlider:
			(ctrl as HSlider).value = float(state[pid])
