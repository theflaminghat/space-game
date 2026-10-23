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

## Surface maps for moons that have one, by moon node name (see PlanetData.MOON_NAMES).  The rest
## are plain grey spheres.
const MOON_TEXTURES := {
	"earth_moon_0": preload("res://luna.svg"),     # Luna
	"mars_moon_0":  preload("res://phobos.svg"),   # Phobos
	"mars_moon_1":  preload("res://deimos.svg"),   # Deimos
	"jupiter_moon_0": preload("res://io.svg"),     # Io
	"jupiter_moon_1": preload("res://europa.svg"), # Europa
	"jupiter_moon_2": preload("res://ganymede.svg"), # Ganymede
}

## Orbital infrastructure lanes.  Each buildable orbital structure gets its OWN ring around
## the planet (distinct radius = separate lane) and its own placeholder-textured mesh, so a
## planet's orbital build-out is visible the way the Dyson swarm is around the Sun.  One
## instance orbits per building of that type the player has raised there.
## Every orbital structure gets a lane, a stand-in shape and the shared placeholder texture, so
## anything the player puts in orbit is actually visible there — around a planet or around the
## Sun.  Lanes are spaced 0.04 apart in planet radii; colour groups them by what they do
## (amber = heat, blue = power link, grey = storage, green = people).
##
## The band runs 0.980 .. 1.780 planet radii, which around the SUN puts it OUTSIDE the Dyson
## swarm rather than through it.  Both bands scale with the star, so the comparison is a fixed
## one: at the Sun's base scale of ~4.70 these lanes span 4.61 .. 8.37 world units, against the
## swarm's 3.05 .. 4.39 and Mercury's perihelion at 8.58.  It used to run 0.640 .. 1.700, i.e.
## 3.01 .. 7.99 — straight through the collector shell, with most of the infrastructure
## embedded in it.  tests/verify_infra_band.gd holds all three apart.
##
## "ground" marks the two that are NOT orbital on a world with a surface: a radiator field and a
## superconducting storage ring both stand on the ground of a rocky planet.  They still get a
## lane around a gas giant, where there is no ground to stand on and everything built is hanging
## in vacuum by definition.  The Matter Depot has no lane at all — silos and bunkers are not
## orbital infrastructure anywhere, and solar orbit stores its matter in Orbital Vaults.
## Golden angle (rad).  Stepping each successive lane's orbital plane by this spreads the planes
## evenly over the sphere however many lanes there are, with no two consecutive ones alike.
const INFRA_PLANE_ANGLE: float = 2.399963229728653

