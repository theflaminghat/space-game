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
var _capacity_label:       Label = null
var _capacity_natural_label: Label = null
var _capacity_built_label:   Label = null
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


## Star rows, by key: { key: Label, value: Label }.  Only the Sun shows them.
var _star_rows: Dictionary = {}


func _ready() -> void:
	# Hide the scene-defined Tree; we replace it with a scrollable row list.
	composition_tree.hide()
	var tree_idx: int = composition_tree.get_index()

	# ── Carrying capacity row ─────────────────────────────────────────────────
	# How many people this world can hold, split into what it supports on its OWN and what has
	# been built for it.  Off Earth the first figure is zero — a colony's ceiling is exactly
	# the domes and habitats standing on it — and that is the fact worth showing here.
	var _cap_key := Label.new()
	_cap_key.text = "Capacity"
	_cap_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_grid.add_child(_cap_key)
	_capacity_label = Label.new()
	_capacity_label.text = "-"
	_capacity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stats_grid.add_child(_capacity_label)

	# The two halves get a row each rather than sharing one as "natural / built".  They are
	# separate quantities that move for different reasons — one with the climate, one with what
	# you build — and a slash between them reads as a ratio, which it is not.
	_capacity_natural_label = _sub_row("  natural")
	_capacity_built_label   = _sub_row("  built")

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

	# ── Star rows (the Sun only) ──────────────────────────────────────────────
	# The Sun has no population or larder; what matters about it is its state as a star, and —
	# once stellar engineering starts — what the player has done to it.  These rows stay hidden
	# for every other body.
	for spec: Array in [["Mass", "mass"], ["Luminosity", "luminosity"], ["Radius", "radius"],
			["Ageing", "ageing"], ["Shading", "shade"], ["Rejuvenated", "rejuvenated"],
			["Thrust", "thrust"], ["Fate", "fate"], ["Red giant", "red_giant"],
			["Nebula", "nebula"]]:
		var k := Label.new()
		k.text = str(spec[0])
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats_grid.add_child(k)
		var v := Label.new()
		v.text = "-"
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stats_grid.add_child(v)
		_star_rows[str(spec[1])] = {"key": k, "value": v}
		k.hide()
		v.hide()

	custom_minimum_size = Vector2(340, 0)


