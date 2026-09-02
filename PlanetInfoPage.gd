extends PanelContainer

@onready var planet_name_label: Label         = $MarginContainer/VBoxContainer/PlanetName
@onready var energy_label:      Label         = $MarginContainer/VBoxContainer/GridContainer/EnergyValue
@onready var population_label:  Label         = $MarginContainer/VBoxContainer/GridContainer/PopulationValue
@onready var compute_label:     Label         = $MarginContainer/VBoxContainer/GridContainer/ComputeValue
@onready var stats_grid:        GridContainer = $MarginContainer/VBoxContainer/GridContainer
@onready var composition_tree:  Tree          = $MarginContainer/VBoxContainer/ResourcesList

# Dynamically-created storage labels (added to stats_grid in _ready).
var _storage_minerals_label: Label = null
var _storage_energy_label:   Label = null
## Manufacturing Capacity readout ("used / capacity"), added to stats_grid in _ready.
var _mc_label: Label = null
var _construction_key: Label = null
var _construction_label: Label = null

# Composition section (replaces the Tree node at runtime).
var _composition_scroll:    ScrollContainer = null
var _composition_container: VBoxContainer   = null

# ── Change-detection state ────────────────────────────────────────────────────
## Planet name the panel was last fully built for.  When this changes the composition
## section is rebuilt; otherwise only the numeric labels are patched.  (The material
## stockpile now lives in its own Inventory tab, not here.)
var _last_planet: String = ""


const LAYER_ORDER: Array[String] = ["atmosphere", "crust", "mantle", "core"]

const LAYER_LABEL: Dictionary = {
	"atmosphere": "Atmosphere",
	"crust":      "Crust",
	"mantle":     "Mantle",
	"core":       "Core",
}

const LAYER_COLOR: Dictionary = {
	"atmosphere": Color(0.55, 0.80, 1.00),
	"crust":      Color(0.80, 0.65, 0.45),
	"mantle":     Color(1.00, 0.55, 0.30),
	"core":       Color(1.00, 0.82, 0.30),
}


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index in [
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		accept_event()


func _ready() -> void:
	# Hide the scene-defined Tree; we replace it with a scrollable row list.
	composition_tree.hide()
	var tree_idx: int = composition_tree.get_index()

	# ── Manufacturing capacity row ────────────────────────────────────────────
	# How much the world can run in the recipe panel at once (used / capacity, in
	# work-units/day).  Factories raise the capacity; see Game's Manufacturing Capacity.
	var _mc_key := Label.new()
	_mc_key.text = "Manufacturing"
	_mc_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_grid.add_child(_mc_key)
	_mc_label = Label.new()
	_mc_label.text = "-"
	_mc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stats_grid.add_child(_mc_label)

	# ── Construction row (hidden unless this world is building something) ──────
	# Build speed is gated by Manufacturing capacity, so what's rising and how far
	# along it is lives right under the MC readout.
	_construction_key = Label.new()
	_construction_key.text = "Construction"
	_construction_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_grid.add_child(_construction_key)
	_construction_label = Label.new()
	_construction_label.text = ""
	_construction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stats_grid.add_child(_construction_label)
	_construction_key.hide()
	_construction_label.hide()

	# ── Storage capacity rows ─────────────────────────────────────────────────
	var _stor_min_key := Label.new()
	_stor_min_key.text = "Matter Storage"
	_stor_min_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_grid.add_child(_stor_min_key)
	_storage_minerals_label = Label.new()
	_storage_minerals_label.text = "-"
	_storage_minerals_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stats_grid.add_child(_storage_minerals_label)

	var _stor_en_key := Label.new()
	_stor_en_key.text = "Energy Storage"
	_stor_en_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_grid.add_child(_stor_en_key)
	_storage_energy_label = Label.new()
	_storage_energy_label.text = "-"
	_storage_energy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stats_grid.add_child(_storage_energy_label)

	# ── Composition scroll (inserted where the Tree was) ──────────────────────
	var vbox: VBoxContainer = composition_tree.get_parent()

	_composition_scroll = ScrollContainer.new()
	_composition_scroll.custom_minimum_size = Vector2(0, 200)
	_composition_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_composition_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_composition_scroll)
	vbox.move_child(_composition_scroll, tree_idx)

	_composition_container = VBoxContainer.new()
	_composition_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_composition_container.add_theme_constant_override("separation", 2)
	_composition_scroll.add_child(_composition_container)

	custom_minimum_size = Vector2(340, 0)


