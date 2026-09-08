extends Control

@onready var tree: EvolutionTreeControl = $ScrollContainer/EvolutionTree

## Column spacing per lineage depth, and row spacing between successive variants.
const COL_STEP: float = 260.0
const ROW_STEP: float = 110.0
const ROW_TOP: float  = 60.0

## Row index of the next dynamically-added variant (keeps variants from overlapping).
var _row: int = 0

var _info:       PanelContainer = null
var _info_title: Label = null
var _info_sub:   Label = null
var _info_body:  Label = null
var _selected_id: String = "homo_sapiens"
var _rates: Dictionary = {}

# ── Lifecycle ─────────────────────────────────────────────────────────────────

## Swallow mouse-wheel events so scrolling over this panel doesn't zoom the
## solar-system camera behind it.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index in [
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		accept_event()

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
		scroll.offset_bottom = -INFO_H          # leave the strip below for the readout

	_build_info_panel()
	reset_to_baseline()
	tree.node_selected.connect(_on_node_selected)

# ── Public API (called by Game.gd) ────────────────────────────────────────────

## Reset to the single baseline root, fully unlocked.  Call on a fresh run.
func reset_to_baseline() -> void:
	_row = 0
	tree.load_tree(
		{"homo_sapiens": EvolutionTreeData.baseline()},
		{"homo_sapiens": true})
	_selected_id = "homo_sapiens"
	_refresh_info()

## Height of the readout strip under the tree.
const INFO_H: float = 150.0

## The lineage tree says how humanity has SPLIT; this says what each of those populations
## actually is right now.  Without it the panel is a diagram of names — the numbers that make a
## lineage a people (how many, how long they live, whether they are fed) lived only in tabs
## that never mention evolution at all.
func _build_info_panel() -> void:
	_info = PanelContainer.new()
	_info.anchor_left = 0.0
	_info.anchor_right = 1.0
	_info.anchor_top = 1.0
	_info.anchor_bottom = 1.0
	_info.offset_top = -INFO_H
	_info.offset_bottom = 0.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.13, 0.96)
	sb.border_color = Color(0.30, 0.40, 0.55)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(8)
	_info.add_theme_stylebox_override("panel", sb)
	add_child(_info)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_info.add_child(box)

	_info_title = Label.new()
	_info_title.add_theme_font_size_override("font_size", 13)
	_info_title.modulate = Color(0.90, 0.93, 1.00)
	box.add_child(_info_title)

	_info_sub = Label.new()
	_info_sub.add_theme_font_size_override("font_size", 10)
	_info_sub.modulate = Color(0.62, 0.70, 0.85)
	box.add_child(_info_sub)

	_info_body = Label.new()
	_info_body.add_theme_font_size_override("font_size", 11)
	_info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_info_body)

## Push the per-capita rates from Game: what a person eats, and what a person can staff.  These
## are civilisation-wide constants rather than per-world figures, which is why this replaced the
## population push — a lineage's intake and output do not depend on how many of them there are.
func set_lineage_rates(rates: Dictionary) -> void:
	_rates = rates
	_refresh_info()

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
	_selected_id = node_id
	_refresh_info()

## Fill the readout for the selected lineage.
func _refresh_info() -> void:
	if _info_title == null:
		return
	var node: Dictionary = tree.tree_data.get(_selected_id, {})
	_info_title.text = str(node.get("name", "Homo sapiens"))
	_info_sub.text = str(node.get("subtitle", ""))
	_info_body.text = _rate_lines(node)

## What one member of this lineage takes in and puts out.  A node on this tree is a KIND of
## human, not a headcount — the tree already shows how many worlds there are, and the population
## tab shows how many people — so what belongs here is the thing that makes a lineage a lineage:
## what it needs to live, and what it gives back.
func _rate_lines(node: Dictionary) -> String:
	if _rates.is_empty():
		return "No data yet."
	var lines: Array = []
	lines.append("INTAKE   per person per day")
	lines.append("    %s of food" % Units.format_si(float(_rates.get("food_per_capita", 0.0)), "g"))
	lines.append("")
	lines.append("OUTPUT   per person")
	# Compute is a property of the lineage itself, carried on its own node.
	lines.append("    %s of thought" % Units.format_si(float(node.get("compute", 0.0)), "FLOP/s"))
	# Labour is how much built capacity one pair of hands can staff; automation multiplies it.
	var labour: float = float(_rates.get("work_per_capita", 0.0))
	var auto: float = float(_rates.get("automation", 1.0))
	lines.append("    %s of work per day" % Units.format_si(labour * auto, ""))
	if auto > 1.001:
		lines.append("        %s unaided, x%.1f from automation" % [
			Units.format_si(labour, ""), auto])
	return "\n".join(lines)
