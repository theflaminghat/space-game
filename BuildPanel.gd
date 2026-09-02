extends PanelContainer

## Each carries how many to act on, so a batch is one request rather than N clicks.
signal build_requested(planet_name: String, building_name: String, count: int)
signal demolish_requested(planet_name: String, building_name: String, count: int)
## Retrofit standing copies of this building into the next level up.
signal upgrade_requested(planet_name: String, building_name: String, count: int)
## How many of the standing copies are switched on.  Idle buildings cost nothing and do nothing.
signal active_changed(planet_name: String, building_name: String, count: int)

@onready var build_list: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/BuildList

var current_planet: String = ""

## Cost line-item labels, tracked so affordability colouring can be refreshed live
## without rebuilding the whole list (which would reset scroll position).
## Each entry: { "label": Label, "key": String, "amount": float }
var _cost_items: Array = []

## Per-LEVEL mutable widgets, keyed by full building name ("Mine", "Mine II"), so a build,
## demolish, or upgrade can patch counts and button states in place instead of tearing down and
## recreating the whole list (which was the frame-stutter on every build).
## Each: { count, build[], demolish[], upgrade[], available, min_count }.
var _rows: Dictionary = {}
## Per-FAMILY header widgets, keyed by base name, holding the total standing across all levels
## and the shared construction badge.  Each: { total: Label, badge: Label }.
var _families: Dictionary = {}

## Batch sizes offered for build / demolish / upgrade.  Catalogue entries are single buildings,
## so infrastructure is raised by the hundred and one-at-a-time clicking is not a real option.
const BATCH_SIZES: Array = [1, 10, 100]

