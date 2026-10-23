extends PanelContainer

signal launch_requested(params: Dictionary)
## The player has chosen a different founding population for colony ships.  Game is the
## authority (see set_colony_stock there) and pushes the accepted order back.
signal colony_stock_changed(founders_id: String, traits: Array)

# Valid launch *origins* — you can only depart from a planet.
## Launch endpoints.  These START as the planets and are REPLACED by Game via set_bodies()
## with the full list — planets plus every buildable moon — because a moon's display name and
## its body id are different strings ("Luna" vs "earth_moon_0"), and every lookup here needs
## the id.  The two arrays stay index-aligned with the dropdowns.
var PLANETS: Array = ["Mercury", "Venus", "Earth", "Mars",
	"Jupiter", "Saturn", "Uranus", "Neptune"]
var _origin_ids: Array = ["mercury", "venus", "earth", "mars",
	"jupiter", "saturn", "uranus", "neptune"]

# Valid launch *targets* — the planets plus the Sun.  The Sun accepts orbit
# missions only (you cannot land on or colonise it).
var TARGETS: Array = ["Mercury", "Venus", "Earth", "Mars",
	"Jupiter", "Saturn", "Uranus", "Neptune", "Sun"]
var _target_ids: Array = ["mercury", "venus", "earth", "mars",
	"jupiter", "saturn", "uranus", "neptune", "sun"]

## Body id for a dropdown index — never derive one by lowercasing a display name.
func _origin_id(i: int) -> String:
	return str(_origin_ids[i]) if i >= 0 and i < _origin_ids.size() else ""

func _target_id(i: int) -> String:
	return str(_target_ids[i]) if i >= 0 and i < _target_ids.size() else ""

## Replace the endpoint lists with the bodies Game says are reachable.  Each entry is
## [display name, body id]; the current selections are preserved by id where possible.
func set_bodies(origins: Array, targets: Array) -> void:
	var keep_o: String = _origin_id(origin_option.selected) if origin_option else ""
	var keep_t: String = _target_id(planet_option.selected) if planet_option else ""
	PLANETS = []
	_origin_ids = []
	for e: Array in origins:
		PLANETS.append(str(e[0]))
		_origin_ids.append(str(e[1]))
	TARGETS = []
	_target_ids = []
	for e: Array in targets:
		TARGETS.append(str(e[0]))
		_target_ids.append(str(e[1]))
	_populate_origin()
	_populate_planets()
	if keep_o != "" and _origin_ids.has(keep_o):
		origin_option.selected = _origin_ids.find(keep_o)
	if keep_t != "" and _target_ids.has(keep_t):
		planet_option.selected = _target_ids.find(keep_t)
	_refresh_validity()
	_update_cost()

## Tell the panel what kind each body is (see Game.body_kinds).
func set_body_kinds(kinds: Dictionary) -> void:
	_body_kinds = kinds
	_refresh_validity()


## The kind of the currently selected target, or "" when nothing sensible is selected.
func _target_kind() -> String:
	return str(_body_kinds.get(_target_id(planet_option.selected), ""))


## Grey out every choice the launch would refuse, and move any stale selection off one.
##
## Three lists have to agree: a mission that only flies to the Sun, a target with no ground, an
## arrival that lands on it.  Rather than let the player build an impossible combination and then
## silently drop it, the mission list is filtered by the chosen target, the arrival list by both,
## and the target picker by the chosen mission.
func _refresh_validity() -> void:
	if _body_kinds.is_empty() or mission_option == null:
		return
	var kind: String = _target_kind()

	# Missions that cannot fly to this target.
	for i in range(MissionData.MISSION_TYPES.size()):
		if i >= mission_option.item_count:
			break
		var ok: bool = MissionData.allows_target(MissionData.MISSION_TYPES[i], kind)
		mission_option.set_item_disabled(i, not ok)
		var why: String = MissionData.refusal(MissionData.MISSION_TYPES[i], kind, "orbit")
		mission_option.set_item_tooltip(i, "" if ok else why.capitalize())
	# A selection that has just become impossible moves to the first that is not.
	if mission_option.selected >= 0 \
			and not MissionData.allows_target(MissionData.MISSION_TYPES[mission_option.selected], kind):
		var first: int = MissionData.first_valid_index(kind)
		if first >= 0:
			mission_option.selected = first
			_refresh_cargo()

	# Targets this mission cannot reach: greyed in the picker, so the hierarchy still shows
	# everything and says which entries are closed rather than hiding them.
	if _target_picker:
		var valid: Array = []
		var m_def: Dictionary = _selected_mission_def()
		for id: String in _target_ids:
			if MissionData.allows_target(m_def, str(_body_kinds.get(id, ""))):
				valid.append(id)
		_target_picker.set_valid_ids(valid)

	_update_arrival_options()


## The mission currently selected, or {} when none is.
func _selected_mission_def() -> Dictionary:
	var i: int = mission_option.selected if mission_option else -1
	return MissionData.MISSION_TYPES[i] if i >= 0 and i < MissionData.MISSION_TYPES.size() else {}


## Hierarchical pickers shown in place of the two option buttons: the Sun and the planets at the
## top level, moons folded under their planet.  The option buttons stay, hidden, as the selection
## every other function here reads (see launch_body_picker.gd).
## Body id → kind ("star", "rocky", "gas_giant", "belt"), from Game.  Every validity question
## here goes through MissionData with one of these, so the panel offers exactly what the launch
## will accept.
var _body_kinds: Dictionary = {}

var _origin_picker: LaunchBodyPicker = null
var _target_picker: LaunchBodyPicker = null