const INFRA_LANES := [
	{"type": "Orbital Laser",         "radius": 1.140, "color": Color(1.00, 0.45, 0.40),
		"mesh": "laser", "texture": "res://models/orbital_laser_albedo.png"},
	{"type": "Space Telescope",       "radius": 1.220, "color": Color(0.60, 0.85, 1.00),
		"mesh": "telescope", "texture": "res://models/orbital_telescope_albedo.png"},
	{"type": "Thermal Radiator",      "radius": 1.260, "color": Color(0.95, 0.75, 0.40),
		"mesh": "thermal", "ground": true,
		"texture": "res://models/orbital_thermal_radiator_albedo.png"},
	{"type": "Orbital Vault",         "radius": 1.300, "color": Color(0.72, 0.74, 0.80), "mesh": "depot",
		"texture": "res://models/orbital_depot_albedo.png"},
	{"type": "Orbital Battery",       "radius": 1.340, "color": Color(0.50, 0.95, 0.62),
		"mesh": "battery", "texture": "res://models/orbital_battery_albedo.png"},
	# Power link: receiving and transmitting apertures.
	{"type": "Microwave Uplink",      "radius": 1.380, "color": Color(0.55, 0.80, 0.95),
		"mesh": "uplink", "texture": "res://models/orbital_uplink_albedo.png"},
	{"type": "Orbital Rectenna",      "radius": 1.420, "color": Color(0.45, 0.75, 1.00),
		"mesh": "rectenna", "texture": "res://models/orbital_rectenna_albedo.png"},
	{"type": "Power Relay Satellite", "radius": 1.460, "color": Color(0.70, 0.70, 1.00),
		"mesh": "relay", "texture": "res://models/orbital_relay_sat_albedo.png"},
	{"type": "Orbital Power Grid",    "radius": 1.500, "color": Color(0.60, 0.72, 1.00),
		"mesh": "grid", "texture": "res://models/orbital_power_grid_albedo.png"},
	{"type": "Stellar Rectenna Grid", "radius": 1.540, "color": Color(0.40, 0.68, 1.00),
		"mesh": "rect_grid", "texture": "res://models/orbital_rectenna_grid_albedo.png"},
	{"type": "Swarm Relay Network",   "radius": 1.580, "color": Color(0.78, 0.68, 1.00),
		"mesh": "swarm_relay", "texture": "res://models/orbital_swarm_relay_albedo.png"},
	# Heat: the other half of any large power economy.
	{"type": "Orbital Radiator Array","radius": 1.620, "color": Color(1.00, 0.70, 0.35),
		"mesh": "radiator", "texture": "res://models/orbital_radiator_array_albedo.png"},
	{"type": "Radiator Swarm",        "radius": 1.660, "color": Color(1.00, 0.62, 0.30),
		"mesh": "rad_swarm", "texture": "res://models/orbital_radiator_swarm_albedo.png"},
	# Storage.
	{"type": "Superconducting Storage Ring", "radius": 1.700, "color": Color(0.62, 0.90, 0.80),
		"mesh": "sc_ring", "ground": true,
		"texture": "res://models/orbital_storage_ring_albedo.png"},
	{"type": "Orbital Ring Store",    "radius": 1.740, "color": Color(0.55, 0.85, 0.78),
		"mesh": "ring_store", "texture": "res://models/orbital_ring_store_albedo.png"},
	# People.
	{"type": "Orbital Habitat",       "radius": 1.780, "color": Color(0.70, 0.95, 0.65),
		"mesh": "habitat", "texture": "res://models/orbital_habitat_albedo.png"},
	# Industry and its stores, flown out to a build site that has no ground.
	{"type": "Orbital Construction Station", "radius": 1.180, "color": Color(0.85, 0.88, 0.95),
		"mesh": "station", "texture": "res://models/orbital_construction_station_albedo.png"},
	# Stellar engineering: the lifters hang closest of anything here, because they have to.
	{"type": "Star Lifter",           "radius": 1.060, "color": Color(1.00, 0.85, 0.45),
		"mesh": "lifter", "texture": "res://models/orbital_star_lifter_albedo.png"},
	{"type": "Sunshade Constellation","radius": 1.100, "color": Color(0.70, 0.78, 0.95),
		"mesh": "sunshade", "texture": "res://models/orbital_sunshade_albedo.png"},
	{"type": "Core Mixing Array",     "radius": 1.020, "color": Color(0.95, 0.60, 0.95),
		"mesh": "core_mixer", "texture": "res://models/orbital_core_mixer_albedo.png"},
	{"type": "Shkadov Mirror",        "radius": 0.980, "color": Color(0.95, 0.95, 1.00),
		"mesh": "shkadov", "texture": "res://models/orbital_shkadov_albedo.png"},
]
const INFRA_MAX_PER_LANE: int = 64   # cap per lane (MultiMesh instance budget)

## Shared magenta-free grey checkerboard placeholder texture (built once, tinted per lane).
static var _placeholder_tex: ImageTexture = null

## Per-lane runtime state: [{ mm, type, radius, phase, motion, incl }].
var _infra: Array = []
var _infra_poll: float = 0.0
## Set once the star has had its orbital lanes created (it skips the planet build-out above).
var _star_infra_built: bool = false
## Whether the lanes are currently drawn — false past ORBIT_BLUR_ABOVE_MULT (100x) unless paused.
var _infra_visible: bool = true

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
## The Sun's evolutionary track now lives with the rest of its physics, keyed by the star's own
## age rather than the calendar (see star_model.gd).  Aliased here because the swarm renderer and
## the encyclopedia read the table directly.
const SUN_STAGES: Array = StarModel.SUN_STAGES

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
	"asteroid_belt": Color(0.45, 0.42, 0.38),
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
## position for any year when motion is frozen (above SolarSystem.ORBIT_BLUR_ABOVE_MULT).
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
	else:
		_apply_polar_blur()

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

## Surface shader that softens a texture map's poles (see planet_polar_blur.gdshader).
const POLAR_BLUR_SHADER: Shader = preload("res://planet_polar_blur.gdshader")