## Format a whole-number population with thousands separators, e.g. 2300000000
## → "2,300,000,000".  Populations are always integers (a count of people).
func _fmt_population(n: int) -> String:
	var s: String = str(maxi(0, n))
	var out: String = ""
	var c: int = 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out

## Compact human-readable build ETA (game-days → days / months / years).
func _fmt_build_eta(days: float) -> String:
	if days < 60.0:
		return "%d days" % int(ceil(days))
	if days < 730.0:
		return "%d months" % int(ceil(days / 30.0))
	return "%.1f years" % (days / 365.25)

func set_planet_info(data: Dictionary) -> void:
	var planet_name: String = str(data.get("name", ""))

	planet_name_label.text = planet_name

	var scap: Dictionary = data.get("storage_cap", {})
	var min_cap: float   = scap.get("minerals", 0.0)
	var en_cap:  float   = scap.get("energy",   0.0)
	if _storage_minerals_label:
		_storage_minerals_label.text = Units.format_si(min_cap, "g") if min_cap > 0.0 else "None"
		_storage_energy_label.text   = Units.format_si(en_cap,  "J") if en_cap  > 0.0 else "None"

	energy_label.text     = Units.format_si_verbose(float(data.get("energy",  0.0)), "Watts")
	# Power made off-world only counts once it has been beamed home.  When the link is the
	# binding constraint, say so here -- otherwise a swarm that is throttled just looks broken.
	var l_off: float = float(data.get("link_offered", 0.0))
	var l_del: float = float(data.get("link_delivered", 0.0))
	if l_off > l_del + 1.0:
		energy_label.text += "  · link full, %s stranded" % Units.format_si(l_off - l_del, "W")
		energy_label.modulate = Color(0.95, 0.65, 0.30)
	else:
		energy_label.modulate = Color(1, 1, 1)
	population_label.text = _fmt_population(int(data.get("population", 0)))
	# Food: how long the larder lasts at the current rate, and who is going hungry.  A world
	# eating into its stores reads as a countdown; one that has run out reads as a death rate.
	var fam: float = float(data.get("famine", 0.0))
	var fdays: float = float(data.get("food_days", -1.0))
	if fam > 0.0:
		population_label.text += "  ·  FAMINE — %d%% unfed" % int(round(fam * 100.0))
		population_label.modulate = Color(0.95, 0.35, 0.30)
	elif fdays >= 0.0:
		population_label.text += "  ·  %s food, %s left" % [
			Units.format_si(float(data.get("food_stored", 0.0)), "g"),
			("%.0f days" % fdays) if fdays < 720.0 else ("%.1f years" % (fdays / 365.25))]
		population_label.modulate = Color(0.95, 0.65, 0.30) if fdays < 60.0 else Color(1, 1, 1)
	else:
		population_label.modulate = Color(1, 1, 1)
	compute_label.text    = Units.format_si_verbose(float(data.get("compute", 0.0)), "FLOP/s")

	if _mc_label:
		var mc_cap:  float = float(data.get("mc_capacity", 0.0))
		var mc_used: float = float(data.get("mc_used", 0.0))
		if mc_cap > 0.0:
			_mc_label.text = "%s / %s" % [
				Units.format_si_verbose(mc_used, ""), Units.format_si_verbose(mc_cap, "")]
			# Show the labour drag when the workforce can't fully staff built capacity.
			var staffing: float = float(data.get("labor_staffing", 1.0))
			if staffing < 0.99:
				_mc_label.text += "  · labour %d%%" % int(round(staffing * 100.0))
			# Amber when demand outstrips capacity (jobs on this world are throttled).
			_mc_label.modulate = Color(0.95, 0.65, 0.30) if mc_used > mc_cap + 0.5 \
				else Color(0.85, 0.85, 0.85)
		else:
			_mc_label.text = "-"
			_mc_label.modulate = Color(0.85, 0.85, 0.85)

	# Construction status — what this world's manufacturing capacity is currently raising.
	if _construction_label:
		var con: Array = data.get("construction", [])
		if con.is_empty():
			_construction_label.text = ""
			_construction_label.hide()
			if _construction_key:
				_construction_key.hide()
		else:
			if _construction_key:
				_construction_key.show()
			var front: Dictionary = con[0]
			var pct: int = int(round(float(front.get("frac", 0.0)) * 100.0))
			var txt: String = "Building %s  %d%%" % [str(front.get("name", "")), pct]
			var eta: float = float(front.get("eta_days", -1.0))
			if eta >= 0.0:
				txt += "  (~%s)" % _fmt_build_eta(eta)
			else:
				txt += "  (waiting on capacity)"   # recipes are using all this world's MC
			if con.size() > 1:
				txt += "  +%d queued" % (con.size() - 1)
			_construction_label.text = txt
			_construction_label.modulate = Color(0.95, 0.70, 0.30)
			_construction_label.show()

	# Crust composition is static per body, so it only needs rebuilding when the planet
	# changes.  (The material stockpile is shown in the separate Inventory tab now.)
	if planet_name != _last_planet:
		_last_planet = planet_name
		_rebuild_composition(data.get("composition_g", {}))
	# Visibility is managed by the parent TabContainer / Game (this is a tab page now).

