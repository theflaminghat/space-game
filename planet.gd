class_name Planet
extends MeshInstance3D

enum Type { STAR, GAS_GIANT, ROCKY }

@export var type: Type = Type.ROCKY

## Semi-major axis in AU before _ready() transforms it into the log-scaled
## visual radius.  Used only as a fallback when no PlanetData entry exists.
@export var orbit_radius: float = 1.0

## Fallback initial orbit angle in radians (used when no PlanetData entry).
@export var orbit_offset: float = 0.0

## Fallback speed multiplier relative to Earth's period (used when no PlanetData entry).
@export var speed: float = 1.0

# ── Public state (read by satellite spawner and other systems) ─────────────────

var _orbit_line: MeshInstance3D = null
var _orbit_line_built: bool = false  # deferred until first _process tick
var _rings: MeshInstance3D = null    # planetary rings (gas giants only)
var _blur_torus: MeshInstance3D = null  # translucent motion-blur ring shown post-freeze
var _body_visual_radius: float = 0.0    # apparent radius (game units); sizes the blur tube

## Cosmetic moons orbiting this body in its local (scaled) frame, so they track and
## size with the planet automatically.  Each entry: { node, radius, speed, angle, incl }.
var _moons: Array = []

## How many moons each body shows, by lowercase name.  Roughly mirrors the major
## satellites of each world; bodies absent here (Mercury, Venus, the Sun) get none.
const MOON_COUNTS := {
	"earth": 1, "mars": 2, "jupiter": 4, "saturn": 4, "uranus": 3, "neptune": 2,
}

## Per-gas-giant ring appearance.  Radii are multiples of the planet's own
## radius; tilt matches each body's real axial tilt (Uranus rings are nearly
## perpendicular to the ecliptic).  Alpha sets overall ring prominence.
## ── Stellar evolution (star only) ────────────────────────────────────────────
## Accurate solar evolutionary track.  Each entry:
##   [year, emission_color, scale_multiplier, emission_energy_mult]
##
## Scale × SUN_RADIUS_BASE_AU (0.00465 AU) = sun radius in AU at that year.
## Engulfment thresholds (orbital AU / 0.00465):
##   Mercury 0.387 AU → scale  83   Venus 0.723 AU → scale 156
##   Earth   1.000 AU → scale 215   Mars  1.524 AU → scale 328
##
## Key phases (all years relative to game year 2026 ≈ 0):
##   0 – 1 B yr   : stable main sequence (barely changes)
##   1 B – 5.4 B  : slow brightening; luminosity +30%, radius negligible
##   5.4 B        : hydrogen exhaustion — leaves main sequence (subgiant)
##   5.4 B – 7 B  : subgiant branch, swells to ~2× and cools slightly
##   7 B – 7.59 B : Red Giant Branch (RGB) ascent — rapid expansion
##                  Mercury engulfed ~7.40 B, Venus ~7.54 B, Earth ~7.59 B
##   7.59 B       : RGB tip / HELIUM FLASH — sun SHRINKS back to ~10× and turns
##                  blue-white (a dramatic visible reversal)
##   7.59 – 7.7 B : Core Helium Burning (CHeB / horizontal branch) ~100 M yr stable
##   7.7 – 8.0 B  : Early Asymptotic Giant Branch (AGB) expansion begins again
##   8.0 – 8.2 B  : AGB thermal pulses — peak radius ~1.8 AU (Mars engulfed ~8.12 B)
##   8.2 B        : Sun ejects outer envelope → planetary nebula + white dwarf
##                  All remaining solar-system colonies sterilised.
const SUN_STAGES: Array = [
	# Each entry: [year, color, visual_mult, emiss_mult, solar_radii]
	#
	# visual_mult  — multiplied by _sun_base_scale (= log(16) ≈ 2.773) for display.
	#                _sun_base_scale × visual_mult × sphere_radius (0.5) = game-unit radius.
	#                Calibrated so visual_mult 16.0 = Earth orbit ring (22.18 game units).
	#                Proportional formula: visual_mult ≈ solar_radii × (16.0 / 215).
	#
	# Orbit ring radii and visual_mult needed to reach them:
	#   Mercury 10.47 game units → 7.55×    Venus 17.42 → 12.57×
	#   Earth   22.18 game units → 16.00×   Mars  29.63 → 21.37× (NOT reached — AGB only ~12.6×)
	#
	# solar_radii  — AU-radius physics only (Game.gd/_get_sun_radius_au).
	#
	# Timeline notes:
	#   RGB tip (7.59B): peak expansion, Earth engulfed.
	#   Helium flash (7.591B): rapid collapse back to ~10 solar radii — still 3.5× modern sun,
	#     NOT tiny.  The 1 M yr window between RGB tip and CHeB represents the flash + settling.
	#   AGB tip (8.2B): second expansion peaks at ~170 solar radii (~0.79 AU).
	#     Mars at 1.524 AU is NOT engulfed.  Outer-system colonies survive until the
	#     planetary nebula fires at PLANETARY_NEBULA_YEAR (8.21B), which sterilises everything
	#     via intense UV/X-ray radiation regardless of orbital distance.
	[0,              Color(1.00, 0.95, 0.80),   1.00,  1.0,    1.0],  # modern Sun
	[1_000_000_000,  Color(1.00, 0.92, 0.72),   1.00,  1.1,    1.05], # brightening MS — imperceptible change
	[5_400_000_000,  Color(1.00, 0.84, 0.45),   1.15,  1.4,    1.5],  # subgiant begins
	[7_000_000_000,  Color(1.00, 0.60, 0.18),   3.50,  2.5,   10.0],  # lower RGB (≈10 SR)
	[7_500_000_000,  Color(1.00, 0.32, 0.06),   9.50,  5.5,  100.0],  # upper RGB — past Mercury, near Venus
	[7_590_000_000,  Color(0.96, 0.18, 0.04),  16.00,  8.0,  215.0],  # RGB tip — Earth orbit
	[7_591_000_000,  Color(0.60, 0.82, 1.00),   3.50, 14.0,   10.0],  # helium flash — shrinks to ~lower RGB size, turns blue-white
	[7_700_000_000,  Color(0.90, 0.88, 0.80),   3.50,  3.5,   11.0],  # CHeB stable (~100 M yr, ~11 SR)
	[8_000_000_000,  Color(1.00, 0.58, 0.20),   5.50,  4.0,   50.0],  # early AGB — past Mercury again
	[8_200_000_000,  Color(0.94, 0.14, 0.03),  12.60,  7.0,  170.0],  # AGB tip (~170 SR = 0.79 AU, past Venus but NOT Mars)
	[8_210_000_000,  Color(0.62, 0.80, 1.00),   0.05, 22.0,    0.05], # planetary nebula → white dwarf
]