## Show the star block for the Sun and hide it for everything else.  The two dates are the ones
## stellar engineering exists to move, so they are spelled out as years rather than countdowns.
func _set_star_rows(star: Dictionary) -> void:
	var show: bool = not star.is_empty()
	for key: String in _star_rows:
		(_star_rows[key]["key"] as Label).visible = show
		(_star_rows[key]["value"] as Label).visible = show
	if not show:
		return
	var mass: float = float(star.get("mass_msun", 1.0))
	var engineered: bool = bool(star.get("engineered", false))
	_star_rows["mass"]["value"].text = "%.4f M☉" % mass
	# An untouched Sun is the baseline; a lifted one says how much is gone, which is the number
	# every other figure here follows from.
	_star_rows["mass"]["value"].modulate = Color(0.55, 0.85, 1.0) if engineered else Color(1, 1, 1)
	if engineered:
		_star_rows["mass"]["value"].text += "  (−%.2f%%)" % ((1.0 - mass) * 100.0)
	_star_rows["luminosity"]["value"].text = "%s L☉" % _fmt_solar(float(star.get("luminosity", 1.0)))
	_star_rows["radius"]["value"].text = "%s R☉" % _fmt_solar(float(star.get("radius_solar", 1.0)))
	# How fast the star is living, against the calendar.  This is the whole return on lifting
	# mass: below 1.00× the Sun is ageing slower than the years are passing.
	var ageing: float = float(star.get("ageing", 1.0))
	_star_rows["ageing"]["value"].text = "%.3f× calendar" % ageing
	_star_rows["ageing"]["value"].modulate = Color(0.55, 0.85, 1.0) if engineered else Color(1, 1, 1)
	# Shading and rejuvenation are the other two levers; both read "none" until something stands.
	var shade: float = float(star.get("shade", 0.0))
	_star_rows["shade"]["value"].text = "none" if shade <= 0.0 else "%.3f%% of the light" % (shade * 100.0)
	_star_rows["shade"]["value"].modulate = Color(0.55, 0.85, 1.0) if shade > 0.0 else Color(1, 1, 1)
	var rejuv: float = float(star.get("rejuvenated", 0.0))
	_star_rows["rejuvenated"]["value"].text = "none" if rejuv <= 0.0 else Units.format_si(rejuv, "yr")
	_star_rows["rejuvenated"]["value"].modulate = Color(0.55, 0.85, 1.0) if rejuv > 0.0 else Color(1, 1, 1)
	# Where the star is going, once there are mirrors pushing it.
	var mirrors: float = float(star.get("mirrors", 0.0))
	var drift: float = float(star.get("drift", 0.0))
	if mirrors <= 0.0 and drift <= 0.0:
		_star_rows["thrust"]["value"].text = "none"
		_star_rows["thrust"]["value"].modulate = Color(1, 1, 1)
	else:
		var aim: String = str(star.get("thrust_aim", ""))
		_star_rows["thrust"]["value"].text = "%s ly at %s%s" % [
			("%.3f" % drift).rstrip("0").rstrip("."),
			Units.format_si(float(star.get("drift_speed", 0.0)), "m/s"),
			"" if aim == "" else " → %s" % aim]
		_star_rows["thrust"]["value"].modulate = Color(0.55, 0.85, 1.0)

	# What the star is bound to become — and, when lifting has taken it below helium ignition,
	# there is no giant branch left to date, so the two dates read "never" rather than a number.
	var dated: bool = bool(star.get("dated_fate", true))
	_star_rows["fate"]["value"].text = str(star.get("fate", ""))
	_star_rows["fate"]["value"].modulate = Color(1, 1, 1) if dated else Color(0.55, 0.85, 1.0)
	_star_rows["red_giant"]["value"].text = Units.format_si(float(star.get("red_giant", 0.0)), "yr") \
		if dated else "never"
	_star_rows["nebula"]["value"].text = Units.format_si(float(star.get("nebula", 0.0)), "yr") \
		if dated else "never"


## Solar units read better as plain decimals than as SI: 0.365 L☉, not "365.4 m L☉".  Falls back
## to SI at the extremes, where a red giant's thousands of suns need it.
func _fmt_solar(v: float) -> String:
	if v >= 0.001 and v < 1000.0:
		return ("%.3f" % v).rstrip("0").rstrip(".")
	return Units.format_si(v, "")


## Format a whole-number population with thousands separators, e.g. 2300000000
## → "2,300,000,000".  Populations are always integers (a count of people).
## A dimmed key/value pair under the row above it — used for the halves of a total, where the
## indent and the colour say "this is part of the number above" without repeating its name.
func _sub_row(key: String) -> Label:
	var k := Label.new()
	k.text = key
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.modulate = Color(0.65, 0.70, 0.80)
	stats_grid.add_child(k)
	var v := Label.new()
	v.text = "-"
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.modulate = Color(0.65, 0.70, 0.80)
	stats_grid.add_child(v)
	return v

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

	_set_star_rows(data.get("star", {}))

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
	# Carrying capacity, and where it comes from.
	if _capacity_label:
		var nat: float = float(data.get("natural_capacity", 0.0))
		var art: float = float(data.get("artificial_capacity", 0.0))
		var cap: float = nat + art
		_capacity_label.text = _fmt_population(int(cap)) if cap > 0.0 else "Uninhabitable"
		_capacity_natural_label.text = _fmt_population(int(nat))
		_capacity_built_label.text   = _fmt_population(int(art))
		# Amber once the world is close to full: the ceiling is about to become the constraint.
		var pop_now: float = float(data.get("population", 0))
		var near_full: bool = cap > 0.0 and pop_now > cap * 0.9
		_capacity_label.modulate = Color(0.95, 0.65, 0.30) if near_full else Color(0.85, 0.90, 0.70)
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
