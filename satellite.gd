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
## The arc is live — it homes on a target that keeps orbiting — but a plan does not need
## re-striking sixty times a second.
const PATH_REBUILD_SEC: float = 0.2

enum State { TRANSFER, ORBIT, LANDING, DONE }

# ── Public config (set by spawner before begin_transfer) ─────────────────────────
var arrival_mode: String = "orbit"
var orbit_center: Node3D = null
## For arrival_mode == "swarm": the fixed swarm-slot world position the craft flies to,
## then removes itself (the deployed collector takes its place).
var swarm_target_pos: Vector3 = Vector3.ZERO
## Reserved slot index, so the craft can home on the slot's LIVE position as the lane rotates
## rather than on where it was when the launch was ordered.  -1 falls back to the snapshot.
var swarm_slot_index: int = -1
## Where the reserved slot is NOW, for craft flying to something other than a swarm slot (an
## orbital-lane berth, say).  Takes precedence over swarm_slot_index when set; returns a Vector3.
var slot_provider: Callable = Callable()
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
## every frame in _transfer_point() is pure overhead.
var _sun_pos:       Vector3 = Vector3.ZERO

# ── Continuously-unwrapped heliocentric sweep to the (moving) target ──────────────
## Prograde angular distance from departure to the target's live angle.  Kept
## continuous frame-to-frame so the arc never snaps by a full revolution when the
## target crosses the departure angle (the 0/TAU branch point of a wrapped sweep).
var _sweep:      float = 0.0
var _sweep_init: bool  = false

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
	_outward       = target.get_visual_radius() >= _depart_radius

	_park_radius = maxf(target.scale.x * PARKING_SCALE, PARKING_MIN)
	_orbit_tilt  = deg_to_rad(ORBIT_TILT_DEG)
	_tilt_sin    = sin(_orbit_tilt)
	_tilt_cos    = cos(_orbit_tilt)

	_elapsed_days = clampf(elapsed_days, 0.0, _flight_days)
	_started      = true
	_sweep_init   = false   # seeded on the first _transfer_point() call below
	_local        = origin == target

	# Swarm deployment: fly straight to the reserved slot, then vanish (the collector
	# appears there).  Handled before the origin==target shortcut below.
	_is_swarm  = arrival_mode == "swarm"
	_start_pos = origin.global_position
	var p0: float = _elapsed_days / _flight_days
	if _is_swarm:
		_state = State.TRANSFER
		_set_craft_pos(_swarm_point(p0))
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
	_set_craft_pos(_transfer_point(p0))

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

	# After the state pass, so the line is cut from the same sweep the dot was placed with.
	if _path_shown and visible and _state != State.DONE:
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
		_set_craft_pos(_swarm_point(p))
		if p >= 1.0:
			arrived.emit("swarm")
			_state = State.DONE
			queue_free()
		return

	_set_craft_pos(_transfer_point(p))

	if p >= 1.0:
		arrived.emit(arrival_mode)
		# _orbit_dir and _orbit_entry_angle are already current from _transfer_point.
		if arrival_mode == "land":
			_state     = State.LANDING
			_land_days = 0.0
		else:
			_state       = State.ORBIT
			_orbit_angle = _orbit_entry_angle

## Heliocentric transfer down to a swarm slot.
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
func _swarm_point(p: float) -> Vector3:
	# Track the LIVE slot: the lane keeps rotating during the flight, so homing on a snapshot
	# would arrive where the slot used to be and jump on hand-off to the collector.
	var slot: Vector3 = _live_swarm_slot()
	var srel: Vector3 = slot - _sun_pos
	# Unwrap the prograde sweep so a rotating lane does not snap the path by +-TAU.
	_track_sweep(atan2(srel.x, srel.z))
	return _lane_point(p, slot)

## The lane-entry arc at fraction p, off the sweep as it currently stands.
##
## Pure, and the slot is passed in rather than re-read: drawing the plan samples this a couple
## of hundred times, and every one of those would otherwise be a round trip to the swarm
## renderer -- and would carry the flight's own sweep along with it.
func _lane_point(p: float, slot: Vector3) -> Vector3:
	var srel: Vector3 = slot - _sun_pos
	var r2: float = maxf(srel.length(), 0.01)
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
	var plane_y: float = srel.y * smoothstep(0.0, 1.0, p)
	return _sun_pos + Vector3(sin(ang) * r, plane_y, cos(ang) * r)

