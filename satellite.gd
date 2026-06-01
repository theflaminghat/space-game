class_name Satellite
extends Node3D

## Animated transfer craft.
##
## Runs on the same game-day clock the planets use (delta / seconds_per_day), so
## it respects pause and every timescale.  Three phases:
##
##   TRANSFER – follows a Hohmann-style ellipse whose endpoints are re-evaluated
##              every frame against the target planet's *live* position, so the
##              craft homes onto the planet even though it keeps orbiting during
##              the flight.  Flight time equals the mission's duration in days.
##   ORBIT    – ("orbit" arrival) settles into a tilted parking orbit around the
##              target and follows it indefinitely.
##   LANDING  – ("land" arrival) spirals down to the surface, then frees itself.

signal arrived(mode: String)

# ── Tuning ──────────────────────────────────────────────────────────────────────
const DOT_RADIUS         := 0.10
const PARKING_SCALE      := 2.5     # parking radius = target.scale.x × this
const PARKING_MIN        := 0.6     # …but never smaller than this
const ORBIT_PERIOD_DAYS  := 40.0    # game-days per revolution in parking orbit
const ORBIT_TILT_DEG     := 18.0
const LAND_DESCEND_DAYS  := 8.0
const DEFAULT_FLIGHT_DAYS := 60.0

const DOT_COLOR  := Color(1.00, 1.00, 1.00, 1.00)

enum State { TRANSFER, ORBIT, LANDING, DONE }

# ── Public config (set by spawner before begin_transfer) ─────────────────────────
var arrival_mode: String = "orbit"
var orbit_center: Node3D = null

# ── Live planet references ───────────────────────────────────────────────────────
var _origin: Planet = null
var _target: Planet = null

# ── Departure geometry captured at launch (world-relative to the sun) ────────────
var _depart_angle:  float = 0.0
var _depart_radius: float = 0.0
var _outward:       bool  = true

# ── Game-day timing ──────────────────────────────────────────────────────────────
var _flight_days:  float = DEFAULT_FLIGHT_DAYS
var _elapsed_days: float = 0.0
var _state:        int   = State.TRANSFER
var _started:      bool  = false   # false until begin_transfer() is called

# ── Orbit / landing phase ────────────────────────────────────────────────────────
var _orbit_angle: float = 0.0
var _park_radius: float = 1.0
var _orbit_tilt:  float = 0.0
var _land_days:   float = 0.0

# ── Visual nodes ─────────────────────────────────────────────────────────────────
var _dot: MeshInstance3D = null

# ── Lifecycle ────────────────────────────────────────────────────────────────────

func _ready() -> void:
	SolarSystem.active_changed.connect(_sync_visibility)
	SolarSystem.paused_changed.connect(_sync_visibility)
	_build_dot()
	_sync_visibility()

## Begin the transfer.  flight_days should be the mission's duration so the
## animation finishes exactly when the mission does.
func begin_transfer(center: Node3D, origin: Planet, target: Planet,
		flight_days: float = DEFAULT_FLIGHT_DAYS) -> void:
	orbit_center = center
	_origin      = origin
	_target      = target
	_flight_days = maxf(flight_days, 1.0)

	var sun: Vector3 = center.global_position
	var rel: Vector3 = origin.global_position - sun
	_depart_radius = rel.length()
	_depart_angle  = atan2(rel.x, rel.z)
	_outward       = target.get_visual_radius() >= _depart_radius

	_park_radius = maxf(target.scale.x * PARKING_SCALE, PARKING_MIN)
	_orbit_tilt  = deg_to_rad(ORBIT_TILT_DEG)

	_elapsed_days = 0.0
	_state        = State.TRANSFER
	_started      = true
	_set_craft_pos(_transfer_point(0.0))

func _process(delta: float) -> void:
	if not _started:
		return   # template / not-yet-launched satellite stays idle
	if SolarSystem.paused or SolarSystem.ui_paused:
		return
	if _state == State.DONE:
		return
	# Frozen solar system → planets are hidden and motionless; hold position.
	if not SolarSystem.solar_system_active:
		return
	if _target == null or not is_instance_valid(_target):
		queue_free()
		return
	var spd: float = SolarSystem.seconds_per_day
	if spd <= 0.0:
		return
	var delta_days: float = delta / spd

	match _state:
		State.TRANSFER: _process_transfer(delta_days)
		State.ORBIT:    _process_orbit(delta_days)
		State.LANDING:  _process_landing(delta_days)

