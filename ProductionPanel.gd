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
## LOG_MIN = -3  →  0.001×   |   LOG_MAX = 12  →  1 000 000 000 000×
## LOG_STEP = 0.05  →  each tick ≈ ×1.12  (20 ticks per decade, 300 across the range).
## The ceiling tracks Units.MASS_SCALE: one Mine yields 10 000 t/day, so a line that can
## actually consume a mining operation has to reach millions of tonnes per day.
## A rate of 1× is exactly one gram of product per game-day (see RecipeData.scale), so the
## multiplier reads directly as output mass — 5 000× is 5 kg/day.  Twelve decades is a lot of
## travel for a slider, so the readout beside it is editable: type an exact figure instead.
const LOG_MIN:  float = -3.0
const LOG_MAX:  float =  12.0
const LOG_STEP: float =  0.05

# ── Internal state ───────────────────────────────────────────────────────────────
var _jobs:       Array = []   # active production jobs
var _job_status_labels: Dictionary = {}   # job_id → Label  (running / stalled)
var _job_rate_labels:   Dictionary = {}   # job_id → Label  (rate readout "1.0×")
var _job_out_labels:    Dictionary = {}   # job_id → Label  (output flow)
var _job_work_labels: Dictionary = {}
var _job_in_labels:     Dictionary = {}   # job_id → Label  (input flow)
var _next_id:    int   = 1
var _all_recipes: Array = []   # full recipe list (updated on research change)

# ── UI refs built in _build_ui ───────────────────────────────────────────────────
var _recipe_menu:    MenuButton    = null   # dropdown with one submenu per category
var _selected_recipe_name: String  = ""     # source of truth for the current pick
var _cat_submenus:   Array         = []      # category PopupMenu nodes, freed on rebuild
var _rate_slider:    HSlider      = null
## Editable rate readout — typing an exact multiplier is the practical way to hit a precise
## figure now that the slider spans twelve decades.
var _rate_label:     LineEdit     = null
var _add_button:     Button       = null
var _job_list:       VBoxContainer = null
## Drag-to-reorder state.  Cards and their job ids are kept in display order so a drop can be
## resolved to an insertion index by comparing the pointer against each card's midpoint.
var _job_cards:      Array = []
var _card_job_ids:   Array = []
var _drag_job_id:    int = -1
var _drag_started:   bool = false
var _drag_press_y:   float = 0.0
var _scroll:         ScrollContainer = null
## Rank labels, refreshed in place after a drag so the list never has to be rebuilt mid-gesture.
var _job_rank_labels: Dictionary = {}
var _inputs_label:   Label        = null
var _outputs_label:  Label        = null
var _mc_label:       Label        = null
var _title_label:    Label        = null
## The body this panel currently manages — set by Game from the selected planet/moon tab.
## New jobs target it and the list is filtered to it (no in-panel planet picker any more).
var _active_planet:  String       = "earth"
## planet_lower → { "capacity": work/day, "demand": work/day }, pushed by Game.gd.
var _mc_state:       Dictionary   = {}

# ── Log-scale helpers ────────────────────────────────────────────────────────────

## Slider position (log₁₀) → actual multiplier.
static func _log_to_rate(log_val: float) -> float:
	return pow(10.0, log_val)

## Actual multiplier → slider position (log₁₀), clamped to valid range.
static func _rate_to_log(rate: float) -> float:
	return clampf(log(maxf(rate, 1e-6)) / log(10.0), LOG_MIN, LOG_MAX)

## The rate box is an editable field, so it holds the RAW multiplier and nothing else — no SI
## prefix, no "×".  What it shows is exactly what you could type back in: "0.001", "1", "2500",
## "1000000000".  Trailing zeros are trimmed so the field stays readable at any magnitude.
static func _fmt_rate(rate: float) -> String:
	if rate >= 1.0 and rate == floorf(rate):
		return "%d" % int(rate)                 # whole numbers print without a decimal point
	var s: String = "%.4f" % rate
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s = s.substr(0, s.length() - 1)
	return s

