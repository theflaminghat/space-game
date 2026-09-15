class_name AsteroidBelt
extends Planet

## The main asteroid belt as a world the player can select, settle and build on.
##
## It IS a Planet — the type every system that addresses a world expects: launches fly to it,
## the camera focuses on it, colonies are founded on it, its orbital structures appear around
## it, and it hides, snaps and is engulfed exactly as the planets are.  The body the Planet
## machinery draws and moves is CERES, the belt's largest member and the hub its traffic lands
## at; its orbit comes from PlanetData.PLANETS["asteroid_belt"], along with the composition the
## belt's mines work (the whole belt's bulk chemistry).
##
## What it adds is the belt itself: a field of procedural rocks between BELT_INNER_AU and
## BELT_OUTER_AU, each on its own Keplerian orbit, and a hit-test over the whole band so the
## player can click anywhere on the belt rather than having to find Ceres (see body_picker.gd).
## Its orbital structures also differ from a planet's: they circle the Sun among the rocks, not
## the hub (see _create_infra_lanes).  Which structures can be built here is decided by the
## "belt" body type in BuildingData.

const BODY_NAME: String = "asteroid_belt"

## Ceres at the same visual scale convention as the planets (size = ln(scale + 1)).
const HUB_SCALE: float = 0.15
const HUB_COLOR: Color = Color(0.45, 0.42, 0.38)

# ── Scale constants (must match Planet.orbit_radius_mult; EARTH_ORBIT_DAYS is Planet's) ──
const ORBIT_RADIUS_MULT: float = 32.0

# ── Belt shape ─────────────────────────────────────────────────────────────────
## Real main-belt bounds are ~2.06–3.27 AU; we round to a clean band that renders
## entirely in the gap between Mars (1.524 AU) and Jupiter (5.203 AU).
const BELT_INNER_AU: float = 2.10
const BELT_OUTER_AU: float = 3.30
const ASTEROID_COUNT: int  = 160
const MESH_VARIANTS:  int  = 5

## Kirkwood gaps — mean-motion resonances with Jupiter that real asteroids avoid.
## Each entry is [center_AU, half_width_AU]; samples landing inside are rejected.
const KIRKWOOD_GAPS: Array = [
	[2.50, 0.045],   # 3:1 resonance
	[2.82, 0.040],   # 5:2 resonance
	[2.95, 0.035],   # 7:3 resonance
	[3.27, 0.050],   # 2:1 resonance (outer edge)
]

## Points per edge when the band's outline is projected for the hover highlight.
const OUTLINE_SEGMENTS: int = 96

## Structure lanes sit this far inside the band's edges, so none of them rides the boundary.
const INFRA_LANE_MARGIN_AU: float = 0.15
## Largest tilt of a structure lane out of the ecliptic: flatter than the rocks (≤ 9°), since
## what the belt's settlers build follows the busy plane rather than the scattered outliers.
const INFRA_LANE_MAX_INCL: float = 0.07   # rad, ~4°

# ── Per-asteroid orbital state (flat parallel arrays for cache efficiency) ──────
var _a_au:        PackedFloat32Array = PackedFloat32Array()  # semi-major axis (AU)
var _ecc:         PackedFloat32Array = PackedFloat32Array()  # eccentricity
var _peri:        PackedFloat32Array = PackedFloat32Array()  # longitude of periapsis (rad)
var _mean_anom:   PackedFloat32Array = PackedFloat32Array()  # current mean anomaly (rad)
var _mean_motion: PackedFloat32Array = PackedFloat32Array()  # rad per game-day
var _incl_amp:    PackedFloat32Array = PackedFloat32Array()  # vertical amplitude (game units)
var _node_phase:  PackedFloat32Array = PackedFloat32Array()  # phase of vertical bob (rad)
var _size:        PackedFloat32Array = PackedFloat32Array()  # per-instance scale
var _spin_axis:   PackedVector3Array = PackedVector3Array()  # tumble axis (unit)
var _spin_rate:   PackedFloat32Array = PackedFloat32Array()  # tumble speed (rad/day)
var _spin_angle:  PackedFloat32Array = PackedFloat32Array()  # current tumble angle (rad)
var _variant:     PackedInt32Array   = PackedInt32Array()    # which mesh / MultiMesh
var _local_idx:   PackedInt32Array   = PackedInt32Array()    # instance index within that MultiMesh

