extends PanelContainer

@onready var planet_name_label: Label = $MarginContainer/VBoxContainer/PlanetName
@onready var resources_label: Label = $MarginContainer/VBoxContainer/ResourcesTitle
@onready var energy_label: Label = $MarginContainer/VBoxContainer/GridContainer/EnergyValue
@onready var population_label: Label = $MarginContainer/VBoxContainer/GridContainer/PopulationValue
@onready var compute_label: Label = $MarginContainer/VBoxContainer/GridContainer/ComputeValue
@onready var buildings_list: ItemList = $MarginContainer/VBoxContainer/BuildingsList

func _ready() -> void:
	hide()

func set_planet_info(data: Dictionary) -> void:
	planet_name_label.text = str(data.get("name", "Unknown Planet"))
	resources_label.text = str(data.get("resources", 0))
	energy_label.text = str(data.get("energy", 0))
	population_label.text = str(data.get("population", 0))
	compute_label.text = str(data.get("compute", 0))

	buildings_list.clear()
	var buildings: Array = data.get("buildings", [])
	for building in buildings:
		if building is Dictionary:
			var b_name: String = str(building.get("name", "Unknown Building"))
			var count: int = int(building.get("count", 1))
			buildings_list.add_item("%s x%d" % [b_name, count])
		else:
			buildings_list.add_item(str(building))

	show()

func clear_planet_info() -> void:
	planet_name_label.text = "No Planet Selected"
	resources_label.text = "-"
	energy_label.text = "-"
	population_label.text = "-"
	compute_label.text = "-"
	buildings_list.clear()
	hide()