## Parse a typed multiplier back to a number, accepting the same shorthand _fmt_rate emits
## ("2.5k", "1M×", "3 G") as well as plain figures.  Returns -1.0 when it can't be read.
static func _parse_rate(text: String) -> float:
	var s: String = text.strip_edges().replace("×", "").replace(",", "").replace(" ", "")
	if s == "":
		return -1.0
	var mult: float = 1.0
	var last: String = s.substr(s.length() - 1, 1)
	match last:
		"k", "K": mult = 1.0e3
		"m", "M": mult = 1.0e6
		"g", "G", "b", "B": mult = 1.0e9
		"t", "T": mult = 1.0e12
	if mult != 1.0:
		s = s.substr(0, s.length() - 1)
	if not s.is_valid_float():
		return -1.0
	return s.to_float() * mult

# ── Lifecycle ────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_all_recipes = RecipeData.RECIPES
	_build_ui()
	set_process(false)   # only a live drag needs a per-frame tick (see _process)

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
	elif missing_input == "capacity":
		# Throttled by the world's Manufacturing Capacity, not an input shortage.
		lbl.text    = "⚙ capacity limited"
		lbl.modulate = Color(0.70, 0.80, 0.95)
	else:
		lbl.text    = "⚠ missing: %s" % missing_input if missing_input != "" else "⚠ stalled"
		lbl.modulate = Color(0.90, 0.55, 0.20)

## Point the panel at a body (planet OR moon).  New jobs target it and the list shows only its
## jobs; called by Game when the active planet tab changes.
func set_planet(planet: String) -> void:
	var p := planet.to_lower()
	if p == "":
		p = "earth"
	if p == _active_planet and not _jobs.is_empty():
		_update_mc_label()   # cheap refresh; avoid a full rebuild when nothing moved
		return
	_active_planet = p
	if _title_label:
		_title_label.text = "Manufacturing — %s" % p.capitalize()
	_rebuild_job_list()
	_update_mc_label()

## Push the per-planet Manufacturing Capacity state (from Game.gd) for the readout.
func set_mc_state(state: Dictionary) -> void:
	_mc_state = state
	_update_mc_label()

## Refresh the capacity readout for the active body.
## Pools a world runs, in the order they read: factory floor, then the two agricultural ones.
## Keys match Game's _last_mc_state — the factory pool is stored under the bare planet name,
## the others under "planet|pool".
const POOL_LABELS: Array = [["", "Factory"], ["|farm", "Arable"], ["|ranch", "Pasture"]]

func _update_mc_label() -> void:
	if _mc_label == null:
		return
	# Show EVERY pool this world actually has, not just the factory one.  A world can be an
	# industrial giant and still be out of arable land, and before this the panel only ever
	# reported the pool that happened to be listed first.
	var parts: Array = []
	var over: bool = false
	for entry: Array in POOL_LABELS:
		var info: Dictionary = _mc_state.get(_active_planet + str(entry[0]), {})
		var cap: float = float(info.get("capacity", 0.0))
		var used: float = float(info.get("demand", 0.0))
		if cap <= 0.0 and used <= 0.0:
			continue                     # this world has no such capacity and asks nothing of it
		if used > cap + 0.5:
			over = true
		parts.append("%s %s / %s" % [str(entry[1]),
			Units.format_si(used, ""), Units.format_si(cap, "")])
	_mc_label.text = ("  ·  ".join(parts) + "  work/day") if not parts.is_empty() else "No capacity here"
	# Tint amber when any pool's demand outstrips it (jobs drawing on it are throttled).
	_mc_label.modulate = Color(0.95, 0.65, 0.30) if over else Color(0.70, 0.80, 0.95)

## "Draws 3.4 G work/day from Arable" — the line's own demand and the pool it competes in.
func _fmt_work(recipe: Dictionary, rate: float) -> String:
	var pool: String = POOL_OF.get(str(recipe.get("category", "")), "Factory")
	return "Draws %s work/day from %s" % [
		Units.format_si(RecipeData.work_per_rate(recipe) * rate, ""), pool]

