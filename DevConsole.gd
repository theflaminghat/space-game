extends CanvasLayer
class_name DevConsole

## Developer console.  Toggle with the backtick (`) key.  Type `help` for commands.
## Wired to Game.gd so commands can trigger extinction events and other state.

var _game: Node = null

var _panel:      PanelContainer
var _output:     RichTextLabel
var _cmd_input:  LineEdit   # NOT named _input — that would clash with the _input() virtual
var _open: bool = false

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS   # works even while the game is paused
	_build_ui()
	_set_open(false)
	_log("[color=#7fb0ff]Developer console.[/color] Type [color=#ffd24a]help[/color] for commands.")

## Called by Game.gd so commands can reach game state.
func setup(game: Node) -> void:
	_game = game

# ── UI ────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 0.0
	_panel.offset_bottom = 340.0
	add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	_output = RichTextLabel.new()
	_output.bbcode_enabled = true
	_output.scroll_following = true
	_output.selection_enabled = true
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.custom_minimum_size = Vector2(0, 280)
	_output.add_theme_font_size_override("normal_font_size", 13)
	vbox.add_child(_output)

	_cmd_input = LineEdit.new()
	_cmd_input.placeholder_text = "command…  (try: help)"
	_cmd_input.text_submitted.connect(_on_submit)
	vbox.add_child(_cmd_input)

# ── Toggle / input ──────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_QUOTELEFT:           # backtick toggles, never gets typed
			_set_open(not _open)
			get_viewport().set_input_as_handled()
		elif _open and key.keycode == KEY_ESCAPE:
			_set_open(false)
			get_viewport().set_input_as_handled()

func _set_open(open: bool) -> void:
	_open = open
	if _panel:
		_panel.visible = open
	if open and _cmd_input:
		_cmd_input.clear()
		_cmd_input.grab_focus()

# ── Command handling ──────────────────────────────────────────────────────────

func _on_submit(text: String) -> void:
	_cmd_input.clear()
	var cmd := text.strip_edges()
	if cmd == "":
		return
	_log("[color=#888888]> %s[/color]" % cmd)
	_run(cmd)
	_cmd_input.grab_focus()

func _run(cmd: String) -> void:
	var parts := cmd.split(" ", false)
	var name := (parts[0] as String).to_lower()
	var args: Array = parts.slice(1)

	if _game == null and name != "help":
		_err("game reference not set")
		return

	match name:
		"help":
			_log("Commands:")
			_log("  [color=#ffd24a]impact[/color]            — trigger an asteroid impact now")
			_log("  [color=#ffd24a]solar[/color] | redgiant  — extinction: solar envelope expansion")
			_log("  [color=#ffd24a]nebula[/color]            — extinction: planetary nebula")
			_log("  [color=#ffd24a]extinct[/color] [cause…]  — generic extinction with a custom cause")
			_log("  [color=#ffd24a]sandbox[/color]           — (re)write the god-mode sandbox save slot")
			_log("  [color=#ffd24a]clear[/color]             — clear this log")
			_log("  [color=#ffd24a]close[/color]             — close the console")
		"impact":
			if _game.has_method("_trigger_asteroid_impact"):
				_game._trigger_asteroid_impact()
				_ok("asteroid impact triggered")
			else:
				_err("impact handler not found")
		"solar", "redgiant":
			_extinct("Solar envelope expansion",
				"Sol's photosphere now encloses every inhabited world. Inhabited worlds outside the photosphere: 0.")
		"nebula":
			_extinct("Planetary nebula",
				"Sol has ejected its outer envelope. System-wide ultraviolet flux exceeds habitable tolerance. Inhabited worlds: 0.")
		"extinct":
			var cause := " ".join(args) if not args.is_empty() else "Console-triggered extinction"
			_extinct(cause, "Extinction triggered from the developer console.")
		"sandbox":
			SandboxSave.write()
			_ok("wrote sandbox save → load \"%s\" from the start menu" % SandboxSave.SLOT_NAME)
		"clear":
			_output.clear()
		"close":
			_set_open(false)
		_:
			_err("unknown command: %s  (type help)" % name)

func _extinct(cause: String, desc: String) -> void:
	if not _game.has_method("trigger_game_over"):
		_err("trigger_game_over not found")
		return
	if _game.get("game_over"):
		_log("[color=#888888]already extinct — re-triggering[/color]")
	_game.trigger_game_over(cause, desc)
	_ok("extinction: %s" % cause)

# ── Output helpers ──────────────────────────────────────────────────────────────

func _log(s: String) -> void:
	if _output:
		_output.append_text(s + "\n")

func _ok(s: String) -> void:
	_log("[color=#5fd07a]%s[/color]" % s)

func _err(s: String) -> void:
	_log("[color=#e06a4a]%s[/color]" % s)