## Base scale stored at scene-load so we can multiply cleanly.
var _sun_base_scale: Vector3 = Vector3.ONE
var _sun_mat: StandardMaterial3D = null
var _sun_last_year: int = -1   # throttle updates to once per year

## Representative colour for each planet's post-freeze motion-blur ring.
const PLANET_BLUR_COLORS: Dictionary = {
	"mercury": Color(0.62, 0.57, 0.50),
	"venus":   Color(0.92, 0.80, 0.55),
	"earth":   Color(0.32, 0.52, 0.92),
	"mars":    Color(0.82, 0.42, 0.26),
	"jupiter": Color(0.82, 0.71, 0.56),
	"saturn":  Color(0.86, 0.78, 0.60),
	"uranus":  Color(0.60, 0.85, 0.90),
	"neptune": Color(0.36, 0.50, 0.95),
}

const RING_SEGMENTS: int = 96
const RING_SPECS: Dictionary = {
	"jupiter": {"inner": 1.35, "outer": 1.80, "bands": 3, "tilt_deg":  3.1, "color": Color(0.78, 0.72, 0.62, 0.10)},
	"saturn":  {"inner": 1.28, "outer": 2.30, "bands": 8, "tilt_deg": 26.7, "color": Color(0.88, 0.80, 0.62, 0.55)},
	"uranus":  {"inner": 1.55, "outer": 2.00, "bands": 4, "tilt_deg": 97.8, "color": Color(0.58, 0.78, 0.80, 0.24)},
	"neptune": {"inner": 1.70, "outer": 2.20, "bands": 4, "tilt_deg": 28.3, "color": Color(0.52, 0.62, 0.84, 0.18)},
}

## Current ecliptic longitude in radians.  For Keplerian planets this equals
## (true anomaly ν) + (longitude of periapsis ω̄).
var orbit_angle: float = 0.0

## Log-scaled visual semi-major axis in game units = log(a_AU + 1) * orbit_radius_mult.
## Kept constant so the satellite spawner can use it for Hohmann transfer sizing.
var orbit_radius_mult: float = 32.0
var size_mult: float = 1.0

