extends PanelContainer

signal build_requested(planet_name: String, building_name: String)
signal demolish_requested(planet_name: String, building_name: String)

@onready var build_list: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/BuildList

var current_planet: String = ""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index in [
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		accept_event()


func set_planet(planet_name: String, catalog: Array) -> void:
	current_planet = planet_name
	_populate(catalog)
	show()

func _populate(catalog: Array) -> void:
	for child in build_list.get_children():
		child.queue_free()

	for building in catalog:
		var available: bool = building.get("available", true)
		var count:     int  = building.get("count", 0)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		# ── Name + production ──────────────────────────────────────────────────
		var info_box := VBoxContainer.new()
		info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_box.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
		info_box.add_theme_constant_override("separation", 0)

		var name_label := Label.new()
		name_label.text = building["name"]
		if not available and count == 0:
			name_label.modulate = Color(0.55, 0.55, 0.55)
		info_box.add_child(name_label)

		var prod_text := _format_production(building.get("production", {}))
		if prod_text != "":
			var prod_label := Label.new()
			prod_label.text = prod_text
			prod_label.add_theme_font_size_override("font_size", 10)
			prod_label.modulate = Color(0.50, 0.72, 0.95) if (available or count > 0) \
				else Color(0.45, 0.45, 0.45)
			info_box.add_child(prod_label)

		row.add_child(info_box)

		# ── Cost or requirement ────────────────────────────────────────────────
		if available:
			var cost_label := Label.new()
			cost_label.text = _format_cost(building.get("cost", {}))
			cost_label.add_theme_font_size_override("font_size", 11)
			cost_label.modulate = Color(0.75, 0.75, 0.75)
			row.add_child(cost_label)
		elif count == 0:
			var req_id: String = building.get("requires", "")
			var req_label := Label.new()
			req_label.text = "Requires: " + req_id.replace("_", " ").capitalize()
			req_label.add_theme_font_size_override("font_size", 11)
			req_label.modulate = Color(0.55, 0.55, 0.55)
			row.add_child(req_label)

		# ── Storage contribution (shown for storage buildings only) ───────────
		var stor: Dictionary = building.get("storage", {})
		if not stor.is_empty():
			var stor_label := Label.new()
			stor_label.text = _format_storage(stor)
			stor_label.add_theme_font_size_override("font_size", 11)
			stor_label.modulate = Color(0.55, 0.90, 0.65)
			row.add_child(stor_label)

		# ── [−] [count] [+] ───────────────────────────────────────────────────
		var minus_btn := Button.new()
		minus_btn.text               = "−"
		minus_btn.flat               = true
		minus_btn.custom_minimum_size = Vector2(24, 24)
		minus_btn.disabled           = count == 0
		minus_btn.pressed.connect(_on_demolish_pressed.bind(building["name"]))
		row.add_child(minus_btn)

		var count_label := Label.new()
		count_label.text                    = str(count)
		count_label.custom_minimum_size     = Vector2(22, 0)
		count_label.horizontal_alignment    = HORIZONTAL_ALIGNMENT_CENTER
		count_label.add_theme_font_size_override("font_size", 13)
		row.add_child(count_label)

		var plus_btn := Button.new()
		plus_btn.text               = "+"
		plus_btn.flat               = true
		plus_btn.custom_minimum_size = Vector2(24, 24)
		plus_btn.disabled           = not available
		plus_btn.pressed.connect(_on_build_pressed.bind(building["name"]))
		row.add_child(plus_btn)

		build_list.add_child(row)

func _format_cost(cost: Dictionary) -> String:
	return Units.format_cost(cost)

## Compact per-second output string shown under the building name.
##   {"compute": 80.0}            → "80 FLOP/s"
##   {"energy": 1800.0}           → "1.8 KiloWatts"
##   {"minerals": 500.0}          → "500 Grams/s"
## Returns "" for buildings with no direct production (domes, storage).
func _format_production(prod: Dictionary) -> String:
	var parts: Array = []
	for key: String in ["compute", "energy", "minerals"]:
		if prod.has(key) and float(prod[key]) > 0.0:
			parts.append(Units.format_rate(key, float(prod[key])))
	return "  ".join(parts)

## Compact storage-capacity string shown in green next to storage buildings.
##   {"minerals": 1e6, "energy": 1e6} → "+1.0 Mg  +1.0 MJ"
func _format_storage(stor: Dictionary) -> String:
	var parts: Array = []
	if stor.has("minerals"):
		parts.append("+%s" % Units.format_si(float(stor["minerals"]), "g"))
	if stor.has("energy"):
		parts.append("+%s" % Units.format_si(float(stor["energy"]), "J"))
	return "  ".join(parts)

func _on_build_pressed(building_name: String) -> void:
	build_requested.emit(current_planet, building_name)

func _on_demolish_pressed(building_name: String) -> void:
	demolish_requested.emit(current_planet, building_name)
