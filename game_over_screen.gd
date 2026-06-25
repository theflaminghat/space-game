## GameOverScreen — fullscreen extinction-event overlay.
## Attach to a CanvasLayer node (layer = 100, process_mode = ALWAYS).
extends CanvasLayer

signal restart_requested

const ENDGAME_STREAM := preload("res://endgame.mp3")
var _music_player: AudioStreamPlayer = null

const EPILOGUE_LINES: Array = [
	"Civilizations rose,",
	"civilizations fell,",
	"but for a brief moment,",
	"the universe knew itself.",
]
const EPILOGUE_HOLD  := 1.5   # seconds of pure black before first line
const EPILOGUE_FADE  := 2.5   # seconds for each line to fade in
const EPILOGUE_GAP   := 0.6   # pause between lines landing and the next starting
const EPILOGUE_PAUSE := 1.2   # beat after the last line before the button appears

var _cause_label: Label = null
var _desc_label:  Label = null
var _year_label:  Label = null
var _stats_label: Label = null
var _graph: StatsGraph  = null   # mirror of the in-game Statistics chart for this run

# ── Menu vs. cinematic layers ───────────────────────────────────────────────────
var _overlay: ColorRect       = null   # the dimmed game-over menu backdrop
var _center:  CenterContainer = null   # the game-over menu panel container
var _epilogue:        Control = null   # opaque black cinematic overlay
var _epilogue_line_labels: Array  = []   # one Label per poem line
var _epilogue_button:      Button = null
var _epilogue_tween:       Tween  = null  # held so any input can kill it and skip

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 100
	_build_ui()
	visible = false
	# Music player lives here so it can be started in show_game_over before the
	# screen goes black, giving the MP3 decoder a full frame to buffer.
	# process_mode ALWAYS keeps it running while the game sim is paused.
	_music_player = AudioStreamPlayer.new()
	_music_player.stream       = ENDGAME_STREAM
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music_player)
	# Pre-warm: play then immediately stop so the decoder initialises now
	# rather than on first extinction (avoids a cold-start gap at game start).
	_music_player.play()
	_music_player.stop()

# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Full-screen dark overlay — also blocks mouse input to the game below
	_overlay = ColorRect.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(0.0, 0.0, 0.0, 0.88)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	# CenterContainer so the panel is always centred regardless of resolution
	_center = CenterContainer.new()
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_center)
	var center := _center

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(680, 800)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	# ── "EXTINCTION" header ────────────────────────────────────────────────────
	var header := Label.new()
	header.text = "EXTINCTION"
	header.add_theme_font_size_override("font_size", 54)
	header.add_theme_color_override("font_color", Color(0.88, 0.12, 0.12))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	# ── Final year ─────────────────────────────────────────────────────────────
	_year_label = Label.new()
	_year_label.text = "Final Year: 2026"
	_year_label.add_theme_font_size_override("font_size", 17)
	_year_label.add_theme_color_override("font_color", Color(0.62, 0.65, 0.78))
	_year_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_year_label)

	vbox.add_child(HSeparator.new())

	# ── Cause (bright orange) ─────────────────────────────────────────────────
	_cause_label = Label.new()
	_cause_label.text = ""
	_cause_label.add_theme_font_size_override("font_size", 32)
	_cause_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.08))
	_cause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cause_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_cause_label)

	# ── Description ────────────────────────────────────────────────────────────
	_desc_label = Label.new()
	_desc_label.text = ""
	_desc_label.add_theme_font_size_override("font_size", 13)
	_desc_label.add_theme_color_override("font_color", Color(0.74, 0.77, 0.86))
	_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.custom_minimum_size = Vector2(560, 72)
	vbox.add_child(_desc_label)

	vbox.add_child(HSeparator.new())

	# ── Final stats row ────────────────────────────────────────────────────────
	_stats_label = Label.new()
	_stats_label.text = ""
	_stats_label.add_theme_font_size_override("font_size", 12)
	_stats_label.add_theme_color_override("font_color", Color(0.58, 0.62, 0.74))
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_stats_label)

	vbox.add_child(HSeparator.new())

	# ── Run-history graph (mirrors the in-game Statistics page) ─────────────────
	var graph_label := Label.new()
	graph_label.text = "Run History"
	graph_label.add_theme_font_size_override("font_size", 13)
	graph_label.add_theme_color_override("font_color", Color(0.58, 0.62, 0.74))
	graph_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(graph_label)

	_graph = StatsGraph.new()
	_graph.custom_minimum_size = Vector2(620, 240)
	_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_graph)

	vbox.add_child(HSeparator.new())

	# ── Buttons (stacked vertically) ─────────────────────────────────────────────
	var btn_box := VBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_box)

	var btn_new := Button.new()
	btn_new.text = "Start New Civilization"
	btn_new.add_theme_font_size_override("font_size", 16)
	btn_new.custom_minimum_size = Vector2(260, 46)
	btn_new.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn_new.pressed.connect(_on_restart_pressed)
	btn_box.add_child(btn_new)

	var btn_menu := Button.new()
	btn_menu.text = "Quit to Menu"
	btn_menu.add_theme_font_size_override("font_size", 16)
	btn_menu.custom_minimum_size = Vector2(260, 46)
	btn_menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn_menu.pressed.connect(_on_quit_to_menu_pressed)
	btn_box.add_child(btn_menu)

	var btn_desktop := Button.new()
	btn_desktop.text = "Quit to Desktop"
	btn_desktop.add_theme_font_size_override("font_size", 16)
	btn_desktop.custom_minimum_size = Vector2(260, 46)
	btn_desktop.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn_desktop.pressed.connect(_on_quit_to_desktop_pressed)
	btn_box.add_child(btn_desktop)

	_build_epilogue()