const EARTH_ORBIT_DAYS: float = 365.25

## Calendar year the orbital epoch (DAYS_J2000_TO_GAME_EPOCH → 1945-01-01) refers
## to.  Used to recompute true positions from a target year when motion is frozen.
const GAME_EPOCH_YEAR: int = 1945

# ── Keplerian state ────────────────────────────────────────────────────────────
var _use_kepler: bool = false

## True AU semi-major axis stored separately for Kepler calculations.
var _semi_major_axis_au: float = 0.0

## Orbital eccentricity e.
var _eccentricity: float = 0.0
## Pre-computed sqrt(1 ± e) factors used every frame in _update_kepler_position.
var _sqrt_1pe: float = 1.0   # sqrt(1 + e)
var _sqrt_1me: float = 1.0   # sqrt(1 - e)

## Longitude of periapsis ω̄ (radians) at the game epoch.
## orbit_angle = true_anomaly + _long_periapsis_rad
var _long_periapsis_rad: float = 0.0

## Current mean anomaly M (radians), advanced each frame by _mean_motion_rad_per_day.
var _mean_anomaly_rad: float = 0.0

## Mean anomaly at the game epoch (1945-01-01), kept so we can recompute the true
## position for any year when motion is frozen (past ORBIT_FREEZE_YEAR).
var _mean_anomaly_epoch: float = 0.0

## Mean motion n = 2π / T  (radians per game-day).
var _mean_motion_rad_per_day: float = 0.0

## Actual visual radius at the current true anomaly (updated every frame).
## Use this instead of orbit_radius when the satellite needs to START exactly
## at the planet's current position rather than at the semi-major axis.
var _current_visual_radius: float = 0.0

# ──────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	SolarSystem.active_changed.connect(_sync_visibility)
	SolarSystem.paused_changed.connect(_sync_visibility)

	# Set up the star material BEFORE size is adjusted so we have a handle on it.
	if type == Type.STAR:
		var existing: Material = get_surface_override_material(0)
		if existing is StandardMaterial3D:
			_sun_mat = (existing as StandardMaterial3D).duplicate() as StandardMaterial3D
		else:
			_sun_mat = StandardMaterial3D.new()
			_sun_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_sun_mat.emission_enabled = true
		set_surface_override_material(0, _sun_mat)

	var pname: String = name.to_lower()
	if PlanetData.PLANETS.has(pname):
		_init_from_planet_data(PlanetData.PLANETS[pname])
	else:
		# Fallback: simple circular orbit with speed multiplier.
		# The log transform is applied here for ALL non-Keplerian bodies including
		# the sun, so _sun_base_scale is captured afterwards to match.
		orbit_radius = log(orbit_radius + 1.0) * orbit_radius_mult
		size_mult = log(scale.x + 1.0)
		scale = Vector3(size_mult, size_mult, size_mult)
		orbit_angle = orbit_offset
		_update_position()

	# Apparent radius in the parent (orbit) space — sizes the motion-blur tube.
	# SphereMesh AABB is the unscaled diameter; half it and apply the node scale.
	if mesh != null:
		_body_visual_radius = mesh.get_aabb().size.x * 0.5 * scale.x

	# Capture the log-scaled base size, then apply the initial stellar appearance.
	if type == Type.STAR:
		_sun_base_scale = scale
		_update_sun_appearance(SolarSystem.current_year)

	# Orbit line is built on the first _process tick so that add_child() runs
	# after the full scene tree has settled (not during _ready() propagation).

	_sync_visibility()

