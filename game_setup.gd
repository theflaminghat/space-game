extends Control

## The setup page, shown between the start menu and a new run.
##
## It is a page rather than a dialog because the choices here are not adjustments to something
## already running — they are the terms of the run itself, fixed before the first day and, for
## most of them, not revisitable.  Options come from GameSession.options(), which fills the
## doctrine list from DoctrineData, so adding a choice in one place is enough; nothing has to be
## rebuilt in the editor to match.

const GAME_SCENE  := "res://node_3d.tscn"
const START_SCENE := "res://start_menu.tscn"
const PANEL_W: float = 660.0

var _opts: Dictionary = {}     # option id → OptionButton
var _help: Dictionary = {}     # option id → Label describing the current choice


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.07)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_W, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.12, 0.98)
	sb.border_color = Color(0.35, 0.45, 0.62)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", sb)
	centre.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "New Run"
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)

	var blurb := Label.new()
	blurb.text = "Run parameters. All but the opening doctrine are fixed once the run begins."
	blurb.add_theme_font_size_override("font_size", 12)
	blurb.modulate = Color(0.62, 0.70, 0.85)
	box.add_child(blurb)
	box.add_child(HSeparator.new())

	for opt: Dictionary in GameSession.options():
		_add_option(box, opt)

	box.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_END
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(110, 34)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(START_SCENE))
	row.add_child(back)
	var begin := Button.new()
	begin.text = "Begin"
	begin.custom_minimum_size = Vector2(140, 34)
	begin.pressed.connect(_on_begin)
	row.add_child(begin)
	box.add_child(row)


## One labelled dropdown plus the live description of whatever is selected.
func _add_option(parent: Control, opt: Dictionary) -> void:
	var id: String = str(opt["id"])
	var choices: Array = opt["choices"]
	if choices.is_empty():
		return
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var lbl := Label.new()
	lbl.text = str(opt["label"])
	lbl.custom_minimum_size = Vector2(160, 0)
	lbl.add_theme_font_size_override("font_size", 14)
	head.add_child(lbl)
	var dd := OptionButton.new()
	dd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dd.tooltip_text = str(opt.get("help", ""))
	for i in range(choices.size()):
		dd.add_item(str((choices[i] as Dictionary)["name"]), i)
	dd.select(GameSession._default_index(id))
	dd.item_selected.connect(func(_i: int) -> void: _refresh_help(id))
	head.add_child(dd)
	parent.add_child(head)

	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(PANEL_W - 60, 0)
	help.add_theme_font_size_override("font_size", 11)
	help.modulate = Color(0.60, 0.68, 0.82)
	parent.add_child(help)

	_opts[id] = dd
	_help[id] = help
	_refresh_help(id)


## Show what the selected choice actually means, not just its name.
func _refresh_help(id: String) -> void:
	var dd: OptionButton = _opts.get(id, null)
	var help: Label = _help.get(id, null)
	if dd == null or help == null:
		return
	for opt: Dictionary in GameSession.options():
		if str(opt["id"]) != id:
			continue
		var choices: Array = opt["choices"]
		help.text = str((choices[clampi(dd.selected, 0, choices.size() - 1)] as Dictionary).get("desc", ""))
		return


func _on_begin() -> void:
	GameSession.setup = {}
	for id: String in _opts:
		GameSession.setup[id] = (_opts[id] as OptionButton).selected
	GameSession.should_load_on_start = false
	get_tree().change_scene_to_file(GAME_SCENE)
