extends Control

@onready var tree: EvolutionTreeControl = $ScrollContainer/EvolutionTree

## Column spacing per lineage depth, and row spacing between successive variants.
const COL_STEP: float = 260.0
const ROW_STEP: float = 110.0
const ROW_TOP: float  = 60.0

## Row index of the next dynamically-added variant (keeps variants from overlapping).
var _row: int = 0

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Fill the sidebar vertically so the tree reaches the bottom of the screen.
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical   = Control.SIZE_EXPAND_FILL
	# The ScrollContainer is anchor-positioned (not container-managed), so stretch
	# it to a full rect here.
	var scroll := get_node_or_null("ScrollContainer") as ScrollContainer
	if scroll:
		scroll.anchor_left   = 0.0
		scroll.anchor_top    = 0.0
		scroll.anchor_right  = 1.0
		scroll.anchor_bottom = 1.0
		scroll.offset_left   = 0.0
		scroll.offset_top    = 0.0
		scroll.offset_right  = 0.0
		scroll.offset_bottom = 0.0

	reset_to_baseline()
	tree.node_selected.connect(_on_node_selected)

# ── Public API (called by Game.gd) ────────────────────────────────────────────

## Reset to the single baseline root, fully unlocked.  Call on a fresh run.
func reset_to_baseline() -> void:
	_row = 0
	tree.load_tree(
		{"homo_sapiens": EvolutionTreeData.baseline()},
		{"homo_sapiens": true})

## True once `planet` has diverged into its own lineage node.
func has_variant(planet: String) -> bool:
	return tree.tree_data.has(EvolutionTreeData.variant_id(planet))

## Add (and unlock) the lineage for `planet`, descending from `parent_planet`'s
## variant — or from the baseline when `parent_planet` is "" or has not diverged.
## Returns true if a new node was created.
func add_planet_variant(planet: String, parent_planet: String = "") -> bool:
	var node_id: String = EvolutionTreeData.variant_id(planet)
	if tree.tree_data.has(node_id):
		return false

	var parent_id: String = "homo_sapiens"
	if parent_planet != "":
		var pid: String = EvolutionTreeData.variant_id(parent_planet)
		if tree.tree_data.has(pid):
			parent_id = pid

	var parent_pos: Vector2 = (tree.tree_data.get(parent_id, {}) as Dictionary).get(
		"pos", Vector2(60, 60))
	var pos := Vector2(parent_pos.x + COL_STEP, ROW_TOP + _row * ROW_STEP)
	_row += 1

	tree.add_node(node_id, EvolutionTreeData.planet_variant(planet, parent_id, pos))
	tree.unlock_node(node_id)
	return true

## Highest compute (FLOP/s per individual) across all currently unlocked lineages.
## The baseline is always unlocked, so this never drops below the neocortex floor.
func get_unlocked_compute_per_individual() -> float:
	var best: float = 0.0
	for node_id: String in tree.unlocked:
		if tree.unlocked[node_id]:
			var node_data: Dictionary = tree.tree_data.get(node_id, {})
			best = maxf(best, float(node_data.get("compute", 0.0)))
	return best

# ── Internal ──────────────────────────────────────────────────────────────────

func _on_node_selected(node_id: String) -> void:
	print("[Evolution] Selected: ", node_id)