@onready var origin_option:   OptionButton  = $MarginContainer/VBoxContainer/FormGrid/OriginOption
@onready var planet_option:   OptionButton  = $MarginContainer/VBoxContainer/FormGrid/PlanetOption
@onready var mission_option:  OptionButton  = $MarginContainer/VBoxContainer/FormGrid/MissionOption
@onready var duration_value:  Label         = $MarginContainer/VBoxContainer/FormGrid/DurationRow/DurationValue
@onready var cost_value:      Label         = $MarginContainer/VBoxContainer/FormGrid/CostValue
@onready var arrival_option:  OptionButton  = $MarginContainer/VBoxContainer/FormGrid/ArrivalOption
@onready var launch_button:   Button        = $MarginContainer/VBoxContainer/LaunchButton
@onready var launch_list:     VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/LaunchList

# ── Fuel & acceleration ────────────────────────────────────────────────────────
# The chosen FUEL fixes the transfer acceleration: faster fuels (fusion, antimatter)
# are gated by propulsion research and cost far more to manufacture, so speed is paid
# in fuel.  All trajectory cost/time math lives in LaunchPlanner (shared with the
# AutomationPanel executor); this panel just feeds it the player's selections.

## Fuel selector (replaces the old acceleration slider).
var _fuel_option: OptionButton = null
var _fuel_map:    Array        = []   # fuel-dropdown index → MissionData.FUELS index
## Per-origin stock of rockets + fuels, pushed by Game.gd for the cost readout / gate:
## { planet_lower → { "Rocket": n, "Propellant": n, ... } }.
var _launch_stock: Dictionary = {}

# ── Calendar date picker (replaces the old StartOption dropdown) ───────────────
var _calendar: CalendarPicker = null
## Current game date in 1-indexed form — updated via set_game_date().
var _cur_year:  int = 1945
var _cur_month: int = 1
var _cur_day:   int = 1

## Per-origin launch modifiers from surface infrastructure (e.g. Space Elevator),
## pushed by Game.gd: { planet_name_lower → { "cost": float, "duration": float } }.
var _launch_mods: Dictionary = {}

## Live orbital angle (radians) of each planet, pushed by Game.gd:
## { planet_name_lower → orbit_angle }.  Drives the launch-window energy penalty.
var _planet_angles: Dictionary = {}

## Dyson-swarm state pushed by Game.gd, so a Solar Deployment can show its satellite
## payload and refuse to fly with nothing to carry (or a full swarm).
var _sat_stock: Dictionary = {}   # { planet_lower → satellites in stock }
var _sat_deployed: int = 0
var _sat_max: int = 0

## Swallow mouse-wheel events so scrolling over this panel doesn't zoom the
## solar-system camera behind it.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index in [
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		accept_event()

func _ready() -> void:
	# Hide the legacy "Start:" label and dropdown that were in the scene.
	var start_lbl: Node = get_node_or_null(
		"MarginContainer/VBoxContainer/FormGrid/StartLabel")
	var start_opt: Node = get_node_or_null(
		"MarginContainer/VBoxContainer/FormGrid/StartOption")
	if start_lbl: start_lbl.visible = false
	if start_opt: start_opt.visible = false

	# Inject the CalendarPicker between the form grid and the Launch button.
	var vbox: VBoxContainer = $MarginContainer/VBoxContainer
	_build_cargo_ui(vbox)   # manifest editor, shown only for cargo missions
	_build_stock_ui(vbox)   # founding population, shown only for a colony ship
	var date_section := VBoxContainer.new()
	date_section.add_theme_constant_override("separation", 2)

	var date_lbl := Label.new()
	date_lbl.text = "Start date:"
	date_lbl.add_theme_font_size_override("font_size", 11)
	date_lbl.modulate = Color(0.75, 0.75, 0.75)
	date_section.add_child(date_lbl)

	_calendar = CalendarPicker.new()
	# A later start date shifts planet positions → different distance, time and cost.
	# Colour every day by how well the transfer is phased on that date.
	_calendar.set_quality_provider(func(off: float) -> float:
		var o := _origin_name()
		var t := _target_name()
		if o == "" or t == "" or _is_local_orbit():
			return 1.0
		return LaunchPlanner.window_quality(o, t, _planet_angles, off))
	_calendar.date_selected.connect(func(_y: int, _m: int, _d: int) -> void:
		_update_duration(); _update_cost())
	date_section.add_child(_calendar)

	# Insert before the LaunchButton (second-to-last child of vbox).
	vbox.add_child(date_section)
	var btn_idx := launch_button.get_index()
	vbox.move_child(date_section, btn_idx)

	# Fuel selector, injected just above the start-date section.  The chosen fuel sets
	# the transfer acceleration and is what the launch consumes.
	var fuel_section := VBoxContainer.new()
	fuel_section.add_theme_constant_override("separation", 2)
	var fuel_lbl := Label.new()
	fuel_lbl.text = "Fuel:"
	fuel_lbl.add_theme_font_size_override("font_size", 11)
	fuel_lbl.modulate = Color(0.75, 0.75, 0.75)
	fuel_section.add_child(fuel_lbl)
	_fuel_option = OptionButton.new()
	_fuel_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fuel_option.item_selected.connect(func(_i): _update_duration(); _update_cost())
	fuel_section.add_child(_fuel_option)
	vbox.add_child(fuel_section)
	vbox.move_child(fuel_section, date_section.get_index())
	_populate_fuels()

	# The two mission-specific editors sit directly under the form grid, which puts each against
	# the Cost line it is the explanation for: a colony ship's vehicle count is mostly the people
	# in it, and a supply run's is mostly the hold.  Both are built earlier — they have to exist
	# before the refreshes that show and hide them — and moved here, the same way the two
	# sections above are.
	#
	# add_child alone appends past the launch list, which is where both of them first landed and
	# where nothing would ever have seen them — the cargo editor had been sitting below "Active
	# Launches" since it was written.  Only one is ever visible at a time (no mission both
	# carries people and takes a manifest), so their order between themselves decides nothing.
	if _stock_box:
		vbox.move_child(_stock_box, fuel_section.get_index())
	if _cargo_box:
		vbox.move_child(_cargo_box, fuel_section.get_index())

	# Swap each body option button for a hierarchical picker in the same grid cell.
	_origin_picker = _replace_with_picker(origin_option)
	_target_picker = _replace_with_picker(planet_option)

	_populate_origin()
	_populate_planets()
	_populate_missions()
	_populate_arrival()
	origin_option.item_selected.connect(func(_i):
		_manifest.clear()          # a hold loaded at one world cannot fly from another
		_update_duration(); _refresh_cargo(); _update_cost())
	planet_option.item_selected.connect(func(_i):
		_refresh_validity(); _update_duration(); _update_cost())
	mission_option.item_selected.connect(func(_i):
		_refresh_cargo(); _refresh_stock_ui(); _refresh_validity(); _update_cost())
	arrival_option.item_selected.connect(func(_i): _update_duration(); _update_cost())
	launch_button.pressed.connect(_on_launch_pressed)
	_update_arrival_options()
	_refresh_stock_ui()
	_update_duration()
	_update_cost()