func _init_from_planet_data(data: Dictionary) -> void:
	_semi_major_axis_au = float(data["semi_major_axis_au"])
	_eccentricity       = float(data["eccentricity"])
	_long_periapsis_rad = deg_to_rad(float(data["long_periapsis_deg"]))

	# ── Mean motion from Kepler's 3rd law: T = 365.25 × a^1.5 days ──────────
	var period_days: float = EARTH_ORBIT_DAYS * pow(_semi_major_axis_au, 1.5)
	_mean_motion_rad_per_day = TAU / period_days

	# ── Mean anomaly at game start (J2000.0 + DAYS_J2000_TO_GAME_EPOCH) ───────
	# M = L − ω̄  (mean longitude minus longitude of periapsis)
	# Propagate forward from J2000.0 using the secular mean-anomaly rate:
	#   dM/dt = dL/dt − dω̄/dt  (degrees per Julian century)
	var M0_deg: float = float(data["mean_longitude_deg"]) - float(data["long_periapsis_deg"])
	var dM_deg_per_cy: float = float(data["dmL_deg_per_cy"]) - float(data["dlong_peri_deg_per_cy"])
	var t_cy: float = PlanetData.DAYS_J2000_TO_GAME_EPOCH / 36525.0
	var M_start_deg: float = M0_deg + dM_deg_per_cy * t_cy

	_mean_anomaly_rad = deg_to_rad(fmod(M_start_deg, 360.0))
	if _mean_anomaly_rad < 0.0:
		_mean_anomaly_rad += TAU
	_mean_anomaly_epoch = _mean_anomaly_rad

	# ── Pre-compute constant sqrt factors used every frame in true-anomaly calc ──
	_sqrt_1pe = sqrt(1.0 + _eccentricity)
	_sqrt_1me = sqrt(1.0 - _eccentricity)

	# ── Log-scaled visual semi-major axis (constant, for satellite compat) ────
	orbit_radius = log(_semi_major_axis_au + 1.0) * orbit_radius_mult
	_current_visual_radius = orbit_radius  # initial value; refined on first _update_kepler_position

	# ── Visual size (same log-scale as original code) ─────────────────────────
	size_mult = log(scale.x + 1.0)
	scale = Vector3(size_mult, size_mult, size_mult)

	_use_kepler = true
	_update_kepler_position()

## Sample the orbit centreline as `segments`+1 points (closed: last == first).
## Kepler orbits trace their true ellipse; fallback bodies trace a circle.
## Shared by the orbit ribbon and the post-freeze motion-blur torus.
func _orbit_path_points(segments: int) -> PackedVector3Array:
	var pts := PackedVector3Array()
	pts.resize(segments + 1)
	if _use_kepler:
		for i in range(segments + 1):
			var nu := (float(i) / float(segments)) * TAU
			var r_au := _semi_major_axis_au \
				* (1.0 - _eccentricity * _eccentricity) \
				/ (1.0 + _eccentricity * cos(nu))
			var r_vis := log(r_au + 1.0) * orbit_radius_mult
			var angle := nu + _long_periapsis_rad
			pts[i] = Vector3(r_vis * sin(angle), 0.0, r_vis * cos(angle))
	else:
		for i in range(segments + 1):
			var angle := (float(i) / float(segments)) * TAU
			pts[i] = Vector3(orbit_radius * sin(angle), 0.0, orbit_radius * cos(angle))
	return pts

## Build a translucent tube swept along the orbit — the planet smeared into a ring
## once it is spinning round its orbit faster than the eye can follow (post-freeze).
func _create_blur_torus() -> void:
	const PATH_SEGS: int = 128
	const RING_SEGS: int = 8
	var pts := _orbit_path_points(PATH_SEGS)
	# Tube cross-section diameter == planet diameter, so the smeared band is exactly
	# as thick as the body it represents.  tube_r is the cross-section *radius*,
	# which therefore equals the planet's visual radius.
	var tube_r: float = maxf(_body_visual_radius, 0.01)
	var up := Vector3(0.0, 1.0, 0.0)

	var verts := PackedVector3Array()
	var r_max: float = 0.0
	for i in range(PATH_SEGS):
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		# Cross-section spans the radial + vertical directions, so the tube hugs the
		# orbit plane.  Radial dir ≈ the point's own XZ direction from the centre.
		var s0: Vector3 = Vector3(p0.x, 0.0, p0.z)
		s0 = s0.normalized() if s0.length_squared() > 1e-9 else Vector3(1, 0, 0)
		var s1: Vector3 = Vector3(p1.x, 0.0, p1.z)
		s1 = s1.normalized() if s1.length_squared() > 1e-9 else Vector3(1, 0, 0)
		r_max = maxf(r_max, Vector2(p0.x, p0.z).length())
		for j in range(RING_SEGS):
			var a0 := TAU * float(j)       / float(RING_SEGS)
			var a1 := TAU * float(j + 1)   / float(RING_SEGS)
			var o00 := p0 + (cos(a0) * s0 + sin(a0) * up) * tube_r
			var o01 := p0 + (cos(a1) * s0 + sin(a1) * up) * tube_r
			var o10 := p1 + (cos(a0) * s1 + sin(a0) * up) * tube_r
			var o11 := p1 + (cos(a1) * s1 + sin(a1) * up) * tube_r
			verts.append(o00); verts.append(o10); verts.append(o11)
			verts.append(o00); verts.append(o11); verts.append(o01)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var tmesh := ArrayMesh.new()
	tmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	# Very muted, low-saturation tint at low alpha so the ring reads as a faint,
	# dull smear rather than a solid coloured band.
	var base: Color = PLANET_BLUR_COLORS.get(name.to_lower(), Color(0.70, 0.70, 0.75))
	var grey: float = base.get_luminance()
	var col := base.lerp(Color(grey, grey, grey), 0.75)   # heavily desaturated → duller
	col = col.darkened(0.20)                               # dimmer
	col.a = 0.06                                           # lower opacity
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = col
	tmesh.surface_set_material(0, mat)

	_blur_torus = MeshInstance3D.new()
	_blur_torus.mesh        = tmesh
	_blur_torus.name        = name + "_blur_torus"
	_blur_torus.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ext: float = r_max + tube_r
	_blur_torus.custom_aabb = AABB(
		Vector3(-ext, -tube_r, -ext),
		Vector3(ext * 2.0, tube_r * 2.0, ext * 2.0))
	_blur_torus.visible = false
	get_parent().add_child(_blur_torus)

