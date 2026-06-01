extends PanelContainer

## ProductionPanel — lets the player queue manufacturing recipes.
##
## Emits production_changed(jobs: Array) whenever the job list changes.
## Each job is a Dictionary:
##   { "recipe": String, "planet": String, "rate": float, "id": int }
##
## Game.gd should listen to production_changed and process the active jobs
## every frame: consume inputs from resources/compound_inventory and produce outputs.

signal production_changed(jobs: Array)

const PLANETS: Array = [
	"Earth", "Mercury", "Venus", "Mars",
	"Jupiter", "Saturn", "Uranus", "Neptune",
]
const RATE_MIN:  float = 0.1
const RATE_MAX:  float = 10.0
const RATE_STEP: float = 0.1

# ── Internal state ───────────────────────────────────────────────────────────────
var _jobs:       Array = []   # active production jobs
var _job_status_labels: Dictionary = {}   # job_id (int) → Label
var _next_id:    int   = 1
var _all_recipes: Array = []   # full recipe list (updated on research change)

# ── UI refs built in _build_ui ───────────────────────────────────────────────────
var _recipe_option:  OptionButton = null
var _planet_option:  OptionButton = null
var _rate_slider:    HSlider      = null
var _rate_label:     Label        = null
var _add_button:     Button       = null
var _job_list:       VBoxContainer = null
var _inputs_label:   Label        = null
var _outputs_label:  Label        = null

