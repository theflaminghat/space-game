extends Node3D

## Procedural orbital decoration attached to WorldRoot/Planets — the node that
## parents every planet — so it shares the planets' orbit-centered local space and
## their log-scaled distance convention (r_vis = ln(a_AU + 1) · ORBIT_RADIUS_MULT).
##
## Two features live here, both drawn with MultiMesh (one draw call each) and both
## advanced on their own Keplerian-rate orbits, mirroring Planet visibility/pause:
##
##   • The main asteroid belt between Mars and Jupiter (purely visual).
##   • A Dyson swarm of solar collectors hugging the Sun across several tilted
##     orbital lanes.  Each collector is one Solar Satellite the player has
##     manufactured and launched to the Sun — so the swarm literally grows around
##     the star, lane by lane, as the megastructure is built out.

# ── Scale constants (must match Planet.gd) ─────────────────────────────────────
const ORBIT_RADIUS_MULT: float = 32.0
const EARTH_ORBIT_DAYS:   float = 365.25

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

# ── Dyson swarm ──────────────────────────────────────────────────────────────
## A shell of flat solar collectors close to the Sun (inside Mercury's orbit),
## spread across several circular lanes at increasing inclinations so the lanes
## cross like a 3D swarm.  Each collector is one Solar Satellite the player has
## manufactured and launched to the Sun: satellites fill the evenly-spaced slots of
## one lane, and once a lane is full new arrivals spill into the next lane.
const SWARM_LANES:    int   = 18    # more lanes, each packed with as many panels as fit
const SWARM_INNER_AU: float = 0.10   # hugs the Sun, inside Mercury's orbit
const SWARM_OUTER_AU: float = 0.26
const PANEL_W:    float = 0.30   # collector panel width (game units)
const PANEL_THIN: float = 0.04   # panel thickness
## Arc length each panel occupies on its ring (panel width + a clear gap), so a lane fits
## TAU·radius / this collectors without overlapping.  Bigger (outer) lanes hold more.
const SWARM_PANEL_ARC: float = PANEL_W * 1.4
## Golden angle (rad) — used to spread lane orbital planes evenly over the sphere.
const GOLDEN_ANGLE: float = 2.399963229728653

## Per-lane capacities and the cumulative start index of each lane (built in _build_swarm).
var _lane_cap:    PackedInt32Array = PackedInt32Array()
var _lane_start:  PackedInt32Array = PackedInt32Array()
## For each collector index, which evenly-spaced slot (0..cap) it occupies.  The fill order
## bisects the largest gap each step, so any number of deployed panels is spread as evenly
## as possible around the ring (and the full ring is perfectly uniform).
var _slot_seq:    PackedInt32Array = PackedInt32Array()
var _swarm_max:   int = 0                                 # total collector slots
const SWARM_POLL_SEC: float = 0.5   # how often to re-read the deployed-satellite count

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

## One MultiMesh (and its MultiMeshInstance3D) per mesh variant.
var _multimeshes: Array[MultiMesh] = []
var _mm_nodes:    Array[MultiMeshInstance3D] = []

# ── Dyson swarm state ──────────────────────────────────────────────────────────
var _swarm_mm:  MultiMesh = null
var _swarm_mmi: MultiMeshInstance3D = null
var _sw_lane:   PackedInt32Array   = PackedInt32Array()   # lane index per collector
var _sw_phase:  PackedFloat32Array = PackedFloat32Array() # FIXED base slot phase (rad)
var _lane_rvis:   PackedFloat32Array = PackedFloat32Array()  # visual radius per lane
var _lane_motion: PackedFloat32Array = PackedFloat32Array()  # mean motion (rad/day) per lane
## Shared accumulated rotation per lane.  Every collector in a lane orbits by this same
## angle on top of its fixed slot, so the ring stays perfectly evenly spaced no matter
## when each panel was revealed (advancing per-panel independently desynchronised them).
var _lane_angle:  PackedFloat32Array = PackedFloat32Array()
var _lane_basis:  Array[Basis] = []                          # incl+node rotation per lane
var _swarm_poll_accum: float = 0.0


