class_name Planet
extends MeshInstance3D

@export var orbit_radius: float = 1.0
@export var orbit_offset: float = 0.0
@export var speed: float = 1.0

var orbit_angle: float = 0.0
var orbit_radius_mult: float = 32.0
var size_mult: float = 1.0

const EARTH_ORBIT_DAYS: float = 365.0

func _ready() -> void:
	orbit_radius = log(orbit_radius + 1.0) * orbit_radius_mult
	size_mult = log(scale.x + 1.0)
	scale = Vector3(size_mult, size_mult, size_mult)

	orbit_angle = orbit_offset
	_update_position()

func _process(delta: float) -> void:
	if SolarSystem.ui_paused or SolarSystem.paused:
		return

	if SolarSystem.seconds_per_day <= 0.0:
		return

	var angular_velocity: float = (TAU / (EARTH_ORBIT_DAYS * SolarSystem.seconds_per_day)) * speed
	orbit_angle += angular_velocity * delta
	_update_position()

func _update_position() -> void:
	position = Vector3(
		orbit_radius * sin(orbit_angle),
		0.0,
		orbit_radius * cos(orbit_angle)
	)