## Called by Game.gd whenever the in-game date changes.
## y/m/d are 1-indexed (January = 1, first day = 1).
func set_game_date(y: int, m: int, d: int) -> void:
	_cur_year  = y
	_cur_month = m
	_cur_day   = d
	if _calendar:
		_calendar.set_min_date(y, m, d)

## Called by Game.gd when the panel opens so the origin AND target both default
## to the planet the player is currently viewing, ready for a local orbit launch.
func set_current_planet(planet_name: String) -> void:
	if planet_name == "":
		return
	# By body id: a moon's display name ("Luna") is not its id capitalised ("Earth Moon 0").
	var o: int = _origin_ids.find(planet_name)
	var t: int = _target_ids.find(planet_name)
	if o < 0 or t < 0:
		return
	origin_option.selected  = o
	planet_option.selected  = t   # target = same body → local orbit
	arrival_option.selected = 0   # "Orbit" (not Land)
	_update_duration()
	_update_cost()

## Push the Dyson-swarm state (per-planet satellite stock + deployed/cap) so a Solar
## Deployment mission can size and gate its payload.
func set_swarm_state(stock: Dictionary, deployed: int, max_slots: int) -> void:
	_sat_stock    = stock
	_sat_deployed = deployed
	_sat_max      = max_slots
	_update_cost()

## Satellites stockpiled at the currently-selected origin.
## The building a mission flies out prefabricated, or "" for every other mission.
func _mission_structure(mission_idx: int) -> String:
	if mission_idx < 0 or mission_idx >= MissionData.MISSION_TYPES.size():
		return ""
	return str(MissionData.MISSION_TYPES[mission_idx].get("structure", ""))


## What is missing at the origin to build this mission's structure: resource → shortfall.
## Empty when the origin can cover the whole bill.
func _structure_shortfall(mission_idx: int) -> Dictionary:
	var sname: String = _mission_structure(mission_idx)
	var out: Dictionary = {}
	if sname == "":
		return out
	var def: Dictionary = BuildingData.find(sname)
	for res: String in (def.get("cost", {}) as Dictionary):
		var need: float = float(def["cost"][res])
		if float(_origin_stock(res)) < need:
			out[res] = need - float(_origin_stock(res))
	return out


func _origin_sat_stock() -> int:
	var o := origin_option.selected
	if o < 0 or o >= PLANETS.size():
		return 0
	# _sat_stock is in grams; a deployable unit costs MissionData.PAYLOAD_MASS_PER_UNIT of them.
	return int(float(_sat_stock.get(_origin_id(o), 0)) / MissionData.PAYLOAD_MASS_PER_UNIT)

## Number of satellites the selected Solar Deployment would actually carry.
func _payload_batch(mission_idx: int) -> int:
	var mdef: Dictionary = MissionData.MISSION_TYPES[mission_idx]
	var per:  int = int(mdef.get("payload_per_launch", 0))
	var room: int = maxi(0, _sat_max - _sat_deployed)
	return mini(per, mini(_origin_sat_stock(), room))

func _selected_target_is_sun() -> bool:
	var p := planet_option.selected
	return p >= 0 and p < TARGETS.size() and TARGETS[p] == "Sun"

## Push the per-origin launch modifiers (from Game.gd) and refresh the readouts.
func set_launch_mods(mods: Dictionary) -> void:
	_launch_mods = mods
	_update_duration()
	_update_cost()

## The standing order for what a colony ship carries, pushed by Game: how many founders go,
## multiplied into the vehicle count, and a line of plain text saying what the group is.
##
## Only a Colony Ship pays it — a probe or a cargo run carries nobody — so it is folded into the
## cost multiplier in _mission_rockets rather than into _launch_mods, which is per ORIGIN.
var _colony_mass_mult: float = 1.0
var _colony_stock_text: String = ""

## Game owns the order; this panel only asks for it to change.  Pushing the result back is what
## moves the dropdowns, so the panel never shows a selection the simulation has not accepted —
## and _stock_quiet stops that push from being mistaken for the player touching the control.
var _stock_quiet: bool = false

func set_colony_stock(founders_id: String, traits: Array, available: Array,
		mass_mult: float, text: String) -> void:
	_colony_mass_mult = maxf(mass_mult, 0.01)
	_colony_stock_text = text
	_stock_quiet = true
	_select_by_id(_founders_option, _founders_ids, founders_id)
	_set_traits(traits, available)
	_stock_quiet = false
	if _stock_effects:
		_stock_effects.text = text
	_update_cost()


## Point an option button at the entry whose id matches, leaving it alone if none does.
func _select_by_id(opt: OptionButton, ids: Array, id: String) -> void:
	if opt == null:
		return
	for i in range(ids.size()):
		if str(ids[i]) == id:
			opt.selected = i
			return


## Whether the mission at `mission_idx` carries a founding population.
func _is_colony_mission(mission_idx: int) -> bool:
	if mission_idx < 0 or mission_idx >= MissionData.MISSION_TYPES.size():
		return false
	return str(MissionData.MISSION_TYPES[mission_idx].get("name", "")) == "Colony Ship"