## Opaque black cinematic overlay shown first: an instant cut to black, then the
## epilogue line fades in, then a "Continue" button appears.  Drawn after the menu
## so it sits on top until the player continues.
func _build_epilogue() -> void:
	_epilogue = Control.new()
	_epilogue.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_epilogue.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_epilogue)

	var black := ColorRect.new()
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.color = Color(0.0, 0.0, 0.0, 1.0)
	_epilogue.add_child(black)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_epilogue.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	center.add_child(vbox)

	_epilogue_line_labels.clear()
	for line_text: String in EPILOGUE_LINES:
		var lbl := Label.new()
		lbl.text = line_text
		lbl.add_theme_font_size_override("font_size", 28)
		lbl.add_theme_color_override("font_color", Color(0.86, 0.88, 0.95))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.modulate = Color(1, 1, 1, 0)
		vbox.add_child(lbl)
		_epilogue_line_labels.append(lbl)

	# Spacer between poem and button
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 28)
	vbox.add_child(spacer)

	_epilogue_button = Button.new()
	_epilogue_button.text = "Continue"
	_epilogue_button.add_theme_font_size_override("font_size", 18)
	_epilogue_button.custom_minimum_size = Vector2(220, 48)
	_epilogue_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_epilogue_button.modulate = Color(1, 1, 1, 0)
	_epilogue_button.disabled = true
	_epilogue_button.pressed.connect(_on_epilogue_continue)
	vbox.add_child(_epilogue_button)

	_epilogue.visible = false

# ── Public API ────────────────────────────────────────────────────────────────

## Mirror the run's recorded history from the live Statistics graph onto this screen's
## chart, so the extinction screen shows the same series and data.
func set_graph_history(source: StatsGraph) -> void:
	if _graph == null or source == null:
		return
	_graph.series_meta   = source.series_meta.duplicate(true)
	_graph.active        = source.active.duplicate()
	_graph.history_years = source.history_years.duplicate()
	_graph.history_data  = source.history_data.duplicate(true)
	_graph._cached_vmin  = source._cached_vmin.duplicate()
	_graph._cached_vmax  = source._cached_vmax.duplicate()
	_graph.queue_redraw()

## Display the screen with cause info and final stats.
func show_game_over(cause: String, description: String, final_year: int, stats: Dictionary, people_ever_lived: float = 0.0) -> void:
	# Start the music first — gives the MP3 decoder a head-start so no frames
	# are dropped when the black screen appears on the next render.
	if _music_player and not _music_player.playing:
		_music_player.play()
	_cause_label.text = cause
	_desc_label.text  = description
	_year_label.text  = "Final Year: %s" % _fmt_year(final_year)
	_stats_label.text = _build_stats_text(stats, people_ever_lived)
	# Hide the menu and run the cinematic epilogue.
	_overlay.visible = false
	_center.visible  = false
	visible = true
	_start_epilogue()

# ── Cinematic epilogue ──────────────────────────────────────────────────────────

