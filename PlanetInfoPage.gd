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

# Composition section (replaces the Tree node at runtime).
var _composition_scroll:    ScrollContainer = null
var _composition_container: VBoxContainer   = null

# Inventory section (shown only when mines are present).
var _resources_header:    Label           = null
var _resources_scroll:    ScrollContainer = null
var _resources_container: VBoxContainer   = null

# ── Change-detection state ────────────────────────────────────────────────────
## Planet name the panel was last fully built for.  When this changes the whole
## panel is rebuilt from scratch; otherwise only the numeric labels are patched.
var _last_planet: String = ""

## Flat map of compound → Label for the inventory quantity column.
## Populated during a full rebuild; patched on every subsequent tick.
var _inv_value_labels: Dictionary = {}   # compound → Label (total stock)
var _inv_rate_labels:  Dictionary = {}   # compound → Label (mine rate)

const COMPOUND_NAMES: Dictionary = {
	# ── Ores / raw minerals ───────────────────────────────────────────────────
	"SiO2":    "Silicon Dioxide",
	"Al2O3":   "Aluminium Oxide",
	"Fe2O3":   "Hematite",
	"MgO":     "Periclase",
	"CaO":     "Calcium Oxide",
	"Na2O":    "Sodium Oxide",
	"K2O":     "Potassium Oxide",
	"TiO2":    "Titanium Dioxide",
	"CaCO3":   "Calcite",
	"FeS2":    "Pyrite",
	"FeO":     "Wüstite",
	"CuFeS2":  "Chalcopyrite",
	"Na2S":    "Sodium Sulfide",
	"H2O":     "Water",
	"NaCl":    "Halite",
	"P2O5":    "Phosphorus Pentoxide",
	"UO2":     "Uraninite",
	"ThO2":    "Thorianite",
	"Coal":    "Coal",
	"Oil":     "Petroleum",
	"CaSO4":   "Gypsum",
	"MgSO4":   "Epsomite",
	"N2":      "Nitrogen",
	"O2":      "Oxygen",
	"CO2":     "Carbon Dioxide",
	"Ni":      "Nickel",
	"FeS":     "Troilite",
	"MgS":     "Niningerite",
	"MgSiO3":  "Enstatite",
	"Mg2SiO4": "Forsterite",
	"CaSiO3":  "Wollastonite",
	"C":       "Carbon",
	# ── Refined metals ────────────────────────────────────────────────────────
	"Fe":      "Iron",
	"Si":      "Silicon",
	"Al":      "Aluminium",
	"Ti":      "Titanium",
	"Mg":      "Magnesium",
	"Ca":      "Calcium",
	"Na":      "Sodium",
	"K":       "Potassium",
	"Cu":      "Copper",
	"Steel":   "Steel",
	# ── Chemicals / components ────────────────────────────────────────────────
	"H2SO4":           "Sulfuric Acid",
	"NH3":             "Ammonia",
	"Plastic":         "Plastic",
	"Graphene":        "Graphene",
	"Ceramic":         "Ceramic",
	"CarbonComposite": "Carbon Composite",
	# ── Manufactured goods ────────────────────────────────────────────────────
	"Concrete":      "Concrete",
	"Glass":         "Glass",
	"SolarPanel":    "Solar Panel",
	"SolarSatellite":"Solar Satellite",
	"Microchip":     "Microchip",
	"Battery":       "Battery",
	"Superconductor":"Superconductor",
	"Propellant":    "Rocket Propellant",
	"FusionFuel":    "Fusion Fuel",
	"Rocket":        "Rocket",
	"H2":            "Hydrogen",
	"Aerogel":       "Aerogel",
	"CarbonNanotube":"Carbon Nanotube",
	"Metamaterial":  "Metamaterial",
	"SelfHealingComposite": "Self-Healing Composite",
	"QuantumProcessor":     "Quantum Processor",
	"Antimatter":    "Antimatter",
}

