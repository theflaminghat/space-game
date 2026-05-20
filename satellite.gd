extends Node3D

@export var orbit_center: Node3D
@export var auto_find_parent_as_center: bool = true

@export_group("Body / Gravity")
@export var gravitational_parameter: float = 1000.0
# This is μ = G*M in your game's units.
# Larger μ = faster orbits.

@export_group("Initial Orbit")
@export var semi_major_axis: float = 5.0
@export_range(0.0, 0.99, 0.001) var eccentricity: float = 0.5
@export_range(0.0, 360.0, 0.1) var inclination_degrees: float = 0.0
@export_range(0.0, 360.0, 0.1) var longitude_of_ascending_node_degrees: float = 0.0
@export_range(0.0, 360.0, 0.1) var argument_of_periapsis_degrees: float = 0.0
@export_range(0.0, 360.0, 0.1) var initial_true_anomaly_degrees: float = 0.0

@export_group("Runtime")
@export var face_velocity_direction: bool = false
@export var use_kepler_third_law: bool = true
@export var draw_debug_prints: bool = false

@export_group("Transfer Orbit")
@export var start_in_transfer: bool = false
@export var transfer_target_radius: float = 40.0

var current_orbit_a: float = 20.0
var current_orbit_e: float = 0.0

var true_anomaly: float = 0.0
var angular_momentum: float = 0.0

var transfer_active: bool = false
var transfer_target_a: float = 0.0
var transfer_target_e: float = 0.0
var transfer_target_final_radius: float = 0.0
var transfer_started_outward: bool = true

var velocity_vector: Vector3 = Vector3.ZERO
var acceleration_vector: Vector3 = Vector3.ZERO
var previous_velocity_vector: Vector3 = Vector3.ZERO

var scalar_speed: float = 0.0
var scalar_acceleration: float = 0.0
var orbital_period: float = 0.0

func _ready() -> void:
	if orbit_center == null and auto_find_parent_as_center:
		orbit_center = get_parent() as Node3D

	current_orbit_a = semi_major_axis
	current_orbit_e = clamp(eccentricity, 0.0, 0.99)
	true_anomaly = deg_to_rad(initial_true_anomaly_degrees)

	_recompute_orbit_constants()

	if start_in_transfer:
		begin_hohmann_transfer(transfer_target_radius)

	_force_update_state()

func _physics_process(delta: float) -> void:
	if SolarSystem.paused or SolarSystem.ui_paused:
		return
	if orbit_center == null:
		return
	if gravitational_parameter <= 0.0:
		return
	if current_orbit_a <= 0.0:
		return

	var old_velocity: Vector3 = velocity_vector

	# Keplerian angular rate:
	# dθ/dt = h / r^2
	var radius: float = _radius_from_true_anomaly(current_orbit_a, current_orbit_e, true_anomaly)
	if radius <= 0.0001:
		return

	var angular_rate: float = angular_momentum / (radius * radius)
	true_anomaly += angular_rate * delta

	# Keep bounded
	if true_anomaly > TAU:
		true_anomaly -= TAU
	elif true_anomaly < -TAU:
		true_anomaly += TAU

	_force_update_state()

	acceleration_vector = (velocity_vector - old_velocity) / max(delta, 0.000001)
	scalar_acceleration = acceleration_vector.length()

	if face_velocity_direction and velocity_vector.length() > 0.0001:
		look_at(global_position + velocity_vector.normalized(), Vector3.UP)

	if transfer_active:
		_check_transfer_completion()

	if draw_debug_prints:
		print("r=", _current_radius(), " speed=", scalar_speed, " accel=", scalar_acceleration, " T=", orbital_period)

func _force_update_state() -> void:
	var pos_local: Vector3 = _orbital_plane_position(current_orbit_a, current_orbit_e, true_anomaly)
	var vel_local: Vector3 = _orbital_plane_velocity(current_orbit_a, current_orbit_e, true_anomaly)

	var orbit_basis: Basis = _orbit_basis()

	global_position = orbit_center.global_position + orbit_basis * pos_local
	velocity_vector = orbit_basis * vel_local
	scalar_speed = velocity_vector.length()

	if use_kepler_third_law:
		orbital_period = TAU * sqrt(pow(current_orbit_a, 3.0) / gravitational_parameter)
	else:
		orbital_period = 0.0

func _recompute_orbit_constants() -> void:
	current_orbit_e = clamp(current_orbit_e, 0.0, 0.99)
	current_orbit_a = max(current_orbit_a, 0.001)

	# Specific angular momentum:
	# h = sqrt(μ a (1 - e^2))
	angular_momentum = sqrt(gravitational_parameter * current_orbit_a * (1.0 - current_orbit_e * current_orbit_e))

	if use_kepler_third_law:
		# T = 2π * sqrt(a^3 / μ)
		orbital_period = TAU * sqrt(pow(current_orbit_a, 3.0) / gravitational_parameter)
	else:
		orbital_period = 0.0

