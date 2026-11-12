class_name Satellite
extends Node3D

## Animated transfer craft.
##
## Runs on the same game-day clock the planets use (delta / seconds_per_day), so
## it respects pause and every timescale.  Three phases:
##
##   TRANSFER – follows a Hohmann-style ellipse STRUCK ONCE, at launch, between where the
##              origin is and where the target WILL BE on arrival.  Flight time equals the
##              mission's duration in days.
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

# ── Planned-path line ───────────────────────────────────────────────────────────
## The dashed arc the player gets for clicking this craft's launch on the board.
##
## Dashes are spaced by ARC LENGTH rather than by flight fraction: the arc's geometric speed
## varies along itself, so cutting by fraction alone bunches the dashes up at one end.  And each
## dash is a tube of triangles, for the same reason the orbit ribbons are (see planet.gd): a
## 1-px Vulkan line vanishes at distance, which is most of where this one is drawn.
const PATH_SAMPLES:   int   = 180     # polyline resolution the dashes are cut out of
const PATH_DASHES:    int   = 22      # dashes along the whole arc
const PATH_DUTY:      float = 0.58    # fraction of each dash period that is ink
const PATH_TUBE_R:    float = 0.035   # dash cross-section radius (game units)
const PATH_RING_SEGS: int   = 4       # sides of that cross-section
const PATH_COLOR := Color(0.62, 0.85, 1.00, 0.70)
## A transfer arc never moves, so its line is cut once.  The one plan that does move is a local
## insertion's — a parking orbit around a body that is itself in orbit — and that is re-cut on
## this clock rather than every frame.
const PATH_REBUILD_SEC: float = 0.2

enum State { TRANSFER, ORBIT, LANDING, DONE }

# ── Public config (set by spawner before begin_transfer) ─────────────────────────
var arrival_mode: String = "orbit"
var orbit_center: Node3D = null
## For arrival_mode == "swarm": the world position the craft flies to, where it removes itself
## and what it carried takes its place.  WHERE THE BERTH WILL BE on arrival, not where it is:
## the spawner looks it up for the flight's remaining days (see Game._spawn_swarm_satellite).
var swarm_target_pos: Vector3 = Vector3.ZERO
var _is_swarm:  bool    = false
var _start_pos: Vector3 = Vector3.ZERO   # departure position, captured at launch
## Set when the target IS the origin: there is no interplanetary cruise, so the plan to draw is
## the parking orbit rather than a transfer arc.  Latched instead of re-compared, because a
## planet can be engulfed by the Sun and freed mid-flight.
var _local:     bool    = false

# ── Drawn or not ────────────────────────────────────────────────────────────────
## A mission's craft is a readout of the launch board, not scenery for the solar system, so it
## is only drawn while the player has that board open.  Pushed by Game at spawn and on every
## open and close; false here so a craft launched by an automation rule behind a shut board
## never flickers into view.
var _board_visible: bool = false
var _path_shown:    bool = false
var _path_accum:    float = 0.0

# ── Live planet references ───────────────────────────────────────────────────────
var _origin: Planet = null
var _target: Planet = null

# ── Departure geometry captured at launch (world-relative to the sun) ────────────
var _depart_angle:  float = 0.0
var _depart_radius: float = 0.0
var _outward:       bool  = true
## Sun position cached at launch — the star is static, so re-reading its transform
## every frame is pure overhead.
var _sun_pos:       Vector3 = Vector3.ZERO

# ── Where the flight ENDS, fixed at launch ───────────────────────────────────────
## The arrival point relative to the Sun, and the prograde angle swept to reach it.  Both are
## struck once in begin_transfer and never touched again: that is the whole difference between
## a flight that has a plan and one that merely has a destination.
##
## This used to be re-read from the target's live position every frame.  The craft still landed
## on the planet, but the arc's far end went round with it, so the trajectory swung along behind
## the planet for the length of the flight — and a line drawn along it was not a plan, it was a
## picture of where the craft happened to be pointing this frame.
var _arrive_rel:    Vector3 = Vector3.ZERO
var _arrive_radius: float   = 1.0
var _sweep:         float   = 0.0

