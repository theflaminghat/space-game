extends PanelContainer

## Inventory tab of the merged planet panel.  Shows the material stockpile of the selected
## body — every compound (mined ore, refined metal, crafted good) it holds — grouped into
## collapsible category sections, each row showing the stored mass and the live mine rate.
## Fed by Game each tick (while the tab is visible) via set_inventory.
##
## Moons share their parent planet's stockpile (see Game._planet_inv / get_planet_data), so a
## moon's tab shows the same materials as its planet — intended; one colony spans both.

## Emitted when the player confirms discarding `amount` grams of a compound from this body.
signal dump_requested(compound: String, amount: float)
## A standing order rather than a one-off: hold at most `limit` grams of `compound` on this
## body and discard anything above it as it arrives.  A negative limit clears the order.
signal keep_requested(compound: String, limit: float)

var _list:  VBoxContainer = null
var _empty: Label = null
## Last pushed stockpile, so the dump dialog knows how much of a compound is actually held.
var _inv: Dictionary = {}
# ── Dump dialog (built lazily on first use) ───────────────────────────────────
## Explicit dialog size — popup_centered() with no argument falls back to the contents'
## minimum size, which an autowrap label reports badly enough to stretch it full-screen.
const DUMP_DIALOG_SIZE: Vector2i = Vector2i(400, 210)
var _dump_dialog:  ConfirmationDialog = null
var _dump_slider:  HSlider = null
var _dump_amount:  Label = null
var _dump_title:   Label = null
var _dump_compound: String = ""
var _dump_held:    float = 0.0

## Standing keep limits for the body being shown: compound → grams. Absent means "no limit".
var _keeps: Dictionary = {}
var _keep_dialog:   ConfirmationDialog = null
var _keep_slider:   HSlider = null
var _keep_amount:   Label = null
var _keep_title:    Label = null
var _keep_unlimited: CheckBox = null
var _keep_compound: String = ""
var _keep_btns:     Dictionary = {}   # compound → Button, so limits refresh without a rebuild
## Log-scale bounds for the keep slider: a gram to a yottagram covers every stockpile the
## game can produce, and a linear slider over that range would be useless.
const KEEP_LOG_MIN: float = 0.0
const KEEP_LOG_MAX: float = 24.0
## Change-detection: full structural rebuild only when the body changes or a new compound
## appears; otherwise the amount/rate labels are patched in place (preserves collapse state).
var _last_planet: String = ""
var _val_labels:  Dictionary = {}   # compound → Label (stored mass)
var _rate_labels: Dictionary = {}   # compound → Label (mine rate)

## Swallow scroll-wheel so hovering this tab doesn't zoom the 3-D camera behind it (the inner
## ScrollContainer still gets the wheel first when there's a list to scroll).
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index in [
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		accept_event()

func _ready() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Inventory"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0))
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	_empty = Label.new()
	_empty.text = "No materials stored on this body yet — build mines to extract ore."
	_empty.add_theme_color_override("font_color", Color(0.6, 0.66, 0.76))
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_empty)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)

## Push the selected body's stockpile.  `planet` drives the rebuild-vs-patch decision; `data`
## is Game.get_planet_data output — { "mined_resources": {compound→g/s}, "compound_inventory":
## {compound→g} }.  `mined_resources` is the master list of what to show (mined ores at any
## stock, plus any manufactured good currently held, with a 0 rate).
func set_inventory(planet: String, data: Dictionary) -> void:
	var mined: Dictionary = data.get("mined_resources", {})
	var inv:   Dictionary = data.get("compound_inventory", {})
	_inv = inv
	_keeps = data.get("keep_limits", {})

	# A structural rebuild is needed when the body changes or a compound appears that has no row.
	var new_compound := false
	for compound: String in mined:
		if not _val_labels.has(compound):
			new_compound = true
			break

	if planet != _last_planet or new_compound:
		_last_planet = planet
		_rebuild(mined, inv)
	else:
		for compound: String in _val_labels:
			(_val_labels[compound] as Label).text = Units.format_si(float(inv.get(compound, 0.0)), "g")
		for compound: String in _rate_labels:
			(_rate_labels[compound] as Label).text = "+%s/s" % Units.format_si(float(mined.get(compound, 0.0)), "g")
		for compound: String in _keep_btns:
			_refresh_keep_button(compound)