func _radius_from_true_anomaly(a: float, e: float, theta: float) -> float:
	var numerator: float = a * (1.0 - e * e)
	var denominator: float = 1.0 + e * cos(theta)
	return numerator / denominator

func _orbital_plane_position(a: float, e: float, theta: float) -> Vector3:
	var r: float = _radius_from_true_anomaly(a, e, theta)
	return Vector3(
		r * cos(theta),
		0.0,
		r * sin(theta)
	)

func _orbital_plane_velocity(a: float, e: float, theta: float) -> Vector3:
	# Perifocal-frame velocity:
	# v = (μ / h) * [ -sinθ, 0, e + cosθ ]
	var factor: float = gravitational_parameter / max(angular_momentum, 0.000001)
	return Vector3(
		-factor * sin(theta),
		0.0,
		factor * (e + cos(theta))
	)

func _orbit_basis() -> Basis:
	var inc: float = deg_to_rad(inclination_degrees)
	var lan: float = deg_to_rad(longitude_of_ascending_node_degrees)
	var argp: float = deg_to_rad(argument_of_periapsis_degrees)

	var basis_lan: Basis = Basis(Vector3.UP, lan)
	var basis_inc: Basis = Basis(Vector3.RIGHT, inc)
	var basis_argp: Basis = Basis(Vector3.UP, argp)

	return basis_lan * basis_inc * basis_argp

func _current_radius() -> float:
	return (global_position - orbit_center.global_position).length()

func get_speed() -> float:
	return scalar_speed

func get_acceleration() -> float:
	return scalar_acceleration

func get_velocity_vector() -> Vector3:
	return velocity_vector

func get_acceleration_vector() -> Vector3:
	return acceleration_vector

func get_orbital_period() -> float:
	return orbital_period

func get_current_semi_major_axis() -> float:
	return current_orbit_a

func get_current_eccentricity() -> float:
	return current_orbit_e

func set_circular_orbit(radius: float) -> void:
	current_orbit_a = max(radius, 0.001)
	current_orbit_e = 0.0
	true_anomaly = 0.0
	transfer_active = false
	_recompute_orbit_constants()
	_force_update_state()

func set_elliptical_orbit(a: float, e: float, theta_degrees: float = 0.0) -> void:
	current_orbit_a = max(a, 0.001)
	current_orbit_e = clamp(e, 0.0, 0.99)
	true_anomaly = deg_to_rad(theta_degrees)
	transfer_active = false
	_recompute_orbit_constants()
	_force_update_state()

func begin_hohmann_transfer(target_radius: float) -> void:
	var r1: float = _current_radius()
	var r2: float = max(target_radius, 0.001)

	if r1 <= 0.0001:
		return
	if abs(r2 - r1) < 0.0001:
		return

	# Hohmann transfer ellipse:
	# periapsis = min(r1, r2), apoapsis = max(r1, r2)
	var rp: float
	var ra: float

	if r2 > r1:
		rp = r1
		ra = r2
		transfer_started_outward = true
		true_anomaly = 0.0
	else:
		rp = r2
		ra = r1
		transfer_started_outward = false
		true_anomaly = PI

	transfer_target_a = 0.5 * (rp + ra)
	transfer_target_e = (ra - rp) / (ra + rp)
	transfer_target_final_radius = r2

	current_orbit_a = transfer_target_a
	current_orbit_e = clamp(transfer_target_e, 0.0, 0.99)
	transfer_active = true

	_recompute_orbit_constants()
	_force_update_state()

func _check_transfer_completion() -> void:
	var tolerance: float = 0.25
	var radius_now: float = _current_radius()

	if abs(radius_now - transfer_target_final_radius) > tolerance:
		return

	# outward transfer finishes near apoapsis (theta ≈ π)
	# inward transfer finishes near periapsis (theta ≈ 0)
	if transfer_started_outward:
		if abs(wrapf(true_anomaly, 0.0, TAU) - PI) < 0.08:
			_complete_transfer()
	else:
		var wrapped: float = wrapf(true_anomaly, 0.0, TAU)
		if wrapped < 0.08 or wrapped > TAU - 0.08:
			_complete_transfer()

func _complete_transfer() -> void:
	current_orbit_a = max(transfer_target_final_radius, 0.001)
	current_orbit_e = 0.0
	true_anomaly = 0.0
	transfer_active = false
	_recompute_orbit_constants()
	_force_update_state()
