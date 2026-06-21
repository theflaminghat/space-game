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

const PLANET_ORBIT_AU := {
	"Mercury": 0.387, "Venus": 0.723, "Earth": 1.0,   "Mars": 1.524,
	"Jupiter": 5.203, "Saturn": 9.537, "Uranus": 19.191, "Neptune": 30.069,
	# Close solar orbit (Parker-probe class, ~0.05 AU); shedding Earth's orbital
	# speed to fall this far in makes the Sun the costliest destination.
	"Sun": 0.05,
}

@onready var origin_option:   OptionButton  = $MarginContainer/VBoxContainer/FormGrid/OriginOption
@onready var planet_option:   OptionButton  = $MarginContainer/VBoxContainer/FormGrid/PlanetOption
@onready var mission_option:  OptionButton  = $MarginContainer/VBoxContainer/FormGrid/MissionOption
@onready var duration_value:  Label         = $MarginContainer/VBoxContainer/FormGrid/DurationRow/DurationValue
@onready var cost_value:      Label         = $MarginContainer/VBoxContainer/FormGrid/CostValue
@onready var arrival_option:  OptionButton  = $MarginContainer/VBoxContainer/FormGrid/ArrivalOption
@onready var launch_button:   Button        = $MarginContainer/VBoxContainer/LaunchButton
@onready var launch_list:     VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/LaunchList

# ── Acceleration control ───────────────────────────────────────────────────────
# The ship runs a constant-acceleration (brachistochrone) transfer: thrust to the
# midpoint, flip, decelerate.  Transit time for distance D at acceleration a is
# t = 2·√(D/a), capped at the light-travel time D/c — you can approach c but never
# beat it.  Higher acceleration = a much shorter trip (and much more energy).  The
# slider is logarithmic because usable accelerations span many orders of magnitude;
# its top end is raised by propulsion research (see Game._max_launch_accel).
const ACCEL_MIN:        float = 1.0e-3   # m/s² — efficient low-thrust floor (≈ Hohmann time)
const ACCEL_LOG_STEP:   float = 0.1      # slider granularity, in log10 decades
const ACCEL_ENERGY_EXP: float = 0.35     # energy premium ∝ (a/ACCEL_MIN)^this
const AU_METERS:        float = 1.495978707e11
const LIGHT_SPEED:      float = 2.998e8   # m/s
const STD_GRAVITY:      float = 9.80665   # m/s² per g (for display)
## Days for an orbit-insertion launch from the surface of the origin planet itself.
const LOCAL_ORBIT_DAYS: int   = 30

# ── Launch-cost realism ─────────────────────────────────────────────────────────
# Mission costs scale with the real Δv budget of the trajectory, so reaching a
# distant or deep-gravity target costs far more propellant and energy than a
# local orbit insertion.
## Circular heliocentric orbital speed at 1 AU (Earth), km/s.  v(r) = this / √r.
const V_EARTH_KMS: float          = 29.78
## Reference Δv to climb from a planet's surface to orbit (km/s).  Every launch
## pays it; interplanetary transfers add their Hohmann Δv on top.  Costs scale
## with total Δv ÷ this, so a bare local orbit insertion is the 1.0× baseline.
const SURFACE_TO_ORBIT_DV: float  = 9.0
## Extra energy a worst-case launch window adds, on top of the transfer baseline.
## The actual path depends on where the planets are: a poorly-phased target forces
## a less efficient trajectory, scaling energy from 1.0× (optimal) up to 1+this.
const PHASE_ENERGY_WEIGHT: float  = 1.0