## Which capacity pool a recipe competes in — mirrors Game.RECIPE_POOL.
const POOL_OF: Dictionary = {"agriculture": "Arable", "livestock": "Pasture"}

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

	# Title (shows the active body; updated by set_planet)
	_title_label = Label.new()
	_title_label.text = "Manufacturing — Earth"
	_title_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_title_label)

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
	# Editable readout: drag the slider for a coarse sweep, or type an exact multiplier.
	_rate_label = LineEdit.new()
	_rate_label.text = "1.00×"
	_rate_label.custom_minimum_size = Vector2(92, 0)
	_rate_label.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_rate_label.tooltip_text = "Exact multiplier — 1× = 1 g of product per day. Accepts k / M / G."
	_rate_label.text_submitted.connect(func(txt: String) -> void:
		var v: float = _parse_rate(txt)
		if v > 0.0:
			_rate_slider.value = _rate_to_log(v)   # emits value_changed → refreshes the preview
		else:
			_rate_label.text = _fmt_rate(_log_to_rate(_rate_slider.value))
		_rate_label.release_focus())
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
	var jobs_header := HBoxContainer.new()
	jobs_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(jobs_header)

	var jobs_label := Label.new()
	jobs_label.text = "Active Production"
	jobs_label.add_theme_font_size_override("font_size", 13)
	jobs_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jobs_header.add_child(jobs_label)

	# Per-world Manufacturing Capacity readout for the selected location.
	_mc_label = Label.new()
	_mc_label.add_theme_font_size_override("font_size", 11)
	_mc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mc_label.modulate = Color(0.70, 0.80, 0.95)
	jobs_header.add_child(_mc_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_job_list = VBoxContainer.new()
	_job_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_job_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_job_list)

	_scroll = scroll

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
const CATEGORY_ORDER: Array = ["metals", "materials", "electronics", "aerospace", "chemicals", "fuels", "biologics"]

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
	# Preview the NORMALISED flow so it matches what the job will actually move (1× = 1 g/day).
	rate *= RecipeData.scale(recipe)
	_inputs_label.text  = _fmt_flow(recipe.get("inputs",  {}), rate)
	_outputs_label.text = _fmt_flow(recipe.get("outputs", {}), rate)

func _fmt_flow(flow: Dictionary, rate: float) -> String:
	if flow.is_empty():
		return "—"
	var parts: Array = []
	for k: String in flow:
		parts.append(_fmt_flow_entry(k, float(flow[k]) * rate))
	return "  ".join(parts)

## One input/output entry with its proper unit.  Recipe amounts are consumed and produced PER
## GAME-DAY (see Game._process_production, which multiplies them by elapsed days — the same time
## base as mine output and plant fuel), so every entry reads per day.  Compounds flow as mass;
## the abstract resources carry their own units.
func _fmt_flow_entry(k: String, v: float) -> String:
	match k:
		"energy":
			return "%s energy/day" % Units.format_si(v, "J")
		"science":
			return "%s science/day" % Units.format_si(v, "FLOP")
		"minerals":
			return "%s minerals/day" % Units.format_si(v, "g")
		_:
			return "%s %s/day" % [Units.format_si(v, "g"), k]     # e.g. "1.5 kg Fe/day"

func _selected_recipe() -> Dictionary:
	if _selected_recipe_name == "":
		return {}
	for r in _all_recipes:
		if str(r["name"]) == _selected_recipe_name:
			return r
	return {}

# ── Job list ─────────────────────────────────────────────────────────────────────

func _rebuild_job_list() -> void:
	_end_drag()          # a rebuild frees the cards, so no gesture may survive it
	_job_cards.clear()
	_card_job_ids.clear()
	_job_rank_labels.clear()
	_job_status_labels.clear()
	_job_rate_labels.clear()
	_job_out_labels.clear()
	_job_work_labels.clear()
	_job_in_labels.clear()
	for child in _job_list.get_children():
		child.queue_free()
	# Only this body's jobs (the panel is now per-planet/moon; no in-panel picker).
	for job in _jobs:
		if str(job.get("planet", "earth")).to_lower() == _active_planet:
			_add_job_row(job)

