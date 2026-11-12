class_name AchievementsPage
extends Control

## What this run has been remembered for, and what it could be.
##
## Game owns the record; this only asks. `set_earned()` is pushed in when the page is opened and
## whenever one is awarded, so what is on screen and what is in the save cannot disagree.
##
## ── Why the unearned ones are listed at all ──
##
## The milestone groups are the only place the game says out loud what it expects you to do.
## A player who opens this in their first minute should come away knowing that settling the
## system, replicating, enclosing a star and taking a planet apart are all things that happen
## here — none of which the opening screen tells them.
##
## The failures are the exception and are kept as locked rows until earned: the game springs an
## asteroid, a pandemic and a war on you, and naming them in advance turns each one from an event
## into a countdown.

const EARNED_COLOR:   Color = UIPalette.GOOD
const PENDING_COLOR:  Color = UIPalette.TEXT
const LOCKED_COLOR:   Color = UIPalette.DISABLED
const NOTE_COLOR:     Color = UIPalette.DIM
const HEADING_COLOR:  Color = UIPalette.HEADER

var _list: VBoxContainer = null
var _summary: Label = null
## The run record, and the text form of it for the clipboard. Both pushed in by Game.
var _record: GridContainer = null
var _copy: Button = null
var _record_text: String = ""
## id → the year earned, as Game last pushed it.
var _earned: Dictionary = {}


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	PanelBackground.attach(self)

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	margin.add_child(col)

	var title := Label.new()
	title.text = "Achievements"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UIPalette.TITLE)
	col.add_child(title)

	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", 11)
	_summary.modulate = NOTE_COLOR
	col.add_child(_summary)

	# The run as a record, above the list. The same rows the ending screen shows, because a
	# record only readable once you have lost is not a record you can play toward.
	_record = GridContainer.new()
	_record.columns = 2
	_record.add_theme_constant_override("h_separation", 22)
	_record.add_theme_constant_override("v_separation", 1)
	col.add_child(_record)

	_copy = Button.new()
	_copy.text = "Copy record"
	_copy.add_theme_font_size_override("font_size", 10)
	_copy.custom_minimum_size = Vector2(128, 22)
	_copy.pressed.connect(_on_copy)
	UISound.mark(_copy, UISound.SELECT)
	var copy_row := HBoxContainer.new()
	copy_row.add_child(_copy)
	col.add_child(copy_row)
	col.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 3)
	scroll.add_child(_list)

	_rebuild()


## Game pushes the record. Rebuilds, so a newly-earned one appears without reopening the page.
func set_earned(earned: Dictionary) -> void:
	_earned = earned
	if _list != null:
		_rebuild()


## The run so far, as Game.run_summary() builds it, plus the text form for the clipboard.
func set_record(rows: Array, text: String) -> void:
	_record_text = text
	if _record == null:
		return
	for c in _record.get_children():
		c.queue_free()
	for row: Array in rows:
		var k := Label.new()
		k.text = str(row[0])
		k.add_theme_font_size_override("font_size", 11)
		k.add_theme_color_override("font_color", LOCKED_COLOR)
		_record.add_child(k)
		var v := Label.new()
		v.text = str(row[1])
		v.add_theme_font_size_override("font_size", 11)
		v.add_theme_color_override("font_color", PENDING_COLOR)
		_record.add_child(v)


func _on_copy() -> void:
	if _record_text == "":
		return
	DisplayServer.clipboard_set(_record_text)
	_copy.text = "Copied"


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()

	var total: int = 0
	var got: int = 0
	for a: Dictionary in AchievementData.ACHIEVEMENTS:
		# A hidden one is not part of the count until it is earned — otherwise the total quietly
		# tells the player how many ways there are to lose.
		var hidden: bool = bool(a.get("hidden", false))
		var have: bool = _earned.has(str(a["id"]))
		if have:
			got += 1
		if not hidden or have:
			total += 1
	_summary.text = "%d of %d" % [got, total]

	for group: String in AchievementData.GROUP_ORDER:
		var rows: Array = AchievementData.in_group(group)
		# A group that is nothing but unearned hidden rows is not shown at all — an empty
		# "How It Ended" heading is the same spoiler as listing its contents.
		var any_visible: bool = false
		for a: Dictionary in rows:
			if not bool(a.get("hidden", false)) or _earned.has(str(a["id"])):
				any_visible = true
				break
		if not any_visible:
			continue

		var head := Label.new()
		head.text = str(AchievementData.GROUP_LABELS.get(group, group))
		head.add_theme_font_size_override("font_size", 13)
		head.add_theme_color_override("font_color", HEADING_COLOR)
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(0, 8)
		_list.add_child(pad)
		_list.add_child(head)

		for a: Dictionary in rows:
			var id: String = str(a["id"])
			var have: bool = _earned.has(id)
			if bool(a.get("hidden", false)) and not have:
				_list.add_child(_locked_row())
				continue
			_list.add_child(_row(a, have))


## One achievement. Earned rows carry the year and the nod; unearned ones carry the condition.
func _row(a: Dictionary, have: bool) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	box.add_child(top)

	var mark := Label.new()
	mark.text = "✦" if have else "·"
	mark.custom_minimum_size = Vector2(14, 0)
	mark.add_theme_color_override("font_color", EARNED_COLOR if have else LOCKED_COLOR)
	top.add_child(mark)

	var name_lbl := Label.new()
	name_lbl.text = str(a["name"])
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", EARNED_COLOR if have else PENDING_COLOR)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_lbl)

	if have:
		var yr := Label.new()
		# Plain below ten thousand and SI above it: a run spends most of its length in years
		# with more digits than a label can carry, and "1945" is not "1.9 kyr".
		var y: float = float(_earned[str(a["id"])])
		yr.text = str(int(y)) if absf(y) < 10000.0 else Units.format_si(y, "")
		yr.add_theme_font_size_override("font_size", 10)
		yr.add_theme_color_override("font_color", NOTE_COLOR)
		top.add_child(yr)

	var sub := Label.new()
	# The nod is only shown once earned: before that it would give away what the condition is.
	var note: String = str(a.get("note", ""))
	sub.text = ("%s  ·  %s" % [str(a["desc"]), note]) if (have and note != "") else str(a["desc"])
	sub.add_theme_font_size_override("font_size", 10)
	sub.add_theme_color_override("font_color", LOCKED_COLOR)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var indent := MarginContainer.new()
	indent.add_theme_constant_override("margin_left", 20)
	indent.add_child(sub)
	box.add_child(indent)
	return box


## A hidden achievement nobody has earned: it exists, and that is all it says.
func _locked_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var mark := Label.new()
	mark.text = "·"
	mark.custom_minimum_size = Vector2(14, 0)
	mark.add_theme_color_override("font_color", LOCKED_COLOR)
	row.add_child(mark)
	var lbl := Label.new()
	lbl.text = "— not yet —"
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", LOCKED_COLOR)
	row.add_child(lbl)
	return row