## Full structural rebuild: bucket compounds into collapsible category sections, sorted by
## mine rate within each, with stored mass and rate per row.
func _rebuild(mined: Dictionary, inv: Dictionary) -> void:
	_val_labels.clear()
	_rate_labels.clear()
	_keep_btns.clear()
	for child in _list.get_children():
		child.queue_free()

	if mined.is_empty():
		_empty.visible = true
		return
	_empty.visible = false

	# Sort by rate descending, then bucket by category.
	var pairs: Array = []
	for compound: String in mined:
		pairs.append([compound, float(mined[compound]), float(inv.get(compound, 0.0))])
	pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])

	var by_cat: Dictionary = {}
	for cat: String in CompoundData.CATEGORY_ORDER:
		by_cat[cat] = []
	for pair: Array in pairs:
		var cat: String = CompoundData.CATEGORIES.get(pair[0] as String, "raw")
		(by_cat[cat] as Array).append(pair)

	for cat: String in CompoundData.CATEGORY_ORDER:
		var items: Array  = by_cat[cat] as Array
		var label: String = CompoundData.CATEGORY_LABELS[cat]
		var color: Color  = CompoundData.CATEGORY_COLORS[cat]

		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 2)
		# Raw ores start collapsed (rarely inspected after mines are built); refined and
		# manufactured outputs start expanded so the production lines are visible at a glance.
		content.visible = (cat != "raw")

		var non_zero: int = 0
		for pair: Array in items:
			if float(pair[2]) > 0.0:
				non_zero += 1
		var count_suffix: String = " (%d)" % non_zero if non_zero > 0 else ""

		var header := Button.new()
		header.flat = true
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.add_theme_font_size_override("font_size", 12)
		header.add_theme_color_override("font_color", color)
		header.text = ("▼  " if content.visible else "▶  ") + label + count_suffix
		header.pressed.connect(func() -> void:
			content.visible = not content.visible
			header.text = ("▼  " if content.visible else "▶  ") + label + count_suffix)
		_list.add_child(header)
		_list.add_child(content)

		if items.is_empty():
			var dash := Label.new()
			dash.text = "    —"
			dash.add_theme_font_size_override("font_size", 11)
			dash.add_theme_color_override("font_color", Color(0.45, 0.45, 0.50))
			content.add_child(dash)
			continue
		for pair: Array in items:
			var compound: String = pair[0]
			var row := _make_row(compound, float(pair[2]), float(pair[1]))
			content.add_child(row)

## The Keep button shows the standing limit, so the inventory reads as a set of instructions
## rather than needing each one opened to find out what it says.
func _refresh_keep_button(compound: String) -> void:
	var btn: Button = _keep_btns.get(compound, null)
	if btn == null or not is_instance_valid(btn):
		return
	var lim: float = float(_keeps.get(compound, -1.0))
	if lim < 0.0:
		btn.text = "Keep all"
		btn.modulate = Color(0.60, 0.65, 0.72)
		btn.tooltip_text = "No limit — nothing is discarded automatically"
	else:
		btn.text = "Keep %s" % Units.format_si(lim, "g")
		btn.modulate = Color(0.55, 0.80, 0.95)
		btn.tooltip_text = "Holding at most %s of %s here; the surplus is discarded as it arrives" % [
			Units.format_si(lim, "g"), compound]

## Slider position (log grams) <-> a real amount.
static func _keep_log_to_g(v: float) -> float:
	return pow(10.0, v)

static func _keep_g_to_log(g: float) -> float:
	return clampf(log(maxf(g, 1.0)) / log(10.0), KEEP_LOG_MIN, KEEP_LOG_MAX)