## Cost & duration multipliers for the currently-selected origin planet.
func _origin_mods() -> Dictionary:
	var o_idx := origin_option.selected
	if o_idx < 0:
		return {"cost": 1.0, "duration": 1.0}
	return _launch_mods.get(_origin_id(o_idx), {"cost": 1.0, "duration": 1.0})

## ── Founding population (Colony Ship) ─────────────────────────────────────────
## Who is aboard, and what that costs. Shown only for a Colony Ship — every other mission
## carries machinery, and a founder group it does not have cannot be chosen for it.
##
## The choice is a STANDING ORDER, not a property of this launch: by the late game the von
## Neumann swarm founds tens of thousands of colonies and nobody curates those, so the same
## order governs what a probe carries. The label says so, because a control that looks per-
## launch and is not would be a trap.
var _stock_box:        VBoxContainer = null
var _founders_option:  OptionButton  = null
var _traits_button:    MenuButton    = null
var _stock_effects:    Label         = null
var _founders_ids:     Array         = []
var _trait_ids:        Array         = []
## Ticked in the menu — the order this panel is asking for, which is only what Game accepted.
var _traits_on:        Dictionary    = {}

func _build_stock_ui(parent: Control) -> void:
	_stock_box = VBoxContainer.new()
	_stock_box.add_theme_constant_override("separation", 2)
	parent.add_child(_stock_box)

	var title := Label.new()
	title.text = "Founding population (von Neumann probes carry it too):"
	title.add_theme_font_size_override("font_size", 11)
	title.modulate = Color(0.75, 0.75, 0.75)
	# A Label's minimum width is its whole line, so an unwrapped one longer than the column does
	# not merely overflow — it pushes the column open from the inside and carries every other
	# row with it.  This one fits the 400px panel today; wrapping is what stops a narrower
	# window, or a longer sentence, from being a layout bug somewhere else entirely.
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.tooltip_text = "Settlers are drawn from the origin world, so what they ARE is decided there. This order says how many go and which sequences are spliced into them before they leave — and a small group carries less of its parent's variation, so it expresses an edit less fully whatever is written into it."
	_stock_box.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	# Two dropdowns sharing one row in a 400px column.  fit_to_longest_item is on by default and
	# sizes an OptionButton to its widest ENTRY whether that entry is showing or not, so a pair
	# of them reserves the width of the longest label in each list; clip_text is what lets the
	# one that is showing give way once it has.  Both off, the row asks for 32px instead of 93
	# and the column decides the width rather than its contents.
	_founders_option = OptionButton.new()
	_founders_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_founders_option.fit_to_longest_item = false
	_founders_option.clip_text = true
	for f: Dictionary in StockData.FOUNDERS:
		_founders_option.add_item(str(f["label"]))
		_founders_option.set_item_tooltip(_founders_ids.size(), str(f.get("blurb", "")))
		_founders_ids.append(str(f["id"]))
	_founders_option.item_selected.connect(func(_i): _emit_stock())
	row.add_child(_founders_option)

	# A MENU of checkboxes and not a dropdown, because a stock now holds a SET of traits and a
	# dropdown can only say one thing.  It keeps the one-row layout a 400px column has room for:
	# the button shows the count, the sequences themselves are behind it.
	_traits_button = MenuButton.new()
	_traits_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_traits_button.flat = false
	_traits_button.clip_text = true
	_traits_button.text = "No traits"
	var menu: PopupMenu = _traits_button.get_popup()
	menu.hide_on_checkable_item_selection = false
	for t: Dictionary in StockData.TRAITS:
		var i: int = _trait_ids.size()
		menu.add_check_item(str(t["label"]), i)
		menu.set_item_tooltip(i, str(t.get("blurb", "")))
		_trait_ids.append(str(t["id"]))
	menu.id_pressed.connect(_on_trait_toggled)
	row.add_child(_traits_button)
	_stock_box.add_child(row)

	# What the ship would actually carry, which is not the order: the origin world's own
	# population decides how much of it is realised.  Pushed back by Game.
	_stock_effects = Label.new()
	_stock_effects.add_theme_font_size_override("font_size", 10)
	_stock_effects.modulate = Color(0.68, 0.72, 0.78)
	_stock_effects.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stock_box.add_child(_stock_effects)


## A trait was ticked or unticked.  The menu is left as the player set it only for as long as
## it takes Game to answer — set_colony_stock pushes the accepted order straight back over it,
## so an order that is refused (a sequence nobody holds, a fourth trait) simply snaps back.
func _on_trait_toggled(id: int) -> void:
	if id < 0 or id >= _trait_ids.size():
		return
	var tid: String = str(_trait_ids[id])
	if _traits_on.has(tid):
		_traits_on.erase(tid)
	else:
		_traits_on[tid] = true
	_emit_stock()


## Show the order Game accepted: which boxes are ticked, which are available to tick at all,
## and what the button says.
func _set_traits(traits: Array, available: Array) -> void:
	if _traits_button == null:
		return
	_traits_on = {}
	for v in traits:
		_traits_on[str(v)] = true
	var held: Dictionary = {}
	for v in available:
		held[str(v)] = true
	var menu: PopupMenu = _traits_button.get_popup()
	var on: Array = []
	for i in range(_trait_ids.size()):
		var tid: String = str(_trait_ids[i])
		var ticked: bool = _traits_on.has(tid)
		menu.set_item_checked(i, ticked)
		# A sequence nobody holds cannot be ordered, and greying it is the honest way to say so
		# — a tick that silently snapped back would read as a bug.  One already ticked stays
		# live so it can be taken off again.
		menu.set_item_disabled(i, not ticked and not held.has(tid))
		if ticked:
			on.append(StockData.trait_label(tid))
	# One name fits the column; three do not, and clip_text would cut the third off mid-word
	# with no way to see it.  Past one the button counts them and the tooltip lists them.
	if on.is_empty():
		_traits_button.text = "No traits"
	elif on.size() == 1:
		_traits_button.text = str(on[0])
	else:
		_traits_button.text = "%d traits" % on.size()
	_traits_button.tooltip_text = "%sSequences spliced into the founders before they leave. At most %d — a genome holds no more." % [
		"" if on.is_empty() else "%s.\n" % ", ".join(on), StockData.MAX_TRAITS]


