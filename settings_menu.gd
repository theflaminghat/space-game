## SettingsMenu — in-game settings panel accessible from the pause menu.
## Attach to a CanvasLayer (layer = 101, process_mode = ALWAYS).
## Settings are persisted to user://settings.cfg via Godot's ConfigFile.
extends CanvasLayer

signal closed

const SETTINGS_PATH := "user://settings.cfg"
## Autosave intervals in real seconds (0 = disabled).
const AUTOSAVE_SECONDS: Array[int] = [0, 300, 600, 1800]

# ── Control references ────────────────────────────────────────────────────────
var _fullscreen_btn:   CheckButton  = null
var _vsync_btn:        CheckButton  = null
var _aa_option:        OptionButton = null
var _volume_slider:    HSlider      = null
var _volume_val_label: Label        = null
var _speed_option:     OptionButton = null
var _autosave_option:  OptionButton = null

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 101
	_build_ui()
	visible = false
	_load_and_apply()

# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Click-blocker overlay so the game isn't interactive while settings are open
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.0, 0.0, 0.0, 0.72)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# ── Title ─────────────────────────────────────────────────────────────────
	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	vbox.add_child(_sep())

	# ── Display ───────────────────────────────────────────────────────────────
	_section(vbox, "Display")
	_fullscreen_btn = _check_row(vbox, "Fullscreen")
	_fullscreen_btn.toggled.connect(_on_fullscreen_toggled)
	_vsync_btn = _check_row(vbox, "V-Sync")
	_vsync_btn.toggled.connect(_on_vsync_toggled)

	var aa_row := HBoxContainer.new()
	vbox.add_child(aa_row)
	var aa_lbl := Label.new()
	aa_lbl.text = "Anti-Aliasing"
	aa_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aa_row.add_child(aa_lbl)
	_aa_option = OptionButton.new()
	_aa_option.add_item("Off")
	_aa_option.add_item("FXAA")
	_aa_option.add_item("MSAA 2×")
	_aa_option.add_item("MSAA 4×")
	_aa_option.add_item("MSAA 8×")
	_aa_option.add_item("MSAA 16×")
	_aa_option.selected = 5
	_aa_option.custom_minimum_size = Vector2(150, 0)
	_aa_option.item_selected.connect(_on_aa_changed)
	aa_row.add_child(_aa_option)

	vbox.add_child(_sep())

	# ── Audio ─────────────────────────────────────────────────────────────────
	_section(vbox, "Audio")

	var vol_row := HBoxContainer.new()
	vbox.add_child(vol_row)
	var vol_lbl := Label.new()
	vol_lbl.text = "Master Volume"
	vol_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vol_row.add_child(vol_lbl)
	_volume_val_label = Label.new()
	_volume_val_label.text = "100%"
	_volume_val_label.custom_minimum_size = Vector2(44, 0)
	_volume_val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vol_row.add_child(_volume_val_label)

	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 1.0
	_volume_slider.step = 0.01
	_volume_slider.value = 1.0
	_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume_slider.value_changed.connect(_on_volume_changed)
	vbox.add_child(_volume_slider)
	vbox.add_child(_sep())

	# ── Gameplay ──────────────────────────────────────────────────────────────
	_section(vbox, "Gameplay")

	var speed_row := HBoxContainer.new()
	vbox.add_child(speed_row)
	var speed_lbl := Label.new()
	speed_lbl.text = "Default Game Speed"
	speed_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_row.add_child(speed_lbl)
	_speed_option = OptionButton.new()
	_speed_option.add_item("Slow  (0.25×)")
	_speed_option.add_item("Normal  (1×)")
	_speed_option.add_item("Fast  (4×)")
	_speed_option.selected = 1
	_speed_option.custom_minimum_size = Vector2(150, 0)
	speed_row.add_child(_speed_option)

	var autosave_row := HBoxContainer.new()
	vbox.add_child(autosave_row)
	var autosave_lbl := Label.new()
	autosave_lbl.text = "Auto-save Interval"
	autosave_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	autosave_row.add_child(autosave_lbl)
	_autosave_option = OptionButton.new()
	_autosave_option.add_item("Off")
	_autosave_option.add_item("Every 5 min")
	_autosave_option.add_item("Every 10 min")
	_autosave_option.add_item("Every 30 min")
	_autosave_option.selected = 0
	_autosave_option.custom_minimum_size = Vector2(150, 0)
	autosave_row.add_child(_autosave_option)
	vbox.add_child(_sep())

	# ── Close button ──────────────────────────────────────────────────────────
	var close_btn := Button.new()
	close_btn.text = "Apply & Close"
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.custom_minimum_size = Vector2(220, 46)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(_on_close_pressed)
	vbox.add_child(close_btn)