## Build the keep dialog once and reuse it.  Unlike Dump this is not irreversible — it sets a
## standing order — so it confirms but does not shout.
func _ensure_keep_dialog() -> void:
	if _keep_dialog != null:
		return
	_keep_dialog = ConfirmationDialog.new()
	_keep_dialog.title = "Storage limit"
	_keep_dialog.ok_button_text = "Set limit"
	_keep_dialog.wrap_controls = false
	_keep_dialog.min_size = DUMP_DIALOG_SIZE
	_keep_dialog.max_size = DUMP_DIALOG_SIZE

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(DUMP_DIALOG_SIZE.x - 32, 0)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_keep_title = Label.new()
	_keep_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_keep_title.custom_minimum_size = Vector2(DUMP_DIALOG_SIZE.x - 32, 40)
	_keep_title.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	box.add_child(_keep_title)

	# Log scale: stockpiles run from grams to yottagrams and a linear slider cannot address that.
	_keep_slider = HSlider.new()
	_keep_slider.min_value = KEEP_LOG_MIN
	_keep_slider.max_value = KEEP_LOG_MAX
	_keep_slider.step = 0.05
	_keep_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_keep_slider.value_changed.connect(func(_v: float) -> void: _refresh_keep_amount())
	box.add_child(_keep_slider)

	_keep_amount = Label.new()
	_keep_amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_keep_amount.add_theme_color_override("font_color", Color(0.60, 0.85, 0.95))
	box.add_child(_keep_amount)

	_keep_unlimited = CheckBox.new()
	_keep_unlimited.text = "No limit — keep everything"
	_keep_unlimited.toggled.connect(func(on: bool) -> void:
		_keep_slider.editable = not on
		_refresh_keep_amount())
	box.add_child(_keep_unlimited)

	_keep_dialog.add_child(box)
	_keep_dialog.confirmed.connect(func() -> void:
		if _keep_compound == "":
			return
		var lim: float = -1.0 if _keep_unlimited.button_pressed else _keep_log_to_g(_keep_slider.value)
		_keeps[_keep_compound] = lim
		_refresh_keep_button(_keep_compound)
		keep_requested.emit(_keep_compound, lim))
	add_child(_keep_dialog)

## Live readout under the keep slider.
func _refresh_keep_amount() -> void:
	if _keep_amount == null:
		return
	if _keep_unlimited != null and _keep_unlimited.button_pressed:
		_keep_amount.text = "Keep everything — nothing discarded"
		return
	var g: float = _keep_log_to_g(_keep_slider.value)
	var held: float = float(_inv.get(_keep_compound, 0.0))
	var over: String = ""
	if held > g:
		over = "  ·  %s over, discarded now" % Units.format_si(held - g, "g")
	_keep_amount.text = "Hold up to %s%s" % [Units.format_si(g, "g"), over]

## Open the keep dialog for one compound, starting from its current standing order.
func _open_keep_dialog(compound: String) -> void:
	_ensure_keep_dialog()
	_keep_compound = compound
	var lim: float = float(_keeps.get(compound, -1.0))
	var held: float = float(_inv.get(compound, 0.0))
	_keep_unlimited.button_pressed = lim < 0.0
	_keep_slider.editable = lim >= 0.0
	# Default a fresh limit to what is on hand, so the common case is "stop here".
	_keep_slider.value = _keep_g_to_log(lim if lim >= 0.0 else maxf(held, 1.0))
	_keep_title.text = "How much %s (%s) should this body hold? Anything above the limit is discarded as it arrives." % [
		CompoundData.NAMES.get(compound, compound), compound]
	_refresh_keep_amount()
	_keep_dialog.popup_centered(DUMP_DIALOG_SIZE)

## Build the dump dialog once and reuse it: a slider over how much of the stockpile to discard,
## a live gram readout, and an explicit confirm — dumping is irreversible, so it never fires
## straight off the row button.
func _ensure_dump_dialog() -> void:
	if _dump_dialog != null:
		return
	_dump_dialog = ConfirmationDialog.new()
	_dump_dialog.title = "Discard material"
	_dump_dialog.ok_button_text = "Dump"
	_dump_dialog.get_ok_button().modulate = Color(0.95, 0.60, 0.55)
	# Keep the window at the size we ask for instead of resizing itself around its contents.
	_dump_dialog.wrap_controls = false
	_dump_dialog.min_size = DUMP_DIALOG_SIZE
	_dump_dialog.max_size = DUMP_DIALOG_SIZE

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	# Fixed content size: an autowrapping label's minimum height depends on a width it doesn't
	# know yet, and AcceptDialog sizes itself from that minimum — left free it grows to fill the
	# screen.  Pinning the box (and the label's height) keeps the dialog a dialog.
	box.custom_minimum_size = Vector2(DUMP_DIALOG_SIZE.x - 32, 0)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_dump_title = Label.new()
	_dump_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dump_title.custom_minimum_size = Vector2(DUMP_DIALOG_SIZE.x - 32, 44)
	_dump_title.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	box.add_child(_dump_title)

	_dump_slider = HSlider.new()
	_dump_slider.min_value = 0.0
	_dump_slider.max_value = 100.0     # percent of the stockpile held
	_dump_slider.step = 0.1
	_dump_slider.value = 100.0
	_dump_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dump_slider.value_changed.connect(func(_v: float) -> void: _refresh_dump_amount())
	box.add_child(_dump_slider)

	_dump_amount = Label.new()
	_dump_amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dump_amount.add_theme_color_override("font_color", Color(0.95, 0.70, 0.55))
	box.add_child(_dump_amount)

	_dump_dialog.add_child(box)
	_dump_dialog.confirmed.connect(func() -> void:
		var amount: float = _dump_held * _dump_slider.value / 100.0
		if _dump_compound != "" and amount > 0.0:
			dump_requested.emit(_dump_compound, amount))
	add_child(_dump_dialog)

