extends PanelContainer

signal launch_requested(params: Dictionary)

# Valid launch *origins* — you can only depart from a planet.
const PLANETS := [
	"Mercury", "Venus", "Earth", "Mars",
	"Jupiter", "Saturn", "Uranus", "Neptune",
]

# Valid launch *targets* — the planets plus the Sun.  The Sun accepts orbit
# missions only (you cannot land on or colonise it).
const TARGETS := [
	"Mercury", "Venus", "Earth", "Mars",
	"Jupiter", "Saturn", "Uranus", "Neptune", "Sun",
]

@onready var origin_option:   OptionButton  = $MarginContainer/VBoxContainer/FormGrid/OriginOption
@onready var planet_option:   OptionButton  = $MarginContainer/VBoxContainer/FormGrid/PlanetOption
@onready var mission_option:  OptionButton  = $MarginContainer/VBoxContainer/FormGrid/MissionOption
@onready var duration_value:  Label         = $MarginContainer/VBoxContainer/FormGrid/DurationRow/DurationValue
@onready var cost_value:      Label         = $MarginContainer/VBoxContainer/FormGrid/CostValue
@onready var arrival_option:  OptionButton  = $MarginContainer/VBoxContainer/FormGrid/ArrivalOption
@onready var launch_button:   Button        = $MarginContainer/VBoxContainer/LaunchButton
@onready var launch_list:     VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/LaunchList

# ── Fuel & acceleration ────────────────────────────────────────────────────────
# The chosen FUEL fixes the transfer acceleration: faster fuels (fusion, antimatter)
# are gated by propulsion research and cost far more to manufacture, so speed is paid
# in fuel.  All trajectory cost/time math lives in LaunchPlanner (shared with the
# AutomationPanel executor); this panel just feeds it the player's selections.

## Fuel selector (replaces the old acceleration slider).
var _fuel_option: OptionButton = null
var _fuel_map:    Array        = []   # fuel-dropdown index → MissionData.FUELS index
## Per-origin stock of rockets + fuels, pushed by Game.gd for the cost readout / gate:
## { planet_lower → { "Rocket": n, "Propellant": n, ... } }.
var _launch_stock: Dictionary = {}

# ── Calendar date picker (replaces the old StartOption dropdown) ───────────────
var _calendar: CalendarPicker = null
## Current game date in 1-indexed form — updated via set_game_date().
var _cur_year:  int = 1945
var _cur_month: int = 1
var _cur_day:   int = 1

## Per-origin launch modifiers from surface infrastructure (e.g. Space Elevator),
## pushed by Game.gd: { planet_name_lower → { "cost": float, "duration": float } }.
var _launch_mods: Dictionary = {}

## Live orbital angle (radians) of each planet, pushed by Game.gd:
## { planet_name_lower → orbit_angle }.  Drives the launch-window energy penalty.
var _planet_angles: Dictionary = {}

## Global mission-duration multiplier from policy (e.g. nuclear propulsion = 0.8),
## pushed by Game.gd so the displayed transit time matches what actually happens.
var _mission_dur_mult: float = 1.0

## Dyson-swarm state pushed by Game.gd, so a Solar Deployment can show its satellite
## payload and refuse to fly with nothing to carry (or a full swarm).
var _sat_stock: Dictionary = {}   # { planet_lower → satellites in stock }
var _sat_deployed: int = 0
var _sat_max: int = 0