# ── Game-day timing ──────────────────────────────────────────────────────────────
var _flight_days:  float = DEFAULT_FLIGHT_DAYS
var _elapsed_days: float = 0.0
var _state:        int   = State.TRANSFER
var _started:      bool  = false   # false until begin_transfer() is called

# ── Orbit / landing phase ────────────────────────────────────────────────────────
var _orbit_angle:       float = 0.0
var _orbit_dir:         float = 1.0   # +1 CCW, -1 CW — matched to incoming velocity
var _orbit_entry_angle: float = 0.0   # orbit ring angle where velocity aligns with arrival
var _park_radius:       float = 1.0
var _orbit_tilt:        float = 0.0
var _tilt_sin:          float = 0.0   # cached sin(_orbit_tilt) — constant per flight
var _tilt_cos:          float = 1.0   # cached cos(_orbit_tilt) — constant per flight
var _land_days:         float = 0.0

# ── Visual nodes ─────────────────────────────────────────────────────────────────
var _dot: MeshInstance3D = null
## Built the first time a path is asked for, and nowhere near every craft is ever asked.
var _path: MeshInstance3D = null

# ── Lifecycle ────────────────────────────────────────────────────────────────────

func _ready() -> void:
	SolarSystem.active_changed.connect(_sync_visibility)
	SolarSystem.paused_changed.connect(_sync_visibility)
	_build_dot()
	_sync_visibility()