# Cost-label colours: normal grey when affordable, darker when the player is short.
const COST_OK:    Color = Color(0.75, 0.75, 0.75)
const COST_SHORT: Color = Color(0.42, 0.42, 0.42)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index in [
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		accept_event()


func set_planet(planet_name: String, catalog: Array) -> void:
	current_planet = planet_name
	_populate(catalog)
	# Visibility is managed by the parent TabContainer / Game (this is a tab page now).

## Recolour cost line items against the player's current stockpiles without
## rebuilding the list.  `have` maps resource/compound name → amount held.
func refresh_affordability(have: Dictionary) -> void:
	for item: Dictionary in _cost_items:
		var enough: bool = float(have.get(item["key"], 0.0)) >= float(item["amount"])
		(item["label"] as Label).modulate = COST_OK if enough else COST_SHORT

## Fast in-place update after a build/demolish: patch counts, construction badges, the demolish
## button's disabled state, and affordability — recreating no nodes.  Falls back to a full rebuild
## only when the row set or a building's availability changed (a planet/research/colony change
## reshapes the list).  This is what keeps building from stuttering every click.
## Cheap per-frame refresh of the green/red split alone.  Supply moves continuously as fuel
## drains or a mine catches up, none of which touches the roster — so this cannot ride on
## apply_counts(), which only runs when a building is raised or demolished.  `factors` is the
## world's { building name -> share of inputs met } straight out of Game._fuel_factor; anything
## absent from it consumes nothing and is always fully running.
func refresh_supply(factors: Dictionary) -> void:
	for bname: String in _rows:
		var r: Dictionary = _rows[bname]
		var bar = r.get("supply_bar", null)
		if bar == null:
			continue
		var asl: HSlider = r.get("active_slider", null)
		if asl == null:
			continue
		_apply_supply(bar, r.get("active_label", null), int(asl.value), int(asl.max_value),
			float(factors.get(bname, 1.0)))


func apply_counts(catalog: Array) -> void:
	if catalog.size() != _rows.size():
		_populate(catalog)
		return
	var have_all: Dictionary = {}
	var fam_total: Dictionary = {}    # base name → standing across every level
	var fam_queued: Dictionary = {}   # base name → under construction across every level
	for building: Dictionary in catalog:
		var bname: String = str(building["name"])
		if not _rows.has(bname):
			_populate(catalog)
			return
		var r: Dictionary = _rows[bname]
		if bool(building.get("available", true)) != bool(r["available"]):
			_populate(catalog)   # cost/requirement layout differs — structure changed
			return
		var count: int = int(building.get("count", 0))
		(r["count"] as Label).text = str(count)
		# The slider's ceiling is the standing count, so building or demolishing moves it.
		var asl: HSlider = r.get("active_slider", null)
		if asl != null:
			var act: int = clampi(int(building.get("active", count)), 0, count)
			if int(asl.max_value) != count or int(asl.value) != act:
				asl.set_block_signals(true)
				asl.max_value = count
				asl.value = act
				asl.set_block_signals(false)
			# Refresh the green/red split every pass: supply moves on its own as fuel runs
			# down or a mine catches up, with no slider event to hang it off.
			_apply_supply(r.get("supply_bar", null), r.get("active_label", null),
				act, count, float(building.get("supply", 1.0)))
		# Each batch button is gated on whether that many can actually be acted on.
		var dem: Array = r["demolish"]
		var ups: Array = r["upgrade"]
		var can_up: bool = bool(building.get("can_upgrade", false))
		for i in range(BATCH_SIZES.size()):
			var n: int = int(BATCH_SIZES[i])
			if i < dem.size():
				(dem[i] as Button).disabled = count - n < int(r["min_count"])
			if i < ups.size():
				(ups[i] as Button).disabled = not can_up or count < n
		for k: String in (building.get("have", {}) as Dictionary):
			have_all[k] = building["have"][k]
		# Roll this level up into its family's header figures.
		var base: String = str(building.get("base_name", bname))
		fam_total[base]  = int(fam_total.get(base, 0)) + count
		fam_queued[base] = int(fam_queued.get(base, 0)) + int(building.get("in_progress", 0))
	for base: String in _families:
		var f: Dictionary = _families[base]
		(f["total"] as Label).text = str(int(fam_total.get(base, 0)))
		var badge: Label = f["badge"]
		var q: int = int(fam_queued.get(base, 0))
		badge.text = "+%d⚙" % q
		badge.visible = q > 0
	refresh_affordability(have_all)


## The Active slider's track, drawn in two tones: green for the buildings whose inputs are
## actually being met, red for the ones switched on that cannot run.  Lives as a child of the
## slider with show_behind_parent set, so it replaces the track the theme would have drawn.
class SupplyBar extends Control:
	var running: float = 0.0     # 0..1 of the FULL width — green
	var starved: float = 0.0     # 0..1 of the FULL width — red, drawn after the green

	func set_split(run_frac: float, starve_frac: float) -> void:
		running = clampf(run_frac, 0.0, 1.0)
		starved = clampf(starve_frac, 0.0, 1.0 - running)
		queue_redraw()

	## Track height and how it sits inside the slider's full height.  Drawn as a band rather
	## than filling the control, so it reads as a slider track and leaves room for the grabber
	## to stand proud of it.
	const TRACK_H: float = 6.0

	func _draw() -> void:
		var w: float = size.x
		var y: float = (size.y - TRACK_H) * 0.5
		# Unlit remainder: standing buildings the player has deliberately switched off.
		draw_rect(Rect2(0.0, y, w, TRACK_H), Color(0.18, 0.20, 0.26))
		if running > 0.0:
			draw_rect(Rect2(0.0, y, w * running, TRACK_H), Color(0.35, 0.80, 0.40))
		if starved > 0.0:
			draw_rect(Rect2(w * running, y, w * starved, TRACK_H), Color(0.88, 0.30, 0.28))


## Set the green/red split and annotate the count label when some are starved.  `supply` is the
## share of this type's inputs being met (Game passes it per building type).
func _apply_supply(bar: Control, lbl: Label, act: int, count: int, supply: float) -> void:
	if bar == null or count <= 0:
		return
	var authorised: float = float(act) / float(count)
	var run_frac: float = authorised * clampf(supply, 0.0, 1.0)
	(bar as SupplyBar).set_split(run_frac, authorised - run_frac)
	var running_n: int = int(floor(float(act) * clampf(supply, 0.0, 1.0)))
	if lbl == null:
		return
	if act > 0 and running_n < act:
		# Say what is actually running, and colour the readout to match the bar.
		lbl.text = "%d of %d / %d" % [running_n, act, count]
		lbl.modulate = Color(0.88, 0.45, 0.40)
		lbl.tooltip_text = "%d switched on, %d running — the rest are short of inputs" % [
			act, running_n]
	else:
		lbl.text = "%d / %d" % [act, count]
		lbl.modulate = Color(0.85, 0.90, 0.70)
		lbl.tooltip_text = ""

func _populate(catalog: Array) -> void:
	_cost_items.clear()
	_rows.clear()
	_families.clear()
	for child in build_list.get_children():
		child.queue_free()

	# Group twice: by category for the sections, then by BASE NAME so every level of a building
	# lands in the same card.  Dictionary keys keep insertion order, so families appear in
	# catalogue order and levels in level order.
	var by_cat: Dictionary = {}
	for building in catalog:
		var cat: String = str(building.get("category", "other"))
		var base: String = str(building.get("base_name", building["name"]))
		if not by_cat.has(cat):
			by_cat[cat] = {}
		var fams: Dictionary = by_cat[cat]
		if not fams.has(base):
			fams[base] = []
		(fams[base] as Array).append(building)

	var cats: Array = []
	for c: String in BuildingData.CATEGORY_ORDER:
		if by_cat.has(c):
			cats.append(c)
	for c: String in by_cat:
		if c not in BuildingData.CATEGORY_ORDER:
			cats.append(c)

	for cat: String in cats:
		var fams2: Dictionary = by_cat[cat]
		_add_category_header(cat, fams2.size())   # count families, not individual levels
		for base: String in fams2:
			var tiers: Array = fams2[base]
			tiers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return int(a.get("level", 1)) < int(b.get("level", 1)))
			_add_building_card(base, tiers)

