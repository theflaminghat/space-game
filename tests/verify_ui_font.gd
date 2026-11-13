extends SceneTree

## The UI font draws every symbol the menus use from a fixed fallback, never by searching.
##
## Godot's own font (Open Sans) has no arrows, triangles, ⚙ or ✕, and with its system fallback on
## it asked the operating system for a font that had them afresh for every piece of text — about
## five milliseconds a label.  The Infrastructure tab carries a "↑" on every upgrade button and a
## "▶" and "⚙" on every card, and opening it froze the game for two seconds.  UIPalette.font()
## gives the engine's font named fallbacks, which are consulted before the search is reached.
##
## The search is still there as the last resort, so a character no fallback covers is drawn — but
## slowly, which is the bug again.  So this sweeps every string literal in the source for
## characters outside ASCII and checks each one is covered.  A new symbol that fails here wants a
## font in UIPalette.SYMBOL_FONTS that has it.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

## Every character above ASCII inside a string literal, in every script and scene: what the game
## can actually put on screen.  Comments are dropped first, roughly — they hold far more unicode
## than the strings do, and none of it is ever drawn.
func _used_characters() -> Dictionary:
	var lit := RegEx.new()
	lit.compile("\"((?:[^\"\\\\\\n]|\\\\.)*)\"")
	var esc := RegEx.new()
	esc.compile("\\\\u([0-9a-fA-F]{4})")
	var out: Dictionary = {}
	for f: String in DirAccess.get_files_at("res://"):
		if not (f.ends_with(".gd") or f.ends_with(".tscn")):
			continue
		for line: String in FileAccess.get_file_as_string("res://" + f).split("\n"):
			var code: String = line.get_slice("#", 0) if f.ends_with(".gd") else line
			for m: RegExMatch in lit.search_all(code):
				var s: String = m.get_string(1)
				for e: RegExMatch in esc.search_all(s):
					s = s.replace(e.get_string(0), String.chr(e.get_string(1).hex_to_int()))
				for i in range(s.length()):
					var cp: int = s.unicode_at(i)
					if cp > 127:
						out[cp] = f
	return out

func _shape_ms(f: Font, text: String, n: int = 60) -> float:
	var t0 := Time.get_ticks_usec()
	for i in range(n):
		var tl := TextLine.new()
		tl.add_string("%s %d" % [text, i], f, 16)   # a different string each time: no reuse
		tl.get_size()
	return float(Time.get_ticks_usec() - t0) / 1000.0 / n

func _run() -> void:
	# GameSession has built the UI theme by now, which is what calls UIPalette.font().
	await process_frame
	var ts := TextServerManager.get_primary_interface()
	var f: Font = ThemeDB.fallback_font
	var gs: Node = root.get_node("GameSession")

	# ── The engine's font is the one fixed, and the UI theme uses it ──
	check(gs.ui_theme.default_font == f, "the UI theme's default font is the engine's")
	check(f.fallbacks.size() == load("res://ui_palette.gd").SYMBOL_FONTS.size(),
		"with the symbol fonts as fallbacks: %d" % f.fallbacks.size())
	# The search stays on behind them, so nothing the fallbacks miss is ever a box.
	check(ts.font_is_allow_system_fallback(f.get_rids()[0]),
		"the system search is still there as the last resort")

	# ── Every character the game uses is in the font or a fallback ──
	var used: Dictionary = _used_characters()
	check(used.size() > 20, "the sweep found the game's characters: %d" % used.size())
	var boxes: Array = []
	var from_fallback: int = 0
	for cp: int in used:
		if f.has_char(cp):
			continue            # Font.has_char looks through the fallbacks as well
		boxes.append("U+%04X %s (%s)" % [cp, String.chr(cp), used[cp]])
	var own: RID = f.get_rids()[0]      # the font itself; the rest of get_rids() is its fallbacks
	for cp: int in used:
		if not ts.font_has_char(own, cp) and f.has_char(cp):
			from_fallback += 1
	print("%d characters used, %d drawn from a fallback" % [used.size(), from_fallback])
	check(boxes.is_empty(),
		"every character used is covered, so none goes to the slow search: %s" % str(boxes))
	check(from_fallback > 0, "and the fallbacks are doing the work: %d" % from_fallback)

	# ── And a symbol costs what plain text does ──
	# The regression itself.  Before the fix a line with an arrow in it took about thirty times as
	# long to lay out as one without; the margin here is wide so a slow machine cannot trip it.
	_shape_ms(f, "warm")       # load the fallback faces before timing anything
	_shape_ms(f, "↑")
	var plain: float = _shape_ms(f, "+10")
	var arrow: float = _shape_ms(f, "↑10")
	var gear: float = _shape_ms(f, "+3⚙")
	print("layout: plain %.4f ms, arrow %.4f ms, gear %.4f ms" % [plain, arrow, gear])
	check(arrow < maxf(plain * 5.0, 0.2), "an arrow lays out like plain text: %.4f vs %.4f ms" % [arrow, plain])
	check(gear < maxf(plain * 5.0, 0.2), "and so does a gear: %.4f vs %.4f ms" % [gear, plain])

	print("FAILS: %d" % fails)
	quit()