func _create_orbit_line() -> void:
	var segments := 128
	var pts := _orbit_path_points(segments)
	var r_max: float = 0.0
	for p in pts:
		r_max = maxf(r_max, Vector2(p.x, p.z).length())

	# Build a triangle-based ribbon instead of line primitives.
	# Vulkan (Godot 4 Forward+) draws PRIMITIVE_LINE_STRIP as 1-px lines that
	# disappear at any distance or with MSAA enabled.  Two interlocking ribbons
	# — one flat in the XZ plane (visible top-down), one vertical (visible from
	# the side) — stay visible from every camera angle.
	const FLAT_W: float = 0.02   # XZ-plane ribbon half-width (game units)
	const VERT_H: float = 0.02   # vertical ribbon half-height (game units)

	var tri_verts := PackedVector3Array()
	tri_verts.resize(segments * 12)  # 2 ribbons × 2 triangles × 3 verts per segment
	var vi: int = 0

	for i in range(segments):
		var p1: Vector3 = pts[i]
		var p2: Vector3 = pts[i + 1]
		var d: Vector3  = p2 - p1
		if d.length_squared() < 1e-12:
			vi += 12
			continue
		d = d.normalized()
		var perp: Vector3 = Vector3(-d.z, 0.0, d.x) * FLAT_W
		var up:   Vector3 = Vector3(0.0, VERT_H, 0.0)

		# Flat XZ ribbon
		tri_verts[vi]     = p1 - perp; tri_verts[vi + 1] = p1 + perp; tri_verts[vi + 2] = p2 - perp
		tri_verts[vi + 3] = p1 + perp; tri_verts[vi + 4] = p2 + perp; tri_verts[vi + 5] = p2 - perp
		# Vertical ribbon
		tri_verts[vi + 6]  = p1 - up; tri_verts[vi + 7]  = p1 + up; tri_verts[vi + 8]  = p2 - up
		tri_verts[vi + 9]  = p1 + up; tri_verts[vi + 10] = p2 + up; tri_verts[vi + 11] = p2 - up
		vi += 12

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = tri_verts

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.70, 1.0, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)

	_orbit_line = MeshInstance3D.new()
	_orbit_line.mesh = mesh
	_orbit_line.name = name + "_orbit_line"
	_orbit_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_orbit_line.custom_aabb = AABB(
		Vector3(-r_max, -VERT_H, -r_max),
		Vector3(r_max * 2.0, VERT_H * 2.0, r_max * 2.0)
	)
	get_parent().add_child(_orbit_line)

## Show stars always; show other bodies only when the solar system is active
## or either pause flag is set (so players can still inspect planets when frozen).
func _sync_visibility() -> void:
	if type == Type.STAR:
		visible = true
		return
	# Body shows during normal sim, or whenever paused so the player can inspect it.
	var show := SolarSystem.solar_system_active or SolarSystem.paused or SolarSystem.ui_paused
	visible = show
	# When motion is frozen (past the orbit-freeze cutoff) the body normally holds
	# its last position.  If we're showing it because the player paused, snap it to
	# its true position at the snap year (chosen by Game so the viewed planet keeps
	# its place and the rest fall into their correct relative positions).
	if show and not SolarSystem.solar_system_active:
		_snap_to_year(SolarSystem.snap_year)
	# Orbit lines stay drawn even past the freeze cutoff (when the planet bodies
	# are hidden), so the system's layout remains legible.
	if _orbit_line:
		_orbit_line.visible = true
	# The motion-blur ring appears only while frozen AND fast-forwarding — i.e.
	# exactly when the discrete body is hidden, so the planet reads as a smeared
	# band whipping round its orbit too fast to resolve.
	if _blur_torus:
		_blur_torus.visible = not show