func _start_epilogue() -> void:
	_epilogue.visible = true
	_epilogue_button.modulate = Color(1, 1, 1, 0)
	_epilogue_button.disabled = true
	for lbl: Label in _epilogue_line_labels:
		lbl.modulate = Color(1, 1, 1, 0)

	# Chain: hold on black → fade line 1 → gap → fade line 2 → … → gap → reveal button.
	# PROCESS_MODE_ALWAYS on the CanvasLayer keeps the tween running while the sim is paused.
	_epilogue_tween = create_tween()
	_epilogue_tween.tween_interval(EPILOGUE_HOLD)
	for lbl: Label in _epilogue_line_labels:
		_epilogue_tween.tween_property(lbl, "modulate:a", 1.0, EPILOGUE_FADE)
		_epilogue_tween.tween_interval(EPILOGUE_GAP)
	_epilogue_tween.tween_interval(EPILOGUE_PAUSE)
	_epilogue_tween.tween_callback(_reveal_continue)

func _reveal_continue() -> void:
	_epilogue_tween = null
	# Snap all lines fully visible in case skip jumped here early.
	for lbl: Label in _epilogue_line_labels:
		lbl.modulate = Color(1, 1, 1, 1)
	_epilogue_button.disabled = false
	var tween := create_tween()
	tween.tween_property(_epilogue_button, "modulate:a", 1.0, 0.4)

## Any keypress or mouse click during the poem skips straight to the end.
func _input(event: InputEvent) -> void:
	if not _epilogue or not _epilogue.visible:
		return
	if _epilogue_tween == null:
		return   # already at the end
	var is_press := false
	if event is InputEventKey and event.pressed and not event.echo:
		is_press = true
	elif event is InputEventMouseButton and event.pressed:
		is_press = true
	if is_press:
		_epilogue_tween.kill()
		_epilogue_tween = null
		_reveal_continue()
		get_viewport().set_input_as_handled()

func _on_epilogue_continue() -> void:
	_epilogue.visible = false
	_overlay.visible  = true
	_center.visible   = true

# ── Helpers ───────────────────────────────────────────────────────────────────

func _build_stats_text(stats: Dictionary, people_ever_lived: float) -> String:
	var pop:   int   = int(stats.get("current_population", 0))
	var cols:  int   = int(stats.get("colony_count", 0))
	var total: float = people_ever_lived   # cumulative humans ever born
	# One stat per line, stacked vertically.
	return "Final population: %s\nColonies: %d\nTotal humans who ever lived: ~%s" % [
		_fmt_pop(pop), cols, _fmt_pop_large(total)
	]

## Format very large population figures with appropriate SI suffix.
func _fmt_pop_large(v: float) -> String:
	if v >= 1.0e18: return "%.2f Exa"  % (v * 1.0e-18)
	if v >= 1.0e15: return "%.2f Peta" % (v * 1.0e-15)
	if v >= 1.0e12: return "%.2f T"    % (v * 1.0e-12)
	if v >= 1.0e9:  return "%.2f B"    % (v * 1.0e-9)
	if v >= 1.0e6:  return "%.1f M"    % (v * 1.0e-6)
	if v >= 1.0e3:  return "%.0f K"    % (v * 1.0e-3)
	return "%.0f" % v

func _fmt_year(y: int) -> String:
	if y >= 1_000_000_000:
		return "%.3f billion" % (float(y) / 1_000_000_000.0)
	if y >= 1_000_000:
		return "%.2fM" % (float(y) / 1_000_000.0)
	if y >= 10_000:
		return "%dK" % int(float(y) / 1_000.0)
	return str(y)

func _fmt_pop(p: int) -> String:
	if p >= 1_000_000_000:
		return "%.2fB" % (float(p) / 1_000_000_000.0)
	if p >= 1_000_000:
		return "%.1fM" % (float(p) / 1_000_000.0)
	return str(p)

func _on_restart_pressed() -> void:
	if _music_player: _music_player.stop()
	visible = false
	restart_requested.emit()

func _on_quit_to_menu_pressed() -> void:
	if _music_player: _music_player.stop()
	visible = false
	SolarSystem.paused    = false
	SolarSystem.ui_paused = false
	get_tree().paused     = false
	get_tree().change_scene_to_file("res://start_menu.tscn")

func _on_quit_to_desktop_pressed() -> void:
	get_tree().quit()
