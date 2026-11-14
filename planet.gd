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

# ── Being taken apart ─────────────────────────────────────────────────────────
## The size this body is at full mass, so a partial disassembly has something to scale against.
var _intact_scale: Vector3 = Vector3.ONE
## Last pushed state, so a body that has not moved is not re-set every frame.
var _strip_remaining: float = 1.0
var _strip_look: Dictionary = {}
## The body's size against its intact size while it is being taken apart, 1 otherwise.  The node
## itself is scaled, which carries its moons, rings and orbital lanes with it as children, so they
## are given the inverse of this to stay the size and the distance they were (_hold_satellites).
var _shrink: float = 1.0

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
## Sun.  Lanes are spaced by the size of what flies in them (see INFRA_LANE_PITCH below); colour
## groups them by what they do (amber = heat, blue = power link, grey = storage, green = people).
##
## The band starts at 1.020 scale units, which around the SUN puts it OUTSIDE the Dyson swarm
## rather than through it: at the Sun's base scale of ~4.70 the innermost lane is 4.79 world
## units out, against the swarm's 3.05 .. 4.39 and Mercury's perihelion at 8.58.  It used to run
## 0.640 .. 1.700, i.e. 3.01 .. 7.99 — straight through the collector shell, with most of the
## infrastructure embedded in it.  tests/verify_infra_band.gd holds all three apart, and
## tests/verify_lane_clearance.gd holds every body's band clear of every other body's.
##
## Where the band ENDS is no longer one number: the lanes are a structure-and-a-third apart and
## the structures are capped in world size, so the Sun's twenty lanes close up into 1.020 .. 1.35
## while Earth's spread over 1.020 .. 2.83.  The band is widest, in its own body's units, around
## the smallest bodies — which is what it costs to have hardware that is the same size wherever
## it is built and never standing inside its neighbours'.
##
## It used to start at 0.980, when the Shkadov Mirror had the innermost lane of the band; the
## mirror now stands at the photosphere instead and has no lane at all.
##
## "ground" marks the two that are NOT orbital on a world with a surface: a radiator field and a
## superconducting storage ring both stand on the ground of a rocky planet.  They still get a
## lane around a gas giant, where there is no ground to stand on and everything built is hanging
## in vacuum by definition.  The Matter Depot has no lane at all — silos and bunkers are not
## orbital infrastructure anywhere, and solar orbit stores its matter in Orbital Vaults.
## Where the band sits, how far apart its lanes are, and how big the things flying in them are —
## all three in the body's own scale units, which to_global multiplies by, so the whole band is
## the same shape around every body and around the star.
##
## ONE STRUCTURE PER GAP, and that is the point of these three numbers together. A lane's
## hardware is INFRA_SIZE_FRAC across and the next lane is INFRA_LANE_STEP further out, so a
## structure occupies three quarters of the space between its own lane and its neighbour's and
## no shell can reach another. It did not before: the structures were a FIXED world size
## whatever they orbited — 0.18 to 0.45 units, authored that way one model at a time — while the
## lanes were 0.04 scale units apart, which is 0.013 units around Mercury. Every lane's hardware
## stood inside its neighbours' on every body, nothing but the angle between the orbital planes
## kept any of it apart, and around Mercury (radius 0.161) a single orbital habitat was twice
## the width of the planet it orbited.
##
## The band ends at 1.590 rather than 1.780 because of the one pair of bodies in the system that
## has no room: the Sun's outermost lane stood at 8.367 world units and Mercury's own band
## reaches 0.573 inward from a perihelion of 8.578, so the two overlapped by 4% of the distance
## between them — the star's infrastructure flew through the planet's once an orbit. Moving the
## planets out does not fix that, because the Dyson swarm is placed in AU and moves with them,
## into the inner edge of the very band being made room for. See tests/verify_lane_clearance.gd.
const INFRA_BAND_INNER: float = 1.020
## A structure's LONGEST dimension: this much of the body's scale, and never more than
## INFRA_SIZE_MAX world units however big the body is. Every lane model is normalised to it —
## they were authored over a 2.5x spread — so one piece of orbital hardware is the size of the
## next, and all of them scale with whatever they are in orbit around.
##
## The CAP is what buys the inner system its room. Without it the Sun, at a scale of 4.70, takes
## a band 19 steps of its own size wide, and the only place that band can go is the gap between
## the Dyson swarm and Mercury. Capping the star's hardware rather than everyone's lets the
## fraction be three times what it could otherwise be: Earth's structures are 0.0485 world units
## across instead of 0.0156, and the Sun's are the same 0.06 as Jupiter's.
const INFRA_SIZE_FRAC:  float = 0.070
const INFRA_SIZE_MAX:   float = 0.060
## A lane is four thirds of a structure from the next, so the hardware fills three quarters of
## the space between its own shell and its neighbour's and the two can never meet.
const INFRA_LANE_PITCH: float = 4.0 / 3.0