## Place the planet at the true Keplerian position it would occupy at year `y`.
## A body's mean anomaly advances by one full revolution every a^1.5 years
## (Kepler's third law), so M(y) = M_epoch + (y − epoch)·2π/a^1.5.
## Used when the simulation is frozen but the player pauses to look.
func _snap_to_year(y: float) -> void:
	if not _use_kepler:
		return
	var rad_per_year: float = TAU / pow(_semi_major_axis_au, 1.5)
	_mean_anomaly_rad = fposmod(
		_mean_anomaly_epoch + (y - float(GAME_EPOCH_YEAR)) * rad_per_year, TAU)
	_update_kepler_position()

## Returns the year nearest SolarSystem.current_year at which THIS planet would be
## at its current (frozen) position.  Snapping every planet to this year leaves this
## one exactly where it is — used to anchor the snap to the planet being viewed so
## the camera (which follows it) never jumps.
func compute_anchor_year() -> float:
	if not _use_kepler:
		return float(SolarSystem.current_year)
	var rad_per_year: float = TAU / pow(_semi_major_axis_au, 1.5)
	var period_years: float = pow(_semi_major_axis_au, 1.5)
	# Year (mod period) whose mean anomaly matches the current frozen one, then the
	# revolution k that lands nearest the current year.
	var base: float = float(GAME_EPOCH_YEAR) \
		+ (_mean_anomaly_rad - _mean_anomaly_epoch) / rad_per_year
	var k: float = round((float(SolarSystem.current_year) - base) / period_years)
	return base + k * period_years


func _process(delta: float) -> void:
	# Build orbit line once on the first frame — the scene tree is fully settled
	# by this point so add_child() and rendering-server properties work correctly.
	if not _orbit_line_built and type != Type.STAR:
		_orbit_line_built = true
		_create_orbit_line()
		_create_blur_torus()
		if type == Type.GAS_GIANT:
			_create_rings()
		_create_moons()
		_sync_visibility()

	# Stellar evolution — update once per year so it has zero per-frame cost.
	if type == Type.STAR:
		var cur_year: int = SolarSystem.current_year
		if cur_year != _sun_last_year:
			_sun_last_year = cur_year
			_update_sun_appearance(cur_year)

	if not SolarSystem.solar_system_active:
		return
	if SolarSystem.ui_paused or SolarSystem.paused:
		return
	if SolarSystem.seconds_per_day <= 0.0:
		return

	var delta_days: float = delta / SolarSystem.seconds_per_day

	if _use_kepler:
		_mean_anomaly_rad += _mean_motion_rad_per_day * delta_days
		# Wrap to [0, TAU]
		_mean_anomaly_rad = fmod(_mean_anomaly_rad, TAU)
		if _mean_anomaly_rad < 0.0:
			_mean_anomaly_rad += TAU
		_update_kepler_position()
	else:
		# Fallback: circular orbit with speed multiplier (sun, unknown bodies)
		var angular_velocity: float = (TAU / (EARTH_ORBIT_DAYS * SolarSystem.seconds_per_day)) * speed
		orbit_angle += angular_velocity * delta
		_update_position()

	# Moons spin at a steady real-time rate (cosmetic), decoupled from the wildly
	# varying sim timescale.  Only reached when the system is active and unpaused, so
	# they hold still exactly when the planet does.
	if not _moons.is_empty():
		_update_moons(delta)

# ── Keplerian position update ─────────────────────────────────────────────────

func _update_kepler_position() -> void:
	# 1. Eccentric anomaly E via Newton-Raphson on M = E − e·sin(E)
	var E: float = _solve_kepler(_mean_anomaly_rad, _eccentricity)

	# 2. True anomaly ν from E  (pre-cached sqrt factors avoid two sqrt() calls)
	var nu: float = 2.0 * atan2(
		_sqrt_1pe * sin(E * 0.5),
		_sqrt_1me * cos(E * 0.5)
	)

	# 3. Instantaneous orbital radius in AU:  r = a(1−e²) / (1 + e·cosν)
	var r_au: float = _semi_major_axis_au \
		* (1.0 - _eccentricity * _eccentricity) \
		/ (1.0 + _eccentricity * cos(nu))

	# 4. Log-scale to visual game space
	var r_vis: float = log(r_au + 1.0) * orbit_radius_mult
	_current_visual_radius = r_vis

	# 5. Ecliptic longitude in game plane:  λ = ν + ω̄
	orbit_angle = nu + _long_periapsis_rad

	position = Vector3(
		r_vis * sin(orbit_angle),
		0.0,
		r_vis * cos(orbit_angle)
	)

