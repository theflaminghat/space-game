class_name AutomationPanel
extends PanelContainer

## AutomationPanel — lets the player write standing "automation rules" the game then
## follows on its own.  Three kinds:
##   • build  — keep N of a building on a world (the game builds more whenever it can
##              afford one and the count is short).
##   • launch — keep N missions of a kind in flight (the game re-launches whenever a
##              slot frees up and the origin can supply the rockets + fuel).
##   • defend — shoot down asteroids and/or weapons aimed at a world, without stopping
##              the clock to ask, for as long as the array is up and the shot affordable.
##
## Rules matter because time accelerates toward heat death — past a point you cannot
## hand-place every factory or re-fly every supply run, so you delegate the routine to
## standing orders and watch what your civilisation does without you.
##
## Emits automation_changed(rules: Array); Game.gd stores and executes the rules.
## Rule shapes:
##   { "id": int, "type": "build",  "planet": String, "building": String,
##     "target": int, "enabled": bool }
##   { "id": int, "type": "launch", "mission": String, "origin": String,
##     "target": String, "fuel": String, "arrival": String, "keep": int,
##     "cargo": Dictionary, "enabled": bool }
##   { "id": int, "type": "defend", "planet": String (or DEFEND_ANY),
##     "asteroids": bool, "weapons": bool, "enabled": bool }

signal automation_changed(rules: Array)
## Emitted when the player picks how this civilisation answers contact with another.
signal doctrine_changed(doctrine: String)

## Build/launch origins (planets only); launch targets add the Sun.
## A defence rule's world, when it is not one world: every holding the species has.
const DEFEND_ANY: String = "*"
const PLANETS: Array = [
	"Earth", "Mercury", "Venus", "Mars",
	"Jupiter", "Saturn", "Uranus", "Neptune",
]
const TARGETS: Array = [
	"Mercury", "Venus", "Earth", "Mars",
	"Jupiter", "Saturn", "Uranus", "Neptune", "Sun",
]

var _rules:   Array = []
var _next_id: int   = 1
var _doctrine_opt:  OptionButton = null
var _doctrine_desc: Label = null

# ── Build-form refs ───────────────────────────────────────────────────────────
var _b_planet:   OptionButton = null
var _b_building: OptionButton = null
var _b_count:    SpinBox      = null

# ── Launch-form refs ──────────────────────────────────────────────────────────
## Body id → kind, from Game — the same table the launch panel validates against.
var _body_kinds: Dictionary = {}

var _l_mission: OptionButton = null
var _l_origin:  OptionButton = null
var _l_target:  OptionButton = null
var _l_fuel:    OptionButton = null
var _l_arrival: OptionButton = null
var _l_count:   SpinBox      = null

# ── The hold ─────────────────────────────────────────────────────────────────
## What a standing Supply Run carries.  A cargo mission with an empty manifest flies empty for
## ever, which is the quietest kind of broken rule — the same launch, the same cost, nothing
## delivered — so the manifest is part of the rule rather than something the executor guesses.
##
## Offered from what the ORIGIN actually holds, pushed by Game: a rule that names something the
## world has never dug would simply never fire.
var _l_cargo_box:  VBoxContainer = null
var _l_cargo_pick: OptionButton  = null
var _l_cargo_amt:  LineEdit      = null
var _l_cargo_list: VBoxContainer = null
var _l_cargo:      Dictionary    = {}      # compound → grams, for the rule being composed
var _stocks:       Dictionary    = {}      # origin id → { compound → grams }

## The standing orders, listed in their own column beside the forms that make them, and split
## by what they are: a build rule and a launch rule have nothing to do with each other, and a
## single list mixed them in whatever order they happened to be added.
var _build_rules: VBoxContainer = null
var _launch_rules: VBoxContainer = null
var _defend_rules: VBoxContainer = null

# ── Standing defence ─────────────────────────────────────────────────────────
## An interception is a decision with one sensible answer whenever the shot is affordable, and
## being stopped to make it every time across a million years is the opposite of automation.
var _d_planet:    OptionButton = null
var _d_asteroids: CheckBox     = null
var _d_weapons:   CheckBox     = null