## Swallow mouse-wheel events so scrolling over this panel doesn't zoom the
## solar-system camera behind it.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index in [
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		accept_event()

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
	# A later start date shifts planet positions → different distance, time and cost.
	_calendar.date_selected.connect(func(_y: int, _m: int, _d: int) -> void:
		_update_duration(); _update_cost())
	date_section.add_child(_calendar)

	# Insert before the LaunchButton (second-to-last child of vbox).
	vbox.add_child(date_section)
	var btn_idx := launch_button.get_index()
	vbox.move_child(date_section, btn_idx)

	# Fuel selector, injected just above the start-date section.  The chosen fuel sets
	# the transfer acceleration and is what the launch consumes.
	var fuel_section := VBoxContainer.new()
	fuel_section.add_theme_constant_override("separation", 2)
	var fuel_lbl := Label.new()
	fuel_lbl.text = "Fuel:"
	fuel_lbl.add_theme_font_size_override("font_size", 11)
	fuel_lbl.modulate = Color(0.75, 0.75, 0.75)
	fuel_section.add_child(fuel_lbl)
	_fuel_option = OptionButton.new()
	_fuel_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fuel_option.item_selected.connect(func(_i): _update_duration(); _update_cost())
	fuel_section.add_child(_fuel_option)
	vbox.add_child(fuel_section)
	vbox.move_child(fuel_section, date_section.get_index())
	_populate_fuels()

	_populate_origin()
	_populate_planets()
	_populate_missions()
	_populate_arrival()
	origin_option.item_selected.connect(func(_i): _update_duration(); _update_cost())
	planet_option.item_selected.connect(func(_i):
		_update_arrival_options(); _update_duration(); _update_cost())
	mission_option.item_selected.connect(func(_i): _update_cost())
	arrival_option.item_selected.connect(func(_i): _update_duration(); _update_cost())
	launch_button.pressed.connect(_on_launch_pressed)
	_update_arrival_options()
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

## Called by Game.gd when the panel opens so the origin AND target both default
## to the planet the player is currently viewing, ready for a local orbit launch.
func set_current_planet(planet_name: String) -> void:
	if planet_name == "":
		return
	var cap := planet_name.capitalize()
	for i: int in range(PLANETS.size()):
		if PLANETS[i] == cap:
			origin_option.selected  = i
			planet_option.selected  = i   # target = same planet → local orbit
			arrival_option.selected = 0   # "Orbit" (not Land)
			_update_duration()
			_update_cost()
			break

## Push the Dyson-swarm state (per-planet satellite stock + deployed/cap) so a Solar
## Deployment mission can size and gate its payload.
func set_swarm_state(stock: Dictionary, deployed: int, max_slots: int) -> void:
	_sat_stock    = stock
	_sat_deployed = deployed
	_sat_max      = max_slots
	_update_cost()

## Satellites stockpiled at the currently-selected origin.
func _origin_sat_stock() -> int:
	var o := origin_option.selected
	if o < 0 or o >= PLANETS.size():
		return 0
	return int(_sat_stock.get(PLANETS[o].to_lower(), 0))

## Number of satellites the selected Solar Deployment would actually carry.
func _payload_batch(mission_idx: int) -> int:
	var mdef: Dictionary = MissionData.MISSION_TYPES[mission_idx]
	var per:  int = int(mdef.get("payload_per_launch", 0))
	var room: int = maxi(0, _sat_max - _sat_deployed)
	return mini(per, mini(_origin_sat_stock(), room))

func _selected_target_is_sun() -> bool:
	var p := planet_option.selected
	return p >= 0 and p < TARGETS.size() and TARGETS[p] == "Sun"

## Push the per-origin launch modifiers (from Game.gd) and refresh the readouts.
func set_launch_mods(mods: Dictionary) -> void:
	_launch_mods = mods
	_update_duration()
	_update_cost()

## Cost & duration multipliers for the currently-selected origin planet.
func _origin_mods() -> Dictionary:
	var o_idx := origin_option.selected
	if o_idx < 0:
		return {"cost": 1.0, "duration": 1.0}
	return _launch_mods.get(PLANETS[o_idx].to_lower(), {"cost": 1.0, "duration": 1.0})

func _populate_origin() -> void:
	origin_option.clear()
	for p in PLANETS:
		origin_option.add_item(p)
	origin_option.selected = 2   # default Earth; overridden by set_current_planet()