func _add_job_row(job: Dictionary) -> void:
	var recipe  := _find_recipe(job.get("recipe", ""))
	var rate:   float  = float(job.get("rate", 1.0))
	var job_id  := int(job.get("id", 0))

	# ── Outer card ────────────────────────────────────────────────────────────
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 3)

	# Row 1 doubles as the card's GRAB HANDLE: press anywhere on it and drag the line to a new
	# place in the list.  It is wrapped in a PanelContainer so the bar reads as something you
	# can take hold of, and so it has a background to tint while it is being dragged.
	var handle := PanelContainer.new()
	handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
	handle.tooltip_text = "Drag to reorder — lines higher up are served first"
	var hstyle := StyleBoxFlat.new()
	hstyle.bg_color = Color(0.16, 0.19, 0.26, 1.0)
	hstyle.set_corner_radius_all(3)
	hstyle.content_margin_left = 6
	hstyle.content_margin_right = 4
	hstyle.content_margin_top = 2
	hstyle.content_margin_bottom = 2
	handle.add_theme_stylebox_override("panel", hstyle)
	handle.gui_input.connect(_on_handle_input.bind(job_id))

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 6)
	handle.add_child(header_row)

	var grip := Label.new()
	grip.text = "⣿"
	grip.add_theme_font_size_override("font_size", 11)
	grip.modulate = Color(0.45, 0.50, 0.60)
	grip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(grip)

	# Priority rank.  A job's position in the list IS its claim on scarce inputs and on this
	# world's capacity: the top line is served first and the bottom line gets the remainder.
	var rank_lbl := Label.new()
	rank_lbl.text = "%d." % (_priority_of(job_id) + 1)
	rank_lbl.add_theme_font_size_override("font_size", 11)
	rank_lbl.modulate = Color(0.55, 0.60, 0.70)
	rank_lbl.custom_minimum_size = Vector2(22, 0)
	rank_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header_row.add_child(rank_lbl)
	_job_rank_labels[job_id] = rank_lbl

	var name_lbl := Label.new()
	name_lbl.text = str(job.get("recipe", "?"))
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
	rm.mouse_default_cursor_shape = Control.CURSOR_ARROW
	header_row.add_child(rm)

	card.add_child(handle)
	_job_cards.append(card)
	_card_job_ids.append(job_id)

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

	var rate_lbl := LineEdit.new()
	rate_lbl.text = _fmt_rate(rate)
	rate_lbl.add_theme_font_size_override("font_size", 11)
	rate_lbl.custom_minimum_size = Vector2(92, 0)
	rate_lbl.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rate_lbl.tooltip_text = "Exact multiplier — 1× = 1 g of product per day. Accepts k / M / G."
	rate_lbl.text_submitted.connect(func(txt: String) -> void:
		var v: float = _parse_rate(txt)
		if v > 0.0:
			slider.value = _rate_to_log(v)   # emits value_changed → updates job + flow labels
		else:
			rate_lbl.text = _fmt_rate(_log_to_rate(slider.value))
		rate_lbl.release_focus())
	slider_row.add_child(rate_lbl)
	_job_rate_labels[job_id] = rate_lbl

	card.add_child(slider_row)

	# Row 3: output / input flow (updated live when slider moves), in normalised units.
	var norm: float = RecipeData.scale(recipe) if not recipe.is_empty() else 1.0
	if not recipe.is_empty():
		var out_lbl := Label.new()
		out_lbl.text = "→ " + _fmt_flow(recipe.get("outputs", {}), rate * norm)
		out_lbl.add_theme_font_size_override("font_size", 10)
		out_lbl.modulate = Color(0.55, 0.85, 0.60)
		card.add_child(out_lbl)
		_job_out_labels[job_id] = out_lbl

		# What this line costs the world's capacity — the number that decides which job gets
		# throttled when the pool runs short, and which pool it competes in.
		var work_lbl := Label.new()
		work_lbl.text = _fmt_work(recipe, rate)
		work_lbl.add_theme_font_size_override("font_size", 10)
		work_lbl.modulate = Color(0.62, 0.72, 0.88)
		card.add_child(work_lbl)
		_job_work_labels[job_id] = work_lbl

		var in_lbl := Label.new()
		in_lbl.text = "← " + _fmt_flow(recipe.get("inputs", {}), rate * norm)
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
		if _job_work_labels.has(job_id):
			(_job_work_labels[job_id] as Label).text = _fmt_work(recipe, actual_rate)
		if not recipe.is_empty():
			if _job_out_labels.has(job_id):
				(_job_out_labels[job_id] as Label).text = "→ " + _fmt_flow(recipe.get("outputs", {}), actual_rate * norm)
			if _job_in_labels.has(job_id):
				(_job_in_labels[job_id] as Label).text = "← " + _fmt_flow(recipe.get("inputs", {}), actual_rate * norm)
		production_changed.emit(_jobs.duplicate(true))
	)

	# No separator node between cards: the list's children have to be cards and nothing else,
	# so a live drag can reorder them with move_child() and have the indices line up.  The gap
	# is the container's own separation, and each card's handle bar draws its own edge.
	_job_list.add_child(card)

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
	var job := {
		"id":     _next_id,
		"recipe": recipe["name"],
		"planet": _active_planet,
		"rate":   _log_to_rate(_rate_slider.value),
	}
	_next_id += 1
	_jobs.append(job)
	_add_job_row(job)
	production_changed.emit(_jobs.duplicate(true))