var _accel_slider: HSlider = null
var _accel_label:  Label   = null
## Currently selected acceleration (m/s²) and the research-gated maximum.
var _accel:     float = ACCEL_MIN
var _max_accel: float = 1.0e-2   # raised by propulsion research, pushed from Game

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

	# Acceleration slider (log scale), injected just above the start-date section.
	var accel_section := VBoxContainer.new()
	accel_section.add_theme_constant_override("separation", 2)

	var accel_header := HBoxContainer.new()
	var accel_lbl := Label.new()
	accel_lbl.text = "Acceleration:"
	accel_lbl.add_theme_font_size_override("font_size", 11)
	accel_lbl.modulate = Color(0.75, 0.75, 0.75)
	accel_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	accel_header.add_child(accel_lbl)
	_accel_label = Label.new()
	_accel_label.add_theme_font_size_override("font_size", 11)
	_accel_label.modulate = Color(0.85, 0.85, 0.95)
	_accel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	accel_header.add_child(_accel_label)
	accel_section.add_child(accel_header)

	_accel_slider = HSlider.new()
	_accel_slider.min_value  = log(ACCEL_MIN) / log(10.0)        # log10 of min accel
	_accel_slider.max_value  = log(_max_accel) / log(10.0)       # extended by research
	_accel_slider.step       = ACCEL_LOG_STEP
	_accel_slider.value      = log(ACCEL_MIN) / log(10.0)        # default: efficient/cheap
	_accel_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_accel_slider.value_changed.connect(_on_accel_changed)
	accel_section.add_child(_accel_slider)

	vbox.add_child(accel_section)
	vbox.move_child(accel_section, date_section.get_index())

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
	_update_accel_label()
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

func _compute_hohmann_days(origin_name: String, target_name: String) -> int:
	var a1: float = PLANET_ORBIT_AU.get(origin_name, 1.0)
	var a2: float = PLANET_ORBIT_AU.get(target_name, 1.0)
	return int(365.25 / 2.0 * pow((a1 + a2) / 2.0, 1.5))

## Heliocentric Hohmann transfer Δv (km/s) between two circular orbits (AU).
## Sum of the periapsis and apoapsis burns; 0 when origin and target coincide.
func _hohmann_delta_v(r1: float, r2: float) -> float:
	if is_equal_approx(r1, r2):
		return 0.0
	var vc1: float = V_EARTH_KMS / sqrt(r1)
	var vc2: float = V_EARTH_KMS / sqrt(r2)
	var dv1: float = absf(vc1 * (sqrt(2.0 * r2 / (r1 + r2)) - 1.0))
	var dv2: float = absf(vc2 * (1.0 - sqrt(2.0 * r1 / (r1 + r2))))
	return dv1 + dv2

## Cost multiplier from the trajectory's total Δv relative to a bare surface-to-
## orbit launch.  Local orbit → 1.0×; Earth→Mars ≈ 1.6×; Earth→Neptune ≈ 2.7×.
func _difficulty_factor() -> float:
	var o_idx := origin_option.selected
	var t_idx := planet_option.selected
	if o_idx < 0 or t_idx < 0:
		return 1.0
	var r1: float = float(PLANET_ORBIT_AU.get(PLANETS[o_idx], 1.0))
	var r2: float = float(PLANET_ORBIT_AU.get(TARGETS[t_idx], 1.0))
	var total_dv: float = SURFACE_TO_ORBIT_DV + _hohmann_delta_v(r1, r2)
	return total_dv / SURFACE_TO_ORBIT_DV

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

## Mean motion (rad/day) of a circular orbit at semi-major axis a_au.
func _mean_motion(a_au: float) -> float:
	return TAU / (365.25 * pow(a_au, 1.5))