## Begin the transfer.  flight_days should be the mission's duration so the
## animation finishes exactly when the mission does.
##
## elapsed_days starts the craft part-way along, for a flight restored from a save: the whole
## arc is still the plan, and the craft sits at the fraction of it the calendar says has been
## flown, so it arrives on the day the launch record says it does.
func begin_transfer(center: Node3D, origin: Planet, target: Planet,
		flight_days: float = DEFAULT_FLIGHT_DAYS, elapsed_days: float = 0.0) -> void:
	orbit_center = center
	_origin      = origin
	_target      = target
	_flight_days = maxf(flight_days, 1.0)

	_sun_pos = center.global_position
	var rel: Vector3 = origin.global_position - _sun_pos
	_depart_radius = rel.length()
	_depart_angle  = atan2(rel.x, rel.z)

	_park_radius = maxf(target.scale.x * PARKING_SCALE, PARKING_MIN)
	_orbit_tilt  = deg_to_rad(ORBIT_TILT_DEG)
	_tilt_sin    = sin(_orbit_tilt)
	_tilt_cos    = cos(_orbit_tilt)

	_elapsed_days = clampf(elapsed_days, 0.0, _flight_days)
	_started      = true
	_local        = origin == target

	# Swarm deployment: fly straight to the reserved slot, then vanish (the collector
	# appears there).  Handled before the origin==target shortcut below.
	_is_swarm  = arrival_mode == "swarm"
	_start_pos = origin.global_position
	var p0: float = _elapsed_days / _flight_days

	# ── The arc, struck once ──
	# Aimed at where the destination will be when the craft gets there, which for a Keplerian
	# orbit is exact, so nothing has to be steered afterwards.  A restored flight has only its
	# REMAINING days to lead by, which is why this reads the clock rather than flight_days.
	var lead: float = _flight_days - _elapsed_days
	var arrive: Vector3 = swarm_target_pos if _is_swarm else target.position_in_days(lead)
	_arrive_rel    = arrive - _sun_pos
	_arrive_radius = _arrive_rel.length()
	# Which end of the half-ellipse the flight starts at.  Off the arrival radius the craft is
	# actually aimed at, now that there is one: this used to take the target's orbit radius as
	# a stand-in, which is a different number on an eccentric orbit and, when the two fall on
	# opposite sides of the departure radius, puts the arc's start at the wrong end of itself.
	_outward = _arrive_radius >= _depart_radius

	# How far ROUND the Sun the flight goes.  The bearing to the arrival point only fixes that
	# to within whole revolutions, and over a long flight the difference is the entire shape of
	# the path: aimed at the bearing alone, a craft can spend four hundred days creeping almost
	# straight outward while the planets whirl past it, which is not a transfer anybody would
	# recognise.  So take the revolution count that puts the sweep nearest what something
	# actually orbiting out there covers in the time, which for a short hop is none at all.
	#
	# It did not show before only because the arc was re-struck every frame: the sweep was a
	# bearing to wherever the target had got to, and it wandered through long arcs on its way
	# to the short one it would have ended on.
	var base: float = _prograde_sweep(_depart_angle, atan2(_arrive_rel.x, _arrive_rel.z))
	_sweep = base
	if not _is_swarm:
		var rate: float = 0.5 * (_angular_rate(origin) + _angular_rate(target))
		var revs: float = floor((rate * _flight_days - base) / TAU + 0.5)
		_sweep = base + maxf(0.0, revs) * TAU
	# The insertion hook is a function of where the arc ends, and the arc's end no longer moves,
	# so it is settled here instead of being recomputed on the approach.
	var ins: Vector2 = _insertion_entry(_depart_angle + _sweep)
	_orbit_dir         = ins.x
	_orbit_entry_angle = ins.y

	if _is_swarm:
		_state = State.TRANSFER
		_set_craft_pos(_lane_point(p0))
		return

	# Local orbit insertion: the target *is* the origin planet, so there's no
	# interplanetary cruise — settle straight into a parking orbit so the craft is
	# visible orbiting from the moment it launches.
	if _local:
		_orbit_dir   = 1.0
		_orbit_angle = 0.0
		_state       = State.ORBIT
		_set_craft_pos(_orbit_point(_park_radius))
		return

	_state = State.TRANSFER
	_set_craft_pos(_arc_point(p0))

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

	# The transfer and lane arcs do not move, so their line is cut once when it is asked for and
	# never again.  A local insertion's plan is the parking orbit around a body that DOES move,
	# so that one is re-cut, on its own slow clock.
	if _path_shown and _local and visible and _state != State.DONE:
		_path_accum += delta
		if _path_accum >= PATH_REBUILD_SEC:
			_path_accum = 0.0
			_rebuild_path()

# ── Phase: transfer ──────────────────────────────────────────────────────────────

func _process_transfer(delta_days: float) -> void:
	_elapsed_days += delta_days
	var p: float = clampf(_elapsed_days / _flight_days, 0.0, 1.0)

	# Swarm deployment: glide to the slot, then disappear as the collector materialises.
	if _is_swarm:
		_set_craft_pos(_lane_point(p))
		if p >= 1.0:
			arrived.emit("swarm")
			_state = State.DONE
			queue_free()
		return

	_set_craft_pos(_arc_point(p))

	if p >= 1.0:
		arrived.emit(arrival_mode)
		# _orbit_dir and _orbit_entry_angle were settled at launch, with the arc.
		if arrival_mode == "land":
			_state     = State.LANDING
			_land_days = 0.0
		else:
			_state       = State.ORBIT
			_orbit_angle = _orbit_entry_angle