func _populate_planets() -> void:
	planet_option.clear()
	for p in TARGETS:
		planet_option.add_item(p)

## The Sun can only be orbited, never landed on — disable "Land" while it's the
## selected target (and snap any stale Land selection back to Orbit).
func _update_arrival_options() -> void:
	var t_idx := planet_option.selected
	var is_sun: bool = t_idx >= 0 and TARGETS[t_idx] == "Sun"
	arrival_option.set_item_disabled(1, is_sun)   # index 1 = "Land"
	if is_sun and arrival_option.selected == 1:
		arrival_option.selected = 0               # force Orbit

func _populate_missions() -> void:
	mission_option.clear()
	for m in MissionData.MISSION_TYPES:
		mission_option.add_item(m["name"])

func _populate_arrival() -> void:
	arrival_option.clear()
	arrival_option.add_item("Orbit")
	arrival_option.add_item("Land")

# ── Duration ─────────────────────────────────────────────────────────────────
# The trajectory math itself lives in LaunchPlanner (shared with the automation
# executor); these wrappers just feed it the panel's current selections + state.

## Selected origin / target names ("" when nothing valid is chosen).
func _origin_name() -> String:
	var o := origin_option.selected
	return PLANETS[o] if o >= 0 and o < PLANETS.size() else ""

func _target_name() -> String:
	var t := planet_option.selected
	return TARGETS[t] if t >= 0 and t < TARGETS.size() else ""

## Days from "now" to the chosen start date (planets are propagated to that date).
func _offset_days() -> float:
	if _calendar:
		return float(_calendar.get_offset_days(_cur_year, _cur_month, _cur_day))
	return 0.0

## Cost multiplier from the trajectory's total Δv relative to a bare surface-to-
## orbit launch.  Local orbit → 1.0×; Earth→Mars ≈ 1.6×; Earth→Neptune ≈ 2.7×.
func _difficulty_factor() -> float:
	var o := _origin_name()
	var t := _target_name()
	if o == "" or t == "":
		return 1.0
	return LaunchPlanner.difficulty_factor(o, t)

## Push the planets' live orbital angles (from Game.gd) and refresh the cost,
## which now depends on the actual launch-window geometry.
func set_orbital_state(angles: Dictionary) -> void:
	_planet_angles = angles
	_update_duration()   # transfer distance (and thus time) depends on positions
	_update_cost()

## Push the policy-driven mission-duration multiplier (e.g. nuclear propulsion) so
## the transit time shown to the player is the same time the mission really takes.
func set_mission_duration_mult(m: float) -> void:
	_mission_dur_mult = m
	_update_duration()

## Launch-window energy multiplier (≥ 1.0) from the actual path between the planets
## at the chosen start date (see LaunchPlanner.path_energy_factor).
func _path_energy_factor() -> float:
	var o := _origin_name()
	var t := _target_name()
	if o == "" or t == "":
		return 1.0
	return LaunchPlanner.path_energy_factor(o, t, _planet_angles, _offset_days())

## Short label describing how good the current launch window is.
func _window_label(pf: float) -> String:
	var x: float = (pf - 1.0) / LaunchPlanner.PHASE_ENERGY_WEIGHT   # 0 = optimal, 1 = worst
	if x < 0.15: return "optimal"
	if x < 0.45: return "good"
	if x < 0.75: return "fair"
	return "poor"

## Repopulate the fuel dropdown with the propellants current research has unlocked.
func _populate_fuels() -> void:
	if _fuel_option == null:
		return
	var prev_id: String = str(_selected_fuel().get("id", ""))
	_fuel_option.clear()
	_fuel_map.clear()
	for i in range(MissionData.FUELS.size()):
		var f: Dictionary = MissionData.FUELS[i]
		var req: String = str(f.get("requires", ""))
		if req != "" and not ResearchTree.is_unlocked(req):
			continue
		_fuel_option.add_item(str(f["name"]))
		_fuel_map.append(i)
		if str(f["id"]) == prev_id:
			_fuel_option.selected = _fuel_map.size() - 1
	if _fuel_option.selected < 0 and _fuel_option.item_count > 0:
		_fuel_option.selected = 0