## One MultiMesh per mesh variant, all under _rocks.
var _multimeshes: Array[MultiMesh] = []
## The rocks live in the ORBIT CENTRE's frame, not Ceres's: they circle the Sun, not the hub.
## top_level keeps them out of the hub's moving, scaled transform while still inheriting its
## visibility, so they hide, show and are engulfed along with the rest of the belt.
var _rocks: Node3D = null


func _init() -> void:
	name = BODY_NAME
	type = Planet.Type.ROCKY
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 24
	sphere.rings = 12
	mesh = sphere
	scale = Vector3.ONE * HUB_SCALE
	var mat := StandardMaterial3D.new()
	mat.albedo_color = HUB_COLOR
	mat.roughness = 1.0
	# The same faint self-light the moons carry, so a small dark body stays readable.
	mat.emission_enabled = true
	mat.emission = HUB_COLOR
	mat.emission_energy_multiplier = 0.15
	set_surface_override_material(0, mat)


func _ready() -> void:
	super._ready()                        # Ceres's Kepler orbit, visibility hooks, sizing
	_rocks = Node3D.new()
	_rocks.name = "BeltRocks"
	_rocks.top_level = true
	add_child(_rocks)
	_rocks.global_transform = _centre_xform()
	_build_belt()


func _process(delta: float) -> void:
	super._process(delta)                 # the hub's orbit, orbit line, structure lanes
	if _rocks == null:
		return
	_rocks.global_transform = _centre_xform()
	if not SolarSystem.solar_system_active:
		return
	if SolarSystem.ui_paused or SolarSystem.paused:
		return
	if SolarSystem.seconds_per_day <= 0.0:
		return
	var delta_days: float = delta / SolarSystem.seconds_per_day
	for i in range(ASTEROID_COUNT):
		_mean_anom[i]  = fposmod(_mean_anom[i] + _mean_motion[i] * delta_days, TAU)
		_spin_angle[i] = fposmod(_spin_angle[i] + _spin_rate[i] * delta_days, TAU)
	_update_transforms()


## The frame every orbit is drawn in: the node that parents the planets, centred on the Sun.
func _centre_xform() -> Transform3D:
	var p := get_parent() as Node3D
	return p.global_transform if p else Transform3D.IDENTITY


# ── Picking ────────────────────────────────────────────────────────────────────

## Visual radius (game units) of the belt's inner and outer edges.
func band_radii() -> Vector2:
	return Vector2(log(BELT_INNER_AU + 1.0) * ORBIT_RADIUS_MULT,
		log(BELT_OUTER_AU + 1.0) * ORBIT_RADIUS_MULT)


## Distance along the camera ray under `screen_pos` at which it crosses the belt's band, or INF
## if it misses.  The band is the annulus between the belt's edges in the orbital plane, so the
## whole belt is a click target from any angle except exactly edge-on.
func band_hit(cam: Camera3D, screen_pos: Vector2) -> float:
	if not is_visible_in_tree():
		return INF
	var xf: Transform3D = _centre_xform()
	var n: Vector3 = xf.basis.y.normalized()
	var origin: Vector3 = cam.project_ray_origin(screen_pos)
	var dir: Vector3 = cam.project_ray_normal(screen_pos)
	var denom: float = dir.dot(n)
	if absf(denom) < 1.0e-4:
		return INF                        # looking along the plane: no well-defined crossing
	var t: float = (xf.origin - origin).dot(n) / denom
	if t <= 0.0:
		return INF                        # the plane is behind the camera
	var local: Vector3 = xf.affine_inverse() * (origin + dir * t)
	var r: float = Vector2(local.x, local.z).length()
	var edges: Vector2 = band_radii()
	return t if r >= edges.x and r <= edges.y else INF