## Swap the body's textured StandardMaterial3D for the polar-blur shader, carrying over its map
## and tint.  The material in effect is the first of: material_override, the surface override,
## the mesh's own.  A body with no texture map is left alone — a flat colour has no poles to blur.
func _apply_polar_blur() -> void:
	var src: Material = material_override
	if src == null:
		src = get_surface_override_material(0)
	if src == null and mesh != null and mesh.get_surface_count() > 0:
		src = mesh.surface_get_material(0)
	var base := src as StandardMaterial3D
	if base == null or base.albedo_texture == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = POLAR_BLUR_SHADER
	mat.set_shader_parameter("albedo_tex", base.albedo_texture)
	mat.set_shader_parameter("albedo_color", base.albedo_color)
	material_override = mat


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
	# A thin, translucent 3-D torus swept along the orbit path: a tube with a small circular
	# cross-section (radius + vertical), so it reads as an orbit line but has real volume and
	# stays visible from any camera angle (Vulkan 1-px LINE_STRIP disappears at distance).
	const PATH_SEGS: int = 160
	const RING_SEGS: int = 6
	const TUBE_R:    float = 0.05   # cross-section radius (game units)
	var pts := _orbit_path_points(PATH_SEGS)
	var up := Vector3(0.0, 1.0, 0.0)

	var verts := PackedVector3Array()
	var r_max: float = 0.0
	for i in range(PATH_SEGS):
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		# Cross-section frame: the point's own radial (XZ) direction + world up, so the tube
		# hugs the orbit plane with a small vertical thickness.
		var s0: Vector3 = Vector3(p0.x, 0.0, p0.z)
		s0 = s0.normalized() if s0.length_squared() > 1e-9 else Vector3(1, 0, 0)
		var s1: Vector3 = Vector3(p1.x, 0.0, p1.z)
		s1 = s1.normalized() if s1.length_squared() > 1e-9 else Vector3(1, 0, 0)
		r_max = maxf(r_max, Vector2(p0.x, p0.z).length())
		for j in range(RING_SEGS):
			var a0 := TAU * float(j)     / float(RING_SEGS)
			var a1 := TAU * float(j + 1) / float(RING_SEGS)
			var o00 := p0 + (cos(a0) * s0 + sin(a0) * up) * TUBE_R
			var o01 := p0 + (cos(a1) * s0 + sin(a1) * up) * TUBE_R
			var o10 := p1 + (cos(a0) * s1 + sin(a0) * up) * TUBE_R
			var o11 := p1 + (cos(a1) * s1 + sin(a1) * up) * TUBE_R
			verts.append(o00); verts.append(o10); verts.append(o11)
			verts.append(o00); verts.append(o11); verts.append(o01)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts

	var line_mesh := ArrayMesh.new()
	line_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.70, 1.0, 0.35)   # translucent blue
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
	line_mesh.surface_set_material(0, mat)

	_orbit_line = MeshInstance3D.new()
	_orbit_line.mesh = line_mesh
	_orbit_line.name = name + "_orbit_line"
	_orbit_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ext: float = r_max + TUBE_R
	_orbit_line.custom_aabb = AABB(
		Vector3(-ext, -TUBE_R, -ext),
		Vector3(ext * 2.0, TUBE_R * 2.0, ext * 2.0)
	)
	get_parent().add_child(_orbit_line)

## Show stars always; show other bodies only when the solar system is active
## or either pause flag is set (so players can still inspect planets when frozen).
## Set once the Sun's photosphere swallows this planet — it's gone for good.
var _engulfed: bool = false

## The Sun has engulfed this planet: destroy it and everything orbiting it (moons, rings,
## orbital infrastructure, orbit line), and stop all its per-frame work.
func engulf() -> void:
	if _engulfed:
		return
	_engulfed = true
	visible = false                      # hides the body + its moons + infra MMIs (children)
	if _orbit_line:  _orbit_line.visible  = false
	if _blur_torus:  _blur_torus.visible  = false
	if _rings:       _rings.visible        = false
	set_process(false)                   # no more orbit / moon / infra updates for a dead world