## Section heading above each group of buildings.
func _add_category_header(cat: String, count: int) -> void:
	var header := Label.new()
	header.text = "%s  (%d)" % [
		str(BuildingData.CATEGORY_LABELS.get(cat, cat.capitalize())), count]
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color",
		BuildingData.CATEGORY_COLORS.get(cat, Color(0.70, 0.75, 0.85)))
	build_list.add_child(header)

## One building FAMILY as a single collapsible card: the header carries the base name and the
## total standing across every level, and the body lists each level in turn with its own output,
## cost, and controls.  Grouping them keeps the catalogue the same length it was before levels
## existed, and puts a building's whole upgrade path in one place.
func _add_building_card(base_name: String, tiers: Array) -> void:
	var total: int = 0
	var queued: int = 0
	var any_live: bool = false
	for t: Dictionary in tiers:
		total  += int(t.get("count", 0))
		queued += int(t.get("in_progress", 0))
		if bool(t.get("available", true)) or int(t.get("count", 0)) > 0:
			any_live = true

	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 0)

	# Header: expander + name, then the construction badge and the family total.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)

	var toggle := Button.new()
	toggle.flat = true
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle.text = "▶  " + base_name
	if not any_live:
		toggle.modulate = Color(0.55, 0.55, 0.55)
	header.add_child(toggle)

	var badge := Label.new()
	badge.text = "+%d⚙" % queued
	badge.add_theme_font_size_override("font_size", 11)
	badge.modulate = Color(0.95, 0.70, 0.30)
	badge.tooltip_text = "Under construction (limited by this world's manufacturing capacity)"
	badge.visible = queued > 0
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(badge)

	var total_label := Label.new()
	total_label.text                 = str(total)
	total_label.custom_minimum_size  = Vector2(28, 0)
	total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	total_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	total_label.add_theme_font_size_override("font_size", 13)
	total_label.tooltip_text = "Total standing across all levels"
	header.add_child(total_label)
	card.add_child(header)

	# Body: one block per level, collapsed by default.
	var body := MarginContainer.new()
	body.add_theme_constant_override("margin_left", 16)
	body.add_theme_constant_override("margin_bottom", 6)
	body.visible = false
	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 2)
	body.add_child(detail)
	for i in range(tiers.size()):
		if i > 0:
			var sep := HSeparator.new()
			sep.modulate = Color(1.0, 1.0, 1.0, 0.12)
			detail.add_child(sep)
		_add_tier_block(detail, tiers[i] as Dictionary, tiers.size() > 1)
	card.add_child(body)

	toggle.pressed.connect(func() -> void:
		body.visible = not body.visible
		toggle.text = ("▼  " if body.visible else "▶  ") + base_name)

	_families[base_name] = {"total": total_label, "badge": badge}
	build_list.add_child(card)