## The belt's two edges projected to the screen, as polylines for the hover highlight.  Each edge
## is split wherever it passes behind the camera, so a camera inside the belt still gets clean
## arcs instead of lines torn across the screen.
func band_outline(cam: Camera3D) -> Array:
	var out: Array = []
	var xf: Transform3D = _centre_xform()
	var edges: Vector2 = band_radii()
	for r: float in [edges.x, edges.y]:
		var run := PackedVector2Array()
		for i in range(OUTLINE_SEGMENTS + 1):
			var a: float = TAU * float(i) / float(OUTLINE_SEGMENTS)
			var wp: Vector3 = xf * Vector3(r * sin(a), 0.0, r * cos(a))
			if cam.is_position_behind(wp):
				if run.size() >= 2:
					out.append(run)
				run = PackedVector2Array()
				continue
			run.append(cam.unproject_position(wp))
		if run.size() >= 2:
			out.append(run)
	return out


# ── Orbital structures ─────────────────────────────────────────────────────────

## A planet's orbital structures circle the planet (Planet._create_infra_lanes).  The belt's
## circle the SUN: anything built in the belt is out among the asteroids — on them or flying
## beside them — on its own heliocentric orbit, not parked around Ceres.  So each structure type
## gets a lane at its own radius across the band, in the orbit centre's frame alongside the
## rocks, and every lane advances at the Keplerian rate for that radius on the same game-day
## clock the rocks use.  The "ground" types that get no lane on a rocky planet get one here: in
## the belt, the ground is itself in orbit.
func _create_infra_lanes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(BODY_NAME + "_infra")
	var n: int = INFRA_LANES.size()
	var ext: float = log(BELT_OUTER_AU + 1.0) * ORBIT_RADIUS_MULT + 2.0
	for i in range(n):
		var spec: Dictionary = INFRA_LANES[i]
		var a_au: float = lerpf(BELT_INNER_AU + INFRA_LANE_MARGIN_AU,
			BELT_OUTER_AU - INFRA_LANE_MARGIN_AU, (float(i) + 0.5) / float(n))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _infra_mesh(str(spec["mesh"]))
		mm.instance_count = INFRA_MAX_PER_LANE
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_infra_%s" % [BODY_NAME, str(spec["type"]).replace(" ", "_")]
		mmi.multimesh = mm
		mmi.material_override = _infra_material(spec["color"])
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3(-ext, -ext, -ext), Vector3(ext * 2.0, ext * 2.0, ext * 2.0))
		_rocks.add_child(mmi)
		_infra.append({
			"mm":     mm,
			"type":   str(spec["type"]),
			"r_vis":  log(a_au + 1.0) * ORBIT_RADIUS_MULT,
			"motion": TAU / (EARTH_ORBIT_DAYS * pow(a_au, 1.5)),   # rad per game-day
			"phase":  rng.randf() * TAU,
			"incl":   rng.randf_range(-INFRA_LANE_MAX_INCL, INFRA_LANE_MAX_INCL),
			"node":   rng.randf() * TAU,
		})
	_update_infra(0.0)