func _sync_visibility() -> void:
	# Before the early returns below: the STAR takes one, and solar orbit is where most of this
	# infrastructure actually is.
	_sync_infra_visibility()
	if _engulfed:                        # a swallowed planet stays gone
		visible = false
		if _orbit_line: _orbit_line.visible = false
		if _blur_torus: _blur_torus.visible = false
		return
	if type == Type.STAR:
		visible = true
		return
	# Body shows during normal sim, or whenever paused so the player can inspect it.
	var body_on := SolarSystem.solar_system_active or SolarSystem.paused or SolarSystem.ui_paused
	visible = body_on
	# When motion is frozen (past the orbit-freeze cutoff) the body normally holds
	# its last position.  If we're showing it because the player paused, snap it to
	# its true position at the snap year (chosen by Game so the viewed planet keeps
	# its place and the rest fall into their correct relative positions).
	if body_on and not SolarSystem.solar_system_active:
		_snap_to_year(SolarSystem.snap_year)
	# Orbit lines stay drawn even past the freeze cutoff (when the planet bodies
	# are hidden), so the system's layout remains legible.
	if _orbit_line:
		_orbit_line.visible = true
	# The motion-blur ring appears only while frozen AND fast-forwarding — i.e.
	# exactly when the discrete body is hidden, so the planet reads as a smeared
	# band whipping round its orbit too fast to resolve.
	if _blur_torus:
		_blur_torus.visible = not body_on

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
		_create_infra_lanes()
		_sync_visibility()
	# Orbital lanes are built for the STAR too, on its own flag: the Sun has no orbit line,
	# no blur torus and no moons, but solar orbit is a build site like any other and what is
	# put there has to be visible.
	elif not _star_infra_built and type == Type.STAR:
		_star_infra_built = true
		_create_infra_lanes()
		# The star returns early from _sync_visibility, so its lanes are given their first
		# visibility state here rather than inheriting one.
		_sync_infra_visibility()

	# Orbital infrastructure: refresh counts + orbit them every frame (even while paused, so
	# newly-built structures appear immediately).  Cheap — small counts, polled on a throttle.
	if not _infra.is_empty():
		# Hidden lanes are not laid out: past 100x nothing is drawn, so positioning a few
		# hundred structures every frame would be work with nothing to show for it.
		_sync_infra_visibility()
		if _infra_visible:
			_update_infra(delta)

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

	# Moons orbit on the GAME clock, like the planet carrying them.  They used to spin at a
	# steady real-time rate, deliberately decoupled from the timescale — which meant a world
	# fast-forwarded through a century had a moon going round at exactly the pace it did at 1x,
	# and the only thing on screen that did not react to the speed control.
	if not _moons.is_empty():
		_update_moons(delta * SolarSystem.speed_multiplier())

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
		var tex: Texture2D = MOON_TEXTURES.get(moon.name.to_lower(), null)
		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		# A textured moon is one the camera may be shown up close, so it gets a smooth sphere;
		# a plain grey one stays low-poly.
		sphere.radial_segments = 48 if tex else 12
		sphere.rings = 24 if tex else 6
		moon.mesh = sphere
		moon.scale = Vector3(msize, msize, msize)
		moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		# A little self-emission keeps moons readable even on the night side / when the
		# scene has no light reaching them.
		var g: float = rng.randf_range(0.55, 0.80)
		if tex:
			var smat := ShaderMaterial.new()
			smat.shader = POLAR_BLUR_SHADER
			smat.set_shader_parameter("albedo_tex", tex)
			smat.set_shader_parameter("self_light", 0.18)
			moon.set_surface_override_material(0, smat)
		else:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(g, g, g * 0.96)
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
## `delta` here is GAME time, not wall-clock: the caller has already scaled it by the speed
## multiplier, so a moon's period is the same number of game-days at every rung of the ladder.
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

# ── Orbital infrastructure lanes ───────────────────────────────────────────────

## Grey checkerboard placeholder texture, built once and shared by every planet's lanes.
static func _get_placeholder_tex() -> ImageTexture:
	if _placeholder_tex != null:
		return _placeholder_tex
	var s: int = 16
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in range(s):
		for x in range(s):
			var on: bool = (((x >> 2) + (y >> 2)) & 1) == 0
			img.set_pixel(x, y, Color(0.85, 0.85, 0.90) if on else Color(0.32, 0.32, 0.38))
	_placeholder_tex = ImageTexture.create_from_image(img)
	return _placeholder_tex

## Texture named by a lane spec, loaded once and shared by every body drawing that lane.
##
## A lane without a "texture" key keeps the shared checker, which is still what most of them
## want: a stand-in primitive has no UV layout worth painting for.  A lane WITH one gets a map
## baked against its model's actual unwrap (tools/depot.py), so the two must travel together —
## the texture is meaningless on any other mesh.
##
## The map is greyscale on purpose.  albedo_color tints it with the lane's own colour, exactly
## as it tinted the checker, so what the bake carries is value and not hue.  A missing or
## unimported texture falls back to the checker rather than rendering untextured white.
static var _lane_tex_cache: Dictionary = {}

static func _lane_texture(path: String) -> Texture2D:
	if path.is_empty():
		return _get_placeholder_tex()
	if _lane_tex_cache.has(path):
		return _lane_tex_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		push_warning("planet.gd: %s missing — that lane falls back to the checker." % path)
		tex = _get_placeholder_tex()
	_lane_tex_cache[path] = tex
	return tex