## Ask Game for the order the controls are showing.  Silent while Game is pushing a result
## back into them, which would otherwise echo straight out again.
func _emit_stock() -> void:
	if _stock_quiet or _founders_option == null or _traits_button == null:
		return
	var f: int = _founders_option.selected
	if f < 0 or f >= _founders_ids.size():
		return
	# Emitted in TRAITS order rather than tick order, so the same set is always the same list.
	var want: Array = []
	for tid: String in _trait_ids:
		if _traits_on.has(tid):
			want.append(tid)
	colony_stock_changed.emit(str(_founders_ids[f]), want)


## Show the selector only for the mission that carries people.
func _refresh_stock_ui() -> void:
	if _stock_box == null:
		return
	_stock_box.visible = _is_colony_mission(mission_option.selected)


## ── Cargo manifest (Supply Run) ───────────────────────────────────────────────
## What is in the hold: compound → grams.  Only a mission flagged "cargo" in MissionData shows
## the editor, and the hold is charged and delivered by Game — this is purely the picker.
var _manifest: Dictionary = {}
var _cargo_box:   VBoxContainer = null
var _cargo_pick:  OptionButton  = null
var _cargo_amt:   LineEdit      = null
var _cargo_list:  VBoxContainer = null
var _cargo_total: Label         = null

## True when the selected mission carries freight.
func _mission_has_cargo() -> bool:
	var i := mission_option.selected
	if i < 0 or i >= MissionData.MISSION_TYPES.size():
		return false
	return bool((MissionData.MISSION_TYPES[i] as Dictionary).get("cargo", false))

## Build the manifest editor once, appended under the form.
func _build_cargo_ui(parent: Control) -> void:
	_cargo_box = VBoxContainer.new()
	_cargo_box.add_theme_constant_override("separation", 4)
	parent.add_child(_cargo_box)

	var title := Label.new()
	title.text = "Cargo manifest"
	title.add_theme_font_size_override("font_size", 12)
	_cargo_box.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_cargo_pick = OptionButton.new()
	_cargo_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Same pair as the founding-population dropdowns, and with more reason: the entries here are
	# whatever the origin world happens to be holding, so the widest of them is not something
	# this panel gets to know in advance.  Sizing itself to the longest compound name is how a
	# row in a fixed-width column ends up deciding how wide the column is.
	_cargo_pick.fit_to_longest_item = false
	_cargo_pick.clip_text = true
	row.add_child(_cargo_pick)
	_cargo_amt = LineEdit.new()
	_cargo_amt.placeholder_text = "grams"
	_cargo_amt.custom_minimum_size = Vector2(110, 0)
	row.add_child(_cargo_amt)
	var add := Button.new()
	add.text = "Add"
	add.pressed.connect(_on_cargo_add)
	row.add_child(add)
	_cargo_box.add_child(row)

	_cargo_list = VBoxContainer.new()
	_cargo_list.add_theme_constant_override("separation", 2)
	_cargo_box.add_child(_cargo_list)

	_cargo_total = Label.new()
	_cargo_total.add_theme_font_size_override("font_size", 10)
	_cargo_total.modulate = Color(0.70, 0.80, 0.95)
	_cargo_box.add_child(_cargo_total)
	_refresh_cargo()

## Repopulate the compound dropdown from what the ORIGIN actually holds — you cannot ship what
## is not there, and offering the whole periodic table would bury the few things that are.
func _refresh_cargo_choices() -> void:
	if _cargo_pick == null:
		return
	var held: Dictionary = _launch_stock.get(_origin_id(origin_option.selected), {})
	var keep: String = _cargo_pick.get_item_text(_cargo_pick.selected) if _cargo_pick.selected >= 0 else ""
	_cargo_pick.clear()
	var names: Array = held.keys()
	names.sort()
	for k: String in names:
		if float(held[k]) > 0.0:
			_cargo_pick.add_item(k)
	for i in range(_cargo_pick.item_count):
		if _cargo_pick.get_item_text(i) == keep:
			_cargo_pick.selected = i
			break

## Parse a mass typed into the manifest field.  Returns -1 on anything unparseable.
##
## The unit here is GRAMS, so a trailing lowercase "g" is the unit and is simply dropped, while
## an uppercase "G" is the SI prefix giga — "500g" is five hundred grams and "4G" is four
## billion.  ProductionPanel's own parser reads both as giga, which is right for a field
## denominated in product per day and wrong for one denominated in grams, so this is separate
## rather than shared.
static func _parse_mass(text: String) -> float:
	var t: String = text.strip_edges().replace(",", "").replace(" ", "")
	if t == "":
		return -1.0
	if t.length() > 1 and t.ends_with("g"):
		t = t.substr(0, t.length() - 1)     # the unit, not a prefix
	var mult: float = 1.0
	if t.length() > 1:
		match t.substr(t.length() - 1, 1):
			"k": mult = 1.0e3
			"M": mult = 1.0e6
			"G": mult = 1.0e9
			"T": mult = 1.0e12
			"P": mult = 1.0e15
			"E": mult = 1.0e18
		if mult != 1.0:
			t = t.substr(0, t.length() - 1)
	if not t.is_valid_float():
		return -1.0
	return t.to_float() * mult

func _on_cargo_add() -> void:
	if _cargo_pick == null or _cargo_pick.selected < 0:
		return
	var res: String = _cargo_pick.get_item_text(_cargo_pick.selected)
	var amt: float = _parse_mass(_cargo_amt.text)
	if amt <= 0.0:
		return
	# Never manifest more than the origin is holding.
	var held: float = float((_launch_stock.get(_origin_id(origin_option.selected), {}) as Dictionary).get(res, 0.0))
	amt = minf(amt, held)
	if amt <= 0.0:
		return
	_manifest[res] = float(_manifest.get(res, 0.0)) + amt
	_cargo_amt.text = ""
	_refresh_cargo()
	_update_cost()

