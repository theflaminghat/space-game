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
## Slider operates in log₁₀ space so each position is an equal *ratio* step.
## LOG_MIN = -2  →  0.01×   |   LOG_MAX = 3  →  1 000×
## LOG_STEP = 0.05  →  each tick ≈ ×1.12  (≈ 60 ticks per decade)
const LOG_MIN:  float = -2.0
const LOG_MAX:  float =  3.0
const LOG_STEP: float =  0.05

# ── Internal state ───────────────────────────────────────────────────────────────
var _jobs:       Array = []   # active production jobs
var _job_status_labels: Dictionary = {}   # job_id → Label  (running / stalled)
var _job_rate_labels:   Dictionary = {}   # job_id → Label  (rate readout "1.0×")
var _job_out_labels:    Dictionary = {}   # job_id → Label  (output flow)
var _job_in_labels:     Dictionary = {}   # job_id → Label  (input flow)
var _next_id:    int   = 1
var _all_recipes: Array = []   # full recipe list (updated on research change)

# ── UI refs built in _build_ui ───────────────────────────────────────────────────
var _recipe_menu:    MenuButton    = null   # dropdown with one submenu per category
var _selected_recipe_name: String  = ""     # source of truth for the current pick
var _cat_submenus:   Array         = []      # category PopupMenu nodes, freed on rebuild
var _planet_option:  OptionButton = null
var _rate_slider:    HSlider      = null
var _rate_label:     Label        = null
var _add_button:     Button       = null
var _job_list:       VBoxContainer = null
var _inputs_label:   Label        = null
var _outputs_label:  Label        = null

# ── Log-scale helpers ────────────────────────────────────────────────────────────

## Slider position (log₁₀) → actual multiplier.
static func _log_to_rate(log_val: float) -> float:
	return pow(10.0, log_val)

## Actual multiplier → slider position (log₁₀), clamped to valid range.
static func _rate_to_log(rate: float) -> float:
	return clampf(log(maxf(rate, 1e-6)) / log(10.0), LOG_MIN, LOG_MAX)

## Human-readable rate label: "0.01×", "1.00×", "10×", "1000×".
static func _fmt_rate(rate: float) -> String:
	if rate >= 100.0: return "%d×"    % int(roundf(rate))
	if rate >= 10.0:  return "%.1f×"  % rate
	if rate >= 1.0:   return "%.2f×"  % rate
	return "%.3f×" % rate

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
	_recipe_menu = MenuButton.new()
	_recipe_menu.flat = false
	_recipe_menu.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_recipe_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(_recipe_menu)

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
	_rate_slider.min_value = LOG_MIN
	_rate_slider.max_value = LOG_MAX
	_rate_slider.step      = LOG_STEP
	_rate_slider.value     = 0.0          # 10^0 = 1×
	_rate_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rate_slider.value_changed.connect(_on_rate_changed)
	rate_row.add_child(_rate_slider)
	_rate_label = Label.new()
	_rate_label.text = "1.00×"
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

## Preferred display order for the category submenus; any unknown category is
## appended after these.
const CATEGORY_ORDER: Array = ["materials", "chemicals", "fuels", "energy", "biologics"]

## Rebuild the recipe dropdown as one submenu per category.
func _populate_recipes() -> void:
	var popup := _recipe_menu.get_popup()
	popup.clear()
	for sm in _cat_submenus:
		(sm as Node).queue_free()
	_cat_submenus.clear()

	# Bucket recipe indices by category.
	var by_cat: Dictionary = {}
	for i in range(_all_recipes.size()):
		var cat: String = str(_all_recipes[i].get("category", "other"))
		if not by_cat.has(cat):
			by_cat[cat] = []
		by_cat[cat].append(i)

	# Known categories first (fixed order), then any extras alphabetically.
	var cats: Array = []
	for c in CATEGORY_ORDER:
		if by_cat.has(c):
			cats.append(c)
	var extras: Array = by_cat.keys().filter(func(c): return c not in CATEGORY_ORDER)
	extras.sort()
	cats.append_array(extras)

	for cat: String in cats:
		var sub := PopupMenu.new()
		for idx: int in by_cat[cat]:
			sub.add_item(str(_all_recipes[idx]["name"]), idx)   # id = global recipe index
		sub.id_pressed.connect(_on_recipe_picked)
		_cat_submenus.append(sub)
		popup.add_submenu_node_item(cat.capitalize(), sub)

	# Keep the current pick if it still exists; otherwise default to the first recipe.
	if _selected_recipe().is_empty():
		_selected_recipe_name = str(_all_recipes[0]["name"]) if not _all_recipes.is_empty() else ""
	_update_recipe_menu_text()
	_update_io_preview()

## Update the MenuButton's label to reflect the current selection.
func _update_recipe_menu_text() -> void:
	var r := _selected_recipe()
	if r.is_empty():
		_recipe_menu.text = "Select recipe…"
	else:
		_recipe_menu.text = "%s  [%s]" % [r["name"], (r["category"] as String).capitalize()]

func _update_io_preview() -> void:
	var recipe := _selected_recipe()
	if recipe.is_empty():
		_inputs_label.text  = "—"
		_outputs_label.text = "—"
		return
	var rate: float = _log_to_rate(_rate_slider.value) if _rate_slider else 1.0
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
	if _selected_recipe_name == "":
		return {}
	for r in _all_recipes:
		if str(r["name"]) == _selected_recipe_name:
			return r
	return {}