## Heliocentric transfer down to a berth in an orbital lane, from the departure point to the
## berth the craft was aimed at.
##
## This used to be a straight lerp from the departure planet to the slot.  A swarm lane sits
## inside Mercury's orbit, so that chord passes THROUGH THE SUN whenever the slot is on the far
## side — and it arrived moving radially, straight across the lane it was supposed to join.
##
## It now flies the same kind of arc a real transfer does: an ellipse whose apoapsis is the
## departure radius and whose PERIAPSIS IS THE LANE ITSELF.  Radius falls monotonically from one
## to the other, so the path can never pass inside the destination lane — and therefore never
## through the Sun.  Arriving at periapsis means arriving with velocity purely along-track,
## which is the condition for entering the lane rather than crossing it.
func _lane_point(p: float) -> Vector3:
	var r2: float = maxf(_arrive_radius, 0.01)
	var r1: float = maxf(_depart_radius, r2)   # the swarm is always inside a launch site

	# Ellipse from apoapsis (r1) to periapsis (r2).  theta runs pi -> 2pi, so r decreases
	# monotonically and bottoms out exactly at the lane.
	var a: float = (r1 + r2) * 0.5
	var e: float = (r1 - r2) / maxf(r1 + r2, 1.0e-4)
	var theta: float = PI + p * PI
	var r: float = a * (1.0 - e * e) / (1.0 + e * cos(theta))

	var ang: float = _depart_angle + _sweep * p
	# Out-of-plane: lanes are inclined, so lift the craft onto the slot's plane over the
	# flight instead of dropping onto it at the end.
	var plane_y: float = _arrive_rel.y * smoothstep(0.0, 1.0, p)
	return _sun_pos + Vector3(sin(ang) * r, plane_y, cos(ang) * r)

## Hohmann half-ellipse from the departure point to the arrival point, both fixed at launch.
##
## Pure, and constant for the whole flight: the same p always gives the same place, so the line
## drawn along it IS the path the craft will fly, and sampling it two hundred times to draw that
## line costs the arc nothing.
func _arc_point(p: float) -> Vector3:
	# Floor the arrival radius so a Sun-targeted transfer (arriving at the centre) can't drive
	# the transfer eccentricity to exactly 1.0 -> 0/0 -> NaN position.
	var r2: float = maxf(_arrive_radius, 0.5)
	var r1: float = _depart_radius

	var a: float = (r1 + r2) * 0.5
	var e: float = absf(r2 - r1) / maxf(r1 + r2, 1.0e-4)
	# theta runs 0->pi (outward: periapsis->apoapsis) or pi->2pi (inward), so the
	# radius starts at r1 and ends exactly at r2 in either direction.
	var theta: float = (0.0 if _outward else PI) + p * PI
	var r: float = a * (1.0 - e * e) / (1.0 + e * cos(theta))

	var ang: float = _depart_angle + _sweep * p
	var pos: Vector3 = _sun_pos + Vector3(sin(ang) * r, 0.0, cos(ang) * r)

	# Hook onto the parking orbit over the last quarter, so the craft arrives moving the way it
	# will be moving once it is in orbit rather than turning on the spot at the end.
	if p >= 0.75:
		pos += _orbit_offset(_park_radius, _orbit_entry_angle) * smoothstep(0.75, 1.0, p)
	return pos

# ── Phase: orbit ─────────────────────────────────────────────────────────────────

func _process_orbit(delta_days: float) -> void:
	_orbit_angle += TAU * delta_days / ORBIT_PERIOD_DAYS * _orbit_dir
	_set_craft_pos(_orbit_point(_park_radius))

## A circular orbit around the target, tilted about the X axis so it reads as an
## ellipse rather than an edge-on line from the default camera.
func _orbit_point(radius: float) -> Vector3:
	return _target.global_position + _orbit_offset(radius, _orbit_angle)

## Offset from the target's centre to a point on the tilted parking orbit at the
## given orbital angle.  Shared by the transfer-arc insertion blend and the
## ORBIT/LANDING phases so they line up exactly at angle 0.
func _orbit_offset(radius: float, angle: float) -> Vector3:
	var cx: float = cos(angle) * radius
	var cz: float = sin(angle) * radius
	return Vector3(cx, cz * _tilt_sin, cz * _tilt_cos)

# ── Phase: landing ───────────────────────────────────────────────────────────────