## Normal map belonging to a lane texture, by naming convention: the same path with
## "_albedo" swapped for "_normal".  Returns null when a model has no normal map baked yet,
## and the lane simply goes without one rather than failing.
##
## Kept as a convention rather than another key in the lane spec: the two maps are baked
## together from the same pattern by the same script, and a lane that named one but not the
## other would be describing a state tools/build_models.sh cannot produce.
static var _lane_normal_cache: Dictionary = {}

static func _lane_normal(tex_path: String) -> Texture2D:
	if tex_path.is_empty():
		return null
	if _lane_normal_cache.has(tex_path):
		return _lane_normal_cache[tex_path]
	var path: String = tex_path.replace("_albedo.png", "_normal.png")
	var tex: Texture2D = null
	if path != tex_path and ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_lane_normal_cache[tex_path] = tex
	return tex

## Mesh per infrastructure kind.  The kinds in LANE_MODELS are modelled assets loaded from
## disk; the rest are still simple distinguishable stand-in shapes.
func _infra_mesh(kind: String) -> Mesh:
	if LANE_MODELS.has(kind):
		return _model_mesh(kind)
	# Every lane in INFRA_LANES names a model now, so there is no primitive left to fall
	# back to — only this, for a kind nobody implemented.  It warns, because a silent box
	# looks enough like real infrastructure to sit in the band unnoticed, which is the same
	# failure tests/verify_lane_models.gd watches for at load.
	push_warning("planet.gd: no mesh kind \"%s\" — drawing a placeholder box." % kind)
	var b := BoxMesh.new()
	b.size = Vector3(0.18, 0.16, 0.18)
	return b

## Modelled lane meshes, shared by every lane on every body that draws one.
##
## Built by tools/build_models.sh out of the matching tools/*.py — single-surface,
## material-free meshes with real UVs, because the lane applies its own material_override and
## would discard anything the .glb carried anyway.  Each one's +Y is the radial-outward axis,
## which is the column _update_infra() hands the instance basis.
##
## A kind listed here takes its model; anything else falls through to the primitives below.
## All five stand-in primitives are gone, retired one at a time as their last users got
## models: the rod, the torus, the plain cylinder, the shallow cone that served every
## aperture in the power-link band, and finally the flat plate that served every radiator,
## sail and mirror.  tests/verify_lane_models.gd names all five, so a lane left pointing at
## one cannot fail quietly — it would otherwise reach the placeholder at the end of
## _infra_mesh() and look like real infrastructure.
##
## The torus is the one worth recording, as the rod went before it: three lanes shared it and all
## three now have models, because buildings.gd describes three different things.  The habitat
## is "a spun cylinder", which is the one shape a ring is not; the ring store is "a loop of
## orbital diameter", which wants an empty middle the primitive had no way to leave out; and
## the core mixer "reaches into the core", which points it the opposite way from everything.
const LANE_MODELS := {
	"battery": "res://models/orbital_battery.glb",
	"core_mixer": "res://models/orbital_core_mixer.glb",
	"depot":   "res://models/orbital_depot.glb",
	"grid":    "res://models/orbital_power_grid.glb",
	"habitat": "res://models/orbital_habitat.glb",
	"laser":   "res://models/orbital_laser.glb",
	"lifter":  "res://models/orbital_star_lifter.glb",
	"rad_swarm": "res://models/orbital_radiator_swarm.glb",
	"radiator": "res://models/orbital_radiator_array.glb",
	"rect_grid": "res://models/orbital_rectenna_grid.glb",
	"rectenna": "res://models/orbital_rectenna.glb",
	"relay":   "res://models/orbital_relay_sat.glb",
	"ring_store": "res://models/orbital_ring_store.glb",
	"sc_ring": "res://models/orbital_storage_ring.glb",
	"shkadov": "res://models/orbital_shkadov.glb",
	"station": "res://models/orbital_construction_station.glb",
	"sunshade": "res://models/orbital_sunshade.glb",
	"swarm_relay": "res://models/orbital_swarm_relay.glb",
	"thermal": "res://models/orbital_thermal_radiator.glb",
	"telescope": "res://models/orbital_telescope.glb",
	"uplink":  "res://models/orbital_uplink.glb",
}
static var _model_mesh_cache: Dictionary = {}