func _on_cargo_remove(res: String) -> void:
	_manifest.erase(res)
	_refresh_cargo()
	_update_cost()

## Redraw the manifest rows and the running total.
func _refresh_cargo() -> void:
	if _cargo_box == null:
		return
	var has_cargo: bool = _mission_has_cargo()
	_cargo_box.visible = has_cargo
	if not has_cargo:
		return
	_refresh_cargo_choices()
	for c in _cargo_list.get_children():
		c.queue_free()
	var total: float = 0.0
	for res: String in _manifest:
		total += float(_manifest[res])
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 6)
		var l := Label.new()
		l.text = "%s  %s" % [Units.format_si(float(_manifest[res]), "g"), res]
		l.add_theme_font_size_override("font_size", 11)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(l)
		var x := Button.new()
		x.text = "✕"
		x.flat = true
		x.custom_minimum_size = Vector2(24, 0)
		x.pressed.connect(_on_cargo_remove.bind(res))
		r.add_child(x)
		_cargo_list.add_child(r)
	# The hold costs rockets in proportion to its mass, so say how many before it is ordered.
	var extra: int = int(ceil(total / MissionData.CARGO_PER_ROCKET_G))
	_cargo_total.text = "Hold %s  ·  +%d vehicle%s to lift it" % [
		Units.format_si(total, "g"), extra, "" if extra == 1 else "s"]

func _populate_origin() -> void:
	origin_option.clear()
	for p in PLANETS:
		origin_option.add_item(p)
	# Default Earth, by id rather than by position; overridden by set_current_planet().
	origin_option.selected = maxi(0, _origin_ids.find("earth"))
	if _origin_picker:
		_origin_picker.set_entries(PLANETS, _origin_ids)

func _populate_planets() -> void:
	planet_option.clear()
	for p in TARGETS:
		planet_option.add_item(p)
	if _target_picker:
		_target_picker.set_entries(TARGETS, _target_ids)

## Put a hierarchical picker where `opt` sits in the form grid and hide `opt` (a hidden grid child
## takes no cell).  The option keeps holding the selection; the picker drives it.
func _replace_with_picker(opt: OptionButton) -> LaunchBodyPicker:
	var picker := LaunchBodyPicker.new(opt)
	var parent: Node = opt.get_parent()
	parent.add_child(picker)
	parent.move_child(picker, opt.get_index() + 1)
	opt.visible = false
	return picker

## Landing needs ground: not the Sun, and not a gas giant either — there is nothing to touch
## down on.  Disable "Land" where it cannot happen and snap a stale selection back to Orbit.
func _update_arrival_options() -> void:
	var kind: String = _target_kind()
	var m_def: Dictionary = _selected_mission_def()
	var can_land: bool = MissionData.allows_arrival(m_def, kind, "land")
	arrival_option.set_item_disabled(1, not can_land)   # index 1 = "Land"
	arrival_option.set_item_tooltip(1, "" if can_land
		else MissionData.refusal(m_def, kind, "land").capitalize())
	if not can_land and arrival_option.selected == 1:
		arrival_option.selected = 0                     # force Orbit

func _populate_missions() -> void:
	mission_option.clear()
	for m in MissionData.MISSION_TYPES:
		mission_option.add_item(m["name"])

func _populate_arrival() -> void:
	arrival_option.clear()
	arrival_option.add_item("Orbit")
	arrival_option.add_item("Land")

# ── Duration ─────────────────────────────────────────────────────────────────
# The trajectory math itself lives in LaunchPlanner (shared with the automation
# executor); these wrappers just feed it the panel's current selections + state.

## Selected origin / target names ("" when nothing valid is chosen).
func _origin_name() -> String:
	var o := origin_option.selected
	return PLANETS[o] if o >= 0 and o < PLANETS.size() else ""

func _target_name() -> String:
	var t := planet_option.selected
	return TARGETS[t] if t >= 0 and t < TARGETS.size() else ""

## Days from "now" to the chosen start date (planets are propagated to that date).
func _offset_days() -> float:
	if _calendar:
		return float(_calendar.get_offset_days(_cur_year, _cur_month, _cur_day))
	return 0.0

## Cost multiplier from the trajectory's total Δv relative to a bare surface-to-
## orbit launch.  Local orbit → 1.0×; Earth→Mars ≈ 1.6×; Earth→Neptune ≈ 2.7×.
func _difficulty_factor() -> float:
	var o := _origin_name()
	var t := _target_name()
	if o == "" or t == "":
		return 1.0
	return LaunchPlanner.difficulty_factor(o, t)

## Push the planets' live orbital angles (from Game.gd) and refresh the cost,
## which now depends on the actual launch-window geometry.
func set_orbital_state(angles: Dictionary) -> void:
	_planet_angles = angles
	_update_duration()   # transfer distance (and thus time) depends on positions
	_update_cost()


## Launch-window energy multiplier (≥ 1.0) from the actual path between the planets
## at the chosen start date (see LaunchPlanner.path_energy_factor).
func _path_energy_factor() -> float:
	var o := _origin_name()
	var t := _target_name()
	if o == "" or t == "":
		return 1.0
	return LaunchPlanner.path_energy_factor(o, t, _planet_angles, _offset_days())

## Short label describing how good the current launch window is.
func _window_label(pf: float) -> String:
	var x: float = (pf - 1.0) / LaunchPlanner.PHASE_ENERGY_WEIGHT   # 0 = optimal, 1 = worst
	if x < 0.15: return "optimal"
	if x < 0.45: return "good"
	if x < 0.75: return "fair"
	return "poor"

