extends PanelContainer

signal launch_requested(params: Dictionary)

const PLANETS := [
	"Mercury", "Venus", "Earth", "Mars",
	"Jupiter", "Saturn", "Uranus", "Neptune",
]

const PLANET_ORBIT_AU := {
	"Mercury": 0.387, "Venus": 0.723, "Earth": 1.0,   "Mars": 1.524,
	"Jupiter": 5.203, "Saturn": 9.537, "Uranus": 19.191, "Neptune": 30.069,
}

@onready var origin_option:   OptionButton  = $MarginContainer/VBoxContainer/FormGrid/OriginOption
@onready var planet_option:   OptionButton  = $MarginContainer/VBoxContainer/FormGrid/PlanetOption
@onready var mission_option:  OptionButton  = $MarginContainer/VBoxContainer/FormGrid/MissionOption
@onready var duration_value:  Label         = $MarginContainer/VBoxContainer/FormGrid/DurationRow/DurationValue
@onready var cost_value:      Label         = $MarginContainer/VBoxContainer/FormGrid/CostValue
@onready var arrival_option:  OptionButton  = $MarginContainer/VBoxContainer/FormGrid/ArrivalOption
@onready var launch_button:   Button        = $MarginContainer/VBoxContainer/LaunchButton
@onready var launch_list:     VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/LaunchList

# ── Transit-speed control ──────────────────────────────────────────────────────
# The Hohmann transfer is the minimum-energy trajectory, so it is the baseline:
# speed factor 1.0 = Hohmann time, no surcharge.  Burning harder shortens the
# trip (factor < 1.0 → fewer days) but costs extra energy that grows as the trip
# gets shorter.  Slowing below Hohmann buys nothing, so the slider stops at 1.0.
const SPEED_MIN: float            = 0.4   # fastest transit = 40% of Hohmann time
const SPEED_MAX: float            = 1.0   # baseline Hohmann transfer
const SPEEDUP_ENERGY_MULT: float  = 2.0   # extra energy = base × (1/f − 1) × this

var _speed_slider: HSlider = null
var _speed_factor: float   = 1.0

# ── Calendar date picker (replaces the old StartOption dropdown) ───────────────
var _calendar: CalendarPicker = null
## Current game date in 1-indexed form — updated via set_game_date().
var _cur_year:  int = 2026
var _cur_month: int = 1
var _cur_day:   int = 1

func _ready() -> void:
	# Hide the legacy "Start:" label and dropdown that were in the scene.
	var start_lbl: Node = get_node_or_null(
		"MarginContainer/VBoxContainer/FormGrid/StartLabel")
	var start_opt: Node = get_node_or_null(
		"MarginContainer/VBoxContainer/FormGrid/StartOption")
	if start_lbl: start_lbl.visible = false
	if start_opt: start_opt.visible = false

	# Inject the CalendarPicker between the form grid and the Launch button.
	var vbox: VBoxContainer = $MarginContainer/VBoxContainer
	var date_section := VBoxContainer.new()
	date_section.add_theme_constant_override("separation", 2)

	var date_lbl := Label.new()
	date_lbl.text = "Start date:"
	date_lbl.add_theme_font_size_override("font_size", 11)
	date_lbl.modulate = Color(0.75, 0.75, 0.75)
	date_section.add_child(date_lbl)

	_calendar = CalendarPicker.new()
	date_section.add_child(_calendar)

	# Insert before the LaunchButton (second-to-last child of vbox).
	vbox.add_child(date_section)
	var btn_idx := launch_button.get_index()
	vbox.move_child(date_section, btn_idx)

	# Transit-speed slider, injected just above the start-date section.
	var speed_section := VBoxContainer.new()
	speed_section.add_theme_constant_override("separation", 2)

	var speed_lbl := Label.new()
	speed_lbl.text = "Transit speed:"
	speed_lbl.add_theme_font_size_override("font_size", 11)
	speed_lbl.modulate = Color(0.75, 0.75, 0.75)
	speed_section.add_child(speed_lbl)

	_speed_slider = HSlider.new()
	_speed_slider.min_value  = SPEED_MIN
	_speed_slider.max_value  = SPEED_MAX
	_speed_slider.step       = 0.05
	_speed_slider.value      = SPEED_MAX
	_speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speed_slider.value_changed.connect(_on_speed_changed)
	speed_section.add_child(_speed_slider)

	vbox.add_child(speed_section)
	vbox.move_child(speed_section, date_section.get_index())

	_populate_origin()
	_populate_planets()
	_populate_missions()
	_populate_arrival()
	origin_option.item_selected.connect(func(_i): _update_duration(); _update_cost())
	planet_option.item_selected.connect(func(_i): _update_duration(); _update_cost())
	mission_option.item_selected.connect(func(_i): _update_cost())
	launch_button.pressed.connect(_on_launch_pressed)
	_update_duration()
	_update_cost()

## Called by Game.gd whenever the in-game date changes.
## y/m/d are 1-indexed (January = 1, first day = 1).
func set_game_date(y: int, m: int, d: int) -> void:
	_cur_year  = y
	_cur_month = m
	_cur_day   = d
	if _calendar:
		_calendar.set_min_date(y, m, d)