## Poll how many of each structure the belt holds (throttled, as a planet does) and lay them out
## evenly around their heliocentric lane, advancing the lane on the game-day clock.
func _update_infra(delta: float) -> void:
	_infra_poll += delta
	var repoll: bool = _infra_poll >= 0.5
	if repoll:
		_infra_poll = 0.0
	var game: Node = get_tree().current_scene
	# Orbits advance only while the simulation runs; counts refresh regardless, so something
	# built while paused appears at once.
	var delta_days: float = 0.0
	if SolarSystem.solar_system_active and not SolarSystem.paused and not SolarSystem.ui_paused \
			and SolarSystem.seconds_per_day > 0.0:
		delta_days = delta / SolarSystem.seconds_per_day
	for lane: Dictionary in _infra:
		var mm: MultiMesh = lane["mm"]
		lane["phase"] = fposmod(float(lane["phase"]) + float(lane["motion"]) * delta_days, TAU)
		if repoll and game and game.has_method("_count_building"):
			mm.visible_instance_count = mini(
				int(game._count_building(BODY_NAME, str(lane["type"]))), INFRA_MAX_PER_LANE)
		var count: int = mm.visible_instance_count
		for i in range(count):
			var pos: Vector3 = infra_position(lane, i, count)
			# Each structure's up-axis points away from the Sun, like a satellite bus.
			var radial: Vector3 = pos.normalized()
			var ref: Vector3 = Vector3.UP if absf(radial.y) < 0.95 else Vector3.RIGHT
			var t1: Vector3 = radial.cross(ref).normalized()
			var t2: Vector3 = radial.cross(t1)
			mm.set_instance_transform(i, Transform3D(Basis(t1, radial, t2), pos))


## Where structure `i` of `count` on `lane` is right now, in the orbit centre's frame: evenly
## spaced around the Sun, in the same convention as every other orbit here (x = r·sin,
## z = r·cos), tilted out of the ecliptic about the lane's node.
static func infra_position(lane: Dictionary, i: int, count: int) -> Vector3:
	var r: float = float(lane["r_vis"])
	var th: float = float(lane["phase"]) + TAU * float(i) / float(maxi(count, 1))
	return Vector3(r * sin(th), r * sin(th - float(lane["node"])) * sin(float(lane["incl"])),
		r * cos(th))


# ── Construction ───────────────────────────────────────────────────────────────

func _build_belt() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xA57E401D   # fixed seed → identical belt every run (deterministic saves)

	# 1. Generate the distinct procedural rock meshes and their MultiMesh holders.
	var shared_mat := _make_asteroid_material()
	var per_variant_count: PackedInt32Array = PackedInt32Array()
	per_variant_count.resize(MESH_VARIANTS)
	per_variant_count.fill(0)

	for v in range(MESH_VARIANTS):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors       = true
		mm.mesh             = _make_asteroid_mesh(int(rng.randi()))
		_multimeshes.append(mm)

		var mmi := MultiMeshInstance3D.new()
		mmi.name             = "AsteroidBelt_%d" % v
		mmi.multimesh        = mm
		mmi.material_override = shared_mat
		mmi.cast_shadow      = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Instances are placed up to ~51 units out (incl. eccentricity) and ~7 units
		# above/below the plane.  An explicit AABB stops the whole belt from being
		# frustum-culled when the orbit centre leaves the view.
		mmi.custom_aabb      = AABB(Vector3(-56, -14, -56), Vector3(112, 28, 112))
		_rocks.add_child(mmi)

	# 2. Reserve space in all per-asteroid arrays.
	_a_au.resize(ASTEROID_COUNT)
	_ecc.resize(ASTEROID_COUNT)
	_peri.resize(ASTEROID_COUNT)
	_mean_anom.resize(ASTEROID_COUNT)
	_mean_motion.resize(ASTEROID_COUNT)
	_incl_amp.resize(ASTEROID_COUNT)
	_node_phase.resize(ASTEROID_COUNT)
	_size.resize(ASTEROID_COUNT)
	_spin_axis.resize(ASTEROID_COUNT)
	_spin_rate.resize(ASTEROID_COUNT)
	_spin_angle.resize(ASTEROID_COUNT)
	_variant.resize(ASTEROID_COUNT)
	_local_idx.resize(ASTEROID_COUNT)

	# 3. Roll orbital parameters for every asteroid.
	for i in range(ASTEROID_COUNT):
		# Semi-major axis: triangular distribution biases toward the dense mid-belt,
		# then reject samples that fall inside a Kirkwood resonance gap.
		var a_au: float = _sample_semi_major(rng)
		_a_au[i] = a_au

		# Low eccentricity (mean ~0.07), skewed small.
		_ecc[i] = pow(rng.randf(), 1.6) * 0.18
		_peri[i] = rng.randf() * TAU
		_mean_anom[i] = rng.randf() * TAU

		# Kepler's third law: T = 365.25 · a^1.5 (days) → n = TAU / T.
		var period_days: float = EARTH_ORBIT_DAYS * pow(a_au, 1.5)
		_mean_motion[i] = TAU / period_days

		# Inclination → vertical bob amplitude.  Bias toward the ecliptic plane.
		var incl: float = pow(rng.randf(), 2.2) * deg_to_rad(9.0)
		var a_vis: float = log(a_au + 1.0) * ORBIT_RADIUS_MULT
		_incl_amp[i] = a_vis * sin(incl)
		_node_phase[i] = rng.randf() * TAU

		# Size: mostly tiny rubble, a few large (Vesta/Pallas-class) bodies.
		_size[i] = lerpf(0.05, 0.32, pow(rng.randf(), 3.0))

		# Random tumble.
		_spin_axis[i]  = _random_unit_vector(rng)
		_spin_rate[i]  = rng.randf_range(0.15, 1.8) * (1.0 if rng.randf() < 0.5 else -1.0)
		_spin_angle[i] = rng.randf() * TAU

		# Assign to a mesh variant (round-robin) and record its local index.
		var v: int = i % MESH_VARIANTS
		_variant[i]   = v
		_local_idx[i] = per_variant_count[v]
		per_variant_count[v] += 1

	# 4. Size each MultiMesh to its instance count and paint per-instance colours.
	for v in range(MESH_VARIANTS):
		_multimeshes[v].instance_count = per_variant_count[v]

	for i in range(ASTEROID_COUNT):
		var tint: Color = _asteroid_tint(rng)
		_multimeshes[_variant[i]].set_instance_color(_local_idx[i], tint)

	# 5. Place every asteroid once so the belt is correct on the very first frame
	#    (even while the game starts paused).
	_update_transforms()