## One level inside a family card: its heading and count, what it produces, what it costs, and
## the controls to build, demolish, or retrofit it.
func _add_tier_block(parent: VBoxContainer, building: Dictionary, show_level: bool) -> void:
	var bname:     String = str(building["name"])
	var available: bool = building.get("available", true)
	var count:     int  = building.get("count", 0)
	var buildable: bool = building.get("buildable", true)
	var min_count: int  = building.get("min_count", 0)
	var dimmed:    bool = not available and count == 0

	# Level heading + this level's own count.  A single-level building skips the heading, but the
	# count label is still created (hidden) so apply_counts can patch every row uniformly.
	var count_label := Label.new()
	if show_level:
		var head := HBoxContainer.new()
		var lvl := Label.new()
		lvl.text = "Level %d" % int(building.get("level", 1))
		lvl.add_theme_font_size_override("font_size", 11)
		lvl.modulate = Color(0.85, 0.88, 0.95) if not dimmed else Color(0.50, 0.50, 0.55)
		lvl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(lvl)
		count_label.text = str(count)
		count_label.add_theme_font_size_override("font_size", 11)
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.custom_minimum_size = Vector2(28, 0)
		head.add_child(count_label)
		parent.add_child(head)
	else:
		count_label.visible = false
		parent.add_child(count_label)

	var prod_text := _format_production(building.get("production", {}))
	if prod_text != "":
		parent.add_child(_detail_label(prod_text,
			Color(0.50, 0.72, 0.95) if not dimmed else Color(0.45, 0.45, 0.45)))

	# Fuel draw - this plant only runs while the world can feed it.
	var fuel_text := _format_consumption(building.get("consumption", {}))
	if fuel_text != "":
		var fuel_label := _detail_label(fuel_text,
			Color(0.95, 0.70, 0.35) if not dimmed else Color(0.50, 0.45, 0.40))
		fuel_label.tooltip_text = "Burns fuel from this world's inventory; a plant that can't be fed throttles."
		parent.add_child(fuel_label)

	# Special infrastructure effects (e.g. Space Elevator launch discounts).
	var eff_text := _format_effects(building)
	if eff_text != "":
		parent.add_child(_detail_label(eff_text,
			Color(0.45, 0.85, 0.80) if not dimmed else Color(0.40, 0.45, 0.45)))

	# Storage contribution (storage buildings only).
	var stor: Dictionary = building.get("storage", {})
	if not stor.is_empty():
		parent.add_child(_detail_label(_format_storage(stor), Color(0.55, 0.90, 0.65)))

	# Cost, or the research still standing in the way.
	if available:
		var cost: Dictionary = building.get("cost", {})
		var have: Dictionary = building.get("have", {})
		var cost_box := HBoxContainer.new()
		cost_box.add_theme_constant_override("separation", 8)
		# One label per cost item so resources the player can't afford dim individually.
		for key: String in cost:
			var amount: float = float(cost[key])
			if amount <= 0.0:
				continue
			var affordable: bool = float(have.get(key, 0.0)) >= amount
			var item := Label.new()
			item.text = Units.format_cost_component(key, amount)
			item.add_theme_font_size_override("font_size", 11)
			item.modulate = COST_OK if affordable else COST_SHORT
			cost_box.add_child(item)
			_cost_items.append({"label": item, "key": key, "amount": amount})
		parent.add_child(cost_box)
	elif count == 0:
		var req_id: String = building.get("requires", "")
		parent.add_child(_detail_label(
			"Requires: " + req_id.replace("_", " ").capitalize(), Color(0.55, 0.55, 0.55)))

	# Running cost — nothing operates for free, so this is what each switched-on copy draws.
	var upkeep: float = float(building.get("upkeep", 0.0))
	if upkeep > 0.0:
		var up_lbl := _detail_label("Draws %s/day to run" % Units.format_si(upkeep, "J"),
			Color(0.85, 0.70, 0.95) if not dimmed else Color(0.45, 0.42, 0.50))
		up_lbl.tooltip_text = "Maintenance power, drawn while the building is switched on"
		parent.add_child(up_lbl)

	# Active-count slider: how many of the standing copies are actually running.  Idling a
	# building stops its output AND its running cost, which is the lever when the grid is short.
	var active_lbl: Label = null
	var active_slider: HSlider = null
	var supply_bar: Control = null
	if count > 0:
		var act: int = clampi(int(building.get("active", count)), 0, count)
		var act_row := HBoxContainer.new()
		act_row.add_theme_constant_override("separation", 6)
		var act_name := Label.new()
		act_name.text = "Active"
		act_name.add_theme_font_size_override("font_size", 10)
		act_name.custom_minimum_size = Vector2(52, 0)
		act_name.modulate = Color(0.70, 0.75, 0.85)
		act_row.add_child(act_name)
		active_slider = HSlider.new()
		active_slider.min_value = 0
		active_slider.max_value = count
		active_slider.step = 1
		active_slider.value = act
		active_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		act_row.add_child(active_slider)
		active_lbl = Label.new()
		active_lbl.text = "%d / %d" % [act, count]
		active_lbl.add_theme_font_size_override("font_size", 10)
		active_lbl.custom_minimum_size = Vector2(72, 0)
		active_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		active_lbl.modulate = Color(0.85, 0.90, 0.70)
		act_row.add_child(active_lbl)
		parent.add_child(act_row)

		# The supply split IS the slider's track.  The bar is a child of the slider drawn
		# BEHIND it (show_behind_parent), and the slider's own track styleboxes are blanked so
		# the colour shows through — the grabber still draws on top and stays draggable.  So
		# green/red is not a second readout under the control; it is the control.
		active_slider.add_theme_stylebox_override("slider", StyleBoxEmpty.new())
		active_slider.add_theme_stylebox_override("grabber_area", StyleBoxEmpty.new())
		active_slider.add_theme_stylebox_override("grabber_area_highlight", StyleBoxEmpty.new())
		var bar := SupplyBar.new()
		bar.show_behind_parent = true
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_preset(Control.PRESET_FULL_RECT)
		active_slider.add_child(bar)
		_apply_supply(bar, active_lbl, act, count, float(building.get("supply", 1.0)))
		supply_bar = bar

		active_slider.value_changed.connect(func(v: float) -> void:
			_apply_supply(bar, active_lbl, int(v), count, float(building.get("supply", 1.0)))
			active_changed.emit(current_planet, bname, int(v)))

	# Build / demolish / upgrade, each in 1 / 10 / 100 batches — at single-building scale you
	# raise infrastructure by the hundred, so one-at-a-time clicking is not a real option.
	var demolish_btns: Array = []
	var build_btns: Array = []
	var upgrade_btns: Array = []

	var build_row := HBoxContainer.new()
	build_row.add_theme_constant_override("separation", 4)
	var build_lbl := Label.new()
	build_lbl.text = "Build"
	build_lbl.add_theme_font_size_override("font_size", 10)
	build_lbl.custom_minimum_size = Vector2(52, 0)
	build_lbl.modulate = Color(0.70, 0.75, 0.85)
	build_row.add_child(build_lbl)
	for n: int in BATCH_SIZES:
		var b := Button.new()
		b.text = "+%d" % n
		b.custom_minimum_size = Vector2(44, 24)
		b.disabled = not available or not buildable
		b.pressed.connect(_on_build_pressed.bind(bname, n))
		build_row.add_child(b)
		build_btns.append(b)
	parent.add_child(build_row)

	var dem_row := HBoxContainer.new()
	dem_row.add_theme_constant_override("separation", 4)
	var dem_lbl := Label.new()
	dem_lbl.text = "Demolish"
	dem_lbl.add_theme_font_size_override("font_size", 10)
	dem_lbl.custom_minimum_size = Vector2(52, 0)
	dem_lbl.modulate = Color(0.70, 0.75, 0.85)
	dem_row.add_child(dem_lbl)
	for n: int in BATCH_SIZES:
		var b := Button.new()
		b.text = "−%d" % n
		b.custom_minimum_size = Vector2(44, 24)
		b.disabled = count - n < min_count
		b.pressed.connect(_on_demolish_pressed.bind(bname, n))
		dem_row.add_child(b)
		demolish_btns.append(b)
	parent.add_child(dem_row)

	# Retrofit into the next level, charged at the difference in materials.  Shown whenever a
	# higher level exists so the upgrade path is discoverable before it is affordable.
	var next_level: String = str(building.get("next_level", ""))
	if next_level != "":
		var up_row := HBoxContainer.new()
		up_row.add_theme_constant_override("separation", 4)
		var up_lbl := Label.new()
		up_lbl.text = "Upgrade"
		up_lbl.add_theme_font_size_override("font_size", 10)
		up_lbl.custom_minimum_size = Vector2(52, 0)
		up_lbl.modulate = Color(0.70, 0.75, 0.85)
		up_row.add_child(up_lbl)
		var up_cost: Dictionary = building.get("upgrade_cost", {})
		var tip: String = "Retrofit into %s. Each costs the difference: %s" % [
			str(building.get("upgrade_label", next_level)), Units.format_cost(up_cost)] 			if not up_cost.is_empty() else "Retrofit into the next level"
		for n: int in BATCH_SIZES:
			var b := Button.new()
			b.text = "↑%d" % n
			b.custom_minimum_size = Vector2(44, 24)
			b.disabled = not bool(building.get("can_upgrade", false)) or count < n
			b.tooltip_text = tip
			b.pressed.connect(_on_upgrade_pressed.bind(bname, n))
			up_row.add_child(b)
			upgrade_btns.append(b)
		parent.add_child(up_row)

	_rows[bname] = {
		"count": count_label, "demolish": demolish_btns, "build": build_btns,
		"available": available, "min_count": min_count, "upgrade": upgrade_btns,
		"active_slider": active_slider, "active_label": active_lbl,
		"supply_bar": supply_bar,
	}