func clear_planet_info() -> void:
	_last_planet = ""
	planet_name_label.text = "No Planet Selected"
	energy_label.text      = "-"
	population_label.text  = "-"
	compute_label.text     = "-"
	if _mc_label:
		_mc_label.text = "-"
		_mc_label.modulate = Color(0.85, 0.85, 0.85)
	if _storage_minerals_label:
		_storage_minerals_label.text = "-"
		_storage_energy_label.text   = "-"
	if _composition_container:
		for child in _composition_container.get_children():
			child.queue_free()
	hide()


func _rebuild_composition(composition: Dictionary) -> void:
	for child in _composition_container.get_children():
		child.queue_free()

	var first_layer := true
	for layer_key: String in LAYER_ORDER:
		if not composition.has(layer_key):
			continue
		var compounds: Dictionary = composition[layer_key] as Dictionary
		if compounds.is_empty():
			continue

		if not first_layer:
			_composition_container.add_child(_thin_sep())
		first_layer = false

		var layer_label: String = LAYER_LABEL.get(layer_key, layer_key.capitalize())
		var layer_color: Color  = LAYER_COLOR.get(layer_key, Color.WHITE)

		# Collapsible content container (collapsed by default)
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 2)
		content.visible = false

		# Clickable header button toggles content
		var header := Button.new()
		header.text = "▶  " + layer_label
		header.flat = true
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.add_theme_color_override("font_color", layer_color)
		header.add_theme_font_size_override("font_size", 12)
		header.pressed.connect(func() -> void:
			content.visible = not content.visible
			header.text = ("▼  " if content.visible else "▶  ") + layer_label
		)
		_composition_container.add_child(header)
		_composition_container.add_child(content)

		# Sort by mass descending
		var pairs: Array = []
		for formula: String in compounds:
			pairs.append([formula, float(compounds[formula])])
		pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])

		for pair: Array in pairs:
			var formula: String = pair[0] as String
			var mass: float     = pair[1] as float
			content.add_child(_compound_row(formula, Units.format_si(mass, "g"), "", Color.WHITE))
			content.add_child(_thin_sep())


## Like _compound_row but also returns the two right-side labels so the caller
## can patch them in place on subsequent ticks without rebuilding the row.
## Returns [HBoxContainer, top_label, bottom_label].
func _compound_row(formula: String, right_top: String, right_bottom: String, right_color: Color) -> HBoxContainer:
	var common: String = CompoundData.NAMES.get(formula, formula)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_lbl := Label.new()
	name_lbl.text = common
	name_lbl.add_theme_font_size_override("font_size", 12)
	left.add_child(name_lbl)
	var formula_lbl := Label.new()
	formula_lbl.text = formula
	formula_lbl.add_theme_font_size_override("font_size", 10)
	formula_lbl.add_theme_color_override("font_color", Color(0.60, 0.70, 0.80))
	left.add_child(formula_lbl)
	row.add_child(left)

	var right := VBoxContainer.new()
	var top_lbl := Label.new()
	top_lbl.text = right_top
	top_lbl.add_theme_font_size_override("font_size", 12)
	top_lbl.add_theme_color_override("font_color", right_color)
	top_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(top_lbl)
	if right_bottom != "":
		var bot_lbl := Label.new()
		bot_lbl.text = right_bottom
		bot_lbl.add_theme_font_size_override("font_size", 10)
		bot_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.80))
		bot_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.add_child(bot_lbl)
	row.add_child(right)

	return row


func _thin_sep() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 1)
	sep.modulate = Color(1, 1, 1, 0.15)
	return sep