func _ready() -> void:
	_build_belt()
	_build_swarm()
	SolarSystem.active_changed.connect(_sync_visibility)
	SolarSystem.paused_changed.connect(_sync_visibility)
	_sync_visibility()


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
		# frustum-culled when the Planets node origin leaves the view.
		mmi.custom_aabb      = AABB(Vector3(-56, -14, -56), Vector3(112, 28, 112))
		add_child(mmi)
		_mm_nodes.append(mmi)

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

		# Size: mostly tiny rubble, a few large (Ceres/Vesta-class) bodies.
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

func _process(delta: float) -> void:
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

	# ── Dyson swarm ────────────────────────────────────────────────────────────
	# Re-read the Orbital Array count on a throttle (cheap, but not every frame).
	_swarm_poll_accum += delta
	if _swarm_poll_accum >= SWARM_POLL_SEC:
		_swarm_poll_accum = 0.0
		_refresh_swarm_count()
	# Advance the whole lane by one shared angle (not each visible panel separately, which
	# desynchronised panels revealed at different times and wrecked the even spacing).
	for lane in range(_lane_angle.size()):
		_lane_angle[lane] = fposmod(_lane_angle[lane] + _lane_motion[lane] * delta_days, TAU)
	_update_swarm_transforms()


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


# ── Visibility (mirrors Planet._sync_visibility) ───────────────────────────────

## Show the belt whenever the solar system is active or the game is paused, so it
## stays visible for inspection even after the orbit-freeze cutoff year.
func _sync_visibility() -> void:
	var show: bool = SolarSystem.solar_system_active \
		or SolarSystem.paused or SolarSystem.ui_paused
	for mmi in _mm_nodes:
		mmi.visible = show
	if _swarm_mmi:
		_swarm_mmi.visible = show
		# Make sure a freshly-paused (or just-loaded) swarm shows the right count
		# and is positioned, even though _process is suspended while paused.
		_refresh_swarm_count()
		_update_swarm_transforms()


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


# ── Dyson swarm ────────────────────────────────────────────────────────────────

func _build_swarm() -> void:
	# Per-lane geometry: radius, mean motion, orbital-plane orientation, and a fit-based
	# capacity — each ring holds as many panels as its circumference fits without overlap,
	# so the bigger (outer) lanes carry more collectors than the inner ones.
	_swarm_max = 0
	for lane in range(SWARM_LANES):
		var t: float = float(lane) / float(maxi(1, SWARM_LANES - 1))   # 0..1
		var a_au: float = lerpf(SWARM_INNER_AU, SWARM_OUTER_AU, t)
		var rv: float = log(a_au + 1.0) * ORBIT_RADIUS_MULT
		_lane_rvis.append(rv)
		_lane_motion.append(TAU / (EARTH_ORBIT_DAYS * pow(a_au, 1.5)))
		_lane_angle.append(0.0)
		# Spread each lane's orbital plane over the whole sphere (spherical-Fibonacci
		# lattice of plane normals) so the rings wrap the Sun from every direction — a
		# 3-D shell, not a flat disk.  Because every lane sits at its own radius and the
		# panels are radially thin, rings in different planes never actually collide.
		var yv: float = 1.0 - 2.0 * (float(lane) + 0.5) / float(SWARM_LANES)   # 1 → −1
		var rr: float = sqrt(maxf(0.0, 1.0 - yv * yv))
		var phi: float = GOLDEN_ANGLE * float(lane)
		var normal := Vector3(rr * cos(phi), yv, rr * sin(phi)).normalized()   # plane normal
		var ref := Vector3.UP if absf(normal.y) < 0.95 else Vector3.RIGHT
		var u := normal.cross(ref).normalized()                               # in-plane axis
		var w := normal.cross(u).normalized()                                 # in-plane axis
		_lane_basis.append(Basis(u, normal, w))
		var cap: int = maxi(1, int(TAU * rv / SWARM_PANEL_ARC))   # collectors that fit
		_lane_cap.append(cap)
		_lane_start.append(_swarm_max)
		_swarm_max += cap

	# One shared thin panel mesh; a single MultiMesh → one draw call.
	var panel := BoxMesh.new()
	panel.size = Vector3.ONE

	_swarm_mm = MultiMesh.new()
	_swarm_mm.transform_format = MultiMesh.TRANSFORM_3D
	_swarm_mm.mesh = panel
	_swarm_mm.instance_count = _swarm_max
	_swarm_mm.visible_instance_count = 0   # nothing until collectors are deployed

	_swarm_mmi = MultiMeshInstance3D.new()
	_swarm_mmi.name = "DysonSwarm"
	_swarm_mmi.multimesh = _swarm_mm
	_swarm_mmi.material_override = _make_panel_material()
	_swarm_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Size the culling box for the swarm at its LARGEST — the outer lane scaled by the Sun's
	# peak red-giant size (visual_mult ≈ 16) — so it never culls as the lanes grow.
	var ext: float = log(SWARM_OUTER_AU + 1.0) * ORBIT_RADIUS_MULT * 16.0 + 4.0
	_swarm_mmi.custom_aabb = AABB(
		Vector3(-ext, -ext, -ext), Vector3(ext * 2.0, ext * 2.0, ext * 2.0))
	add_child(_swarm_mmi)

	# Slots laid out lane-major (lane 0's slots first, then lane 1's …).  Because
	# visible_instance_count reveals instances in index order, collectors fill one lane
	# completely before the next; within a lane the bisection order (_even_order) spreads
	# the fill so a partly-filled ring still looks evenly distributed, never bunched.
	_sw_lane.resize(_swarm_max)
	_sw_phase.resize(_swarm_max)
	_slot_seq.resize(_swarm_max)
	var idx: int = 0
	for lane in range(SWARM_LANES):
		var cap: int = _lane_cap[lane]
		var order: PackedInt32Array = _even_order(cap)
		for fill in range(cap):
			_sw_lane[idx] = lane
			_slot_seq[idx] = order[fill]
			_sw_phase[idx] = _slot_phase(lane, fill)
			idx += 1

	_refresh_swarm_count()
	_update_swarm_transforms()