## Launch-window energy multiplier (≥ 1.0) from the *actual* path between the two
## planets.  A Hohmann transfer only rendezvouses if the target leads the origin
## by a specific phase angle at departure; the further the real configuration (at
## the chosen start date) is from that ideal, the more energy the trajectory needs.
func _path_energy_factor() -> float:
	var o_idx := origin_option.selected
	var t_idx := planet_option.selected
	if o_idx < 0 or t_idx < 0:
		return 1.0
	var o_name: String = PLANETS[o_idx]
	var t_name: String = TARGETS[t_idx]
	if o_name == t_name:
		return 1.0   # local orbit — no interplanetary path
	var ol := o_name.to_lower()
	var tl := t_name.to_lower()
	if not (_planet_angles.has(ol) and _planet_angles.has(tl)):
		return 1.0   # no live position data yet

	var a1: float = float(PLANET_ORBIT_AU.get(o_name, 1.0))
	var a2: float = float(PLANET_ORBIT_AU.get(t_name, 1.0))

	# Propagate both planets forward to the chosen start date so a future launch
	# date can target a better window.
	var offset_days: float = 0.0
	if _calendar:
		offset_days = float(_calendar.get_offset_days(_cur_year, _cur_month, _cur_day))
	var ang1: float = float(_planet_angles[ol]) + _mean_motion(a1) * offset_days
	var ang2: float = float(_planet_angles[tl]) + _mean_motion(a2) * offset_days

	# Ideal Hohmann phase: how far the target should lead the origin at departure.
	var ideal_lead: float = PI * (1.0 - pow((a1 + a2) / (2.0 * a2), 1.5))
	var lead: float  = fposmod(ang2 - ang1, TAU)
	var ideal: float = fposmod(ideal_lead, TAU)
	var diff: float = absf(lead - ideal)
	diff = minf(diff, TAU - diff)            # angular error in [0, π]
	return 1.0 + PHASE_ENERGY_WEIGHT * (diff / PI)

## Short label describing how good the current launch window is.
func _window_label(pf: float) -> String:
	var x: float = (pf - 1.0) / PHASE_ENERGY_WEIGHT   # 0 = optimal, 1 = worst
	if x < 0.15: return "optimal"
	if x < 0.45: return "good"
	if x < 0.75: return "fair"
	return "poor"

## Slider moved → read the log-scale value back into a real acceleration.
func _on_accel_changed(value: float) -> void:
	_accel = pow(10.0, value)
	_update_accel_label()
	_update_duration()
	_update_cost()

## Push the research-gated maximum acceleration (from Game) and re-range the slider.
func set_max_accel(a: float) -> void:
	_max_accel = maxf(a, ACCEL_MIN)
	if _accel_slider:
		_accel_slider.max_value = log(_max_accel) / log(10.0)
		_accel = clampf(_accel, ACCEL_MIN, _max_accel)
		_accel_slider.value = log(_accel) / log(10.0)
	_update_accel_label()
	_update_duration()
	_update_cost()

func _update_accel_label() -> void:
	if _accel_label:
		_accel_label.text = _fmt_accel(_accel)

## "0.001 m/s²", "0.10 g", "2.5 g" …  (GDScript's % has no %g specifier).
func _fmt_accel(a: float) -> String:
	if a >= STD_GRAVITY * 0.1:
		return "%.2f g" % (a / STD_GRAVITY)
	if a >= 0.1:
		return "%.2f m/s²" % a
	if a >= 0.001:
		return "%.3f m/s²" % a
	return "%.5f m/s²" % a

func _is_local_orbit() -> bool:
	var o_idx := origin_option.selected
	var t_idx := planet_option.selected
	if o_idx < 0 or t_idx < 0:
		return false
	return PLANETS[o_idx] == TARGETS[t_idx] and arrival_option.selected == 0