## Godot imports a .glb as a PackedScene, so the ArrayMesh is lifted out of its MeshInstance3D
## once and cached: the lanes ask for this per body, and re-instancing the scene each time
## would be hundreds of throwaway nodes at load.  A missing or unimported model falls back to
## the box these lanes used before, so a fresh checkout that has not imported its assets yet
## still draws something rather than crashing the solar system.
static func _model_mesh(kind: String) -> Mesh:
	if _model_mesh_cache.has(kind):
		return _model_mesh_cache[kind]
	var path: String = str(LANE_MODELS.get(kind, ""))
	var mesh: Mesh = null
	if not path.is_empty() and ResourceLoader.exists(path):
		var packed: PackedScene = load(path) as PackedScene
		if packed != null:
			var root: Node = packed.instantiate()
			for n: Node in root.find_children("*", "MeshInstance3D", true, false):
				var mi := n as MeshInstance3D
				if mi != null and mi.mesh != null:
					mesh = mi.mesh
					break
			root.free()
	if mesh == null:
		push_warning("planet.gd: no mesh for lane model \"%s\" (%s) — falling back to a box."
			% [kind, "unlisted" if path.is_empty() else path])
		var b := BoxMesh.new()
		b.size = Vector3(0.18, 0.16, 0.18)
		mesh = b
	_model_mesh_cache[kind] = mesh
	return mesh

## Material: the lane's texture (its own baked map, or the shared checker) tinted with the
## lane's colour + faint self-glow so the structures read in the scene's limited lighting.
func _infra_material(color: Color, tex_path: String = "") -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _lane_texture(tex_path)
	m.albedo_color   = color
	m.metallic       = 0.3
	m.roughness      = 0.7
	# Surface relief, where the model has it baked.  The albedo map carries the same
	# pattern as painted light and dark, which does not move when the light does; this is
	# what makes the plating and the cell grids actually catch it.
	var nrm: Texture2D = _lane_normal(tex_path)
	if nrm != null:
		m.normal_enabled = true
		m.normal_texture = nrm
	m.emission_enabled = true
	m.emission       = color
	m.emission_energy_multiplier = 0.15
	return m

## Build one MultiMesh lane per orbital-infrastructure type (all under this planet, in its
## local scaled frame like the moons).  Each lane starts empty; _update_infra reveals one
## instance per built structure of that type.
func _create_infra_lanes() -> void:
	# The Sun gets lanes like any other body.  Its collectors are the Dyson swarm (drawn in
	# init_planets.gd), but everything servicing them — receivers, relays, radiators, stores and
	# the habitats crewing them — is ordinary orbital infrastructure and is drawn here.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(name) + "_infra")
	for spec: Dictionary in INFRA_LANES:
		# Ground infrastructure gets no lane on a body it can actually stand on.
		if bool(spec.get("ground", false)) and type == Type.ROCKY:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _infra_mesh(str(spec["mesh"]))
		mm.instance_count = INFRA_MAX_PER_LANE
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_infra_%s" % [name, str(spec["type"]).replace(" ", "_")]
		mmi.multimesh = mm
		mmi.material_override = _infra_material(spec["color"], str(spec.get("texture", "")))
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ext: float = float(spec["radius"]) + 0.5
		mmi.custom_aabb = AABB(Vector3(-ext, -ext, -ext), Vector3(ext * 2.0, ext * 2.0, ext * 2.0))
		add_child(mmi)
		_infra.append({
			"mm":     mm,
			"mmi":    mmi,
			"type":   str(spec["type"]),
			"radius": float(spec["radius"]),
			"phase":  rng.randf() * TAU,
			"motion": rng.randf_range(0.15, 0.5) * (1.0 if rng.randf() < 0.5 else -1.0),
			# Orbital planes spread over the WHOLE sphere, by the golden angle so consecutive
			# lanes land nowhere near each other.  They used to sit in a narrow random band of
			# +-0.3 rad, which was fine when the lanes were a quarter of a unit apart in radius
			# and could not touch.  Squeezed into the band between the Dyson swarm and Mercury
			# they are a twenty-fifth of a unit apart, closer than the structures themselves
			# are wide, so what keeps them clear of one another is the angle between their
			# planes rather than the gap between their radii — the same trick the Dyson swarm
			# uses to be a shell instead of a disk.
			"incl":   fposmod(float(_infra.size()) * INFRA_PLANE_ANGLE, PI),
		})
	_update_infra(0.0)