## Refresh the "X g of Y g" readout under the slider.
func _refresh_dump_amount() -> void:
	if _dump_amount == null:
		return
	var amount: float = _dump_held * _dump_slider.value / 100.0
	_dump_amount.text = "%s  (%.1f%% of %s)" % [
		Units.format_si(amount, "g"), _dump_slider.value, Units.format_si(_dump_held, "g")]

## Open the dump dialog for one compound, sized to what this body currently holds.
func _open_dump_dialog(compound: String) -> void:
	var held: float = float(_inv.get(compound, 0.0))
	if held <= 0.0:
		return   # nothing stored — nothing to discard
	_ensure_dump_dialog()
	_dump_compound = compound
	_dump_held = held
	_dump_title.text = "Discard %s (%s) from this body. Mining will replace it over time." % [
		CompoundData.NAMES.get(compound, compound), compound]
	_dump_slider.value = 100.0
	_refresh_dump_amount()
	_dump_dialog.popup_centered(DUMP_DIALOG_SIZE)

## One row: common name + formula on the left, stored mass over mine rate on the right.
func _make_row(compound: String, total: float, rate: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_lbl := Label.new()
	name_lbl.text = CompoundData.NAMES.get(compound, compound)
	name_lbl.add_theme_font_size_override("font_size", 12)
	left.add_child(name_lbl)
	var formula_lbl := Label.new()
	formula_lbl.text = compound
	formula_lbl.add_theme_font_size_override("font_size", 10)
	formula_lbl.add_theme_color_override("font_color", Color(0.60, 0.70, 0.80))
	left.add_child(formula_lbl)
	row.add_child(left)

	var right := VBoxContainer.new()
	var val_lbl := Label.new()
	val_lbl.text = Units.format_si(total, "g")
	val_lbl.add_theme_font_size_override("font_size", 12)
	val_lbl.add_theme_color_override("font_color", Color(0.85, 0.90, 0.70))
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(val_lbl)
	var rate_lbl := Label.new()
	rate_lbl.text = "+%s/s" % Units.format_si(rate, "g")
	rate_lbl.add_theme_font_size_override("font_size", 10)
	rate_lbl.add_theme_color_override("font_color", Color(0.40, 0.90, 0.55))
	rate_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(rate_lbl)
	row.add_child(right)

	# Dump: discard this body's entire stockpile of the compound (mining will refill over time).
	var dump_btn := Button.new()
	dump_btn.text = "Dump"
	dump_btn.flat = true
	dump_btn.add_theme_font_size_override("font_size", 10)
	dump_btn.custom_minimum_size = Vector2(44, 0)
	dump_btn.tooltip_text = "Discard stored %s — choose how much, then confirm" % compound
	dump_btn.modulate = Color(0.95, 0.60, 0.55)
	dump_btn.pressed.connect(func() -> void: _open_dump_dialog(compound))

	# Keep: a standing limit rather than a one-off discard.  Anything arriving above it is
	# thrown away as it lands, so a mine pointed at ore you only need a little of stops
	# quietly filling the hold instead of demanding attention every few minutes.
	var keep_btn := Button.new()
	keep_btn.flat = true
	keep_btn.add_theme_font_size_override("font_size", 10)
	keep_btn.custom_minimum_size = Vector2(86, 0)
	keep_btn.pressed.connect(func() -> void: _open_keep_dialog(compound))
	row.add_child(keep_btn)
	_keep_btns[compound] = keep_btn
	_refresh_keep_button(compound)

	row.add_child(dump_btn)

	_val_labels[compound] = val_lbl
	_rate_labels[compound] = rate_lbl
	return row