# ── Lifecycle ─────────────────────────────────────────────────────────────────

## Swallow mouse-wheel events so scrolling the panel doesn't zoom the system behind it.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index in [
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		accept_event()

func _ready() -> void:
	# Wide enough for two columns.  560 was sized for one, and splitting it put the forms and
	# the rules in half that each — a launch rule's description then wrapped to three lines in
	# a column too narrow to read it in.
	custom_minimum_size = Vector2(820, 520)
	_build_ui()

# ── Public API ────────────────────────────────────────────────────────────────

## Replace the rule list from a loaded save (does not re-emit).
func load_rules(rules: Array) -> void:
	_rules = []
	for r in rules:
		_rules.append((r as Dictionary).duplicate())
		_next_id = maxi(_next_id, int((r as Dictionary).get("id", 0)) + 1)
	_rebuild_rule_list()


## A serialisable copy of the current rules.
func get_rules() -> Array:
	var out: Array = []
	for r in _rules:
		out.append((r as Dictionary).duplicate())
	return out

# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top",    8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.add_theme_constant_override("margin_left",   10)
	margin.add_theme_constant_override("margin_right",  10)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Automation"
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "Standing orders the game carries out on its own as time runs forward."
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(0.70, 0.72, 0.78)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)

	vbox.add_child(HSeparator.new())

	# ── Two columns: what you are setting up, and what is already running ───────
	# The forms are long — a launch rule alone is six fields and a manifest — and the list of
	# what is actually running used to sit underneath all of it, off the bottom of the panel
	# exactly when there was most to see. Side by side, the orders stay in view while another
	# one is composed.
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 12)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(split)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The forms carry labelled dropdowns and the rules carry a line of text apiece, so the
	# space is split in their favour rather than evenly.
	left.size_flags_stretch_ratio = 1.6
	split.add_child(left)
	split.add_child(VSeparator.new())
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(right)

	# Everything that follows builds into the left column.
	vbox = left

	# ── Autonomous von Neumann colonisation ──────────────────────────────────────
	# One global directive: seed a self-replicating colony probe and let it spread on its own.
	# Behaviour is gated on Relativistic Navigation + Self-Replicating Industry (checked by Game).
	_section_label(vbox, "Autonomous Expansion")

	vbox.add_child(HSeparator.new())
	_build_doctrine_form(vbox)
	vbox.add_child(HSeparator.new())

	_build_build_form(vbox)
	vbox.add_child(HSeparator.new())
	_build_launch_form(vbox)
	vbox.add_child(HSeparator.new())
	_build_defend_form(vbox)

	var rules_label := Label.new()
	rules_label.text = "Active Rules"
	rules_label.add_theme_font_size_override("font_size", 13)
	right.add_child(rules_label)

	_build_rules = _rules_column(right, "Building")
	right.add_child(HSeparator.new())
	_launch_rules = _rules_column(right, "Launches")
	right.add_child(HSeparator.new())
	_defend_rules = _rules_column(right, "Defence")

	_rebuild_rule_list()


## One titled, scrolling list of rules.  The two share the right column's height, so a long
## list of one kind does not push the other off the panel.
func _rules_column(parent: Control, title: String) -> VBoxContainer:
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.modulate = Color(0.70, 0.72, 0.78)
	parent.add_child(lbl)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 90)
	parent.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	return list