# ── Job list ─────────────────────────────────────────────────────────────────────

func _rebuild_job_list() -> void:
	_job_status_labels.clear()
	_job_rate_labels.clear()
	_job_out_labels.clear()
	_job_in_labels.clear()
	for child in _job_list.get_children():
		child.queue_free()
	for job in _jobs:
		_add_job_row(job)

func _add_job_row(job: Dictionary) -> void:
	var recipe  := _find_recipe(job.get("recipe", ""))
	var rate:   float  = float(job.get("rate", 1.0))
	var planet: String = (job.get("planet", "earth") as String).capitalize()
	var job_id  := int(job.get("id", 0))

	# ── Outer card ────────────────────────────────────────────────────────────
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 3)

	# Row 1: recipe name + planet + remove button
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 6)

	var name_lbl := Label.new()
	name_lbl.text = "%s  @ %s" % [job.get("recipe", "?"), planet]
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(name_lbl)

	var status_lbl := Label.new()
	status_lbl.text = "…"
	status_lbl.add_theme_font_size_override("font_size", 10)
	status_lbl.modulate = Color(0.55, 0.55, 0.55)
	status_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_row.add_child(status_lbl)
	_job_status_labels[job_id] = status_lbl

	var rm := Button.new()
	rm.text = "✕"
	rm.flat = true
	rm.custom_minimum_size = Vector2(28, 28)
	rm.pressed.connect(_on_remove_pressed.bind(job_id))
	header_row.add_child(rm)

	card.add_child(header_row)

	# Row 2: rate slider + readout
	var slider_row := HBoxContainer.new()
	slider_row.add_theme_constant_override("separation", 6)

	var slider_lbl := Label.new()
	slider_lbl.text = "Rate:"
	slider_lbl.add_theme_font_size_override("font_size", 11)
	slider_lbl.modulate = Color(0.70, 0.70, 0.70)
	slider_row.add_child(slider_lbl)

	var slider := HSlider.new()
	slider.min_value = LOG_MIN
	slider.max_value = LOG_MAX
	slider.step      = LOG_STEP
	slider.value     = _rate_to_log(rate)   # store position in log₁₀ space
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider_row.add_child(slider)

	var rate_lbl := Label.new()
	rate_lbl.text = _fmt_rate(rate)
	rate_lbl.add_theme_font_size_override("font_size", 11)
	rate_lbl.custom_minimum_size = Vector2(38, 0)
	rate_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slider_row.add_child(rate_lbl)
	_job_rate_labels[job_id] = rate_lbl

	card.add_child(slider_row)

	# Row 3: output / input flow (updated live when slider moves)
	if not recipe.is_empty():
		var out_lbl := Label.new()
		out_lbl.text = "→ " + _fmt_flow(recipe.get("outputs", {}), rate)
		out_lbl.add_theme_font_size_override("font_size", 10)
		out_lbl.modulate = Color(0.55, 0.85, 0.60)
		card.add_child(out_lbl)
		_job_out_labels[job_id] = out_lbl

		var in_lbl := Label.new()
		in_lbl.text = "← " + _fmt_flow(recipe.get("inputs", {}), rate)
		in_lbl.add_theme_font_size_override("font_size", 10)
		in_lbl.modulate = Color(0.80, 0.65, 0.55)
		card.add_child(in_lbl)
		_job_in_labels[job_id] = in_lbl

	# Wire slider — convert log position → real rate, then update everything.
	slider.value_changed.connect(func(log_val: float) -> void:
		var actual_rate := _log_to_rate(log_val)
		# Update stored rate
		for j: Dictionary in _jobs:
			if int(j.get("id", -1)) == job_id:
				j["rate"] = actual_rate
				break
		# Update readout and flow labels
		rate_lbl.text = _fmt_rate(actual_rate)
		if not recipe.is_empty():
			if _job_out_labels.has(job_id):
				(_job_out_labels[job_id] as Label).text = "→ " + _fmt_flow(recipe.get("outputs", {}), actual_rate)
			if _job_in_labels.has(job_id):
				(_job_in_labels[job_id] as Label).text = "← " + _fmt_flow(recipe.get("inputs", {}), actual_rate)
		production_changed.emit(_jobs.duplicate(true))
	)

	_job_list.add_child(card)
	_job_list.add_child(HSeparator.new())

func _find_recipe(name: String) -> Dictionary:
	for r in RecipeData.RECIPES:
		if r["name"] == name:
			return r
	return {}

# ── Signals ──────────────────────────────────────────────────────────────────────

## A recipe was chosen from one of the category submenus (id = global recipe index).
func _on_recipe_picked(recipe_idx: int) -> void:
	if recipe_idx >= 0 and recipe_idx < _all_recipes.size():
		_selected_recipe_name = str(_all_recipes[recipe_idx]["name"])
		_update_recipe_menu_text()
		_update_io_preview()

func _on_rate_changed(value: float) -> void:
	_rate_label.text = _fmt_rate(_log_to_rate(value))
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
		"rate":   _log_to_rate(_rate_slider.value),
	}
	_next_id += 1
	_jobs.append(job)
	_add_job_row(job)
	production_changed.emit(_jobs.duplicate(true))

func _on_remove_pressed(job_id: int) -> void:
	_jobs = _jobs.filter(func(j): return int(j.get("id", -1)) != job_id)
	_rebuild_job_list()
	production_changed.emit(_jobs.duplicate(true))