# ── Builder helpers ───────────────────────────────────────────────────────────

func _section(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.45, 0.75, 1.0))
	parent.add_child(lbl)

func _check_row(parent: VBoxContainer, label_text: String) -> CheckButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var btn := CheckButton.new()
	row.add_child(btn)
	return btn

func _sep() -> HSeparator:
	return HSeparator.new()

# ── Persistence ───────────────────────────────────────────────────────────────

func _load_and_apply() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		_fullscreen_btn.set_pressed_no_signal(bool(cfg.get_value("display",  "fullscreen",         false)))
		_vsync_btn.set_pressed_no_signal(     bool(cfg.get_value("display",  "vsync",              true)))
		_aa_option.selected =                  int(cfg.get_value("display",  "aa_idx",             5))
		_volume_slider.value =             float(cfg.get_value("audio",    "master_volume",       1.0))
		_speed_option.selected  =           int(cfg.get_value("gameplay", "default_speed_idx",  1))
		_autosave_option.selected =         int(cfg.get_value("gameplay", "autosave_idx",        0))
	_volume_val_label.text = "%d%%" % int(_volume_slider.value * 100.0)
	_apply_display()
	_apply_volume(_volume_slider.value)

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display",  "fullscreen",        _fullscreen_btn.button_pressed)
	cfg.set_value("display",  "vsync",             _vsync_btn.button_pressed)
	cfg.set_value("display",  "aa_idx",            _aa_option.selected)
	cfg.set_value("audio",    "master_volume",     _volume_slider.value)
	cfg.set_value("gameplay", "default_speed_idx", _speed_option.selected)
	cfg.set_value("gameplay", "autosave_idx",      _autosave_option.selected)
	cfg.save(SETTINGS_PATH)

# ── Applying ──────────────────────────────────────────────────────────────────

func _apply_display() -> void:
	_on_fullscreen_toggled(_fullscreen_btn.button_pressed)
	_on_vsync_toggled(_vsync_btn.button_pressed)
	_apply_aa(_aa_option.selected)

func _apply_aa(idx: int) -> void:
	var vp: Viewport = get_viewport()
	match idx:
		0: # Off
			vp.msaa_3d        = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		1: # FXAA — post-process; lowest cost, slight softening
			vp.msaa_3d        = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		2: # MSAA 2×
			vp.msaa_3d        = Viewport.MSAA_2X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		3: # MSAA 4×
			vp.msaa_3d        = Viewport.MSAA_4X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		4: # MSAA 8×
			vp.msaa_3d         = Viewport.MSAA_8X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		5: # MSAA 16× — MSAA 8× + FXAA (Godot 4 has no native 16× enum)
			vp.msaa_3d         = Viewport.MSAA_8X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA

func _apply_volume(vol: float) -> void:
	var db: float = linear_to_db(maxf(vol, 0.0001))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), db)

# ── Public getters (read by Game.gd) ─────────────────────────────────────────

## Speed multiplier to apply at the start of a new game (0.25 / 1.0 / 4.0).
func get_default_speed_mult() -> float:
	match _speed_option.selected:
		0: return 0.25
		2: return 4.0
		_: return 1.0

## Autosave interval in real seconds; 0 means disabled.
func get_autosave_seconds() -> int:
	return AUTOSAVE_SECONDS[_autosave_option.selected]

# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_fullscreen_toggled(pressed: bool) -> void:
	if pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		_apply_windowed_to_screen()

## Windowed mode sized to the monitor the window is on, instead of reverting to the
## fixed 2560×1080 design resolution.  The canvas_items/keep_height stretch then
## scales the UI to whatever size we pick, so the game fits any screen.
func _apply_windowed_to_screen() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var screen := DisplayServer.window_get_current_screen()
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(screen)
	# Fill ~92% of the usable area (leaving room for the title bar / taskbar).
	var win := Vector2i(int(usable.size.x * 0.92), int(usable.size.y * 0.92))
	win.x = mini(win.x, usable.size.x)
	win.y = mini(win.y, usable.size.y)
	DisplayServer.window_set_size(win)
	DisplayServer.window_set_position(usable.position + (usable.size - win) / 2)

func _on_vsync_toggled(pressed: bool) -> void:
	var mode := (DisplayServer.VSYNC_ENABLED
		if pressed else DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_vsync_mode(mode)

func _on_volume_changed(val: float) -> void:
	_volume_val_label.text = "%d%%" % int(val * 100.0)
	_apply_volume(val)

func _on_aa_changed(idx: int) -> void:
	_apply_aa(idx)

func _on_close_pressed() -> void:
	save_settings()
	visible = false
	closed.emit()
