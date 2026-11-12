extends SceneTree

## The menus make a noise, and only when something is done.
##
## There is no way to ask the audio server what it played, and in a headless run there is no
## audio server to ask — so what is checked is the layer above it: that every control that can
## be pressed is connected exactly once, that the connection is to `pressed` and nothing that a
## pointer crossing the screen can fire, and that each control resolves to the role its kind of
## menu item is supposed to have.
##
## The source file holds two sounds, not six: the hit at 0.045 s is repeated five more times
## between 0.907 and 1.549 s, and only the one at 1.624 s is a different waveform. So three
## roles are built out of two samples, and that is asserted here rather than left as a comment
## nobody checks — a third sample appearing would mean somebody had invented a sound.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var us: Node = root.get_node_or_null("UISound")
	check(us != null, "the UISound autoload is running")
	if us == null:
		print("FAILS: %d" % fails)
		quit()
		return

	# ── Two samples, three roles ──
	var streams: Array = []
	for role: String in us.VOICES:
		var voice: Array = us.VOICES[role]
		var st: AudioStream = voice[0]
		check(st != null, "%s has a sound" % role)
		check(st.get_length() > 0.05 and st.get_length() < 0.3,
			"%s is a blip rather than a tune: %.3f s" % [role, st.get_length()])
		if not streams.has(st):
			streams.append(st)
	check(streams.size() == 2,
		"three roles are made out of the two sounds in the file: %d" % streams.size())
	check(us.VOICES[us.BACK][0] == us.VOICES[us.SELECT][0],
		"leaving is the same sample as choosing")
	check(float(us.VOICES[us.BACK][1]) < float(us.VOICES[us.SELECT][1]),
		"pitched down, so it falls away instead of landing: %f vs %f" % [
			float(us.VOICES[us.BACK][1]), float(us.VOICES[us.SELECT][1])])
	check(us.VOICES[us.MOVE][0] != us.VOICES[us.SELECT][0],
		"and going somewhere does not sound like doing something")

	# ── A player per role, and they run while the game does not ──
	#
	# The pause menu is a menu too. A player left on the default process mode is silent exactly
	# when the player is looking at the menu that pauses the game.
	for role: String in us.VOICES:
		var p: AudioStreamPlayer = us._players.get(role)
		check(p != null, "%s has a player" % role)
		if p != null:
			check(p.process_mode == Node.PROCESS_MODE_ALWAYS,
				"%s plays while the game is paused" % role)
	check(us.process_mode == Node.PROCESS_MODE_ALWAYS, "and so does the autoload holding them")

	# ── Every button is connected, once ──
	var buttons: Array = g.get_node("main_ui").find_children("*", "BaseButton", true, false)
	check(buttons.size() > 50, "there are buttons to check: %d" % buttons.size())
	var unwired: Array = []
	for n: Node in buttons:
		if not n.has_meta(us.META_WIRED):
			unwired.append(str(n.name))
	check(unwired.is_empty(), "every button is wired: %s" % str(unwired.slice(0, 6)))

	var btn: Button = g.get_node("main_ui/VBoxContainer3/HBoxContainer2/sidebar/research")
	var before: int = int(us.plays[us.MOVE])
	btn.pressed.emit()
	btn.pressed.emit()
	check(int(us.plays[us.MOVE]) - before == 2,
		"two presses are two sounds, not four: %d" % (int(us.plays[us.MOVE]) - before))

	# ── And nothing a pointer can do on its own makes a noise ──
	#
	# The whole of the request: a menu that sounds when the pointer crosses it is a menu that
	# sounds continuously. Asserted twice — the counter does not move, and there is no
	# connection to either signal for it to move through.
	var quiet: int = int(us.plays[us.MOVE])
	btn.mouse_entered.emit()
	btn.mouse_exited.emit()
	btn.focus_entered.emit()
	check(int(us.plays[us.MOVE]) == quiet,
		"hovering and focusing are silent: %d vs %d" % [int(us.plays[us.MOVE]), quiet])
	var listening: Array = []
	for sig: String in ["mouse_entered", "mouse_exited", "focus_entered"]:
		for c: Dictionary in btn.get_signal_connection_list(sig):
			if c["callable"].get_object() == us:
				listening.append(sig)
	check(listening.is_empty(), "and nothing is listening for them: %s" % str(listening))

	# ── A control says what kind of menu item it is ──
	var plain := Button.new()
	g.add_child(plain)
	await process_frame
	check(us.role_of(plain) == us.MOVE, "an unmarked button navigates: %s" % us.role_of(plain))
	var panel := Control.new()
	g.add_child(panel)
	var inner := Button.new()
	panel.add_child(inner)
	await process_frame
	us.mark(panel, us.SELECT)
	check(us.role_of(inner) == us.SELECT,
		"marking a panel marks what is in it: %s" % us.role_of(inner))
	us.mark(inner, us.BACK)
	check(us.role_of(inner) == us.BACK,
		"and a button's own mark wins over its panel's: %s" % us.role_of(inner))
	# Re-parenting must not connect it a second time: the planet panel's pages are moved into a
	# TabContainer at startup, so this is the real case and not a hypothetical one.
	panel.remove_child(inner)
	g.add_child(inner)
	await process_frame
	var twice: int = int(us.plays[us.BACK])
	inner.pressed.emit()
	check(int(us.plays[us.BACK]) - twice == 1,
		"a re-parented button still sounds once: %d" % (int(us.plays[us.BACK]) - twice))
	plain.queue_free()
	inner.queue_free()
	panel.queue_free()

	# ── The kinds, on the real controls ──
	#
	# One from each: the sidebar opens a page, the launch button spends a rocket, the star map's
	# dialog cancel backs out of one.
	for spec: Array in [
			["main_ui/VBoxContainer3/HBoxContainer2/sidebar/research", us.MOVE],
			["main_ui/VBoxContainer3/HBoxContainer2/sidebar/politics", us.MOVE]]:
		var c: Node = g.get_node_or_null(str(spec[0]))
		check(c != null, "%s is there" % str(spec[0]))
		if c != null:
			check(us.role_of(c) == str(spec[1]),
				"%s is %s: %s" % [str(spec[0]), str(spec[1]), us.role_of(c)])
	check(us.role_of(g.launch_panel.launch_button) == us.SELECT,
		"launching commits: %s" % us.role_of(g.launch_panel.launch_button))
	check(us.role_of(g.sidebar.star_map._dlg_confirm) == us.SELECT,
		"and so does confirming a star-map action: %s" % us.role_of(
			g.sidebar.star_map._dlg_confirm))
	var sm_cancel: Node = g.sidebar.star_map._dlg_confirm.get_parent().get_node_or_null("cancel")
	if sm_cancel == null:
		for n: Node in g.sidebar.star_map._dlg_confirm.get_parent().get_children():
			if n is Button and str((n as Button).text).to_lower().contains("cancel"):
				sm_cancel = n
	check(sm_cancel != null, "the star map's dialog has a cancel")
	if sm_cancel != null:
		check(us.role_of(sm_cancel) == us.BACK,
			"cancelling leaves: %s" % us.role_of(sm_cancel))
	# The speed buttons are navigation, and there are a lot of them: a commit sound on every
	# change of pace would be the loudest thing in the game.
	var speeds: int = 0
	for n: Node in g.get_node("main_ui").find_children("*", "Button", true, false):
		if str((n as Button).text).ends_with("×"):
			speeds += 1
			check(us.role_of(n) == us.MOVE, "a speed button navigates: %s" % str((n as Button).text))
	check(speeds >= 5, "the speed ladder is read: %d" % speeds)

	# ── A tab the player clicks sounds; one the game switches does not ──
	#
	# Game moves the planet panel to a tab of its own when it opens one, and the forecast and
	# the tests move it too. Those are not clicks.
	var bar: TabBar = (g._planet_tabs as TabContainer).get_tab_bar()
	check(bar != null, "the planet panel has a tab strip")
	if bar != null:
		var tabs_before: int = int(us.plays[us.MOVE])
		g._planet_tabs.current_tab = 1
		await process_frame
		g._planet_tabs.current_tab = 0
		await process_frame
		check(int(us.plays[us.MOVE]) == tabs_before,
			"switching a tab in code is silent: %d vs %d" % [
				int(us.plays[us.MOVE]), tabs_before])
		bar.tab_clicked.emit(1)
		check(int(us.plays[us.MOVE]) == tabs_before + 1,
			"clicking one is not: %d vs %d" % [int(us.plays[us.MOVE]), tabs_before])
		# And wiring it again — which is what a node leaving and re-entering the tree does —
		# must not leave two connections on it. A button is safe either way, because Godot
		# refuses a second identical connection; a tab strip and a popup are connected through
		# a lambda, and a fresh lambda is never equal to the last one, so nothing but the guard
		# stops those two from sounding twice per click for ever.
		us._wire(bar)
		var again: int = int(us.plays[us.MOVE])
		bar.tab_clicked.emit(1)
		check(int(us.plays[us.MOVE]) == again + 1,
			"and wiring the strip twice does not play it twice: %d" % (
				int(us.plays[us.MOVE]) - again))

	print("FAILS: %d" % fails)
	quit()