func _detail_label(text: String, col: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.modulate = col
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return lbl

func _format_cost(cost: Dictionary) -> String:
	return Units.format_cost(cost)

## Compact per-second output string shown under the building name.
##   {"compute": 80.0}            → "80 FLOP/s"
##   {"energy": 1800.0}           → "1.8 KiloWatts"
##   {"minerals": 500.0}          → "500 Grams/s"
## Returns "" for buildings with no direct production (domes, storage).
func _format_production(prod: Dictionary) -> String:
	var parts: Array = []
	for key: String in ["compute", "energy", "minerals"]:
		if prod.has(key) and float(prod[key]) > 0.0:
			parts.append(Units.format_rate(key, float(prod[key])))
	# Foodstuffs are produced by name rather than as a pooled resource, so they need listing
	# individually — without this every farm reads as producing nothing at all.
	for key: String in prod:
		if key in ["compute", "energy", "minerals"]:
			continue
		var rate: float = float(prod[key])
		if rate > 0.0:
			parts.append("%s %s/day" % [Units.format_si(rate, "g"), key])
	return "  ".join(parts)

## Fuel a building burns per game-day, e.g. {"Coal": 1.5} → "Burns 1.5 g Coal/day".
## Returns "" for buildings that need no fuel (solar, nuclear, fusion, the Biomass Burner).
func _format_consumption(burn: Dictionary) -> String:
	var parts: Array = []
	for key: String in burn:
		var amount: float = float(burn[key])
		if amount <= 0.0:
			continue
		# Energy is not a mass — a farm drawing 3.5e12 J/day must not read as "3.5 TG".
		if key == "energy":
			parts.append("%s/day" % Units.format_si(amount, "J"))
		else:
			parts.append("%s %s/day" % [Units.format_si(amount, "g"), key])
	if parts.is_empty():
		return ""
	return "Consumes " + "  ".join(parts)

## Compact description of special infrastructure effects shown in teal under the
## building's production line.  Currently covers launch cost/time discounts (the
## Space Elevator).  Returns "" when the building has no such effect.
func _format_effects(building: Dictionary) -> String:
	var parts: Array = []
	if building.has("launch_cost_mult"):
		var cpct: int = int(round((1.0 - float(building["launch_cost_mult"])) * 100.0))
		if cpct != 0:
			parts.append("Launch cost −%d%%" % cpct)
	if building.has("launch_duration_mult"):
		var dpct: int = int(round((1.0 - float(building["launch_duration_mult"])) * 100.0))
		if dpct != 0:
			parts.append("Launch time −%d%%" % dpct)
	if building.has("detection") and float(building["detection"]) > 0.0:
		parts.append("Signature detection +%d" % int(round(float(building["detection"]))))
	# Capacity a building adds to one of its world's work pools.  This is what a Factory or a
	# Farm actually IS — the building produces nothing on its own, it raises the ceiling on what
	# the Production panel's lines can draw — and until now the panel never said so.
	for cap: Array in [["mc_capacity", "Factory"], ["farm_capacity", "Arable"],
			["ranch_capacity", "Pasture"]]:
		var key: String = str(cap[0])
		if building.has(key) and float(building[key]) > 0.0:
			parts.append("%s capacity +%s work/day" % [
				str(cap[1]), Units.format_si(float(building[key]), "")])
	if building.has("radiator_capacity") and float(building["radiator_capacity"]) > 0.0:
		parts.append("Heat radiating +%s" % Units.format_si(float(building["radiator_capacity"]), "W"))
	if building.has("beam_send") and float(building["beam_send"]) > 0.0:
		parts.append("Power transmit +%s" % Units.format_si(float(building["beam_send"]), "W"))
	if building.has("beam_recv") and float(building["beam_recv"]) > 0.0:
		parts.append("Power receive +%s" % Units.format_si(float(building["beam_recv"]), "W"))
	if building.has("atmo_rate") and float(building["atmo_rate"]) > 0.0:
		parts.append("Condenses %s/day from the atmosphere"
			% Units.format_si(float(building["atmo_rate"]), "g"))
	if building.has("shelter") and float(building["shelter"]) > 0.0:
		parts.append("Shelters %s through nuclear war and impacts"
			% Units.format_si(float(building["shelter"]), ""))
	return "  ".join(parts)

## Compact storage-capacity string shown in green next to storage buildings.
##   {"minerals": 1e6, "energy": 1e6} → "+1.0 Mg  +1.0 MJ"
func _format_storage(stor: Dictionary) -> String:
	var parts: Array = []
	if stor.has("minerals"):
		parts.append("+%s" % Units.format_si(float(stor["minerals"]), "g"))
	if stor.has("energy"):
		parts.append("+%s" % Units.format_si(float(stor["energy"]), "J"))
	return "  ".join(parts)

func _on_build_pressed(building_name: String, count: int) -> void:
	build_requested.emit(current_planet, building_name, count)

func _on_demolish_pressed(building_name: String, count: int) -> void:
	demolish_requested.emit(current_planet, building_name, count)

func _on_upgrade_pressed(building_name: String, count: int) -> void:
	upgrade_requested.emit(current_planet, building_name, count)