func _section_label(parent: Control, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.modulate = Color(0.85, 0.88, 0.95)
	parent.add_child(lbl)

## Tell the panel what kind each body is (see Game.body_kinds).
func set_body_kinds(kinds: Dictionary) -> void:
	_body_kinds = kinds
	_refresh_launch_validity()


## The id this rule editor's target list means — its entries are planet names and the Sun.
func _target_rule_id() -> String:
	var i: int = _l_target.selected if _l_target else -1
	return str(TARGETS[i]).to_lower() if i >= 0 and i < TARGETS.size() else ""


## Grey out whatever this target (or mission) makes impossible, and move a stale selection off it.
func _refresh_launch_validity() -> void:
	if _l_mission == null or _l_target == null or _l_arrival == null or _body_kinds.is_empty():
		return
	var kind: String = str(_body_kinds.get(_target_rule_id(), ""))
	for i in range(MissionData.MISSION_TYPES.size()):
		if i >= _l_mission.item_count:
			break
		var m: Dictionary = MissionData.MISSION_TYPES[i]
		var ok: bool = MissionData.allows_target(m, kind)
		_l_mission.set_item_disabled(i, not ok)
		_l_mission.set_item_tooltip(i, "" if ok else MissionData.refusal(m, kind, "orbit").capitalize())
	if _l_mission.selected >= 0 \
			and not MissionData.allows_target(MissionData.MISSION_TYPES[_l_mission.selected], kind):
		var first: int = MissionData.first_valid_index(kind)
		if first >= 0:
			_l_mission.selected = first
	var m_def: Dictionary = MissionData.MISSION_TYPES[_l_mission.selected] \
		if _l_mission.selected >= 0 else {}
	# Only a mission with a hold gets a manifest; everything else carries machinery.
	if _l_cargo_box:
		_l_cargo_box.visible = bool(m_def.get("cargo", false))
	var can_land: bool = MissionData.allows_arrival(m_def, kind, "land")
	_l_arrival.set_item_disabled(1, not can_land)
	_l_arrival.set_item_tooltip(1, "" if can_land
		else MissionData.refusal(m_def, kind, "land").capitalize())
	if not can_land and _l_arrival.selected == 1:
		_l_arrival.selected = 0


func _form_label(grid: Control, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.modulate = Color(0.75, 0.75, 0.75)
	grid.add_child(lbl)

func _count_spin() -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = 1
	sb.max_value = 999
	sb.step      = 1
	sb.value     = 1
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return sb

## Contact doctrine: the standing rule for answering another civilisation.  It sits here rather
## than on the star map because it is not an order aimed at one system — it is what this
## civilisation does every time, and the other side can read it from the choice itself.
func _build_doctrine_form(parent: Control) -> void:
	var title := Label.new()
	title.text = "Contact Doctrine"
	title.add_theme_font_size_override("font_size", 13)
	parent.add_child(title)

	_doctrine_opt = OptionButton.new()
	_doctrine_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in range(DoctrineData.DOCTRINES.size()):
		var d: Dictionary = DoctrineData.DOCTRINES[i]
		_doctrine_opt.add_item(str(d["name"]), i)
	_doctrine_opt.item_selected.connect(func(idx: int) -> void:
		var d: Dictionary = DoctrineData.DOCTRINES[idx]
		_refresh_doctrine_desc(idx)
		doctrine_changed.emit(str(d["id"])))
	parent.add_child(_doctrine_opt)

	_doctrine_desc = Label.new()
	_doctrine_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_doctrine_desc.add_theme_font_size_override("font_size", 10)
	_doctrine_desc.modulate = Color(0.72, 0.78, 0.88)
	parent.add_child(_doctrine_desc)
	_refresh_doctrine_desc(0)

## Show what the selected doctrine actually commits you to, including the parts that cost.
func _refresh_doctrine_desc(idx: int) -> void:
	if _doctrine_desc == null or idx < 0 or idx >= DoctrineData.DOCTRINES.size():
		return
	var d: Dictionary = DoctrineData.DOCTRINES[idx]
	var prov: float = float(d["provocation"])
	var salvo: int = int(d["retaliate"])
	var parts: Array = []
	parts.append("provokes ×%.2f" % prov)
	if salvo > 0:
		parts.append("answers with %d missile%s" % [salvo, "" if salvo == 1 else "s"])
	else:
		parts.append("never answers")
	if bool(d["first_strike"]):
		parts.append("fires on every civilisation on sight" if str(d.get("targets", "hostile")) == "all"
			else "fires on hostiles on sight")
	if not bool(d["forgives"]):
		parts.append("never forgives")
	_doctrine_desc.text = "%s
%s
[%s]" % [str(d["desc"]), str(d["detail"]), "  ·  ".join(parts)]

## Reflect the loaded doctrine without re-emitting.
func set_doctrine(id: String) -> void:
	if _doctrine_opt == null:
		return
	for i in range(DoctrineData.DOCTRINES.size()):
		if str((DoctrineData.DOCTRINES[i] as Dictionary)["id"]) == id:
			_doctrine_opt.select(i)
			_refresh_doctrine_desc(i)
			return

func _build_build_form(vbox: VBoxContainer) -> void:
	_section_label(vbox, "Automated Building")

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	vbox.add_child(grid)

	_form_label(grid, "World:")
	_b_planet = OptionButton.new()
	_b_planet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for p in PLANETS:
		_b_planet.add_item(p)
	grid.add_child(_b_planet)

	_form_label(grid, "Building:")
	_b_building = OptionButton.new()
	_b_building.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for b in BuildingData.all():
		_b_building.add_item(str((b as Dictionary)["name"]))
	grid.add_child(_b_building)

	_form_label(grid, "Keep at least:")
	_b_count = _count_spin()
	grid.add_child(_b_count)

	var add := Button.new()
	add.text = "+ Add build rule"
	add.custom_minimum_size = Vector2(0, 32)
	add.pressed.connect(_on_add_build)
	vbox.add_child(add)

func _build_launch_form(vbox: VBoxContainer) -> void:
	_section_label(vbox, "Automated Launches")

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	vbox.add_child(grid)

	_form_label(grid, "Mission:")
	_l_mission = OptionButton.new()
	_l_mission.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m in MissionData.MISSION_TYPES:
		_l_mission.add_item(str((m as Dictionary)["name"]))
	grid.add_child(_l_mission)

	_form_label(grid, "From:")
	_l_origin = OptionButton.new()
	_l_origin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for p in PLANETS:
		_l_origin.add_item(p)
	grid.add_child(_l_origin)

	_form_label(grid, "To:")
	_l_target = OptionButton.new()
	_l_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for p in TARGETS:
		_l_target.add_item(p)
	_l_target.selected = TARGETS.find("Mars")
	grid.add_child(_l_target)

	_form_label(grid, "Fuel:")
	_l_fuel = OptionButton.new()
	_l_fuel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for f in MissionData.FUELS:
		_l_fuel.add_item(str((f as Dictionary)["name"]))
	grid.add_child(_l_fuel)

	_form_label(grid, "Arrival:")
	_l_arrival = OptionButton.new()
	_l_arrival.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_l_arrival.add_item("Orbit")
	_l_arrival.add_item("Land")
	grid.add_child(_l_arrival)

	_form_label(grid, "Keep active:")
	_l_count = _count_spin()
	grid.add_child(_l_count)

	_build_cargo_ui(vbox)

	# A standing order fires the same launch for ever, so an impossible combination here is not
	# one dropped launch but a rule that silently never fires.  The same rules the launch panel
	# offers apply: pick a target and the missions that cannot reach it grey out, and so does an
	# arrival the body has no ground for.
	_l_mission.item_selected.connect(func(_i) -> void: _refresh_launch_validity())
	_l_target.item_selected.connect(func(_i) -> void: _refresh_launch_validity())
	_l_origin.item_selected.connect(func(_i) -> void: _refresh_cargo_choices())
	_refresh_launch_validity()

	var add := Button.new()
	add.text = "+ Add launch rule"
	add.custom_minimum_size = Vector2(0, 32)
	add.pressed.connect(_on_add_launch)
	vbox.add_child(add)

## The manifest editor, shown only for a mission that has a hold.
func _build_cargo_ui(parent: Control) -> void:
	_l_cargo_box = VBoxContainer.new()
	_l_cargo_box.add_theme_constant_override("separation", 3)
	_l_cargo_box.hide()
	parent.add_child(_l_cargo_box)

	var lbl := Label.new()
	lbl.text = "Hold:"
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.modulate = Color(0.75, 0.75, 0.75)
	_l_cargo_box.add_child(lbl)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_l_cargo_pick = OptionButton.new()
	_l_cargo_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_l_cargo_pick.fit_to_longest_item = false
	_l_cargo_pick.clip_text = true
	row.add_child(_l_cargo_pick)
	_l_cargo_amt = LineEdit.new()
	_l_cargo_amt.placeholder_text = "grams"
	_l_cargo_amt.custom_minimum_size = Vector2(96, 0)
	row.add_child(_l_cargo_amt)
	var add := Button.new()
	add.text = "Add"
	add.pressed.connect(_on_cargo_add)
	row.add_child(add)
	_l_cargo_box.add_child(row)

	_l_cargo_list = VBoxContainer.new()
	_l_cargo_list.add_theme_constant_override("separation", 2)
	_l_cargo_box.add_child(_l_cargo_list)


## What the chosen origin is holding, pushed by Game.
func set_launch_stock(stocks: Dictionary) -> void:
	_stocks = stocks
	_refresh_cargo_choices()


## Repopulate the compound list from what the selected origin actually holds — a rule naming
## something that world has never dug would never fire.
func _refresh_cargo_choices() -> void:
	if _l_cargo_pick == null:
		return
	var prev: String = _l_cargo_pick.get_item_text(_l_cargo_pick.selected) \
		if _l_cargo_pick.selected >= 0 else ""
	_l_cargo_pick.clear()
	var origin: String = str(PLANETS[_l_origin.selected]).to_lower() \
		if _l_origin and _l_origin.selected >= 0 else ""
	var held: Dictionary = _stocks.get(origin, {}) as Dictionary
	var keys: Array = held.keys()
	keys.sort()
	for k in keys:
		if float(held[k]) <= 0.0:
			continue
		_l_cargo_pick.add_item(str(k))
		if str(k) == prev:
			_l_cargo_pick.selected = _l_cargo_pick.item_count - 1


func _on_cargo_add() -> void:
	if _l_cargo_pick == null or _l_cargo_pick.selected < 0:
		return
	var key: String = _l_cargo_pick.get_item_text(_l_cargo_pick.selected)
	var amt: float = maxf(0.0, float(_l_cargo_amt.text))
	if amt <= 0.0:
		return
	_l_cargo[key] = float(_l_cargo.get(key, 0.0)) + amt
	_l_cargo_amt.text = ""
	_refresh_cargo_list()


func _refresh_cargo_list() -> void:
	if _l_cargo_list == null:
		return
	for c in _l_cargo_list.get_children():
		c.queue_free()
	for k: String in _l_cargo:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = "%s  %s" % [Units.format_si(float(_l_cargo[k]), "g"), k]
		l.add_theme_font_size_override("font_size", 11)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var x := Button.new()
		x.text = "x"
		x.pressed.connect(func() -> void:
			_l_cargo.erase(k)
			_refresh_cargo_list())
		row.add_child(x)
		_l_cargo_list.add_child(row)


## Standing orders to shoot down what is coming at a world.
func _build_defend_form(vbox: VBoxContainer) -> void:
	_section_label(vbox, "Automated Defence")

	var hint := Label.new()
	hint.text = "Fires the orbital array without stopping to ask. Needs a built array and the energy for the shot; without either, the warning still comes up."
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(0.70, 0.72, 0.78)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	vbox.add_child(grid)

	_form_label(grid, "World:")
	_d_planet = OptionButton.new()
	_d_planet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_d_planet.fit_to_longest_item = false
	_d_planet.clip_text = true
	# Projectiles are aimed at interstellar colonies too, and by the time that happens there are
	# more of them than a dropdown can hold.  One entry covers the lot.
	_d_planet.add_item("Everywhere")
	_d_planet.set_item_tooltip(0, "Every world the species holds, Sol and the colonies both.")
	for p in PLANETS:
		_d_planet.add_item(p)
	grid.add_child(_d_planet)

	_form_label(grid, "Protect from:")
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	_d_asteroids = CheckBox.new()
	_d_asteroids.text = "Asteroids"
	_d_asteroids.button_pressed = true
	_d_asteroids.tooltip_text = "A mountain-sized body on an intercept course. The array holds on it until it comes apart, and the world takes a meteor shower instead of a crater."
	box.add_child(_d_asteroids)
	_d_weapons = CheckBox.new()
	_d_weapons.text = "Weapons"
	_d_weapons.button_pressed = true
	_d_weapons.tooltip_text = "Relativistic missiles and berserker swarms, which cross at a fraction of c and can be burned down on the way in. A laser strike arrives with the light that announces it and cannot be intercepted by anything."
	box.add_child(_d_weapons)
	grid.add_child(box)

	var add := Button.new()
	add.text = "+ Add defence rule"
	add.custom_minimum_size = Vector2(0, 32)
	add.pressed.connect(_on_add_defend)
	vbox.add_child(add)


# ── Rule creation ─────────────────────────────────────────────────────────────

func _on_add_build() -> void:
	if _b_planet.selected < 0 or _b_building.selected < 0:
		return
	_rules.append({
		"id":       _next_id,
		"type":     "build",
		"planet":   str(PLANETS[_b_planet.selected]).to_lower(),
		"building": _b_building.get_item_text(_b_building.selected),
		"target":   int(_b_count.value),
		"enabled":  true,
	})
	_next_id += 1
	_commit()

func _on_add_launch() -> void:
	if _l_mission.selected < 0 or _l_origin.selected < 0 or _l_target.selected < 0 \
			or _l_fuel.selected < 0:
		return
	var fuel_def: Dictionary = MissionData.FUELS[_l_fuel.selected]
	_rules.append({
		"id":      _next_id,
		"type":    "launch",
		"mission": _l_mission.get_item_text(_l_mission.selected),
		"origin":  str(PLANETS[_l_origin.selected]).to_lower(),
		"target":  str(TARGETS[_l_target.selected]).to_lower(),
		"fuel":    str(fuel_def["id"]),
		"arrival": "land" if _l_arrival.selected == 1 else "orbit",
		"keep":    int(_l_count.value),
		"cargo":   _l_cargo.duplicate(),
		"enabled": true,
	})
	_next_id += 1
	_l_cargo = {}
	_refresh_cargo_list()
	_commit()

func _on_add_defend() -> void:
	if _d_planet.selected < 0:
		return
	# A rule that protects against nothing would sit in the list looking like cover.
	if not _d_asteroids.button_pressed and not _d_weapons.button_pressed:
		return
	_rules.append({
		"id":        _next_id,
		"type":      "defend",
		"planet":    DEFEND_ANY if _d_planet.selected == 0 \
			else str(PLANETS[_d_planet.selected - 1]).to_lower(),
		"asteroids": _d_asteroids.button_pressed,
		"weapons":   _d_weapons.button_pressed,
		"enabled":   true,
	})
	_next_id += 1
	_commit()


func _remove_rule(rule_id: int) -> void:
	for i in range(_rules.size()):
		if int((_rules[i] as Dictionary).get("id", -1)) == rule_id:
			_rules.remove_at(i)
			break
	_commit()

func _set_enabled(rule_id: int, on: bool) -> void:
	for r in _rules:
		if int((r as Dictionary).get("id", -1)) == rule_id:
			(r as Dictionary)["enabled"] = on
			break
	_commit()

func _commit() -> void:
	_rebuild_rule_list()
	automation_changed.emit(get_rules())

# ── Rule list rendering ───────────────────────────────────────────────────────

func _rebuild_rule_list() -> void:
	if _build_rules == null or _launch_rules == null or _defend_rules == null:
		return
	for c in _build_rules.get_children():
		c.queue_free()
	for c in _launch_rules.get_children():
		c.queue_free()
	for c in _defend_rules.get_children():
		c.queue_free()
	var n_build: int = 0
	var n_launch: int = 0
	var n_defend: int = 0
	for r in _rules:
		var rule: Dictionary = r
		match str(rule.get("type", "")):
			"launch":
				_launch_rules.add_child(_make_rule_row(rule))
				n_launch += 1
			"defend":
				_defend_rules.add_child(_make_rule_row(rule))
				n_defend += 1
			_:
				_build_rules.add_child(_make_rule_row(rule))
				n_build += 1
	# Each list says so for itself: "no rules yet" under Building while six launches are running
	# is the useful message, and a single shared one could not give it.
	if n_build == 0:
		_build_rules.add_child(_empty_note("Nothing is being kept built."))
	if n_launch == 0:
		_launch_rules.add_child(_empty_note("Nothing is being kept in flight."))
	if n_defend == 0:
		_defend_rules.add_child(_empty_note("Nothing is being defended."))


func _empty_note(text: String) -> Label:
	var empty := Label.new()
	empty.text = text
	empty.add_theme_font_size_override("font_size", 11)
	empty.modulate = Color(0.6, 0.6, 0.6)
	return empty

func _make_rule_row(rule: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var rid: int = int(rule.get("id", 0))

	var on := CheckBox.new()
	on.button_pressed = bool(rule.get("enabled", true))
	on.toggled.connect(func(p): _set_enabled(rid, p))
	row.add_child(on)

	var info := Label.new()
	info.text = _describe(rule)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_font_size_override("font_size", 11)
	# Wrapped, because a Label's minimum width is its whole line: in a column half the panel
	# wide an unwrapped rule description does not merely overflow, it pushes the column open
	# from the inside and takes the checkbox and the remove button off the edge with it.
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(60, 0)
	if not bool(rule.get("enabled", true)):
		info.modulate = Color(0.55, 0.55, 0.55)
	row.add_child(info)

	var rm := Button.new()
	rm.text = "✕"
	rm.add_theme_font_size_override("font_size", 11)
	rm.pressed.connect(func(): _remove_rule(rid))
	row.add_child(rm)

	return row

func _describe(rule: Dictionary) -> String:
	if str(rule.get("type", "")) == "defend":
		var against: Array = []
		if bool(rule.get("asteroids", false)):
			against.append("asteroids")
		if bool(rule.get("weapons", false)):
			against.append("weapons")
		var where: String = str(rule.get("planet", "?"))
		return "Defend  ·  %s from %s" % [
			"Everywhere" if where == DEFEND_ANY else where.capitalize(),
			" and ".join(against) if not against.is_empty() else "nothing"]
	if str(rule.get("type", "")) == "build":
		return "Build  ·  keep ≥ %d × %s on %s" % [
			int(rule.get("target", 1)),
			str(rule.get("building", "?")),
			str(rule.get("planet", "?")).capitalize()]
	# launch
	var fuel_name: String = str(rule.get("fuel", ""))
	for f in MissionData.FUELS:
		if str((f as Dictionary)["id"]) == fuel_name:
			fuel_name = str((f as Dictionary)["name"])
			break
	var line: String = "Launch  ·  keep %d active  %s  %s→%s  [%s, %s]" % [
		int(rule.get("keep", 1)),
		str(rule.get("mission", "?")),
		str(rule.get("origin", "?")).capitalize(),
		str(rule.get("target", "?")).capitalize(),
		fuel_name,
		str(rule.get("arrival", "orbit"))]
	# A rule saved before these checks existed (or edited by hand) can hold a combination the
	# launch refuses.  It would simply never fire, which looks like nothing at all — so say so.
	var why: String = _rule_refusal(rule)
	if why != "":
		line += "   ⚠ never fires — %s" % why
	return line


## Why a standing launch order can never fire, or "" when it is fine.
func _rule_refusal(rule: Dictionary) -> String:
	if _body_kinds.is_empty():
		return ""
	var m_def: Dictionary = {}
	for m in MissionData.MISSION_TYPES:
		if str((m as Dictionary)["name"]) == str(rule.get("mission", "")):
			m_def = m
			break
	if m_def.is_empty():
		return "no such mission"
	return MissionData.refusal(m_def, str(_body_kinds.get(str(rule.get("target", "")), "")),
		str(rule.get("arrival", "orbit")))