## Straight-line distance the ship crosses (AU): the live separation between the
## origin and target at the chosen start date.  Falls back to the orbit radii.
func _transfer_distance_au() -> float:
	var o_idx := origin_option.selected
	var t_idx := planet_option.selected
	if o_idx < 0 or t_idx < 0:
		return 0.0
	var o_name: String = PLANETS[o_idx]
	var t_name: String = TARGETS[t_idx]
	var r1: float = float(PLANET_ORBIT_AU.get(o_name, 1.0))
	var r2: float = float(PLANET_ORBIT_AU.get(t_name, 1.0))
	var ol := o_name.to_lower()
	var tl := t_name.to_lower()
	if _planet_angles.has(ol) and _planet_angles.has(tl):
		var offset_days: float = 0.0
		if _calendar:
			offset_days = float(_calendar.get_offset_days(_cur_year, _cur_month, _cur_day))
		var a1: float = float(_planet_angles[ol]) + _mean_motion(r1) * offset_days
		var a2: float = float(_planet_angles[tl]) + _mean_motion(r2) * offset_days
		var p1 := Vector2(r1 * sin(a1), r1 * cos(a1))
		var p2 := Vector2(r2 * sin(a2), r2 * cos(a2))
		return maxf(p1.distance_to(p2), 0.001)
	# No live data: use a representative separation (mean of closest and farthest).
	return maxf((r1 + r2 + absf(r2 - r1)) * 0.5, 0.001)

func _selected_duration_days() -> int:
	var o_idx := origin_option.selected
	var t_idx := planet_option.selected
	if o_idx < 0 or t_idx < 0:
		return 0
	var origin_name: String = PLANETS[o_idx]
	var target_name: String = TARGETS[t_idx]
	# Combine the origin's infrastructure discount (Space Elevator) with the global
	# policy multiplier (nuclear propulsion) so the shown time is the real time.
	var dmult: float = float(_origin_mods().get("duration", 1.0)) * _mission_dur_mult
	if origin_name == target_name:
		# Surface-to-orbit insertion — fixed baseline, not a brachistochrone cruise.
		if arrival_option.selected == 0:   # Orbit
			return maxi(1, int(round(LOCAL_ORBIT_DAYS * dmult)))
		return 0
	# Brachistochrone: t = 2·√(D/a), floored at light-travel time D/c.
	var d_m: float = _transfer_distance_au() * AU_METERS
	var t_s: float = maxf(2.0 * sqrt(d_m / _accel), d_m / LIGHT_SPEED)
	return maxi(1, int(round(t_s / 86400.0 * dmult)))

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
		var d_m: float = _transfer_distance_au() * AU_METERS
		var light_limited: bool = 2.0 * sqrt(d_m / _accel) <= d_m / LIGHT_SPEED
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
	var txt: String = Units.format_cost(_actual_cost(idx))
	# Surface the launch-window quality so the player can see why energy varies and
	# can pick a better start date.
	if not _is_local_orbit():
		var pf: float = _path_energy_factor()
		if pf > 1.005:
			txt += "   (+%d%% energy — %s window)" % [
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

## Base mission cost scaled by destination Δv, launch window, and how hard the
## ship burns: higher acceleration spends much more energy (∝ peak kinetic energy),
## so a near-light dash costs orders of magnitude more than an efficient cruise.
func _actual_cost(mission_idx: int) -> Dictionary:
	var base: Dictionary = MissionData.MISSION_TYPES[mission_idx].get("cost", {})
	# Scale propellant (minerals) and energy by the destination's Δv difficulty —
	# a Neptune transfer burns far more than a local orbit insertion.
	var diff: float = _difficulty_factor()
	var cost: Dictionary = {}
	for k: String in base:
		cost[k] = float(base[k]) * diff
	# The actual path between the planets (launch-window phasing) scales the energy
	# the trajectory demands — a badly-aligned target needs a less efficient burn.
	if cost.has("energy"):
		cost["energy"] = float(cost["energy"]) * _path_energy_factor()
	# Acceleration premium: energy grows with how hard the ship thrusts above the
	# efficient low-thrust floor (1.0× at ACCEL_MIN).
	if cost.has("energy"):
		var accel_premium: float = pow(_accel / ACCEL_MIN, ACCEL_ENERGY_EXP)
		cost["energy"] = float(cost["energy"]) * accel_premium
	# Origin-infrastructure discount (e.g. a Space Elevator), then round to ints.
	var cmult: float = float(_origin_mods().get("cost", 1.0))
	for k: String in cost:
		cost[k] = maxi(0, int(round(float(cost[k]) * cmult)))
	return cost

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
