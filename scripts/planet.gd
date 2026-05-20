class_name planet
extends MeshInstance3D

@export var orbit_radius: float = 1.0
@export var orbit_offset: float = 0.0
@export var speed: float = 0.65


var time: float = 0.0
var orbit_radius_mult = 16
var size_mult = log(self.scale[0]+1)

func _ready():
	orbit_radius=log(orbit_radius+1)*orbit_radius_mult
	self.scale = Vector3(size_mult,size_mult,size_mult)

func _process(delta):
	time += delta
	var angle = time * speed + orbit_offset
	
	position = Vector3(
		orbit_radius * sin(angle),
		0.0,
		orbit_radius * cos(angle)
	)