## Repopulate the fuel dropdown with the propellants current research has unlocked.
func _populate_fuels() -> void:
	if _fuel_option == null:
		return
	var prev_id: String = str(_selected_fuel().get("id", ""))
	_fuel_option.clear()
	_fuel_map.clear()
	for i in range(MissionData.FUELS.size()):
		var f: Dictionary = MissionData.FUELS[i]
		var req: String = str(f.get("requires", ""))
		if req != "" and not ResearchTree.is_unlocked(req):
			continue
		_fuel_option.add_item(str(f["name"]))
		_fuel_map.append(i)
		if str(f["id"]) == prev_id:
			_fuel_option.selected = _fuel_map.size() - 1
	if _fuel_option.selected < 0 and _fuel_option.item_count > 0:
		_fuel_option.selected = 0

## The selected fuel definition (defaults to the first/chemical fuel).
func _selected_fuel() -> Dictionary:
	if _fuel_option == null or _fuel_option.selected < 0 or _fuel_option.selected >= _fuel_map.size():
		return MissionData.FUELS[0]
	return MissionData.FUELS[_fuel_map[_fuel_option.selected]]

## Transfer acceleration (m/s²) the selected fuel provides.
func _selected_accel() -> float:
	return float(_selected_fuel().get("accel", 1.0e-2))

## Called by Game.gd to refresh available fuels after a research unlock.
func refresh_fuels() -> void:
	_populate_fuels()
	_update_duration()
	_update_cost()

func _is_local_orbit() -> bool:
	var o_idx := origin_option.selected
	var t_idx := planet_option.selected
	if o_idx < 0 or t_idx < 0:
		return false
	return PLANETS[o_idx] == TARGETS[t_idx] and arrival_option.selected == 0

## Duration multiplier from origin infrastructure (a Space Elevator).
func _duration_mult() -> float:
	return float(_origin_mods().get("duration", 1.0))

func _selected_duration_days() -> int:
	var o := _origin_name()
	var t := _target_name()
	if o == "" or t == "":
		return 0
	var arrival: String = "land" if arrival_option.selected == 1 else "orbit"
	return LaunchPlanner.duration_days(
		o, t, arrival, _selected_accel(), _planet_angles, _offset_days(), _duration_mult())

func _update_duration() -> void:
	var days := _selected_duration_days()
	if days <= 0:
		duration_value.text = "-"
		return
	# Tag launches that benefit from a Space Elevator at the chosen origin.
	var elevator: String = ""
	if float(_origin_mods().get("cost", 1.0)) < 1.0 \
			or float(_origin_mods().get("duration", 1.0)) < 1.0:
		elevator = "  ⛓ elevator"
	if _is_local_orbit():
		duration_value.text = "%s  (local orbit insertion)%s" % [_format_days(days), elevator]
	else:
		# Flag transfers that are pinned at the light-travel-time floor.
		var light_limited: bool = LaunchPlanner.is_light_limited(
			_origin_name(), _target_name(), _selected_accel(), _planet_angles, _offset_days())
		var tag: String = "  (light-speed limit)" if light_limited else ""
		duration_value.text = _format_days(days) + tag + elevator

func _format_days(days: int) -> String:
	if days >= 365:
		# Whole years and the days left over — the pair only makes sense if the division
		# truncates, which is what the % on the next line assumes.
		@warning_ignore("integer_division")
		var years := days / 365
		var rem   := days % 365
		if rem == 0:
			return "%dy" % years
		return "%dy%dd" % [years, rem]
	return "%dd" % days

# ── Cost ─────────────────────────────────────────────────────────────────────

## Grid energy this launch expends (see LaunchPlanner.energy_cost).
func _launch_energy(idx: int) -> float:
	var o := _origin_name()
	var t := _target_name()
	if o == "" or t == "":
		return 0.0
	return LaunchPlanner.energy_cost(idx, o, t, _planet_angles, _offset_days(),
		float(_origin_mods().get("cost_mult", 1.0)))

func _update_cost() -> void:
	var idx := mission_option.selected
	if idx < 0 or idx >= MissionData.MISSION_TYPES.size():
		cost_value.text = "-"
		return
	var fuel: Dictionary = _selected_fuel()
	var rockets: int    = _mission_rockets(idx)
	var fuel_amt: float = _mission_fuel(idx)
	var have_f: float   = float(_origin_stock(str(fuel["id"])))
	# A launch expends propellant AND the vehicles carrying it -- staging is not recovered.  The
	# energy figure is shown because it is what sets the propellant quantity.
	var e_cost: float = _launch_energy(idx)
	var rk_need: float = float(rockets) * MissionData.ROCKET_UNIT_MASS_G
	var have_rk: float = float(_origin_stock("Rocket"))
	var txt: String = "%s %s (have %s)%s\n%d vehicle%s, %s (have %s)%s\n%s of work to fly" % [
		Units.format_si(fuel_amt, "g"), str(fuel["name"]), Units.format_si(have_f, "g"),
		("" if have_f >= fuel_amt else "  ✗"),
		rockets, ("" if rockets == 1 else "s"),
		Units.format_si(rk_need, "g"), Units.format_si(have_rk, "g"),
		("" if have_rk >= rk_need else "  ✗"),
		Units.format_si(e_cost, "J")]
	# What the vehicles are FOR is said once, by the selector immediately below this block —
	# repeating the whole line here put the same sentence twice in adjacent paragraphs.
	# Surface the launch-window quality so the player can see why fuel varies and
	# can pick a better start date.
	if not _is_local_orbit():
		var pf: float = _path_energy_factor()
		if pf > 1.005:
			txt += "\n(+%d%% fuel — %s window)" % [
				int(round((pf - 1.0) * 100.0)), _window_label(pf)]
	# A carrier flying a finished structure: name it, and say what the origin is short of.
	var carried: String = _mission_structure(idx)
	if carried != "":
		txt += "\n+ 1 %s, built at the origin" % carried
		if not _selected_target_is_sun():
			txt += "  — target must be the Sun"
		else:
			var missing: Dictionary = _structure_shortfall(idx)
			if not missing.is_empty():
				var parts: PackedStringArray = []
				for res: String in missing:
					parts.append("%s %s" % [Units.format_si(float(missing[res]), ""), res])
				txt += "  — short %s" % ", ".join(parts)
	# Solar Deployment: show the satellite payload and why it might be blocked.
	elif MissionData.MISSION_TYPES[idx].get("sun_only", false):
		var avail: int = _origin_sat_stock()
		var batch: int = _payload_batch(idx)
		txt += "\n+ %d Solar Satellite payload (have %d)" % [batch, avail]
		if not _selected_target_is_sun():
			txt += "  — target must be the Sun"
		elif _sat_deployed >= _sat_max:
			txt += "  — swarm full"
		elif avail <= 0:
			txt += "  — none in stock at origin"
	cost_value.text = txt