func _solve_kepler(M: float, e: float) -> float:
	## Newton-Raphson solution of Kepler's equation M = E − e·sin(E).
	## First-order initial guess E₀ = M + e·sin(M) cuts typical iterations
	## from 4-5 down to 2-3 for all solar-system eccentricities (e ≤ 0.21).
	var E: float = M + e * sin(M)
	for _i in range(8):
		var dE: float = (E - e * sin(E) - M) / (1.0 - e * cos(E))
		E -= dE
		if abs(dE) < 1.0e-10:
			break
	return E

# ── Fallback circular position update ────────────────────────────────────────

func _update_position() -> void:
	_current_visual_radius = orbit_radius  # circular — radius equals semi-major axis
	position = Vector3(
		orbit_radius * sin(orbit_angle),
		0.0,
		orbit_radius * cos(orbit_angle)
	)

# ── Moons ─────────────────────────────────────────────────────────────────────

## Spawn this body's cosmetic moons as children, so they live in the planet's scaled
## local frame: the body has radius 0.5 here, so orbits a few units out read as a few
## body-radii and scale with the planet.  Variety is seeded from the name so it's
## stable across runs and doesn't disturb the global RNG.
func _create_moons() -> void:
	var count: int = int(MOON_COUNTS.get(name.to_lower(), 0))
	if count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(name))
	for i in range(count):
		var radius: float = 1.3 + 0.55 * float(i) + rng.randf_range(-0.1, 0.1)
		var msize: float  = clampf(0.22 - 0.02 * float(i), 0.08, 0.22)

		var moon := MeshInstance3D.new()
		moon.name = "%s_moon_%d" % [name, i]
		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		sphere.radial_segments = 12
		sphere.rings = 6
		moon.mesh = sphere
		moon.scale = Vector3(msize, msize, msize)
		moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var mat := StandardMaterial3D.new()
		var g: float = rng.randf_range(0.55, 0.80)
		mat.albedo_color = Color(g, g, g * 0.96)
		# A little self-emission keeps moons readable even on the night side / when the
		# scene has no light reaching them.
		mat.emission_enabled = true
		mat.emission = Color(g, g, g)
		mat.emission_energy_multiplier = 0.18
		moon.set_surface_override_material(0, mat)
		add_child(moon)

		_moons.append({
			"node":   moon,
			"radius": radius,
			"speed":  rng.randf_range(0.5, 1.3) * (1.0 if i % 2 == 0 else -1.0),
			"angle":  rng.randf_range(0.0, TAU),
			"incl":   rng.randf_range(-0.35, 0.35),
		})
	_update_moons(0.0)

## Advance each moon along its tilted circular orbit in the planet's local frame.
func _update_moons(delta: float) -> void:
	for m in _moons:
		var a: float = float(m["angle"]) + float(m["speed"]) * delta
		m["angle"] = a
		var r: float = float(m["radius"])
		var incl: float = float(m["incl"])
		var z: float = r * sin(a)
		(m["node"] as Node3D).position = Vector3(
			r * cos(a),
			z * sin(incl),
			z * cos(incl)
		)

## Returns the planet's current visual distance from the orbit centre.
## For Keplerian orbits this varies with true anomaly; for circular fallback
## it equals orbit_radius (the semi-major axis).
## Satellite spawner should use this instead of orbit_radius so the craft
## starts exactly at the planet's position.
func get_visual_radius() -> float:
	return _current_visual_radius

# ── Stellar evolution ─────────────────────────────────────────────────────────