## Triangular semi-major-axis sample that avoids the Kirkwood gaps.
func _sample_semi_major(rng: RandomNumberGenerator) -> float:
	for _attempt in range(8):
		# Average of two uniforms → triangular peak at mid-belt.
		var a: float = (rng.randf_range(BELT_INNER_AU, BELT_OUTER_AU)
			+ rng.randf_range(BELT_INNER_AU, BELT_OUTER_AU)) * 0.5
		var in_gap := false
		for gap in KIRKWOOD_GAPS:
			if absf(a - float(gap[0])) < float(gap[1]):
				in_gap = true
				break
		if not in_gap:
			return a
	# Fallback after repeated gap hits — accept the last roll.
	return (rng.randf_range(BELT_INNER_AU, BELT_OUTER_AU)
		+ rng.randf_range(BELT_INNER_AU, BELT_OUTER_AU)) * 0.5


# ── Procedural mesh + material ─────────────────────────────────────────────────

## Build one lumpy "potato" rock by radially displacing a UV sphere with simplex
## noise, then stretching it along random axes so each variant has its own shape.
func _make_asteroid_mesh(mesh_seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = mesh_seed

	var noise := FastNoiseLite.new()
	noise.seed       = mesh_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency  = rng.randf_range(0.9, 1.8)

	var lump: float = rng.randf_range(0.28, 0.46)       # displacement strength
	var axis_scale := Vector3(                          # elongation per variant
		rng.randf_range(0.75, 1.25),
		rng.randf_range(0.60, 1.00),
		rng.randf_range(0.80, 1.25))

	const RINGS:   int = 5
	const SECTORS: int = 6

	# Pre-compute the displaced vertex grid.
	var grid: Array = []
	for r in range(RINGS + 1):
		var theta: float = PI * float(r) / float(RINGS)
		var row := PackedVector3Array()
		for s in range(SECTORS + 1):
			var phi: float = TAU * float(s) / float(SECTORS)
			var dir := Vector3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))
			var n: float = noise.get_noise_3d(dir.x * 2.0, dir.y * 2.0, dir.z * 2.0)  # [-1,1]
			var rad: float = maxf(0.45, 1.0 + lump * n)
			var v := dir * rad
			row.append(Vector3(v.x * axis_scale.x, v.y * axis_scale.y, v.z * axis_scale.z))
		grid.append(row)

	# Emit two triangles per quad; generate_normals() gives a faceted rocky look.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in range(RINGS):
		var row0: PackedVector3Array = grid[r]
		var row1: PackedVector3Array = grid[r + 1]
		for s in range(SECTORS):
			var v00: Vector3 = row0[s]
			var v10: Vector3 = row1[s]
			var v11: Vector3 = row1[s + 1]
			var v01: Vector3 = row0[s + 1]
			# Outward winding for Y-up sphere parameterisation.
			st.add_vertex(v00); st.add_vertex(v01); st.add_vertex(v11)
			st.add_vertex(v00); st.add_vertex(v11); st.add_vertex(v10)
	st.generate_normals()
	return st.commit()