## The selected fuel definition (defaults to the first/chemical fuel).
func _selected_fuel() -> Dictionary:
	if _fuel_option == null or _fuel_option.selected < 0 or _fuel_option.selected >= _fuel_map.size():
		return MissionData.FUELS[0]
	return MissionData.FUELS[_fuel_map[_fuel_option.selected]]

## Transfer acceleration (m/s²) the selected fuel provides.
func _selected_accel() -> float:
	return float(_selected_fuel().get("accel", 1.0e-2))

## Called by Game.gd to refresh available fuels after a research unlock.
func refresh_fuels() -> void:
	_populate_fuels()
	_update_duration()
	_update_cost()

func _is_local_orbit() -> bool:
	var o_idx := origin_option.selected
	var t_idx := planet_option.selected
	if o_idx < 0 or t_idx < 0:
		return false
	return PLANETS[o_idx] == TARGETS[t_idx] and arrival_option.selected == 0

## Combined duration multiplier: origin infrastructure (Space Elevator) × policy.
func _duration_mult() -> float:
	return float(_origin_mods().get("duration", 1.0)) * _mission_dur_mult

func _selected_duration_days() -> int:
	var o := _origin_name()
	var t := _target_name()
	if o == "" or t == "":
		return 0
	var arrival: String = "land" if arrival_option.selected == 1 else "orbit"
	return LaunchPlanner.duration_days(
		o, t, arrival, _selected_accel(), _planet_angles, _offset_days(), _duration_mult())

func _update_duration() -> void:
	var days := _selected_duration_days()
	if days <= 0:
		duration_value.text = "-"
		return
	# Tag launches that benefit from a Space Elevator at the chosen origin.
	var elevator: String = ""
	if float(_origin_mods().get("cost", 1.0)) < 1.0 \
			or float(_origin_mods().get("duration", 1.0)) < 1.0:
		elevator = "  ⛓ elevator"
	if _is_local_orbit():
		duration_value.text = "%s  (local orbit insertion)%s" % [_format_days(days), elevator]
	else:
		# Flag transfers that are pinned at the light-travel-time floor.
		var light_limited: bool = LaunchPlanner.is_light_limited(
			_origin_name(), _target_name(), _selected_accel(), _planet_angles, _offset_days())
		var tag: String = "  (light-speed limit)" if light_limited else ""
		duration_value.text = _format_days(days) + tag + elevator

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
	var fuel: Dictionary = _selected_fuel()
	var rockets: int  = _mission_rockets(idx)
	var fuel_amt: int = _mission_fuel(idx)
	var have_r: int = _origin_stock("Rocket")
	var have_f: int = _origin_stock(str(fuel["id"]))
	var txt: String = "%d Rocket (have %d)%s\n%d %s (have %d)%s" % [
		rockets, have_r, ("" if have_r >= rockets else "  ✗"),
		fuel_amt, str(fuel["name"]), have_f, ("" if have_f >= fuel_amt else "  ✗")]
	# Surface the launch-window quality so the player can see why fuel varies and
	# can pick a better start date.
	if not _is_local_orbit():
		var pf: float = _path_energy_factor()
		if pf > 1.005:
			txt += "\n(+%d%% fuel — %s window)" % [
				int(round((pf - 1.0) * 100.0)), _window_label(pf)]
	# Solar Deployment: show the satellite payload and why it might be blocked.
	if MissionData.MISSION_TYPES[idx].get("sun_only", false):
		var avail: int = _origin_sat_stock()
		var batch: int = _payload_batch(idx)
		txt += "\n+ %d Solar Satellite payload (have %d)" % [batch, avail]
		if not _selected_target_is_sun():
			txt += "  — target must be the Sun"
		elif _sat_deployed >= _sat_max:
			txt += "  — swarm full"
		elif avail <= 0:
			txt += "  — none in stock at origin"
	cost_value.text = txt