# ── Lifecycle ────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_all_recipes = RecipeData.RECIPES
	_build_ui()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index in [
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		accept_event()

# ── Public API ───────────────────────────────────────────────────────────────────

## Refresh which recipes are selectable (call after a research unlock).
func refresh_recipes(completed_research: Dictionary) -> void:
	_all_recipes = RecipeData.available(completed_research)
	_populate_recipes()

## Replace the job list from a loaded save.
func load_jobs(jobs: Array) -> void:
	_jobs = []
	for j in jobs:
		_jobs.append(j.duplicate())
		_next_id = maxi(_next_id, int(j.get("id", 0)) + 1)
	_rebuild_job_list()

## Called each frame by Game.gd to show whether a job is running or stalled.
func set_job_status(job_id: int, running: bool, missing_input: String = "") -> void:
	var lbl: Label = _job_status_labels.get(job_id, null)
	if lbl == null:
		return
	if running:
		lbl.text    = "● running"
		lbl.modulate = Color(0.35, 0.80, 0.45)
	else:
		lbl.text    = "⚠ missing: %s" % missing_input if missing_input != "" else "⚠ stalled"
		lbl.modulate = Color(0.90, 0.55, 0.20)

## Returns a serialisable copy of the current job list.
func get_jobs() -> Array:
	var out: Array = []
	for j in _jobs:
		out.append(j.duplicate())
	return out

# ── UI construction ──────────────────────────────────────────────────────────────

func _build_ui() -> void:
	custom_minimum_size = Vector2(540, 480)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top",    8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.add_theme_constant_override("margin_left",   10)
	margin.add_theme_constant_override("margin_right",  10)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Manufacturing"
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# ── Form: recipe / planet / rate / IO preview ────────────────────────────────
	var form := GridContainer.new()
	form.columns = 2
	form.add_theme_constant_override("h_separation", 12)
	form.add_theme_constant_override("v_separation", 6)
	vbox.add_child(form)

	_form_label(form, "Recipe:")
	_recipe_option = OptionButton.new()
	_recipe_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipe_option.item_selected.connect(_on_recipe_selected)
	form.add_child(_recipe_option)

	_form_label(form, "Location:")
	_planet_option = OptionButton.new()
	_planet_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for p in PLANETS:
		_planet_option.add_item(p)
	form.add_child(_planet_option)

	_form_label(form, "Rate:")
	var rate_row := HBoxContainer.new()
	rate_row.add_theme_constant_override("separation", 8)
	rate_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rate_slider = HSlider.new()
	_rate_slider.min_value = RATE_MIN
	_rate_slider.max_value = RATE_MAX
	_rate_slider.step      = RATE_STEP
	_rate_slider.value     = 1.0
	_rate_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rate_slider.value_changed.connect(_on_rate_changed)
	rate_row.add_child(_rate_slider)
	_rate_label = Label.new()
	_rate_label.text = "1.0×"
	_rate_label.custom_minimum_size = Vector2(38, 0)
	rate_row.add_child(_rate_label)
	form.add_child(rate_row)

	# IO preview
	_form_label(form, "Inputs:")
	_inputs_label = Label.new()
	_inputs_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inputs_label.add_theme_font_size_override("font_size", 11)
	_inputs_label.modulate = Color(0.80, 0.65, 0.55)
	_inputs_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(_inputs_label)

	_form_label(form, "Outputs:")
	_outputs_label = Label.new()
	_outputs_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_outputs_label.add_theme_font_size_override("font_size", 11)
	_outputs_label.modulate = Color(0.55, 0.85, 0.60)
	_outputs_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(_outputs_label)

	# Add button
	_add_button = Button.new()
	_add_button.text = "+ Add Production"
	_add_button.custom_minimum_size = Vector2(0, 36)
	_add_button.pressed.connect(_on_add_pressed)
	vbox.add_child(_add_button)

	vbox.add_child(HSeparator.new())

	# ── Active jobs section ──────────────────────────────────────────────────────
	var jobs_label := Label.new()
	jobs_label.text = "Active Production"
	jobs_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(jobs_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_job_list = VBoxContainer.new()
	_job_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_job_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_job_list)

	_populate_recipes()
	_update_io_preview()

# ── UI helpers ───────────────────────────────────────────────────────────────────

func _form_label(parent: Control, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.modulate = Color(0.75, 0.75, 0.75)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(lbl)

func _populate_recipes() -> void:
	_recipe_option.clear()
	for r in _all_recipes:
		_recipe_option.add_item("%s  [%s]" % [r["name"], (r["category"] as String).capitalize()])
	_update_io_preview()

func _update_io_preview() -> void:
	var recipe := _selected_recipe()
	if recipe.is_empty():
		_inputs_label.text  = "—"
		_outputs_label.text = "—"
		return
	var rate: float = _rate_slider.value if _rate_slider else 1.0
	_inputs_label.text  = _fmt_flow(recipe.get("inputs",  {}), rate)
	_outputs_label.text = _fmt_flow(recipe.get("outputs", {}), rate)

func _fmt_flow(flow: Dictionary, rate: float) -> String:
	if flow.is_empty():
		return "—"
	var parts: Array = []
	for k: String in flow:
		var v: float = float(flow[k]) * rate
		parts.append("%s %s/s" % [_fmt_amount(v), k])
	return "  ".join(parts)

func _fmt_amount(v: float) -> String:
	if v >= 1e9:  return "%.2fG" % (v * 1e-9)
	if v >= 1e6:  return "%.2fM" % (v * 1e-6)
	if v >= 1e3:  return "%.2fk" % (v * 1e-3)
	if v >= 1.0:  return "%.2f"  % v
	return "%.3f" % v

func _selected_recipe() -> Dictionary:
	var idx := _recipe_option.selected if _recipe_option else -1
	if idx < 0 or idx >= _all_recipes.size():
		return {}
	return _all_recipes[idx]

# ── Job list ─────────────────────────────────────────────────────────────────────

func _rebuild_job_list() -> void:
	_job_status_labels.clear()
	for child in _job_list.get_children():
		child.queue_free()
	for job in _jobs:
		_add_job_row(job)

func _add_job_row(job: Dictionary) -> void:
	var recipe := _find_recipe(job.get("recipe", ""))
	var rate:   float  = float(job.get("rate",   1.0))
	var planet: String = (job.get("planet", "earth") as String).capitalize()

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	# Info vbox
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)

	var name_lbl := Label.new()
	name_lbl.text = "%s  @ %s  (%.1f×)" % [job.get("recipe", "?"), planet, rate]
	name_lbl.add_theme_font_size_override("font_size", 12)
	info.add_child(name_lbl)

	if not recipe.is_empty():
		var out_lbl := Label.new()
		out_lbl.text = "→ " + _fmt_flow(recipe.get("outputs", {}), rate)
		out_lbl.add_theme_font_size_override("font_size", 10)
		out_lbl.modulate = Color(0.55, 0.85, 0.60)
		info.add_child(out_lbl)

		var in_lbl := Label.new()
		in_lbl.text = "← " + _fmt_flow(recipe.get("inputs", {}), rate)
		in_lbl.add_theme_font_size_override("font_size", 10)
		in_lbl.modulate = Color(0.80, 0.65, 0.55)
		info.add_child(in_lbl)

	row.add_child(info)

	# Status indicator ("✓ running" / "⚠ missing inputs")
	var job_id := int(job.get("id", 0))
	var status_lbl := Label.new()
	status_lbl.text = "…"
	status_lbl.add_theme_font_size_override("font_size", 10)
	status_lbl.modulate = Color(0.55, 0.55, 0.55)
	status_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info.add_child(status_lbl)
	_job_status_labels[job_id] = status_lbl

	# Remove button
	var rm := Button.new()
	rm.text = "✕"
	rm.flat = true
	rm.custom_minimum_size = Vector2(28, 28)
	rm.pressed.connect(_on_remove_pressed.bind(job_id))
	row.add_child(rm)

	_job_list.add_child(row)
	_job_list.add_child(HSeparator.new())

func _find_recipe(name: String) -> Dictionary:
	for r in RecipeData.RECIPES:
		if r["name"] == name:
			return r
	return {}

# ── Signals ──────────────────────────────────────────────────────────────────────

func _on_recipe_selected(_idx: int) -> void:
	_update_io_preview()

func _on_rate_changed(value: float) -> void:
	_rate_label.text = "%.1f×" % value
	_update_io_preview()

func _on_add_pressed() -> void:
	var recipe := _selected_recipe()
	if recipe.is_empty():
		return
	var planet_idx := _planet_option.selected if _planet_option else 0
	var planet: String = PLANETS[planet_idx].to_lower()
	var job := {
		"id":     _next_id,
		"recipe": recipe["name"],
		"planet": planet,
		"rate":   _rate_slider.value,
	}
	_next_id += 1
	_jobs.append(job)
	_add_job_row(job)
	production_changed.emit(_jobs.duplicate(true))

func _on_remove_pressed(job_id: int) -> void:
	_jobs = _jobs.filter(func(j): return int(j.get("id", -1)) != job_id)
	_rebuild_job_list()
	production_changed.emit(_jobs.duplicate(true))