## One structure's longest dimension in WORLD units, around a body of this scale.
static func infra_structure_size(body_scale: float) -> float:
	return minf(INFRA_SIZE_FRAC * body_scale, INFRA_SIZE_MAX)

## The gap between one lane and the next, in the body's scale units.
static func infra_lane_step(body_scale: float) -> float:
	return infra_structure_size(body_scale) * INFRA_LANE_PITCH / maxf(body_scale, 0.0001)

## Where lane `order` sits, in the body's scale units.
static func infra_lane_radius(order: int, body_scale: float) -> float:
	return INFRA_BAND_INNER + infra_lane_step(body_scale) * float(order)

## The outermost lane's hardware, in the body's scale units: what a moon has to clear.
static func infra_band_outer(body_scale: float) -> float:
	return infra_lane_radius(INFRA_LANES.size() - 1, body_scale) \
		+ 0.5 * infra_structure_size(body_scale) / maxf(body_scale, 0.0001)


## Golden angle (rad).  Stepping each successive lane's orbital plane by this spreads the planes
## evenly over the sphere however many lanes there are, with no two consecutive ones alike.
const INFRA_PLANE_ANGLE: float = 2.399963229728653

const INFRA_LANES := [
	{"type": "Orbital Laser",         "order": 3, "color": Color(1.00, 0.45, 0.40),
		"mesh": "laser", "texture": "res://models/orbital_laser_albedo.png"},
	{"type": "Space Telescope",       "order": 5, "color": Color(0.60, 0.85, 1.00),
		"mesh": "telescope", "texture": "res://models/orbital_telescope_albedo.png"},
	{"type": "Thermal Radiator",      "order": 6, "color": Color(0.95, 0.75, 0.40),
		"mesh": "thermal", "ground": true,
		"texture": "res://models/orbital_thermal_radiator_albedo.png"},
	{"type": "Orbital Vault",         "order": 7, "color": Color(0.72, 0.74, 0.80), "mesh": "depot",
		"texture": "res://models/orbital_depot_albedo.png"},
	{"type": "Orbital Battery",       "order": 8, "color": Color(0.50, 0.95, 0.62),
		"mesh": "battery", "texture": "res://models/orbital_battery_albedo.png"},
	# Power link: receiving and transmitting apertures.
	{"type": "Microwave Uplink",      "order": 9, "color": Color(0.55, 0.80, 0.95),
		"mesh": "uplink", "texture": "res://models/orbital_uplink_albedo.png"},
	{"type": "Orbital Rectenna",      "order": 10, "color": Color(0.45, 0.75, 1.00),
		"mesh": "rectenna", "texture": "res://models/orbital_rectenna_albedo.png"},
	{"type": "Power Relay Satellite", "order": 11, "color": Color(0.70, 0.70, 1.00),
		"mesh": "relay", "texture": "res://models/orbital_relay_sat_albedo.png"},
	{"type": "Orbital Power Grid",    "order": 12, "color": Color(0.60, 0.72, 1.00),
		"mesh": "grid", "texture": "res://models/orbital_power_grid_albedo.png"},
	{"type": "Stellar Rectenna Grid", "order": 13, "color": Color(0.40, 0.68, 1.00),
		"mesh": "rect_grid", "texture": "res://models/orbital_rectenna_grid_albedo.png"},
	{"type": "Swarm Relay Network",   "order": 14, "color": Color(0.78, 0.68, 1.00),
		"mesh": "swarm_relay", "texture": "res://models/orbital_swarm_relay_albedo.png"},
	# Heat: the other half of any large power economy.
	{"type": "Orbital Radiator Array","order": 15, "color": Color(1.00, 0.70, 0.35),
		"mesh": "radiator", "texture": "res://models/orbital_radiator_array_albedo.png"},
	{"type": "Radiator Swarm",        "order": 16, "color": Color(1.00, 0.62, 0.30),
		"mesh": "rad_swarm", "texture": "res://models/orbital_radiator_swarm_albedo.png"},
	# Storage.
	{"type": "Superconducting Storage Ring", "order": 17, "color": Color(0.62, 0.90, 0.80),
		"mesh": "sc_ring", "ground": true,
		"texture": "res://models/orbital_storage_ring_albedo.png"},
	{"type": "Orbital Ring Store",    "order": 18, "color": Color(0.55, 0.85, 0.78),
		"mesh": "ring_store", "texture": "res://models/orbital_ring_store_albedo.png"},
	# People.
	{"type": "Orbital Habitat",       "order": 19, "color": Color(0.70, 0.95, 0.65),
		"mesh": "habitat", "texture": "res://models/orbital_habitat_albedo.png"},
	# Industry and its stores, flown out to a build site that has no ground.
	{"type": "Orbital Construction Station", "order": 4, "color": Color(0.85, 0.88, 0.95),
		"mesh": "station", "texture": "res://models/orbital_construction_station_albedo.png"},
	# Stellar engineering: the lifters hang closest of anything here, because they have to.
	{"type": "Star Lifter",           "order": 1, "color": Color(1.00, 0.85, 0.45),
		"mesh": "lifter", "texture": "res://models/orbital_star_lifter_albedo.png"},
	{"type": "Sunshade Constellation","order": 2, "color": Color(0.70, 0.78, 0.95),
		"mesh": "sunshade", "texture": "res://models/orbital_sunshade_albedo.png"},
	{"type": "Core Mixing Array",     "order": 0, "color": Color(0.95, 0.60, 0.95),
		"mesh": "core_mixer", "texture": "res://models/orbital_core_mixer_albedo.png"},
	# The Shkadov Mirror has NO LANE.  There is one of it, it does not orbit, and it stands at
	# the photosphere rather than out in the band — see "The Shkadov mirror" below.
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
	# What the body is when nothing has been taken off it.  Captured after the log-scaling above
	# has settled, so set_disassembly has an untouched size to work back to — the same thing
	# _sun_base_scale is for the star.
	_intact_scale = scale

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

	# ── Visual size (same log-scale as original code) ─────────────────────────
	size_mult = log(scale.x + 1.0)
	scale = Vector3(size_mult, size_mult, size_mult)

	_use_kepler = true
	_update_kepler_position()

## Surface shader that softens a texture map's poles (see planet_polar_blur.gdshader).
const POLAR_BLUR_SHADER: Shader = preload("res://planet_polar_blur.gdshader")

## Swap the body's StandardMaterial3D for the polar-blur shader, carrying over its map and tint.
## The material in effect is the first of: material_override, the surface override, the mesh's
## own.
##
## A body with no map gets the shader too, on a single white texel, which times its colour is
## exactly the colour it had.  It has no poles to blur, but the disassembly look lives on this
## shader: Uranus, the one plain-coloured planet, used to be left on its StandardMaterial3D and
## shrank as it was taken apart without ever stopping looking like itself.
func _apply_polar_blur() -> void:
	var src: Material = material_override
	if src == null:
		src = get_surface_override_material(0)
	if src == null and mesh != null and mesh.get_surface_count() > 0:
		src = mesh.surface_get_material(0)
	var base := src as StandardMaterial3D
	if base == null:
		return
	var tex: Texture2D = base.albedo_texture
	if tex == null:
		tex = _white_texel()
	var mat := ShaderMaterial.new()
	mat.shader = POLAR_BLUR_SHADER
	mat.set_shader_parameter("albedo_tex", tex)
	mat.set_shader_parameter("albedo_color", base.albedo_color)
	material_override = mat


static var _white: ImageTexture = null

## One white texel, shared: the map for a body that has none.
static func _white_texel() -> ImageTexture:
	if _white == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(img)
	return _white


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
## Show this world as `remaining` of its mass, excavated to `depth` — see disassembly.gd.
##
## Two things change, and both of them are the point.  The body SHRINKS, by the cube root of what
## is left (mass goes as the cube of the radius, so the first tenth off a planet is barely
## visible and that is correct — a crust is a skin).  And its surface stops being a surface: the
## map is taken away and what is under it shows — DisassemblyData.look, which Game works out from
## the ledger and hands over whole, so the layer rules live in one place and not here.
func set_disassembly(remaining: float, look: Dictionary) -> void:
	var rem: float = clampf(remaining, 0.0, 1.0)
	if absf(rem - _strip_remaining) < 0.0005 and _same_look(look, _strip_look):
		return
	_strip_remaining = rem
	_strip_look = look
	# A floor, not zero: a body still being worked on has to stay clickable, and the world is
	# removed outright by Game the moment the last layer goes (see _finish_disassembly).
	var f: float = maxf(DisassemblyData.radius_frac(rem), 0.03)
	scale = _intact_scale * f
	if mesh != null:
		_body_visual_radius = mesh.get_aabb().size.x * 0.5 * scale.x
	if f != _shrink:
		_shrink = f
		_hold_satellites()
	var mat := material_override as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("strip_mix", float(look["mix"]))
		mat.set_shader_parameter("strip_color", look["color"] as Color)
		mat.set_shader_parameter("strip_glow", float(look["glow"]))
		mat.set_shader_parameter("strip_metallic", float(look["metallic"]))


## Keep the moons, the rings and the orbital structures as they were while the body under them
## shrinks.
##
## They are the node's children, so its scale reaches them: a moon used to get smaller and orbit
## closer as its planet was eaten, Saturn's rings drew in with Saturn, and every lane of orbital
## hardware closed in on the surface and shrank — none of which was being taken apart.  Each gets
## the inverse of the shrink: the rings and the lanes in their scale (both sit on the centre, so
## that alone holds their radius too), a moon in its scale and its orbit, which _update_moons
## divides by _shrink every frame.
func _hold_satellites() -> void:
	var inv: float = 1.0 / maxf(_shrink, 0.0001)
	if _rings != null:
		_rings.scale = Vector3.ONE * inv
	for lane: Dictionary in _infra:
		(lane["mmi"] as Node3D).scale = Vector3.ONE * inv
	for m in _moons:
		var sz: float = float(m["size"]) * inv
		(m["node"] as Node3D).scale = Vector3(sz, sz, sz)
	_update_moons(0.0)


## Close enough not to push again: this is asked on every tick of a disassembly.
static func _same_look(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return a.is_empty() and b.is_empty()
	for k: String in ["mix", "glow", "metallic"]:
		if absf(float(a.get(k, 0.0)) - float(b.get(k, 0.0))) >= 0.0005:
			return false
	return (a.get("color", Color()) as Color).is_equal_approx(b.get("color", Color()) as Color)


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
		_create_star_mirror()
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
		_update_star_mirror()
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

	# 5. Ecliptic longitude in game plane:  λ = ν + ω̄
	orbit_angle = nu + _long_periapsis_rad

	position = Vector3(
		r_vis * sin(orbit_angle),
		0.0,
		r_vis * cos(orbit_angle)
	)

## Where this body will be `days` game-days from now, in WORLD space.
##
## Exact, and pure.  A Keplerian orbit is a function of the mean anomaly and the mean anomaly
## advances at a constant rate per game-day, so a position any distance into the future is one
## Kepler solve away - the same solve _update_kepler_position does for the present.
##
## This is what lets a launch be AIMED at where its target will be instead of steered at where
## it is.  A craft that re-reads the live position every frame does arrive on the planet, but
## its whole trajectory swings round behind the planet as it orbits, so the flight has no plan
## to show: the path the player is looking at is not the path the craft will fly.
func position_in_days(days: float) -> Vector3:
	var local: Vector3 = position
	if _use_kepler:
		var m: float = _mean_anomaly_rad + _mean_motion_rad_per_day * days
		var ecc: float = _solve_kepler(fposmod(m, TAU), _eccentricity)
		var nu: float = 2.0 * atan2(
			_sqrt_1pe * sin(ecc * 0.5),
			_sqrt_1me * cos(ecc * 0.5)
		)
		var r_au: float = _semi_major_axis_au \
			* (1.0 - _eccentricity * _eccentricity) \
			/ (1.0 + _eccentricity * cos(nu))
		var r_vis: float = log(r_au + 1.0) * orbit_radius_mult
		var lam: float = nu + _long_periapsis_rad
		local = Vector3(r_vis * sin(lam), 0.0, r_vis * cos(lam))
	elif speed != 0.0:
		# The fallback circular orbit, in the same terms: _process advances orbit_angle by
		# angular_velocity * delta, and angular_velocity already carries 1/seconds_per_day, so
		# per game-day it turns TAU/EARTH_ORBIT_DAYS * speed.  (The Sun has speed 0 and stays
		# where it is, which falls out of the branch above it.)
		var ang: float = orbit_angle + (TAU / EARTH_ORBIT_DAYS) * speed * days
		local = Vector3(orbit_radius * sin(ang), 0.0, orbit_radius * cos(ang))
	var parent := get_parent() as Node3D
	return parent.to_global(local) if parent != null else local


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
## What a moon leaves between itself and the outermost structure, in scale units: the largest
## moon's own radius (0.11) and the 0.1 of jitter that can take it inward.
const MOON_CLEARANCE: float = 0.250

func _create_moons() -> void:
	var count: int = int(MOON_COUNTS.get(name.to_lower(), 0))
	if count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(name))
	# Outside this body's own band, which is wider around a small body than a large one because
	# the structures are capped in world size: the Sun's lanes end at 1.35 scale units and
	# Earth's at 2.83.
	# Off the INTACT size: a save that has the body part eaten shrinks it before its first frame,
	# which is when these are built, and the moons would come up on orbits it never had.
	var moon_inner: float = infra_band_outer(_intact_scale.x) + MOON_CLEARANCE
	for i in range(count):
		# OUTSIDE the infrastructure band, which the innermost moon used to fly through: it
		# orbited at 1.3 +- 0.1 scale units with a radius of its own, against lanes running
		# 1.020 to 1.590, so a moon passed through eight or nine shells of hardware twice an
		# orbit. The first one now clears the outermost lane, the structures on it, and its own
		# radius, with the jitter taken off the bottom.
		var radius: float = moon_inner + 0.55 * float(i) + rng.randf_range(-0.1, 0.1)
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

		# Grey level only — a moon is lit by the sun like everything else, and its night side
		# is black. This used to carry a self-emission to keep it readable where no light
		# reached, which is the same thing as saying it was never unlit.
		var g: float = rng.randf_range(0.55, 0.80)
		if tex:
			var smat := ShaderMaterial.new()
			smat.shader = POLAR_BLUR_SHADER
			smat.set_shader_parameter("albedo_tex", tex)
			smat.set_shader_parameter("self_light", 0.0)   # sunlight only
			moon.set_surface_override_material(0, smat)
		else:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(g, g, g * 0.96)
			moon.set_surface_override_material(0, mat)
		add_child(moon)

		_moons.append({
			"node":   moon,
			"radius": radius,
			"size":   msize,
			"speed":  rng.randf_range(0.5, 1.3) * (1.0 if i % 2 == 0 else -1.0),
			"angle":  rng.randf_range(0.0, TAU),
			"incl":   rng.randf_range(-0.35, 0.35),
		})
	# Through _hold_satellites rather than straight to _update_moons: a save can put the body part
	# eaten before its moons exist, and they must come into being at their own size.
	_hold_satellites()

## Advance each moon along its tilted circular orbit in the planet's local frame.
## `delta` here is GAME time, not wall-clock: the caller has already scaled it by the speed
## multiplier, so a moon's period is the same number of game-days at every rung of the ladder.
func _update_moons(delta: float) -> void:
	for m in _moons:
		var a: float = float(m["angle"]) + float(m["speed"]) * delta
		m["angle"] = a
		# In the planet's local frame, which shrinks with it while it is taken apart: divided back
		# out, so the moon keeps the orbit it had (see _hold_satellites).
		var r: float = float(m["radius"]) / _shrink
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
## The maps carry the hardware's own colour, and albedo_color is left WHITE so nothing
## multiplies through them.  They were greyscale for a long time, back when the lane tinted
## them; the lane's grouping now lives in the material's emission instead.  A missing or
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
##
## "shkadov" is gone from here, and is the only model to have been retired rather than adopted.
## It was a stepped dish on a boom with a statite bus behind it, authored at lane scale, and the
## mirror is now ONE sail a hundred times that across: a piece of satellite hardware the width
## of a star.  It is built as a plain spherical cap instead — see "The Shkadov mirror" below.
## res://models/orbital_shkadov.glb and its two maps are no longer loaded by anything.
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
	"station": "res://models/orbital_construction_station.glb",
	"sunshade": "res://models/orbital_sunshade.glb",
	"swarm_relay": "res://models/orbital_swarm_relay.glb",
	"thermal": "res://models/orbital_thermal_radiator.glb",
	"telescope": "res://models/orbital_telescope.glb",
	"uplink":  "res://models/orbital_uplink.glb",
}
static var _model_mesh_cache: Dictionary = {}
static var _model_scale_cache: Dictionary = {}