## Rockets (vehicle mass) the mission needs, via LaunchPlanner with the origin's
## infrastructure discount (e.g. a Space Elevator).
func _mission_rockets(mission_idx: int) -> int:
	var o := _origin_name()
	var t := _target_name()
	if o == "" or t == "":
		return 1
	return LaunchPlanner.rockets(mission_idx, o, t, float(_origin_mods().get("cost", 1.0)))

## Fuel units the mission burns, via LaunchPlanner; consumed as the selected propellant.
func _mission_fuel(mission_idx: int) -> int:
	var o := _origin_name()
	var t := _target_name()
	if o == "" or t == "":
		return 0
	return LaunchPlanner.fuel(
		mission_idx, o, t, _planet_angles, _offset_days(), float(_origin_mods().get("cost", 1.0)))

## Stock of a good (rockets or a fuel) at the currently-selected origin.
func _origin_stock(key: String) -> int:
	var o := origin_option.selected
	if o < 0 or o >= PLANETS.size():
		return 0
	return int((_launch_stock.get(PLANETS[o].to_lower(), {}) as Dictionary).get(key, 0))

## Push the per-origin rocket + fuel stock (from Game.gd) for the cost readout / gate.
func set_launch_stock(stock: Dictionary) -> void:
	_launch_stock = stock
	_update_cost()

# ── Launch ───────────────────────────────────────────────────────────────────

func _on_launch_pressed() -> void:
	var m_idx := mission_option.selected
	var p_idx := planet_option.selected
	var o_idx := origin_option.selected
	if m_idx < 0 or p_idx < 0 or o_idx < 0:
		return
	var origin_name: String = PLANETS[o_idx]
	var target_name: String = TARGETS[p_idx]
	var duration := _selected_duration_days()
	if duration <= 0:
		return   # invalid combination (e.g. land on the same body or on the Sun)
	# A Solar Deployment must fly to the Sun and actually carry satellites.
	if MissionData.MISSION_TYPES[m_idx].get("sun_only", false):
		if target_name != "Sun" or _payload_batch(m_idx) <= 0:
			return
	var fuel: Dictionary = _selected_fuel()
	var rockets: int  = _mission_rockets(m_idx)
	var fuel_amt: int = _mission_fuel(m_idx)
	# Don't fly if the origin can't supply the vehicle or its fuel.
	if _origin_stock("Rocket") < rockets or _origin_stock(str(fuel["id"])) < fuel_amt:
		return
	var start_offset: int = 0
	if _calendar:
		start_offset = _calendar.get_offset_days(_cur_year, _cur_month, _cur_day)
	launch_requested.emit({
		"mission":      MissionData.MISSION_TYPES[m_idx]["name"],
		"origin":       origin_name.to_lower(),
		"target":       target_name.to_lower(),
		"start_offset": start_offset,
		"duration":     duration,
		"rockets":      rockets,
		"fuel_id":      str(fuel["id"]),
		"fuel_amount":  fuel_amt,
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
	var origin: String = (launch.get("origin", "") as String).capitalize()
	var target: String = (launch.get("target", "") as String).capitalize()
	var arrival: String = launch.get("arrival", "orbit")

	if origin == target:
		# Local orbit — show clearly instead of "Mars → Mars"
		info.text = "%s: %s orbit" % [launch["mission"], target]
	else:
		var arrival_tag: String = " [land]" if arrival == "land" else ""
		info.text = "%s  %s → %s%s" % [launch["mission"], origin, target, arrival_tag]

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
		var days_left: int = launch.get("days_remaining", 0)
		status.text = _format_days(days_left) + " left"
	row.add_child(status)

	launch_list.add_child(row)