## A fill order over `n` evenly-spaced slots that keeps every prefix as uniform as
## possible: each new slot lands in the middle of the currently-largest gap.  So three
## panels sit ~120° apart, four ~90°, and so on — never clustered.
func _even_order(n: int) -> PackedInt32Array:
	var order := PackedInt32Array()
	if n <= 0:
		return order
	var used := PackedByteArray()
	used.resize(n)
	order.append(0)
	used[0] = 1
	var occ := [0]                       # occupied slots, kept sorted
	while order.size() < n:
		var m: int = occ.size()
		var best_gap: int = -1
		var best_mid: int = -1
		for j in range(m):
			var a: int = occ[j]
			var b: int = occ[(j + 1) % m] + (n if j + 1 == m else 0)
			var gap: int = b - a
			if gap > best_gap:
				@warning_ignore("integer_division")
				var mid: int = ((a + b) / 2) % n
				if used[mid] == 0:
					best_gap = gap
					best_mid = mid
		if best_mid < 0:                 # all midpoints taken — take any free slot
			for s in range(n):
				if used[s] == 0:
					best_mid = s
					break
		order.append(best_mid)
		used[best_mid] = 1
		occ.append(best_mid)
		occ.sort()
	return order

## Base orbital phase (rad) of the `fill`-th collector to enter `lane` — its assigned
## evenly-spaced slot, so panels never overlap (one per TAU/cap arc) and any partial
## count is spread evenly around the ring.
func _slot_phase(lane: int, fill: int) -> float:
	var cap: int = _lane_cap[lane]
	var slot: int = _slot_seq[_lane_start[lane] + fill]
	return fposmod(TAU * float(slot) / float(cap) + float(lane) * 0.37, TAU)

## Lane that holds collector `index` (lane-major), via the cumulative start offsets.
func _lane_of_index(index: int) -> int:
	for lane in range(SWARM_LANES - 1, -1, -1):
		if index >= _lane_start[lane]:
			return lane
	return 0

## World position of collector `index` at its base phase — the spot a rocket flies to
## before it transforms into a deployed panel.  Unrevealed slots hold this static
## position (they don't orbit until they become visible).
func swarm_slot_world_pos(index: int) -> Vector3:
	if index < 0 or index >= _swarm_max:
		return global_position
	var lane: int = _lane_of_index(index)
	var fill: int = index - _lane_start[lane]
	var rv: float = _lane_rvis[lane] * _sun_visual_mult()   # track the growing Sun
	var th: float = _slot_phase(lane, fill) + _lane_angle[lane]   # current (rotated) slot spot
	return to_global(_lane_basis[lane] * Vector3(rv * cos(th), 0.0, rv * sin(th)))