## How much to scale lane model `kind` by, in the body's own units, so that it is drawn
## infra_structure_size(body_scale) world units across.
##
## The models are authored at whatever size suited each one in Blender and ranged over 2.5x:
## 0.178 units for a relay satellite against 0.453 for a ring store, with the Orbital Habitat
## alone wider than Mercury's radius. Normalising here rather than in the .glb files keeps the
## authoring free and the band's geometry answerable to one number.
##
## The LONGEST dimension, not the volume or the diagonal, because the longest is what bounds the
## radial reach of a structure however it is turned, and the lane step is set against it. Shape
## is untouched: a flat ring stays a flat ring, it is just a flat ring the size of everything
## else. Cached per kind beside the meshes themselves.
static func infra_model_scale(kind: String, body_scale: float) -> float:
	return infra_structure_size(body_scale) / maxf(body_scale, 0.0001) * infra_model_norm(kind)


## One over lane model `kind`'s longest dimension: multiply by a size to draw it that size.
## The belt asks for this directly — its lanes are heliocentric and far wider apart than a
## body's, so its hardware is drawn to its own gap by the same three-quarters rule.
static func infra_model_norm(kind: String) -> float:
	if _model_scale_cache.has(kind):
		return _model_scale_cache[kind]
	var a: AABB = _model_mesh(kind).get_aabb()
	var longest: float = maxf(a.size.x, maxf(a.size.y, a.size.z))
	var f: float = 1.0 / maxf(longest, 0.0001)
	_model_scale_cache[kind] = f
	return f

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

