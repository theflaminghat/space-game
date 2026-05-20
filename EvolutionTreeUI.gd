extends Control

@onready var tree: EvolutionTreeControl = $ScrollContainer/EvolutionTree

func _ready() -> void:
	var data: Dictionary = EvolutionTreeData.build()

	var unlocked_map: Dictionary = {
		"homo_sapiens": true,
		"homo_sapiens_orbitalis": true,
		"homo_sapiens_martis": true
	}

	tree.load_tree(data, unlocked_map)
	tree.node_selected.connect(_on_node_selected)

func _on_node_selected(node_id: String) -> void:
	print("Selected: ", node_id)
