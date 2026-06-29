class_name AutomationPanel
extends PanelContainer

## AutomationPanel — lets the player write standing "automation rules" the game then
## follows on its own.  Two kinds:
##   • build  — keep N of a building on a world (the game builds more whenever it can
##              afford one and the count is short).
##   • launch — keep N missions of a kind in flight (the game re-launches whenever a
##              slot frees up and the origin can supply the rockets + fuel).
##
## Rules matter because time accelerates toward heat death — past a point you cannot
## hand-place every factory or re-fly every supply run, so you delegate the routine to
## standing orders and watch what your civilisation does without you.
##
## Emits automation_changed(rules: Array); Game.gd stores and executes the rules.
## Rule shapes:
##   { "id": int, "type": "build",  "planet": String, "building": String,
##     "target": int, "enabled": bool }
##   { "id": int, "type": "launch", "mission": String, "origin": String,
##     "target": String, "fuel": String, "arrival": String, "keep": int,
##     "enabled": bool }

signal automation_changed(rules: Array)

## Build/launch origins (planets only); launch targets add the Sun.
const PLANETS: Array = [
	"Earth", "Mercury", "Venus", "Mars",
	"Jupiter", "Saturn", "Uranus", "Neptune",
]
const TARGETS: Array = [
	"Mercury", "Venus", "Earth", "Mars",
	"Jupiter", "Saturn", "Uranus", "Neptune", "Sun",
]

var _rules:   Array = []
var _next_id: int   = 1

# ── Build-form refs ───────────────────────────────────────────────────────────
var _b_planet:   OptionButton = null
var _b_building: OptionButton = null
var _b_count:    SpinBox      = null

# ── Launch-form refs ──────────────────────────────────────────────────────────
var _l_mission: OptionButton = null
var _l_origin:  OptionButton = null
var _l_target:  OptionButton = null
var _l_fuel:    OptionButton = null
var _l_arrival: OptionButton = null
var _l_count:   SpinBox      = null

var _rule_list: VBoxContainer = null

# ── Lifecycle ─────────────────────────────────────────────────────────────────

## Swallow mouse-wheel events so scrolling the panel doesn't zoom the system behind it.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index in [
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		accept_event()

func _ready() -> void:
	custom_minimum_size = Vector2(560, 520)
	_build_ui()

# ── Public API ────────────────────────────────────────────────────────────────

## Replace the rule list from a loaded save (does not re-emit).
func load_rules(rules: Array) -> void:
	_rules = []
	for r in rules:
		_rules.append((r as Dictionary).duplicate())
		_next_id = maxi(_next_id, int((r as Dictionary).get("id", 0)) + 1)
	_rebuild_rule_list()

## A serialisable copy of the current rules.
func get_rules() -> Array:
	var out: Array = []
	for r in _rules:
		out.append((r as Dictionary).duplicate())
	return out

# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top",    8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.add_theme_constant_override("margin_left",   10)
	margin.add_theme_constant_override("margin_right",  10)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Automation"
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "Standing orders the game carries out on its own as time runs forward."
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(0.70, 0.72, 0.78)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)

	vbox.add_child(HSeparator.new())

	_build_build_form(vbox)
	vbox.add_child(HSeparator.new())
	_build_launch_form(vbox)

	vbox.add_child(HSeparator.new())

	var rules_label := Label.new()
	rules_label.text = "Active Rules"
	rules_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(rules_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_rule_list = VBoxContainer.new()
	_rule_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rule_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_rule_list)

	_rebuild_rule_list()