## Material for one orbital lane: its own baked map, lit enough to read in a scene that is
## mostly shadow.
##
## NO LANE TINT. The colour comes from the map and from nowhere else. The lane's grouping colour
## used to be applied as flat emission, and because emission without a texture floods the whole
## hull with one value it was, at the strength it needs to be visible here, the only colour left
## — a laser dish came out uniformly pink and a telescope uniformly blue, with the gold blanket
## and the cell grids underneath invisible. The maps carry the hardware's own colour; that is
## what they are for.
func _infra_material(tex_path: String = "") -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _lane_texture(tex_path)
	# WHITE. albedo_color MULTIPLIES through the texture, so any tint here would muddy the
	# hardware colours the map carries — gold blanket, blue solar cells, white tankage.
	m.albedo_color   = Color.WHITE
	m.metallic       = 0.3
	m.roughness      = 0.7
	# Surface relief, where the model has it baked.  The albedo map carries the same
	# pattern as painted light and dark, which does not move when the light does; this is
	# what makes the plating and the cell grids actually catch it.
	var nrm: Texture2D = _lane_normal(tex_path)
	if nrm != null:
		m.normal_enabled = true
		m.normal_texture = nrm
	# NO self-light. Everything in the system is lit by the sun and nothing else, so a structure
	# on the night side of its planet is black — which is what it would be.
	#
	# This carried a faint emission for years, then briefly carried it through the albedo map so
	# the glow followed the plating. Both were the same compromise: a stand-in for lighting,
	# keeping hardware readable where the sun does not reach it. It also meant nothing on screen
	# was ever actually dark.
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
	# The lanes are laid out for the body as it is whole, and held there (_hold_satellites), so a
	# save that loads a world part eaten builds the band it had rather than one fitted to the
	# remnant.  The star's own scale moves with its age and is never shrunk, so this is its scale.
	var inv: float = 1.0 / maxf(_shrink, 0.0001)
	var body_scale: float = scale.x * inv
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
		mmi.material_override = _infra_material(str(spec.get("texture", "")))
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ext: float = infra_lane_radius(int(spec["order"]), body_scale) + 0.5
		mmi.custom_aabb = AABB(Vector3(-ext, -ext, -ext), Vector3(ext * 2.0, ext * 2.0, ext * 2.0))
		mmi.scale = Vector3.ONE * inv
		add_child(mmi)
		_infra.append({
			"mm":     mm,
			"mmi":    mmi,
			"type":   str(spec["type"]),
			"radius": infra_lane_radius(int(spec["order"]), body_scale),
			# Normalised model scale, in the body's own units: the lanes are children of the
			# scaled body, so an instance basis of this size draws a structure INFRA_SIZE_FRAC
			# of the body across, on every body, with nothing to cancel.
			"mscale": infra_model_scale(str(spec["mesh"]), body_scale),
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
	# NOTHING cancels the body's scale here any more. The lanes are children of the scaled body,
	# so an instance basis of lane["mscale"] draws a structure INFRA_SIZE_FRAC of the body across
	# wherever it is — which is what keeps a lane's hardware inside the gap to the next lane,
	# since that gap scales with the body too.
	#
	# It used to divide by the scale to hold every structure at one world size on every body, so
	# that they stayed visible around the small ones. They did: around Mercury, whose radius is
	# 0.161 world units, an orbital habitat was 0.365 across — the planet was the smaller of the
	# two — and the lanes it crossed were 0.013 apart.
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
			var ms: float = float(lane["mscale"])
			mm.set_instance_transform(i, Transform3D(
				infra_orientation(pos, onormal).scaled(Vector3(ms, ms, ms)), pos))

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
		# Through the lane's own node, which is held at the body's whole size while it is being
		# taken apart: the slot is where the structure is drawn, not where the remnant's scale
		# would put it.
		return (lane["mmi"] as Node3D).to_global(Vector3(r * cos(th), z * sin(incl), z * cos(incl)))
	return global_position


# ── The Shkadov mirror (star only) ────────────────────────────────────────
## The one orbital structure with no lane, because it is not in orbit and there is not a fleet
## of it.
##
## A statite does not orbit: it hovers, held off the star by the pressure of the light it is
## reflecting, so it stands still over one spot on the photosphere while everything in the band
## circles past it.  And buildings.gd caps it at one ("max_count"), so what levelling it up buys
## is a WIDER mirror and not a second one — which is why this is a single MeshInstance3D built
## from a number instead of a MultiMesh lane filled from a count.
##
## That number is SolarSystem.star_mirror_coverage, the same one StarModel.shkadov_thrust_n
## turns into newtons, so the picture cannot drift from the physics — and with the sail drawn as
## a SPHERICAL CAP on a shell concentric with the star, it is not merely proportional to it: the
## cap's own area over the sphere's is exactly (1 − cos th)/2, which is the coverage the thrust
## was computed from.  What is on screen is the number, not a stand-in for it.
##
## A mirror with no coverage — none built, or the one built switched off — is a mirror furled,
## and not drawn.
##
## It is NOT hidden with the lanes past 100x.  They are hidden because a few hundred structures
## smeared round the Sun at a thousand times real time is a bright knot that says nothing about
## where anything is; the mirror does not move, so it cannot smear, and at that speed it is the
## one piece of stellar engineering still worth looking at.
##
## There is no model.  It was drawn with the lane mesh the fleet used — a stepped dish on a boom
## with a statite bus behind it — which at a hundred times its authored size was a piece of
## satellite hardware the width of a star, and whose boom reaching back towards the photosphere
## had to be solved around so it did not end up inside it.  A sail is a surface.  This one is
## built here, at the size it needs to be, which is also the only way it can be a cap rather
## than a disc.

## How far the sail flies above the photosphere, in the star's own local units — where the
## surface is at 0.5, because the body mesh is a unit-diameter sphere and the node carries the
## scale.
##
## A cap is at this distance at EVERY point of itself, rim included, which is what lets it be
## any size at all: a flat disc standing on the star has its rim further out than its centre, so
## a wide one reached up into the Dyson swarm's inner lane, and a curved sheet does not.
const MIRROR_GAP: float = 0.02
## Which side of the star it stands on.  "One side" is the only constraint the physics puts on
## it, so this is a visual choice: 35 degrees out of the ecliptic, high enough that the default
## camera — which looks down on the system — never catches the sail edge-on or loses it behind
## the star, and far enough off the pole that it still reads as standing to one side rather than
## as a cap on top.
const MIRROR_SIDE := Vector3(0.671, 0.574, 0.469)
## How finely the cap is built: rings from its pole down to its rim, and sectors around it.  It
## is rebuilt only when the coverage moves, which is when the mirror is built, retrofitted,
## idled or demolished, so this costs nothing per frame.
const MIRROR_RINGS: int = 16
const MIRROR_SECTORS: int = 64
var _mirror: MeshInstance3D = null
## The coverage the mirror is currently built at, so the mesh is rebuilt only when it moves.
## Starts negative because zero is a real value and means "furled".
var _mirror_coverage: float = -1.0

## The half-angle of sky a mirror of `coverage` subtends, in radians.
##
## A spherical cap of half-angle th covers (1 − cos th)/2 of the sky, so the half-angle a given
## coverage implies is that inverted.  This is where the two halves of the mirror meet: coverage
## is what the thrust is computed from, and this is the cap that is built from it.
##
## It needs no bound.  Coverage runs to 1.0 — the dev console and the tests drive it there — and
## a half-angle of pi is a cap that has closed into a complete shell around the star, which is
## what covering the whole sky means.  The flat disc this replaced had no such limit: its rim
## ran away to infinity as the half-angle approached a right angle, and had to be clamped.
static func mirror_half_angle(coverage: float) -> float:
	return acos(clampf(1.0 - 2.0 * clampf(coverage, 0.0, 1.0), -1.0, 1.0))

## The distance every point of the sail stands from the star's centre, in local units.
static func mirror_standoff() -> float:
	return 0.5 + MIRROR_GAP

## How wide the sail is, in local units: the radius of its rim about its own axis.  Not what it
## is drawn from — the cap carries its own size — but what "it got bigger" means as a number.
static func mirror_radius(coverage: float) -> float:
	return mirror_standoff() * sin(mirror_half_angle(coverage))

## The sail: a spherical cap of half-angle `half_angle`, on the shell at mirror_standoff(),
## centred on +Y.  Direction is left to the transform, so the mesh depends on the size alone.
##
## Wound a → c → b rather than a → b → c.  Godot's front faces are the other way round from the
## order the rings come out in, and a surface built the obvious way is a surface whose front is
## its inside: the renderer culls the faces pointing at you and keeps the ones facing away.
## That is the same mirrored-winding fault that had the orbital structures and then the belt
## shaded from the inside, reached here by index order instead of by a negative determinant.
## Settled by measurement, not by reasoning: SurfaceTool.generate_normals() uses the engine's own
## convention, and on this order it agrees with the outward normals set below.
static func mirror_cap_mesh(half_angle: float) -> ArrayMesh:
	var r: float = mirror_standoff()
	var th: float = clampf(half_angle, 0.0, PI)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i in range(MIRROR_RINGS + 1):
		var t: float = th * float(i) / float(MIRROR_RINGS)
		for j in range(MIRROR_SECTORS + 1):
			var phi: float = TAU * float(j) / float(MIRROR_SECTORS)
			var dir := Vector3(sin(t) * cos(phi), cos(t), sin(t) * sin(phi))
			verts.append(dir * r)
			norms.append(dir)
			uvs.append(Vector2(float(j) / float(MIRROR_SECTORS),
				float(i) / float(MIRROR_RINGS)))
	var idx := PackedInt32Array()
	var row: int = MIRROR_SECTORS + 1
	# A ring at a pole is one point repeated, so the quad against it is a triangle and the other
	# half of it is three vertices in a line.  Left in, those are sixty-four zero-area triangles
	# at the top of every cap and another sixty-four at the bottom of a closed one - degenerate,
	# so they have no normal of their own and nothing can say which way they face.  The cap is a
	# fan at each pole instead.
	var closed: bool = th >= PI - 1.0e-9
	for i in range(MIRROR_RINGS):
		for j in range(MIRROR_SECTORS):
			var a: int = i * row + j
			var b: int = a + 1
			var c: int = b + row
			var d: int = a + row
			if i > 0:
				idx.append_array([a, c, b])
			if not (closed and i == MIRROR_RINGS - 1):
				idx.append_array([a, d, c])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Where the sail stands, in the star's local frame: a pure rotation taking the cap's +Y axis
## onto MIRROR_SIDE.  No translation and no scale — the mesh is already built at the right
## distance and the right size, and the star's own scale is inherited through the parent, which
## is what keeps a share of the sky a share of the sky as the star swells up the giant branch.
##
## Through infra_orientation for the guarantee it carries rather than for the frame it picks:
## Basis(x, y, z) is right-handed only when x cross y is z, and a mirrored basis reverses the
## effective winding of everything it draws.  Any reference not parallel to the radial will do
## here, because the mirror holds one position for ever.
static func mirror_transform() -> Transform3D:
	return Transform3D(infra_orientation(MIRROR_SIDE, Vector3.UP), Vector3.ZERO)

## The sail's material.  No map and no self-light: a mirror is a surface, and everything in the
## system is lit by the sun and nothing else — so the face turned away from the star is black,
## which is what it would be.  The six lights of the sun's shell all sit on the photosphere,
## inside the sail's standoff, so from outside that is the only face there is to see and the
## mirror reads as a silhouette against the star it stands on.
static func mirror_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.90, 0.92, 0.96)
	m.metallic = 0.9
	m.roughness = 0.15
	# A sail has no back and no front as far as the renderer is concerned: it is one surface and
	# has to exist from both sides of itself.
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

## Raise the mirror's node, hidden until there is a mirror to draw.
func _create_star_mirror() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "%s_shkadov_mirror" % name
	mi.material_override = mirror_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = mirror_transform()
	mi.visible = false
	add_child(mi)
	_mirror = mi
	_update_star_mirror()

## Follow the coverage: build the cap that coverage implies, or hide the sail when there is
## none.  Called every frame and does nothing on almost all of them — the number only moves when
## the mirror is built, retrofitted, idled or demolished.
func _update_star_mirror() -> void:
	if _mirror == null:
		return
	var cov: float = SolarSystem.star_mirror_coverage
	if cov == _mirror_coverage:
		return
	_mirror_coverage = cov
	if cov <= 0.0:
		_mirror.visible = false
		return
	_mirror.mesh = mirror_cap_mesh(mirror_half_angle(cov))
	_mirror.visible = true

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
	# Its own size whatever the body has come to, if a save made it smaller first.
	_rings.scale       = Vector3.ONE / maxf(_shrink, 0.0001)
	add_child(_rings)
