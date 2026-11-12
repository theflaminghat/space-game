class_name CargoPicker
extends Button

## The Supply Run's item menu: what the origin world is holding, folded under the same headings
## the Inventory tab files it under — Food, Raw Materials, Refined Materials, Components,
## Manufactured Goods — instead of one alphabetical list of formulae.
##
## That list was a developed world's whole inventory sorted by formula, so "Al" sat between
## "Aerogel" and "Algae" and the one thing worth sending was somewhere in a scroll of sixty.
## Each heading is a fold, entries go by name rather than by formula, and each shows how much of
## it the origin is holding — the one figure needed to type the amount beside it.
##
## Like LaunchBodyPicker it DRIVES a hidden OptionButton rather than replacing it.  The option's
## item texts stay the compound keys, so every caller that reads `get_item_text(selected)` — and
## every test that lists what is offered — keeps working; a pick here is `option.select(i)` plus
## the `item_selected` the option itself would have sent.

const POPUP_SIZE: Vector2i = Vector2i(320, 360)
const AMOUNT_COL_W: int = 90

var option: OptionButton = null
var _held: Dictionary = {}
var _popup: PopupPanel = null
var _tree: Tree = null
## What the button label last showed: the selected key, or EMPTY when there is nothing to pick.
var _shown: String = "\u0000"
const EMPTY: String = "\u0001"


func _init(opt: OptionButton = null) -> void:
	option = opt
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# The same reason the option it stands in for clips: the entries are whatever the origin
	# happens to hold, so the widest one must not get to decide how wide the column is.
	clip_text = true
	pressed.connect(_open)


func _ready() -> void:
	_popup = PopupPanel.new()
	add_child(_popup)
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.columns = 2
	# The whole row lights up, name and holding together: it is one choice, not two cells.
	_tree.select_mode = Tree.SELECT_ROW
	_tree.set_column_expand(0, true)
	_tree.set_column_expand(1, false)
	_tree.set_column_custom_minimum_width(1, AMOUNT_COL_W)
	_tree.custom_minimum_size = Vector2(POPUP_SIZE)
	_tree.item_mouse_selected.connect(func(_at: Vector2, button: int) -> void:
		if button == MOUSE_BUTTON_LEFT:
			_choose())
	_tree.item_activated.connect(_on_activated)
	_tree.item_collapsed.connect(_on_folded)
	_popup.add_child(_tree)


## How much of each key the origin holds, for the amount column.  Pushed by the panel from the
## same map it filled the option from, so the two never describe different worlds.
func set_held(held: Dictionary) -> void:
	_held = held


## What a key is called in the menus: its proper name where the encyclopedia has one.
static func display_name(key: String) -> String:
	return str(CompoundData.NAMES.get(key, key))


## Which heading a key is filed under.  CompoundData's own default, so the menu and the Inventory
## tab can never disagree about where something lives.
static func category_of(key: String) -> String:
	return str(CompoundData.CATEGORIES.get(key, "raw"))


## The compound key the option has selected, or "".
func selected_key() -> String:
	if option == null or option.selected < 0 or option.selected >= option.item_count:
		return ""
	return option.get_item_text(option.selected)


## Keep the label on whatever the option has selected, however it was selected — the panel
## repopulates it whenever the mission or the origin changes, and never tells anybody.
func _process(_delta: float) -> void:
	if option == null or not is_visible_in_tree():
		return
	var key: String = selected_key() if option.item_count > 0 else EMPTY
	if key == _shown:
		return
	_shown = key
	if key == EMPTY:
		text = "Nothing here to ship  ▾"
	elif key == "":
		text = "—  ▾"
	else:
		text = "%s  ▾" % display_name(key)