func _section_label(parent: Control, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.modulate = Color(0.85, 0.88, 0.95)
	parent.add_child(lbl)

func _form_label(grid: Control, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.modulate = Color(0.75, 0.75, 0.75)
	grid.add_child(lbl)

func _count_spin() -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = 1
	sb.max_value = 999
	sb.step      = 1
	sb.value     = 1
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return sb

func _build_build_form(vbox: VBoxContainer) -> void:
	_section_label(vbox, "Automated Building")

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	vbox.add_child(grid)

	_form_label(grid, "World:")
	_b_planet = OptionButton.new()
	_b_planet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for p in PLANETS:
		_b_planet.add_item(p)
	grid.add_child(_b_planet)

	_form_label(grid, "Building:")
	_b_building = OptionButton.new()
	_b_building.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for b in BuildingData.BUILDINGS:
		_b_building.add_item(str((b as Dictionary)["name"]))
	grid.add_child(_b_building)

	_form_label(grid, "Keep at least:")
	_b_count = _count_spin()
	grid.add_child(_b_count)

	var add := Button.new()
	add.text = "+ Add build rule"
	add.custom_minimum_size = Vector2(0, 32)
	add.pressed.connect(_on_add_build)
	vbox.add_child(add)

func _build_launch_form(vbox: VBoxContainer) -> void:
	_section_label(vbox, "Automated Launches")

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	vbox.add_child(grid)

	_form_label(grid, "Mission:")
	_l_mission = OptionButton.new()
	_l_mission.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m in MissionData.MISSION_TYPES:
		_l_mission.add_item(str((m as Dictionary)["name"]))
	grid.add_child(_l_mission)

	_form_label(grid, "From:")
	_l_origin = OptionButton.new()
	_l_origin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for p in PLANETS:
		_l_origin.add_item(p)
	grid.add_child(_l_origin)

	_form_label(grid, "To:")
	_l_target = OptionButton.new()
	_l_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for p in TARGETS:
		_l_target.add_item(p)
	_l_target.selected = TARGETS.find("Mars")
	grid.add_child(_l_target)

	_form_label(grid, "Fuel:")
	_l_fuel = OptionButton.new()
	_l_fuel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for f in MissionData.FUELS:
		_l_fuel.add_item(str((f as Dictionary)["name"]))
	grid.add_child(_l_fuel)

	_form_label(grid, "Arrival:")
	_l_arrival = OptionButton.new()
	_l_arrival.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_l_arrival.add_item("Orbit")
	_l_arrival.add_item("Land")
	grid.add_child(_l_arrival)

	_form_label(grid, "Keep active:")
	_l_count = _count_spin()
	grid.add_child(_l_count)

	var add := Button.new()
	add.text = "+ Add launch rule"
	add.custom_minimum_size = Vector2(0, 32)
	add.pressed.connect(_on_add_launch)
	vbox.add_child(add)

# ── Rule creation ─────────────────────────────────────────────────────────────

func _on_add_build() -> void:
	if _b_planet.selected < 0 or _b_building.selected < 0:
		return
	_rules.append({
		"id":       _next_id,
		"type":     "build",
		"planet":   str(PLANETS[_b_planet.selected]).to_lower(),
		"building": _b_building.get_item_text(_b_building.selected),
		"target":   int(_b_count.value),
		"enabled":  true,
	})
	_next_id += 1
	_commit()

func _on_add_launch() -> void:
	if _l_mission.selected < 0 or _l_origin.selected < 0 or _l_target.selected < 0 \
			or _l_fuel.selected < 0:
		return
	var fuel_def: Dictionary = MissionData.FUELS[_l_fuel.selected]
	_rules.append({
		"id":      _next_id,
		"type":    "launch",
		"mission": _l_mission.get_item_text(_l_mission.selected),
		"origin":  str(PLANETS[_l_origin.selected]).to_lower(),
		"target":  str(TARGETS[_l_target.selected]).to_lower(),
		"fuel":    str(fuel_def["id"]),
		"arrival": "land" if _l_arrival.selected == 1 else "orbit",
		"keep":    int(_l_count.value),
		"enabled": true,
	})
	_next_id += 1
	_commit()

func _remove_rule(rule_id: int) -> void:
	for i in range(_rules.size()):
		if int((_rules[i] as Dictionary).get("id", -1)) == rule_id:
			_rules.remove_at(i)
			break
	_commit()

func _set_enabled(rule_id: int, on: bool) -> void:
	for r in _rules:
		if int((r as Dictionary).get("id", -1)) == rule_id:
			(r as Dictionary)["enabled"] = on
			break
	_commit()

func _commit() -> void:
	_rebuild_rule_list()
	automation_changed.emit(get_rules())

# ── Rule list rendering ───────────────────────────────────────────────────────

func _rebuild_rule_list() -> void:
	if _rule_list == null:
		return
	for c in _rule_list.get_children():
		c.queue_free()
	if _rules.is_empty():
		var empty := Label.new()
		empty.text = "No automation rules yet."
		empty.add_theme_font_size_override("font_size", 11)
		empty.modulate = Color(0.6, 0.6, 0.6)
		_rule_list.add_child(empty)
		return
	for r in _rules:
		_rule_list.add_child(_make_rule_row(r as Dictionary))

func _make_rule_row(rule: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var rid: int = int(rule.get("id", 0))

	var on := CheckBox.new()
	on.button_pressed = bool(rule.get("enabled", true))
	on.toggled.connect(func(p): _set_enabled(rid, p))
	row.add_child(on)

	var info := Label.new()
	info.text = _describe(rule)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_font_size_override("font_size", 11)
	if not bool(rule.get("enabled", true)):
		info.modulate = Color(0.55, 0.55, 0.55)
	row.add_child(info)

	var rm := Button.new()
	rm.text = "✕"
	rm.add_theme_font_size_override("font_size", 11)
	rm.pressed.connect(func(): _remove_rule(rid))
	row.add_child(rm)

	return row

func _describe(rule: Dictionary) -> String:
	if str(rule.get("type", "")) == "build":
		return "Build  ·  keep ≥ %d × %s on %s" % [
			int(rule.get("target", 1)),
			str(rule.get("building", "?")),
			str(rule.get("planet", "?")).capitalize()]
	# launch
	var fuel_name: String = str(rule.get("fuel", ""))
	for f in MissionData.FUELS:
		if str((f as Dictionary)["id"]) == fuel_name:
			fuel_name = str((f as Dictionary)["name"])
			break
	return "Launch  ·  keep %d active  %s  %s→%s  [%s, %s]" % [
		int(rule.get("keep", 1)),
		str(rule.get("mission", "?")),
		str(rule.get("origin", "?")).capitalize(),
		str(rule.get("target", "?")).capitalize(),
		fuel_name,
		str(rule.get("arrival", "orbit"))]