func _populate_origin() -> void:
	origin_option.clear()
	for p in PLANETS:
		origin_option.add_item(p)
	origin_option.selected = 2

func _populate_planets() -> void:
	planet_option.clear()
	for p in PLANETS:
		planet_option.add_item(p)

func _populate_missions() -> void:
	mission_option.clear()
	for m in MissionData.MISSION_TYPES:
		mission_option.add_item(m["name"])

func _populate_arrival() -> void:
	arrival_option.clear()
	arrival_option.add_item("Orbit")
	arrival_option.add_item("Land")

# ── Duration ─────────────────────────────────────────────────────────────────

func _compute_hohmann_days(origin_name: String, target_name: String) -> int:
	var a1: float = PLANET_ORBIT_AU.get(origin_name, 1.0)
	var a2: float = PLANET_ORBIT_AU.get(target_name, 1.0)
	return int(365.25 / 2.0 * pow((a1 + a2) / 2.0, 1.5))

func _on_speed_changed(value: float) -> void:
	_speed_factor = value
	_update_duration()
	_update_cost()

## The selected origin→target Hohmann time scaled by the current speed factor,
## or 0 when the selection is invalid (same body / nothing chosen).
func _selected_duration_days() -> int:
	var o_idx := origin_option.selected
	var t_idx := planet_option.selected
	if o_idx < 0 or t_idx < 0:
		return 0
	var origin_name: String = PLANETS[o_idx]
	var target_name: String = PLANETS[t_idx]
	if origin_name == target_name:
		return 0
	var hohmann := _compute_hohmann_days(origin_name, target_name)
	return maxi(1, int(round(hohmann * _speed_factor)))

func _update_duration() -> void:
	var days := _selected_duration_days()
	if days <= 0:
		duration_value.text = "-"
		return
	if _speed_factor < SPEED_MAX - 0.001:
		duration_value.text = "%s  (%.1f× faster)" % [_format_days(days), 1.0 / _speed_factor]
	else:
		duration_value.text = _format_days(days)

func _format_days(days: int) -> String:
	if days >= 365:
		var years := days / 365
		var rem   := days % 365
		if rem == 0:
			return "%dy" % years
		return "%dy%dd" % [years, rem]
	return "%dd" % days

# ── Cost ─────────────────────────────────────────────────────────────────────

func _update_cost() -> void:
	var idx := mission_option.selected
	if idx < 0 or idx >= MissionData.MISSION_TYPES.size():
		cost_value.text = "-"
		return
	cost_value.text = Units.format_cost(_actual_cost(idx))

## Base mission cost plus the energy surcharge for any speed-up beyond Hohmann.
## At factor 1.0 the surcharge is zero, so the cost equals the catalog cost.
func _actual_cost(mission_idx: int) -> Dictionary:
	var base: Dictionary = MissionData.MISSION_TYPES[mission_idx].get("cost", {})
	var cost: Dictionary = base.duplicate(true)
	var base_energy: float = float(base.get("energy", 0.0))
	var surcharge := int(round(base_energy * (1.0 / _speed_factor - 1.0) * SPEEDUP_ENERGY_MULT))
	if surcharge > 0:
		cost["energy"] = int(cost.get("energy", 0)) + surcharge
	return cost

# ── Launch ───────────────────────────────────────────────────────────────────

func _on_launch_pressed() -> void:
	var m_idx := mission_option.selected
	var p_idx := planet_option.selected
	var o_idx := origin_option.selected
	if m_idx < 0 or p_idx < 0 or o_idx < 0:
		return
	var origin_name: String = PLANETS[o_idx]
	var target_name: String = PLANETS[p_idx]
	var duration := _selected_duration_days()
	if duration <= 0:
		duration = 1
	var cost: Dictionary = _actual_cost(m_idx)
	var start_offset: int = 0
	if _calendar:
		start_offset = _calendar.get_offset_days(_cur_year, _cur_month, _cur_day)
	launch_requested.emit({
		"mission":      MissionData.MISSION_TYPES[m_idx]["name"],
		"origin":       origin_name.to_lower(),
		"target":       target_name.to_lower(),
		"start_offset": start_offset,
		"duration":     duration,
		"actual_cost":  cost,
		"arrival":      "land" if arrival_option.selected == 1 else "orbit",
	})

# ── Launch list ──────────────────────────────────────────────────────────────

func refresh_launches(launches: Array) -> void:
	for child in launch_list.get_children():
		child.queue_free()
	for launch in launches:
		_add_launch_row(launch)

func _add_launch_row(launch: Dictionary) -> void:
	var row := HBoxContainer.new()

	var info := Label.new()
	var arrival_tag: String = " [land]" if launch.get("arrival", "orbit") == "land" else ""
	info.text = "%s → %s%s" % [launch["mission"], (launch["target"] as String).capitalize(), arrival_tag]
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	var dates := Label.new()
	dates.text = "%d/%02d" % [launch["start_year"], launch["start_month"] + 1]
	row.add_child(dates)

	var status := Label.new()
	if launch["status"] == "completed":
		status.text = "Done"
		status.modulate = Color.GREEN
	else:
		status.text = "%dd left" % launch.get("days_remaining", 0)
	row.add_child(status)

	launch_list.add_child(row)