const COMPOUND_CATEGORIES: Dictionary = {
	# Raw ores and crustal compounds
	"Coal":    "raw",  "Oil":     "raw",
	"SiO2":   "raw",  "Al2O3":  "raw",  "Fe2O3":  "raw",  "MgO":    "raw",
	"CaO":    "raw",  "Na2O":   "raw",  "K2O":    "raw",  "TiO2":   "raw",
	"CaCO3":  "raw",  "FeS2":   "raw",  "H2O":    "raw",  "NaCl":   "raw",
	"P2O5":   "raw",  "UO2":    "raw",  "ThO2":   "raw",
	"CuFeS2": "raw",  "Na2S":   "raw",  "C":      "raw",  "FeO":    "raw",
	"CaSO4":  "raw",  "MgSO4":  "raw",  "N2":     "raw",
	"Ni":     "raw",  "FeS":    "raw",  "MgS":    "raw",
	# Refined metals (outputs of smelting / electrolysis recipes)
	"Fe":     "refined",
	"Si":     "refined",
	"Al":     "refined",
	"Ti":     "refined",
	"Mg":     "refined",
	"Ca":     "refined",
	"Na":     "refined",
	"K":      "refined",
	"Cu":     "refined",
	"Steel":  "refined",   # primary structural alloy
	"O2":     "refined",   # electrolytic oxygen — useful industrial gas
	# Processed feedstock components
	"Plastic":         "components",
	"Graphene":        "components",
	"Ceramic":         "components",
	"CarbonComposite": "components",
	"H2SO4":           "components",   # industrial chemical feedstock
	"NH3":             "components",
	# Manufactured goods (assembled from refined inputs)
	"Concrete":      "manufactured",
	"Glass":         "manufactured",
	"SolarPanel":    "manufactured",
	"SolarSatellite":"manufactured",
	"Microchip":     "manufactured",
	"Battery":       "manufactured",
	"Superconductor":"manufactured",
	"Propellant":    "manufactured",
	"FusionFuel":    "manufactured",
	"Rocket":        "manufactured",
	"H2":            "refined",
	"Aerogel":       "manufactured",
	"CarbonNanotube":"manufactured",
	"Metamaterial":  "manufactured",
	"SelfHealingComposite": "manufactured",
	"QuantumProcessor":     "manufactured",
	"Antimatter":    "manufactured",
}

const CATEGORY_ORDER: Array[String] = ["raw", "refined", "components", "manufactured"]

const CATEGORY_LABELS: Dictionary = {
	"raw":          "Raw Materials",
	"refined":      "Refined Materials",
	"components":   "Components",
	"manufactured": "Manufactured Goods",
}

const CATEGORY_COLORS: Dictionary = {
	"raw":          Color(0.80, 0.70, 0.50),
	"refined":      Color(0.50, 0.80, 0.65),
	"components":   Color(0.50, 0.70, 1.00),
	"manufactured": Color(0.85, 0.55, 0.90),
}

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

	# ── Inventory scroll ──────────────────────────────────────────────────────
	_resources_header = Label.new()
	_resources_header.text = "Inventory"
	_resources_header.visible = false
	vbox.add_child(_resources_header)

	_resources_scroll = ScrollContainer.new()
	_resources_scroll.custom_minimum_size = Vector2(0, 200)
	_resources_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_resources_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_resources_scroll.visible = false
	vbox.add_child(_resources_scroll)

	_resources_container = VBoxContainer.new()
	_resources_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resources_container.add_theme_constant_override("separation", 2)
	_resources_scroll.add_child(_resources_container)

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
	population_label.text = _fmt_population(int(data.get("population", 0)))
	compute_label.text    = Units.format_si_verbose(float(data.get("compute", 0.0)), "FLOP/s")

	var mined: Dictionary = data.get("mined_resources",   {})
	var inv:   Dictionary = data.get("compound_inventory", {})

	# Rebuild if the planet changed OR if a new compound appeared in the inventory
	# (e.g. a manufacturing recipe produced something not previously shown).
	var compound_set_changed := false
	for compound: String in mined:
		if not _inv_value_labels.has(compound):
			compound_set_changed = true
			break

	if planet_name != _last_planet or compound_set_changed:
		# ── Full structural rebuild — when switching planet or inventory grows ─
		_last_planet = planet_name
		_inv_value_labels.clear()
		_inv_rate_labels.clear()

		_rebuild_composition(data.get("composition_g", {}))
		_rebuild_inventory(mined, inv)
	else:
		# ── Fast path — patch labels in-place, no node creation ───────────────
		for compound: String in _inv_value_labels:
			var total: float = float(inv.get(compound, 0.0))
			(_inv_value_labels[compound] as Label).text = Units.format_si(total, "g")
		# Mine rates don't change tick-to-tick, but update for correctness.
		for compound: String in _inv_rate_labels:
			var rate: float = float(mined.get(compound, 0.0))
			(_inv_rate_labels[compound] as Label).text = "+%s/s" % Units.format_si(rate, "g")

	show()