func _open() -> void:
	if option == null or _tree == null:
		return
	_tree.clear()
	var root: TreeItem = _tree.create_item()
	var cur: String = selected_key()

	var by_cat: Dictionary = {}
	for i in range(option.item_count):
		var key: String = option.get_item_text(i)
		var cat: String = category_of(key)
		if not by_cat.has(cat):
			by_cat[cat] = []
		(by_cat[cat] as Array).append(key)
	var order: Array = CompoundData.CATEGORY_ORDER.duplicate()   # it is a const; this appends
	for cat: String in by_cat:
		if not order.has(cat):
			order.append(cat)        # a heading the Inventory tab does not know yet, last

	var pick: TreeItem = null
	for cat: String in order:
		if not by_cat.has(cat):
			continue
		var keys: Array = by_cat[cat]
		keys.sort_custom(func(a: String, b: String) -> bool:
			return display_name(a).naturalnocasecmp_to(display_name(b)) < 0)
		var head: TreeItem = _tree.create_item(root)
		head.set_text(0, "%s  (%d)" % [
			str(CompoundData.CATEGORY_LABELS.get(cat, cat.capitalize())), keys.size()])
		head.set_custom_color(0, CompoundData.CATEGORY_COLORS.get(cat, UIPalette.HEADER))
		head.set_metadata(0, "")
		# Open only the heading holding the current pick, as the body picker opens only the
		# planet whose moon is picked.  (An OptionButton always selects its first item, so there
		# is always a pick, and a world holding one type of thing opens on it by this rule alone.)
		head.collapsed = not keys.has(cur)
		for key: String in keys:
			var it: TreeItem = _tree.create_item(head)
			it.set_text(0, display_name(key))
			it.set_tooltip_text(0, key)          # the formula, for anyone who reads them
			it.set_metadata(0, key)
			if _held.has(key):
				it.set_text(1, Units.format_si(float(_held[key]), "g"))
				it.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
				it.set_custom_color(1, UIPalette.DIM)
			if key == cur:
				pick = it
	# Highlight the current pick.  Only a highlight: picks come from clicks and Enter.
	if pick != null:
		pick.select(0)
	var at: Vector2 = get_screen_position() + Vector2(0.0, size.y)
	_popup.popup(Rect2i(Vector2i(at), Vector2i(maxi(int(size.x), POPUP_SIZE.x), POPUP_SIZE.y)))


## A click on a row, or Enter on it — and NOT `item_selected`, which is what this used to hang off.
## That signal fires when the highlight MOVES: on every arrow key, so the menu picked and shut on
## the first press of one, and not at all for a click on the row already highlighted, which is
## the current pick — so choosing what was already chosen left the menu open and silent, where
## every OptionButton in the game closes and clicks.
func _choose() -> void:
	var it: TreeItem = _tree.get_selected()
	if it == null or not _popup.visible:
		return
	var key: String = str(it.get_metadata(0))
	if key == "":
		# A heading: anywhere on it opens or shuts the fold, not only its arrow.  The sound comes
		# from _on_folded, which hears the arrow too.
		it.collapsed = not it.collapsed
		return
	_popup.hide()
	# The sound an OptionButton's own menu makes for a pick, every pick — this replaced one.
	UISound.play(UISound.SELECT)
	# By KEY, not by a stored index: the panel can repopulate the option while this is open.
	var idx: int = -1
	for i in range(option.item_count):
		if option.get_item_text(i) == key:
			idx = i
			break
	if idx < 0 or idx == option.selected:
		return
	option.select(idx)
	option.item_selected.emit(idx)


## Enter, or a double-click.  A heading is left to the clicks that make up the double-click (and
## to the left and right arrows, which a Tree folds with on its own); counting the activation
## as a third toggle would leave a double-clicked heading the opposite way to how it looks.
func _on_activated() -> void:
	var it: TreeItem = _tree.get_selected()
	if it != null and str(it.get_metadata(0)) != "":
		_choose()


## Every fold sounds once, however it was made: a click on the heading's name, on its arrow (which
## the Tree handles itself and reports only here), or a key.  Not while the menu is being built,
## when the folds are set up and nobody has done anything.
func _on_folded(_item: TreeItem) -> void:
	if _popup != null and _popup.visible:
		UISound.play(UISound.MOVE)