## Show or hide every orbital-infrastructure lane on this body.
##
## Past ORBIT_BLUR_ABOVE_MULT (100x) individual orbital positions are not worth drawing — the
## bodies themselves are already replaced by motion-blur rings there — and a few hundred
## structures smeared round the Sun at a thousand times real time is a bright knot that says
## nothing about where anything is.  The paused exception is the same one the bodies and the
## Dyson swarm take: pausing is how the player inspects a system the clock has blurred.
func _sync_infra_visibility() -> void:
	var lanes_on: bool = not _engulfed and (SolarSystem.solar_system_active
		or SolarSystem.paused or SolarSystem.ui_paused)
	_infra_visible = lanes_on
	for lane: Dictionary in _infra:
		var mmi: MultiMeshInstance3D = lane.get("mmi")
		if mmi != null:
			mmi.visible = lanes_on


## How one orbital structure sits at `pos` in its body's local frame: up-axis outward, like a
## real satellite bus.  +Y is the radial, which is the contract the models are built to.
##
## RIGHT-HANDED, and that is the whole reason this is a function with a name rather than four
## lines inside the draw loop.  Basis(x, y, z) is right-handed when x cross y is z; built the
## other way round its determinant is -1, which is a MIRROR — and a mirrored instance transform
## reverses the effective winding of everything it draws, so the renderer culls the near faces,
## keeps the far ones, and the structure is shaded from the inside.
##
## It was wrong for every lane and showed on exactly one, because a mirrored box is a box: rod,
## cyl, flat, box, dish and ring are all symmetric enough to hide it, and the Orbital Vault is
## the only lane that draws a modelled hull.  The Dyson swarm's collectors had it too.
##
## CONTINUOUS all the way round, which is the other half of what this function is for.  The
## sideways axis is the ALONG-TRACK direction, taken from the orbit's own plane — a real
## satellite bus flies that way, and more to the point it is defined everywhere on the orbit.
##
## Built instead from a world axis it is not.  The previous version picked a reference of UP, or
## RIGHT when the structure came within 0.95 of straight overhead, and at that threshold the
## whole frame snapped about the radial axis: five of the twenty-one lanes have a steep enough
## inclination to cross it, four times an orbit, turning as much as 171 degrees in one frame.
## That is a structure visibly spinning part way round its orbit and then back.
##
## Any fixed reference has the same failure somewhere — there is no continuous non-vanishing
## tangent field on a sphere — so the fix is not a better constant but a reference that moves
## with the orbit.  The orbit normal is constant per lane and never parallel to the radial, so
## their cross product never vanishes.
##
## Pulled out here because the bug is NOT reachable through the MultiMesh it feeds: a headless
## run has no renderer, set_instance_transform keeps nothing and get_instance_transform hands
## back the identity, so an assertion made against the lanes themselves passes whatever the
## maths does.  This is the part that can actually be checked — see verify_infra_band.
static func infra_orientation(pos: Vector3, orbit_normal: Vector3) -> Basis:
	var radial: Vector3 = pos.normalized() if pos.length_squared() > 1e-9 else Vector3.UP
	var n: Vector3 = orbit_normal.normalized() if orbit_normal.length_squared() > 1e-9 \
		else Vector3.UP
	var tangent: Vector3 = n.cross(radial)
	# Only reachable if a caller hands in a normal its position does not orbit about; on a lane
	# the two are perpendicular by construction.  Fall back to something orthonormal rather than
	# normalising a zero vector into nan.
	if tangent.length_squared() < 1.0e-12:
		var ref: Vector3 = Vector3.UP if absf(radial.y) < 0.95 else Vector3.RIGHT
		tangent = radial.cross(ref)
	tangent = tangent.normalized()
	return Basis(tangent, radial, tangent.cross(radial))


## The normal of the orbital plane a lane at inclination `incl` lies in — the axis
## _update_infra's own parameterisation turns about.
static func infra_orbit_normal(incl: float) -> Vector3:
	return Vector3(0.0, -cos(incl), sin(incl))