## Full rebuild of the inventory section.  Called only when the selected planet changes.
func _rebuild_inventory(mined: Dictionary, inv: Dictionary) -> void:
	if not _resources_container:
		return
	for child in _resources_container.get_children():
		child.queue_free()

	if mined.is_empty():
		if _resources_header: _resources_header.visible = false
		if _resources_scroll: _resources_scroll.visible = false
		return

	if _resources_header: _resources_header.visible = true
	if _resources_scroll: _resources_scroll.visible = true

	# Sort by rate descending, bucket into categories.
	var pairs: Array = []
	for compound: String in mined:
		pairs.append([compound, float(mined[compound]), inv.get(compound, 0.0)])
	pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])

	var by_cat: Dictionary = {}
	for cat: String in CATEGORY_ORDER:
		by_cat[cat] = []
	for pair: Array in pairs:
		var cat: String = COMPOUND_CATEGORIES.get(pair[0] as String, "raw")
		(by_cat[cat] as Array).append(pair)

	for cat: String in CATEGORY_ORDER:
		var items: Array  = by_cat[cat] as Array
		var label: String = CATEGORY_LABELS[cat]
		var color: Color  = CATEGORY_COLORS[cat]

		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 2)
		# Raw ores start collapsed (rarely inspected after mines are built).
		# Refined and manufactured outputs start expanded so the player can
		# immediately see what the production lines are generating.
		content.visible = (cat != "raw")

		var header := Button.new()
		header.flat = true
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.add_theme_font_size_override("font_size", 12)
		header.add_theme_color_override("font_color", color)
		# Suffix shows count of non-zero items so the player can see at a glance
		# how many refined products are in stock even when the section is collapsed.
		var non_zero: int = 0
		for pair: Array in items:
			if float(pair[2]) > 0.0:
				non_zero += 1
		var count_suffix: String = " (%d)" % non_zero if non_zero > 0 else ""
		header.text = ("▼  " if content.visible else "▶  ") + label + count_suffix
		header.pressed.connect(func() -> void:
			content.visible = not content.visible
			header.text = ("▼  " if content.visible else "▶  ") + label + count_suffix
		)
		_resources_container.add_child(header)
		_resources_container.add_child(content)

		if items.is_empty():
			var empty_lbl := Label.new()
			empty_lbl.text = "    —"
			empty_lbl.add_theme_font_size_override("font_size", 11)
			empty_lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.50))
			content.add_child(empty_lbl)
		else:
			for pair: Array in items:
				var compound: String = pair[0]
				var rate: float      = pair[1]
				var total: float     = pair[2]
				var row_data := _compound_row_tracked(
					compound,
					Units.format_si(total, "g"),
					"+%s/s" % Units.format_si(rate, "g"),
					Color(0.40, 0.90, 0.55)
				)
				content.add_child(row_data[0])
				content.add_child(_thin_sep())
				_inv_value_labels[compound] = row_data[1]
				_inv_rate_labels[compound]  = row_data[2]


func clear_planet_info() -> void:
	_last_planet = ""
	_inv_value_labels.clear()
	_inv_rate_labels.clear()
	planet_name_label.text = "No Planet Selected"
	energy_label.text      = "-"
	population_label.text  = "-"
	compute_label.text     = "-"
	if _storage_minerals_label:
		_storage_minerals_label.text = "-"
		_storage_energy_label.text   = "-"
	if _composition_container:
		for child in _composition_container.get_children():
			child.queue_free()
	if _resources_header: _resources_header.visible = false
	if _resources_scroll:
		_resources_scroll.visible = false
		for child in _resources_container.get_children():
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
func _compound_row_tracked(formula: String, right_top: String, right_bottom: String, right_color: Color) -> Array:
	var common: String = COMPOUND_NAMES.get(formula, formula)
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
	var bot_lbl := Label.new()
	bot_lbl.text = right_bottom
	bot_lbl.add_theme_font_size_override("font_size", 10)
	bot_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.80))
	bot_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(bot_lbl)
	row.add_child(right)

	return [row, top_lbl, bot_lbl]

func _compound_row(formula: String, right_top: String, right_bottom: String, right_color: Color) -> HBoxContainer:
	var common: String = COMPOUND_NAMES.get(formula, formula)

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