func _process_landing(delta_days: float) -> void:
	_land_days += delta_days
	var p: float = clampf(_land_days / LAND_DESCEND_DAYS, 0.0, 1.0)
	_orbit_angle += TAU * delta_days / (ORBIT_PERIOD_DAYS * 0.5) * _orbit_dir
	var radius: float = lerpf(_park_radius, _target.scale.x * 0.9, p)
	_set_craft_pos(_orbit_point(radius))
	if p >= 1.0:
		_state = State.DONE
		queue_free()

# ── Craft + trail positioning ────────────────────────────────────────────────────

func _set_craft_pos(pos: Vector3) -> void:
	if _dot:
		_dot.global_position = pos


## Where the craft actually is.  The node itself stays put and only its dot moves, so anything
## asking where the craft is (a test, a camera, a UI marker) has to ask for this rather than the
## node's own transform.
func craft_position() -> Vector3:
	return _dot.global_position if _dot else global_position

# ── Visibility (mirror the planets: hidden when frozen unless paused) ─────────────

func _sync_visibility() -> void:
	visible = _board_visible and (SolarSystem.solar_system_active \
		or SolarSystem.paused or SolarSystem.ui_paused)

## Drawn or not: a craft belongs to the launch board and is shown only while it is open.
func set_board_visible(on: bool) -> void:
	_board_visible = on
	_sync_visibility()

func board_visible() -> bool:
	return _board_visible

## Show this craft's whole plan as a dashed line - what the player gets for clicking this
## launch in the list.  Nothing is built until the first time one is asked for.
func set_path_shown(on: bool) -> void:
	if on == _path_shown:
		return
	_path_shown = on
	_path_accum = 0.0
	if on:
		_ensure_path()
		_rebuild_path()
	if _path:
		_path.visible = on

func path_shown() -> bool:
	return _path_shown

# ── The planned path ─────────────────────────────────────────────────────────────

## The whole plan in world space, departure to arrival, as `samples + 1` points.
##
## Three kinds of plan, because there are three kinds of flight.  A swarm or berth delivery
## glides down its lane-entry ellipse; a local orbit insertion never cruises anywhere at all,
## so its plan is the parking orbit it settles into; everything else flies the transfer arc.
##
## Pure in all three: asking a craft where it is going does not move it.
func path_points(samples: int = PATH_SAMPLES) -> PackedVector3Array:
	var out := PackedVector3Array()
	if not _started or _target == null or not is_instance_valid(_target):
		return out
	var n: int = maxi(samples, 2)
	if _is_swarm:
		for i in range(n + 1):
			out.append(_lane_point(float(i) / float(n)))
		return out
	if _local:
		for i in range(n + 1):
			out.append(_target.global_position
				+ _orbit_offset(_park_radius, TAU * float(i) / float(n)))
		return out
	for i in range(n + 1):
		out.append(_arc_point(float(i) / float(n)))
	return out

func _ensure_path() -> void:
	if _path != null:
		return
	_path = MeshInstance3D.new()
	_path.name = "PlannedPath"
	_path.mesh = ImmediateMesh.new()
	# Its vertices ARE world coordinates, so the instance must not inherit anybody's transform.
	# The craft node sits at the origin and only its dot is moved, but the parent it is added
	# to need not, and a planet certainly does not.
	_path.top_level = true
	_path.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := _unlit_mat(PATH_COLOR, true)
	# The dashes are open-ended tubes seen from any side, so neither face can be dropped.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_path.material_override = mat
	add_child(_path)

