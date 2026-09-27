class_name LaunchBodyPicker
extends Button

## A launch origin/target picker that shows bodies as a hierarchy: the planets (and the Sun, and
## the asteroid belt) at the top level, each moon folded under the planet it orbits.  Clicking a
## planet's fold arrow reveals its moons; clicking any name selects it.
##
## It drives a hidden OptionButton rather than replacing it, so everything in LaunchPanel that
## reads `option.selected` and listens to `item_selected` keeps working unchanged: a pick here is
## an `option.select(i)` plus the same `item_selected` signal a click on the option would send.

const POPUP_SIZE: Vector2i = Vector2i(280, 380)

var option: OptionButton = null
var _names: Array = []
var _ids: Array = []
var _popup: PopupPanel = null
var _tree: Tree = null
var _shown: int = -2        # the option index the button text last showed
## Ids that may be selected; empty means everything.
var _valid_ids: Array = []


func _init(opt: OptionButton = null) -> void:
	option = opt
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pressed.connect(_open)


func _ready() -> void:
	_popup = PopupPanel.new()
	add_child(_popup)
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.custom_minimum_size = Vector2(POPUP_SIZE)
	_tree.item_selected.connect(_on_tree_selected)
	_popup.add_child(_tree)


## The entries, index-aligned with the option's items: display names and body ids.  A moon's id
## is "<planet>_moon_<n>", which is how it is placed under its planet.
func set_entries(names: Array, ids: Array) -> void:
	_names = names
	_ids = ids
	_shown = -2


## Ids the current mission may actually fly to.  Everything else is shown greyed and cannot be
## picked — the hierarchy is a map of the system, so hiding entries would be worse than saying
## which ones are closed.  An empty list (the default) means no restriction.
func set_valid_ids(ids: Array) -> void:
	_valid_ids = ids


## Keep the button's label on whatever the option has selected, however it was selected.
func _process(_delta: float) -> void:
	if option == null:
		return
	var sel: int = option.selected
	if sel != _shown:
		_shown = sel
		text = ("%s  ▾" % str(_names[sel])) if sel >= 0 and sel < _names.size() else "—  ▾"


static func _parent_of(id: String) -> String:
	var i: int = id.find("_moon_")
	return id.substr(0, i) if i > 0 else ""


func _open() -> void:
	if option == null or _tree == null:
		return
	_tree.clear()
	var root: TreeItem = _tree.create_item()
	var by_id: Dictionary = {}
	var sel: int = option.selected
	var sel_parent: String = _parent_of(str(_ids[sel])) if sel >= 0 and sel < _ids.size() else ""
	# Top level first (bodies that orbit the Sun), then every moon under its planet.
	for i in range(_ids.size()):
		var id: String = str(_ids[i])
		if _parent_of(id) != "":
			continue
		var it: TreeItem = _tree.create_item(root)
		it.set_text(0, str(_names[i]))
		it.set_metadata(0, i)
		it.collapsed = id != sel_parent          # open only the branch holding the current pick
		_mark_validity(it, id)
		by_id[id] = it
	for i in range(_ids.size()):
		var id: String = str(_ids[i])
		var parent_id: String = _parent_of(id)
		if parent_id == "":
			continue
		var parent: TreeItem = by_id.get(parent_id, root)
		var it: TreeItem = _tree.create_item(parent)
		it.set_text(0, str(_names[i]))
		it.set_metadata(0, i)
		_mark_validity(it, id)
		by_id[id] = it
	# Highlight the current pick.  This fires item_selected, but the popup is not open yet, which
	# is how _on_tree_selected tells it from a real pick.
	if sel >= 0 and sel < _ids.size() and by_id.has(str(_ids[sel])):
		(by_id[str(_ids[sel])] as TreeItem).select(0)
	var at: Vector2 = get_screen_position() + Vector2(0.0, size.y)
	_popup.popup(Rect2i(Vector2i(at), Vector2i(maxi(int(size.x), POPUP_SIZE.x), POPUP_SIZE.y)))


## Grey an entry the current mission cannot reach, and make it unselectable.
func _mark_validity(item: TreeItem, id: String) -> void:
	if _valid_ids.is_empty() or _valid_ids.has(id):
		return
	item.set_custom_color(0, Color(0.50, 0.52, 0.58))
	item.set_selectable(0, false)
	item.set_tooltip_text(0, "This mission cannot fly here")


func _on_tree_selected() -> void:
	var it: TreeItem = _tree.get_selected()
	if it == null or not _popup.visible:
		return
	var idx: int = int(it.get_metadata(0))
	_popup.hide()
	if idx == option.selected:
		return
	option.select(idx)
	option.item_selected.emit(idx)