## Rockets (vehicle mass) the mission needs, via LaunchPlanner with the origin's
## infrastructure discount (e.g. a Space Elevator).
func _mission_rockets(mission_idx: int) -> int:
	var o := _origin_name()
	var t := _target_name()
	if o == "" or t == "":
		return 1
	var cost: float = float(_origin_mods().get("cost", 1.0))
	if _is_colony_mission(mission_idx):
		cost *= _colony_mass_mult      # ten million founders are ten times a million to lift
	return LaunchPlanner.rockets(mission_idx, o, t, cost)

## Fuel units the mission burns, via LaunchPlanner; consumed as the selected propellant.
## Grams of the selected propellant this launch burns — derived from its energy requirement.
func _mission_fuel(mission_idx: int) -> float:
	var o := _origin_name()
	var t := _target_name()
	if o == "" or t == "":
		return 0.0
	return LaunchPlanner.propellant_mass(mission_idx, o, t, _planet_angles, _offset_days(),
		float(_origin_mods().get("cost", 1.0)), str(_selected_fuel().get("id", "")))

## Stock of a good (rockets or a fuel) at the currently-selected origin, in grams.
##
## A FLOAT, and every caller already wanted one.  These are gram and joule figures that run past
## 2^63 in a developed run, and int() saturates there to INT64_MIN — so the gates below read a
## full stockpile as a large negative and refused launches the origin could easily pay for.
func _origin_stock(key: String) -> float:
	var o := origin_option.selected
	if o < 0 or o >= PLANETS.size():
		return 0.0
	return float((_launch_stock.get(_origin_id(o), {}) as Dictionary).get(key, 0.0))

## Push the per-origin rocket + fuel stock (from Game.gd) for the cost readout / gate.
func set_launch_stock(stock: Dictionary) -> void:
	_launch_stock = stock
	_update_cost()

# ── Launch ───────────────────────────────────────────────────────────────────

func _on_launch_pressed() -> void:
	var m_idx := mission_option.selected
	var p_idx := planet_option.selected
	var o_idx := origin_option.selected
	if m_idx < 0 or p_idx < 0 or o_idx < 0:
		return
	var target_name: String = TARGETS[p_idx]
	var duration := _selected_duration_days()
	if duration <= 0:
		return   # invalid combination (e.g. land on the same body or on the Sun)
	# A structure carrier must fly to the Sun with the whole structure paid for at the origin.
	if _mission_structure(m_idx) != "":
		if target_name != "Sun" or not _structure_shortfall(m_idx).is_empty():
			return
	# A Solar Deployment must fly to the Sun and actually carry satellites.
	elif MissionData.MISSION_TYPES[m_idx].get("sun_only", false):
		if target_name != "Sun" or _payload_batch(m_idx) <= 0:
			return
	var fuel: Dictionary = _selected_fuel()
	var rockets: int    = _mission_rockets(m_idx)
	var fuel_amt: float = _mission_fuel(m_idx)
	# Propellant and the launch vehicles are both expended; either shortfall blocks the launch.
	if float(_origin_stock(str(fuel["id"]))) < fuel_amt:
		return
	if float(_origin_stock("Rocket")) < float(rockets) * MissionData.ROCKET_UNIT_MASS_G:
		return
	var start_offset: int = 0
	if _calendar:
		start_offset = _calendar.get_offset_days(_cur_year, _cur_month, _cur_day)
	launch_requested.emit({
		"mission":      MissionData.MISSION_TYPES[m_idx]["name"],
		# Ids, not lowercased display names — a moon's id is nothing like its name.
		"origin":       _origin_id(o_idx),
		"target":       _target_id(p_idx),
		"cargo":        _manifest.duplicate(),
		"start_offset": start_offset,
		"duration":     duration,
		"rockets":      rockets,
		"fuel_id":      str(fuel["id"]),
		"fuel_amount":  fuel_amt,
		"arrival":      "land" if arrival_option.selected == 1 else "orbit",
	})
	_manifest.clear()          # the hold has flown; the next order starts empty
	_refresh_cargo()

# ── Launch list ──────────────────────────────────────────────────────────────

func refresh_launches(launches: Array) -> void:
	for child in launch_list.get_children():
		child.queue_free()
	for launch in launches:
		_add_launch_row(launch)

func _add_launch_row(launch: Dictionary) -> void:
	var row := HBoxContainer.new()

	var info := Label.new()
	var origin: String = (launch.get("origin", "") as String).capitalize()
	var target: String = (launch.get("target", "") as String).capitalize()
	var arrival: String = launch.get("arrival", "orbit")

	if origin == target:
		# Local orbit — show clearly instead of "Mars → Mars"
		info.text = "%s: %s orbit" % [launch["mission"], target]
	else:
		var arrival_tag: String = " [land]" if arrival == "land" else ""
		info.text = "%s  %s → %s%s" % [launch["mission"], origin, target, arrival_tag]

	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	var dates := Label.new()
	dates.text = "%d/%02d" % [launch["start_year"], launch["start_month"] + 1]
	row.add_child(dates)

	var status := Label.new()
	if launch["status"] == "completed":
		status.text = "Done"
		status.modulate = Color.GREEN
	else:
		var days_left: int = launch.get("days_remaining", 0)
		status.text = _format_days(days_left) + " left"
	row.add_child(status)

	launch_list.add_child(row)
