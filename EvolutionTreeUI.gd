extends Control

@onready var tree: EvolutionTreeControl = $ScrollContainer/EvolutionTree

## Full master reference — every node that can ever appear.
var _master_data: Dictionary = {}

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_master_data = EvolutionTreeData.build()
	reset_to_baseline()
	tree.node_selected.connect(_on_node_selected)

# ── Public API (called by Game.gd) ────────────────────────────────────────────

## Reset tree to the single root node, fully unlocked.
## Call from Game.gd start_new_game() so a fresh run always starts at baseline.
func reset_to_baseline() -> void:
	var initial_data: Dictionary = {
		"homo_sapiens": _master_data["homo_sapiens"],
	}
	var initial_unlocked: Dictionary = {
		"homo_sapiens": true,
	}
	tree.load_tree(initial_data, initial_unlocked)

## Make a node visible in the tree for the first time.
## Returns true if the node was freshly added; false if already visible or unknown.
func add_evolution_node(node_id: String) -> bool:
	if not _master_data.has(node_id):
		push_warning("EvolutionTreeUI: unknown node id '%s'" % node_id)
		return false
	if tree.tree_data.has(node_id):
		return false   # already shown
	tree.add_node(node_id, _master_data[node_id])
	return true

## Colour the node green (unlocked).
func unlock_evolution_node(node_id: String) -> void:
	# Ensure the node is visible first so the unlock is never invisible
	add_evolution_node(node_id)
	tree.unlock_node(node_id)

## True if the node has been added to the visible tree.
func is_node_visible(node_id: String) -> bool:
	return tree.tree_data.has(node_id)

## True if the node is both visible and coloured green.
func is_node_unlocked(node_id: String) -> bool:
	return tree.is_unlocked(node_id)

# ── Save / load ───────────────────────────────────────────────────────────────

## Returns the list of node ids currently visible (for serialisation).
func get_visible_node_ids() -> Array:
	var ids: Array = []
	for key: Variant in tree.tree_data.keys():
		ids.append(str(key))
	return ids

## Returns the unlocked map (for serialisation).
func get_unlocked_map() -> Dictionary:
	return tree.unlocked.duplicate()

## Returns the highest compute value (FLOP/s per individual) across all
## currently unlocked evolution nodes.  Used by Game.gd to convert population
## into a civilisation-wide compute rate.
func get_unlocked_compute_per_individual() -> float:
	var best: float = 0.0
	for node_id: String in tree.unlocked:
		if tree.unlocked[node_id]:
			var node_data: Dictionary = _master_data.get(node_id, {})
			var c: float = float(node_data.get("compute", 0.0))
			if c > best:
				best = c
	return best

## Restore a saved evolution state.
func load_evolution_state(visible_ids: Array, unlocked_map: Dictionary) -> void:
	var data: Dictionary = {}
	for raw_id: Variant in visible_ids:
		var id: String = str(raw_id)
		if _master_data.has(id):
			data[id] = _master_data[id]
	# Always guarantee the root is present
	if not data.has("homo_sapiens"):
		data["homo_sapiens"] = _master_data["homo_sapiens"]
		unlocked_map["homo_sapiens"] = true
	tree.load_tree(data, unlocked_map)

# ── Internal ──────────────────────────────────────────────────────────────────

func _on_node_selected(node_id: String) -> void:
	print("[Evolution] Selected: ", node_id)