func _make_asteroid_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	# Base albedo white so the per-instance MultiMesh colour fully defines the tint.
	mat.albedo_color = Color.WHITE
	mat.roughness    = 1.0
	mat.metallic     = 0.0
	mat.vertex_color_use_as_albedo = true   # MultiMesh instance colours tint the rock
	mat.cull_mode    = BaseMaterial3D.CULL_BACK
	return mat


# ── Per-frame orbital motion ───────────────────────────────────────────────────

## Recompute and upload every asteroid's MultiMesh transform from current state.
func _update_transforms() -> void:
	for i in range(ASTEROID_COUNT):
		var m: float = _mean_anom[i]
		var e: float = _ecc[i]

		# Cheap orbit: equation-of-centre approximation (first order in e) is plenty
		# for tiny background bodies and avoids a Newton-Raphson solve per asteroid.
		var nu:   float = m + 2.0 * e * sin(m)             # true anomaly ≈
		var r_au: float = _a_au[i] * (1.0 - e * cos(m))    # radius ≈ a(1 − e·cosE), E≈M
		var r_vis: float = log(r_au + 1.0) * ORBIT_RADIUS_MULT
		var ang: float = nu + _peri[i]

		var pos := Vector3(
			r_vis * sin(ang),
			_incl_amp[i] * sin(ang + _node_phase[i]),
			r_vis * cos(ang))

		var basis := Basis(_spin_axis[i], _spin_angle[i]).scaled(
			Vector3(_size[i], _size[i], _size[i]))

		_multimeshes[_variant[i]].set_instance_transform(
			_local_idx[i], Transform3D(basis, pos))


# ── Helpers ────────────────────────────────────────────────────────────────────

func _random_unit_vector(rng: RandomNumberGenerator) -> Vector3:
	# Uniform direction on the unit sphere.
	var z: float = rng.randf_range(-1.0, 1.0)
	var t: float = rng.randf() * TAU
	var r: float = sqrt(maxf(0.0, 1.0 - z * z))
	return Vector3(r * cos(t), r * sin(t), z)


## Weathered rock tints: mostly grey-brown C-type, some lighter S-type, rare bright.
func _asteroid_tint(rng: RandomNumberGenerator) -> Color:
	var roll: float = rng.randf()
	var base: Color
	if roll < 0.70:
		base = Color(0.34, 0.30, 0.26)   # dark carbonaceous (C-type)
	elif roll < 0.93:
		base = Color(0.52, 0.45, 0.36)   # silicaceous (S-type)
	else:
		base = Color(0.66, 0.62, 0.55)   # bright metallic (M-type)
	var j: float = rng.randf_range(0.85, 1.15)  # brightness jitter
	return Color(
		clampf(base.r * j, 0.0, 1.0),
		clampf(base.g * j, 0.0, 1.0),
		clampf(base.b * j, 0.0, 1.0))