## Interpolate the Sun's emission colour, scale, and glow across SUN_STAGES.
## Only called once per game-year so it is essentially free.
func _update_sun_appearance(current_year: int) -> void:
	if _sun_mat == null:
		return

	var y: float = float(current_year)

	# Clamp to final stage if beyond the last defined year.
	var last: Array = SUN_STAGES[SUN_STAGES.size() - 1]
	if y >= float(int(last[0])):
		_sun_mat.albedo_color               = last[1] as Color
		_sun_mat.emission                   = last[1] as Color
		_sun_mat.emission_energy_multiplier = float(last[3])   # [3] = emiss_mult
		scale = _sun_base_scale * float(last[2])               # [2] = visual_mult
		return

	# Find the two surrounding stage entries.
	var lo: Array = SUN_STAGES[0]
	var hi: Array = SUN_STAGES[1]
	for i in range(SUN_STAGES.size() - 1):
		if y >= float(int(SUN_STAGES[i][0])) and y < float(int(SUN_STAGES[i + 1][0])):
			lo = SUN_STAGES[i]
			hi = SUN_STAGES[i + 1]
			break

	var span: float = float(int(hi[0])) - float(int(lo[0]))
	var t: float    = 0.0 if span <= 0.0 else clampf((y - float(int(lo[0]))) / span, 0.0, 1.0)

	# Use smoothstep so transitions ease in and out rather than snapping linearly.
	var st: float = t * t * (3.0 - 2.0 * t)

	var col:   Color = (lo[1] as Color).lerp(hi[1] as Color, st)
	var vscl:  float = lerpf(float(lo[2]), float(hi[2]), st)   # visual game-scale mult
	var emiss: float = lerpf(float(lo[3]), float(hi[3]), st)   # emission energy mult

	_sun_mat.albedo_color               = col
	_sun_mat.emission                   = col
	_sun_mat.emission_energy_multiplier = emiss
	scale = _sun_base_scale * vscl

# ── Planetary rings (gas giants) ──────────────────────────────────────────────

## Build a tilted, multi-band transparent annulus as a child of the planet so it
## inherits the body's position, scale and visibility automatically.  Radii in
## RING_SPECS are multiples of the planet's local mesh radius, so the rings scale
## with the planet's apparent size.
func _create_rings() -> void:
	var spec: Dictionary = RING_SPECS.get(name.to_lower(), {})
	if spec.is_empty():
		return

	var base_r: float = 0.5
	if mesh is SphereMesh:
		base_r = (mesh as SphereMesh).radius

	var inner: float = base_r * float(spec["inner"])
	var outer: float = base_r * float(spec["outer"])
	var bands: int   = int(spec["bands"])
	var base_col: Color = spec["color"]

	var verts := PackedVector3Array()
	var cols  := PackedColorArray()

	# Concentric bands, alternating a faint gap between them for a banded look.
	for b in range(bands):
		var t0: float = float(b)       / float(bands)
		var t1: float = float(b + 1)   / float(bands)
		var r0: float = lerpf(inner, outer, t0)
		# Leave a thin gap between bands (90% fill) for visible structure.
		var r1: float = lerpf(inner, outer, lerpf(t0, t1, 0.9))

		# Alpha peaks mid-ring and fades toward the inner/outer edges.
		var mid: float = (t0 + t1) * 0.5
		var fade: float = 1.0 - absf(mid - 0.5) * 2.0      # 0 at edges, 1 at centre
		var a: float = base_col.a * lerpf(0.45, 1.0, fade)
		var col := Color(base_col.r, base_col.g, base_col.b, a)

		for s in range(RING_SEGMENTS):
			var a0: float = TAU * float(s)       / float(RING_SEGMENTS)
			var a1: float = TAU * float(s + 1)   / float(RING_SEGMENTS)
			var i0 := Vector3(cos(a0) * r0, 0.0, sin(a0) * r0)
			var o0 := Vector3(cos(a0) * r1, 0.0, sin(a0) * r1)
			var i1 := Vector3(cos(a1) * r0, 0.0, sin(a1) * r0)
			var o1 := Vector3(cos(a1) * r1, 0.0, sin(a1) * r1)
			# Two triangles per segment (CCW); CULL_DISABLED makes both faces draw.
			verts.append(i0); verts.append(o0); verts.append(o1)
			verts.append(i0); verts.append(o1); verts.append(i1)
			for _i in range(6):
				cols.append(col)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR]  = cols

	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := StandardMaterial3D.new()
	mat.shading_mode             = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode                = BaseMaterial3D.CULL_DISABLED
	mat.transparency             = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	am.surface_set_material(0, mat)

	_rings = MeshInstance3D.new()
	_rings.mesh        = am
	_rings.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rings.rotation    = Vector3(deg_to_rad(float(spec["tilt_deg"])), 0.0, 0.0)
	add_child(_rings)