## Poll how many of each orbital structure the planet has (throttled) and lay the visible
## instances out evenly around their lane, advancing the shared lane angle each frame.
func _update_infra(delta: float) -> void:
	# Wall-clock on purpose, unlike the motion below: this is how often the lanes re-read how
	# many structures exist, which is a UI refresh rate and should not fire a thousand times a
	# frame because the player sped the clock up.
	_infra_poll += delta
	var repoll: bool = _infra_poll >= 0.5
	if repoll:
		_infra_poll = 0.0
	var game: Node = get_tree().current_scene
	var pname: String = str(name).to_lower()
	# Freeze the orbital spin while the game is paused (counts still refresh so newly-built
	# structures appear); only advance the lane angle when the simulation is actually running.
	var running: bool = SolarSystem.solar_system_active \
		and not SolarSystem.paused and not SolarSystem.ui_paused
	# Station-keeping on the GAME clock, for the same reason the moons are: a structure in orbit
	# that holds its pace while the years tear past is the one thing on screen ignoring the speed
	# control.  speed_multiplier() is 1.0 on the base rung, so this is unchanged at 1x and runs
	# proportionally faster above it — and the lanes stop being drawn past 100x anyway, which is
	# what bounds it.
	var sim_delta: float = delta * SolarSystem.speed_multiplier()
	# The lanes are children of the (scaled) planet, so cancel the planet's scale in each
	# instance's basis — the structures render at a constant world size regardless of how
	# big the planet is (their orbit radius still scales, so they hug each world).
	var inv_s: float = 1.0 / maxf(scale.x, 0.0001)
	for lane: Dictionary in _infra:
		var mm: MultiMesh = lane["mm"]
		if running:
			lane["phase"] = fposmod(
				float(lane["phase"]) + float(lane["motion"]) * sim_delta, TAU)
		if repoll and game and game.has_method("_count_building"):
			mm.visible_instance_count = mini(
				int(game._count_building(pname, str(lane["type"]))), INFRA_MAX_PER_LANE)
		var count: int = mm.visible_instance_count
		if count <= 0:
			continue
		var r: float = float(lane["radius"])
		var incl: float = float(lane["incl"])
		var base: float = float(lane["phase"])
		# Constant for the lane, so it is taken once rather than per structure.
		var onormal: Vector3 = infra_orbit_normal(incl)
		for i in range(count):
			var th: float = base + TAU * float(i) / float(count)   # evenly spaced around the ring
			var z: float = r * sin(th)
			var pos := Vector3(r * cos(th), z * sin(incl), z * cos(incl))
			# Basis scaled by inv_s → constant world-space structure size on any planet.
			mm.set_instance_transform(i, Transform3D(
				infra_orientation(pos, onormal).scaled(Vector3(inv_s, inv_s, inv_s)), pos))

## World position of one slot in an orbital lane — where the `index`-th structure of `type` sits
## once the lane holds `total` of them.
##
## This is the same layout _update_infra() draws: evenly spaced around the ring, on the lane's
## live phase and inclination, so a craft flying to a reserved slot tracks it as the lane turns
## rather than aiming at where it was when the launch went up.  A lane redistributes its
## instances whenever the count changes, so the slot is exact only for the count passed in — a
## delivery reserves the position it will occupy on arrival.
##
## Falls back to the body's own position for a type this body has no lane for.
func infra_slot_world_pos(type_name: String, index: int, total: int) -> Vector3:
	for lane: Dictionary in _infra:
		if str(lane["type"]) != type_name:
			continue
		var n: int = maxi(total, 1)
		var r: float = float(lane["radius"])
		var incl: float = float(lane["incl"])
		var th: float = float(lane["phase"]) + TAU * float(clampi(index, 0, n - 1)) / float(n)
		var z: float = r * sin(th)
		return to_global(Vector3(r * cos(th), z * sin(incl), z * cos(incl)))
	return global_position


## Returns the planet's current visual distance from the orbit centre.
## For Keplerian orbits this varies with true anomaly; for circular fallback
## it equals orbit_radius (the semi-major axis).
## Satellite spawner should use this instead of orbit_radius so the craft
## starts exactly at the planet's position.
func get_visual_radius() -> float:
	return _current_visual_radius

# ── Stellar evolution ─────────────────────────────────────────────────────────

## Paint the Sun for the star's CURRENT AGE — which is not the calendar year once mass has been
## lifted: a lightened Sun looks younger because it is.  Colour, size and glow come from the same
## track the physics reads (StarModel.appearance_at_age), so what the player sees and what
## engulfs their planets can never disagree.
## Only called once per in-game year, so it is essentially free.
func _update_sun_appearance(current_year: int) -> void:
	if _sun_mat == null:
		return
	# appearance_at() applies the mass scalings and substitutes the other fates, so a star lifted
	# past helium ignition is drawn as what it now is — a small red dwarf, and eventually a white
	# one — rather than as a 1 M☉ star's track scaled down.
	var look: Dictionary = StarModel.appearance_at(
		SolarSystem.stellar_age(float(current_year)), SolarSystem.star_mass_msun)
	var col: Color = look["color"]
	var vis: float = float(look["visual_mult"])
	var emiss: float = float(look["emiss_mult"])
	scale = _sun_base_scale * vis
	_sun_mat.albedo_color               = col
	_sun_mat.emission                   = col
	_sun_mat.emission_energy_multiplier = emiss

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