# ── Phase: transfer ──────────────────────────────────────────────────────────────

func _process_transfer(delta_days: float) -> void:
	_elapsed_days += delta_days
	var p: float = clampf(_elapsed_days / _flight_days, 0.0, 1.0)
	_set_craft_pos(_transfer_point(p))

	if p >= 1.0:
		arrived.emit(arrival_mode)
		if arrival_mode == "land":
			_state    = State.LANDING
			_land_days = 0.0
		else:
			_state       = State.ORBIT
			_orbit_angle = 0.0

## Hohmann half-ellipse whose far end is recomputed every frame from the target's
## current radius & angle, so the craft homes onto the moving planet.
func _transfer_point(p: float) -> Vector3:
	var sun: Vector3  = orbit_center.global_position
	var trel: Vector3 = _target.global_position - sun
	var r2: float = trel.length()
	var a2: float = atan2(trel.x, trel.z)
	var r1: float = _depart_radius

	var a: float = (r1 + r2) * 0.5
	var e: float = absf(r2 - r1) / maxf(r1 + r2, 1.0e-4)
	# theta runs 0→π (outward: periapsis→apoapsis) or π→2π (inward), so the
	# radius starts at r1 and ends exactly at r2 in either direction.
	var theta: float = (0.0 if _outward else PI) + p * PI
	var r: float = a * (1.0 - e * e) / (1.0 + e * cos(theta))

	var ang: float = _depart_angle + _prograde_sweep(_depart_angle, a2) * p
	return sun + Vector3(sin(ang) * r, 0.0, cos(ang) * r)

# ── Phase: orbit ─────────────────────────────────────────────────────────────────

func _process_orbit(delta_days: float) -> void:
	_orbit_angle += TAU * delta_days / ORBIT_PERIOD_DAYS
	_set_craft_pos(_orbit_point(_park_radius))

## A circular orbit around the target, tilted about the X axis so it reads as an
## ellipse rather than an edge-on line from the default camera.
func _orbit_point(radius: float) -> Vector3:
	var cx: float = cos(_orbit_angle) * radius
	var cz: float = sin(_orbit_angle) * radius
	return _target.global_position + Vector3(
		cx,
		cz * sin(_orbit_tilt),
		cz * cos(_orbit_tilt)
	)

# ── Phase: landing ───────────────────────────────────────────────────────────────

func _process_landing(delta_days: float) -> void:
	_land_days += delta_days
	var p: float = clampf(_land_days / LAND_DESCEND_DAYS, 0.0, 1.0)
	_orbit_angle += TAU * delta_days / (ORBIT_PERIOD_DAYS * 0.5)
	var radius: float = lerpf(_park_radius, _target.scale.x * 0.9, p)
	_set_craft_pos(_orbit_point(radius))
	if p >= 1.0:
		_state = State.DONE
		queue_free()

# ── Craft + trail positioning ────────────────────────────────────────────────────

func _set_craft_pos(pos: Vector3) -> void:
	if _dot:
		_dot.global_position = pos

# ── Visibility (mirror the planets: hidden when frozen unless paused) ─────────────

func _sync_visibility() -> void:
	visible = SolarSystem.solar_system_active \
		or SolarSystem.paused or SolarSystem.ui_paused

# ── Mesh builders ────────────────────────────────────────────────────────────────

func _build_dot() -> void:
	_dot = _make_sphere(DOT_RADIUS, DOT_COLOR)
	add_child(_dot)

func _make_sphere(radius: float, color: Color) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 6
	s.rings = 4
	var inst := MeshInstance3D.new()
	inst.mesh             = s
	inst.cast_shadow      = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.material_override = _unlit_mat(color, color.a < 1.0)
	return inst

func _unlit_mat(color: Color, transparent: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat

# ── Helpers ──────────────────────────────────────────────────────────────────────

## Positive (prograde) angular distance from a to b in [0, TAU).
func _prograde_sweep(a: float, b: float) -> float:
	var d: float = fmod(b - a, TAU)
	if d < 0.0:
		d += TAU
	return d