## Cut the plan into dashes, evenly in ARC LENGTH, and build each as a short tube.
func _rebuild_path() -> void:
	if _path == null:
		return
	var mesh := _path.mesh as ImmediateMesh
	if mesh == null:
		return
	mesh.clear_surfaces()
	var pts := path_points()
	if pts.size() < 2:
		return
	# Where each sample sits along the path, so a dash is a span of LENGTH rather than a span
	# of flight fraction: the arc's geometric speed varies along itself, and dashing by fraction
	# alone piles them up at the slow end.
	var cum := PackedFloat32Array()
	cum.resize(pts.size())
	cum[0] = 0.0
	for i in range(1, pts.size()):
		cum[i] = cum[i - 1] + pts[i].distance_to(pts[i - 1])
	var total: float = cum[pts.size() - 1]
	if total <= 0.0:
		return
	var period: float = total / float(PATH_DASHES)
	var ink: float = period * PATH_DUTY
	var verts := PackedVector3Array()
	for i in range(1, pts.size()):
		# The little segment's MIDPOINT decides whether it is ink or gap, so no dash comes out
		# half-length from where the samples happen to fall against the period.
		if fmod((cum[i] + cum[i - 1]) * 0.5, period) < ink:
			_tube_segment(verts, pts[i - 1], pts[i])
	if verts.is_empty():
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for v: Vector3 in verts:
		mesh.surface_add_vertex(v)
	mesh.surface_end()

## One segment of a dash, as a closed tube from a to b appended to `verts`.
##
## The cross-section frame is built from the segment's own direction, not from the world radial
## the orbit ribbons use: a parking orbit runs ACROSS that radial, which would flatten the tube
## to an edge-on ribbon exactly where the craft arrives.
func _tube_segment(verts: PackedVector3Array, a: Vector3, b: Vector3) -> void:
	var dir: Vector3 = b - a
	var len2: float = dir.length_squared()
	if len2 < 1.0e-12:
		return
	dir /= sqrt(len2)
	var side: Vector3 = dir.cross(Vector3.UP)
	if side.length_squared() < 1.0e-9:
		side = dir.cross(Vector3.RIGHT)   # straight up or down: any perpendicular will do
	side = side.normalized()
	var up: Vector3 = side.cross(dir)
	for j in range(PATH_RING_SEGS):
		var a0: float = TAU * float(j)     / float(PATH_RING_SEGS)
		var a1: float = TAU * float(j + 1) / float(PATH_RING_SEGS)
		var r0: Vector3 = (cos(a0) * side + sin(a0) * up) * PATH_TUBE_R
		var r1: Vector3 = (cos(a1) * side + sin(a1) * up) * PATH_TUBE_R
		verts.append(a + r0); verts.append(b + r0); verts.append(b + r1)
		verts.append(a + r0); verts.append(b + r1); verts.append(a + r1)

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

## How fast a body sweeps round the Sun, in radians per game-day.
##
## Measured off the body's own prediction, one day apart, rather than read out of its orbital
## elements: that way it is right for the Keplerian planets and for the fallback circular ones
## without either having to expose its working, and it is right at the body's CURRENT point on
## an eccentric orbit rather than on average.
func _angular_rate(body: Planet) -> float:
	var a: Vector3 = body.position_in_days(0.0) - _sun_pos
	var b: Vector3 = body.position_in_days(1.0) - _sun_pos
	return _prograde_sweep(atan2(a.x, a.z), atan2(b.x, b.z))

## Positive (prograde) angular distance from a to b in [0, TAU).
func _prograde_sweep(a: float, b: float) -> float:
	var d: float = fmod(b - a, TAU)
	if d < 0.0:
		d += TAU
	return d

## The orbit-ring angle whose velocity is already tangent to the heliocentric arrival velocity,
## so there is no direction flip at insertion, and the direction that goes with it: (dir, angle).
##
## A function of where the arc ENDS and of nothing else, which is what lets the drawn plan and
## the flight agree about the hook on the end of it.
static func _insertion_entry(ang_final: float) -> Vector2:
	var sf: float = sin(ang_final)
	var cf: float = cos(ang_final)
	if sf > 0.0:
		return Vector2(-1.0, atan2(cf, sf))
	return Vector2(1.0, atan2(-cf, -sf))