## Current world position of the reserved slot, falling back to the snapshot taken at launch
## if the swarm renderer is not reachable (loading, or a save restored mid-flight).
func _live_swarm_slot() -> Vector3:
	if slot_provider.is_valid():
		var p: Variant = slot_provider.call()
		if p is Vector3:
			return p
	if swarm_slot_index >= 0 and orbit_center != null:
		var planets: Node = orbit_center.get_parent()
		if planets != null and planets.has_method("swarm_slot_world_pos"):
			return planets.swarm_slot_world_pos(swarm_slot_index)
	return swarm_target_pos

## Hohmann half-ellipse whose far end is recomputed every frame from the target's
## current radius & angle, so the craft homes onto the moving planet.
func _transfer_point(p: float) -> Vector3:
	var trel: Vector3 = _target.global_position - _sun_pos
	# Unwrap the prograde sweep so it varies continuously as the target orbits,
	# instead of snapping by +-TAU when the target passes the departure angle.
	_track_sweep(atan2(trel.x, trel.z))
	# Latched for the ORBIT and LANDING phases, which carry on from where the arc ends.
	# Only from three-quarters of the way out, where the blend in _arc_point can first
	# move the craft: before that this is trig nothing reads.
	if p >= 0.75:
		var ins: Vector2 = _insertion_entry(_depart_angle + _sweep)
		_orbit_dir         = ins.x
		_orbit_entry_angle = ins.y
	return _arc_point(p)

## The transfer arc at fraction p, off the sweep as it currently stands.
##
## Pure, so that asking for the plan cannot disturb the flight following it: the sweep is
## carried by _track_sweep above, and the insertion hook by _insertion_entry, both of which
## depend on the target's live position and neither of which depends on p.
func _arc_point(p: float) -> Vector3:
	var trel: Vector3 = _target.global_position - _sun_pos
	# Floor the target radius so a Sun-targeted transfer (target at the centre)
	# can't drive the transfer eccentricity to exactly 1.0 → 0/0 → NaN position.
	var r2: float = maxf(trel.length(), 0.5)
	var r1: float = _depart_radius

	var a: float = (r1 + r2) * 0.5
	var e: float = absf(r2 - r1) / maxf(r1 + r2, 1.0e-4)
	# theta runs 0→π (outward: periapsis→apoapsis) or π→2π (inward), so the
	# radius starts at r1 and ends exactly at r2 in either direction.
	var theta: float = (0.0 if _outward else PI) + p * PI
	var r: float = a * (1.0 - e * e) / (1.0 + e * cos(theta))

	var ang: float = _depart_angle + _sweep * p
	var pos: Vector3 = _sun_pos + Vector3(sin(ang) * r, 0.0, cos(ang) * r)

	# The velocity-aligned insertion offset is blended in by smoothstep(0.75, 1.0, p),
	# which is zero for the first three-quarters of the flight — so skip the atan2 /
	# trig that compute it until it can actually affect the position.
	if p >= 0.75:
		var ins: Vector2 = _insertion_entry(_depart_angle + _sweep)
		pos += _orbit_offset(_park_radius, ins.y) * smoothstep(0.75, 1.0, p)
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
		var slot: Vector3 = _live_swarm_slot()
		for i in range(n + 1):
			out.append(_lane_point(float(i) / float(n), slot))
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

## Positive (prograde) angular distance from a to b in [0, TAU).
func _prograde_sweep(a: float, b: float) -> float:
	var d: float = fmod(b - a, TAU)
	if d < 0.0:
		d += TAU
	return d

## Carry the unwrapped prograde sweep to the target's current angle.
##
## THE one stateful step of the arc, kept apart from the point functions so that drawing the
## plan - which samples them a couple of hundred times a go - cannot nudge the flight.
func _track_sweep(a2: float) -> void:
	var raw: float = _prograde_sweep(_depart_angle, a2)
	if not _sweep_init:
		_sweep      = raw
		_sweep_init = true
		return
	while raw - _sweep >  PI: raw -= TAU
	while raw - _sweep < -PI: raw += TAU
	_sweep = raw

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