## Reposition every visible collector at its current orbital phase, oriented so the
## flat panel faces the Sun (its thin axis points radially).
func _update_swarm_transforms() -> void:
	if _swarm_mm == null:
		return
	# The whole swarm scales with the Sun: as it swells toward a red giant the lanes grow with
	# it, so the collectors keep orbiting OUTSIDE the photosphere instead of vanishing inside it.
	var sun_f: float = _sun_visual_mult()
	var vis: int = _swarm_mm.visible_instance_count
	for i in range(vis):
		var lane: int = _sw_lane[i]
		var rv: float = _lane_rvis[lane] * sun_f
		var th: float = _sw_phase[i] + _lane_angle[lane]   # fixed slot + shared lane rotation
		var lb: Basis = _lane_basis[lane]
		var pos: Vector3 = lb * Vector3(rv * cos(th), 0.0, rv * sin(th))
		# Orient the panel so its width runs ALONG the ring (the orbit tangent) and its
		# thin axis points at the Sun, so each panel's along-track footprint is exactly
		# PANEL_W — narrower than the slot spacing, so neighbours never overlap.
		var radial:  Vector3 = (lb * Vector3(cos(th), 0.0, sin(th)))
		var tangent: Vector3 = (lb * Vector3(-sin(th), 0.0, cos(th)))
		var across:  Vector3 = radial.cross(tangent).normalized()
		var b := Basis(tangent * PANEL_W, radial * PANEL_THIN, across * PANEL_W)
		_swarm_mm.set_instance_transform(i, Transform3D(b, pos))

## Current visual size multiple of the Sun (1.0 today, up to 16× at the red-giant tip),
## interpolated from Planet.SUN_STAGES exactly as the Sun's own appearance is, so the swarm
## grows in lock-step with the star it orbits.
func _sun_visual_mult() -> float:
	var stages: Array = Planet.SUN_STAGES
	var y: float = float(SolarSystem.current_year)
	var last: Array = stages[stages.size() - 1]
	if y >= float(int(last[0])):
		return maxf(1.0, float(last[2]))
	var lo: Array = stages[0]
	var hi: Array = stages[1]
	for i in range(stages.size() - 1):
		if y >= float(int(stages[i][0])) and y < float(int(stages[i + 1][0])):
			lo = stages[i]
			hi = stages[i + 1]
			break
	var span: float = float(int(hi[0])) - float(int(lo[0]))
	var t: float = 0.0 if span <= 0.0 else clampf((y - float(int(lo[0]))) / span, 0.0, 1.0)
	var st: float = t * t * (3.0 - 2.0 * t)   # smoothstep, matching _update_sun_appearance
	# Floor at 1.0 — the swarm grows with the swelling Sun but never contracts below the lanes
	# it was built at (so it doesn't collapse into an overlapping knot around the white dwarf).
	return maxf(1.0, lerpf(float(lo[2]), float(hi[2]), st))

## Show one collector per Solar Satellite the player has deployed to the Sun.
func _refresh_swarm_count() -> void:
	if _swarm_mm == null:
		return
	_swarm_mm.visible_instance_count = clampi(_deployed_satellite_count(), 0, _swarm_max)

## Total collector slots across all lanes (queried by Game for the swarm cap).
func get_swarm_max() -> int:
	return _swarm_max

## How many Solar Satellites have arrived at the Sun (read from Game).
func _deployed_satellite_count() -> int:
	var game := get_tree().current_scene
	if game == null:
		return 0
	var n: Variant = game.get("solar_satellites_deployed")
	return int(n) if n != null else 0

func _make_panel_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.22, 0.42)        # dark blue photovoltaic
	mat.metallic     = 0.7
	mat.roughness    = 0.3
	mat.emission_enabled = true
	mat.emission     = Color(0.12, 0.18, 0.36)        # faint glow, catching sunlight
	mat.emission_energy_multiplier = 0.5
	mat.cull_mode    = BaseMaterial3D.CULL_DISABLED   # thin panels visible both sides
	return mat