## Ids of this world's jobs, in priority order.  The master list interleaves every planet's
## jobs, so a move has to hop over other worlds' entries rather than shifting one slot.
func _planet_job_ids() -> Array:
	var ids: Array = []
	for j: Dictionary in _jobs:
		if str(j.get("planet", "earth")).to_lower() == _active_planet:
			ids.append(int(j.get("id", -1)))
	return ids

## This job's rank among the jobs shown on this world (-1 if it is not one of them).
func _priority_of(job_id: int) -> int:
	return _planet_job_ids().find(job_id)

## How far the pointer must travel before a press becomes a drag rather than a click.
const DRAG_THRESHOLD_PX: float = 4.0
## Band at the top and bottom of the list where a held card starts scrolling the view, and how
## fast it scrolls at the very edge.  Without this a list taller than the panel cannot be
## reordered past the part of it you can see.
const AUTOSCROLL_EDGE_PX: float = 44.0
const AUTOSCROLL_PX_PER_SEC: float = 900.0

## Handle events on a card's grab bar.  Press arms a drag, motion past the threshold starts it,
## and every further motion re-sorts the list live so the other tiles slide past the one being
## carried.  Godot keeps routing motion and the release to whichever control took the press, so
## the pointer may leave the bar — and the card may be moved around the tree — without the
## gesture breaking.
func _on_handle_input(event: InputEvent, job_id: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_job_id = job_id
			_drag_started = false
			_drag_press_y = event.global_position.y
		else:
			var moved: bool = _drag_started
			_end_drag()
			if moved:
				_commit_order()
		accept_event()
	elif event is InputEventMouseMotion and _drag_job_id == job_id:
		if not _drag_started:
			if absf(event.global_position.y - _drag_press_y) < DRAG_THRESHOLD_PX:
				return
			_drag_started = true
			_set_card_dragging(job_id, true)
			set_process(true)          # autoscroll needs a per-frame tick, not just motion
		_live_reorder(event.global_position.y)
		accept_event()

## While a card is held, drag it toward an edge and the list scrolls under it.  This runs every
## frame rather than on motion because the pointer can sit still against the edge and still
## expect the view to keep moving.
func _process(delta: float) -> void:
	if not _drag_started or _scroll == null:
		set_process(false)
		return
	var rect: Rect2 = _scroll.get_global_rect()
	var my: float = _scroll.get_global_mouse_position().y
	var push: float = 0.0
	if my < rect.position.y + AUTOSCROLL_EDGE_PX:
		push = -clampf((rect.position.y + AUTOSCROLL_EDGE_PX - my) / AUTOSCROLL_EDGE_PX, 0.0, 1.0)
	elif my > rect.end.y - AUTOSCROLL_EDGE_PX:
		push = clampf((my - (rect.end.y - AUTOSCROLL_EDGE_PX)) / AUTOSCROLL_EDGE_PX, 0.0, 1.0)
	if push == 0.0:
		return
	var before: int = _scroll.scroll_vertical
	_scroll.scroll_vertical = before + int(push * AUTOSCROLL_PX_PER_SEC * delta)
	# Re-sort against the view we just moved, so holding at the edge keeps walking the card
	# down (or up) the list instead of stalling once the pointer stops moving.
	if _scroll.scroll_vertical != before:
		_live_reorder(_scroll.get_global_mouse_position().y)

## Put the carried card where the pointer says it belongs, by moving the actual node.  The
## VBoxContainer re-lays out immediately, so the displaced tiles visibly slide past it.
func _live_reorder(gy: float) -> void:
	var cur: int = _card_job_ids.find(_drag_job_id)
	if cur < 0:
		return
	var card: Control = _job_cards[cur]
	if not is_instance_valid(card):
		return
	# Insertion index = how many OTHER cards have their midpoint above the pointer.
	#
	# The midpoints are computed from the ORDER rather than read off global_position, because
	# move_child() only queues the container's re-sort — the nodes still report last frame's
	# coordinates until it runs.  Reading those stale positions makes a card jump two slots on
	# one motion event and then oscillate.  Heights do not change while dragging, so walking
	# the stack is both exact and immune to that race.
	var sep: float = float(_job_list.get_theme_constant("separation"))
	var y: float = _job_list.global_position.y
	var want: int = 0
	for i in range(_job_cards.size()):
		var c: Control = _job_cards[i]
		if not is_instance_valid(c):
			continue
		if i != cur and gy > y + c.size.y * 0.5:
			want += 1
		y += c.size.y + sep
	if want == cur:
		return
	_job_list.move_child(card, want)
	_job_cards.remove_at(cur)
	_job_cards.insert(want, card)
	var moved_id = _card_job_ids[cur]
	_card_job_ids.remove_at(cur)
	_card_job_ids.insert(want, moved_id)
	_refresh_ranks()

## Renumber the "1." "2." labels in place — cheaper than a rebuild, and a rebuild mid-drag
## would free the very card the gesture is routed through.
func _refresh_ranks() -> void:
	for i in range(_card_job_ids.size()):
		var lbl = _job_rank_labels.get(int(_card_job_ids[i]))
		if lbl and is_instance_valid(lbl):
			(lbl as Label).text = "%d." % (i + 1)

## Tint the card being carried so it is obvious which line is in flight.
func _set_card_dragging(job_id: int, on: bool) -> void:
	var i: int = _card_job_ids.find(job_id)
	if i < 0 or i >= _job_cards.size():
		return
	var c: Control = _job_cards[i]
	if is_instance_valid(c):
		c.modulate = Color(1, 1, 1, 0.55) if on else Color(1, 1, 1, 1)

func _end_drag() -> void:
	if _drag_job_id >= 0 and _drag_started:
		_set_card_dragging(_drag_job_id, false)
	_drag_job_id = -1
	_drag_started = false
	set_process(false)

## Write the order the cards are now in back into the master job list.  Only the slots this
## world's jobs already occupy are rewritten, so every other planet's ordering is untouched by
## construction — no index arithmetic required.
func _commit_order() -> void:
	var slots: Array = []
	for i in range(_jobs.size()):
		if str((_jobs[i] as Dictionary).get("planet", "earth")).to_lower() == _active_planet:
			slots.append(i)
	if slots.size() != _card_job_ids.size():
		return                       # list and view disagree — leave the data alone
	var by_id: Dictionary = {}
	for j: Dictionary in _jobs:
		by_id[int(j.get("id", -1))] = j
	for k in range(slots.size()):
		var j = by_id.get(int(_card_job_ids[k]))
		if j == null:
			return
		_jobs[int(slots[k])] = j
	production_changed.emit(_jobs.duplicate(true))

func _on_remove_pressed(job_id: int) -> void:
	_jobs = _jobs.filter(func(j): return int(j.get("id", -1)) != job_id)
	_rebuild_job_list()
	production_changed.emit(_jobs.duplicate(true))
