extends Node

## The noise the menus make.
##
## ── What is actually in the file ──
##
## `models/freesound_community-menu-select-sound-100466.mp3` is one take of somebody using a
## menu: a blip at 0.045 s, nearly a second of silence, five more blips between 0.907 and
## 1.549 s, and a different, lower one at 1.624 s. That is six hits and one, not seven sounds —
## the six are the same 523 Hz waveform, correlating at 0.99 to 1.00 against the first once the
## lag between them is taken out, and the last is an octave below them at 262 Hz and correlates
## at 0.07. The right channel carries the same seven a shade quieter, with nothing hidden in it.
## `tools/cut_ui_sounds.py` is what measured that, and what cut the two files below; running it
## prints the table again and writes the same bytes.
##
## So there are two sounds in there, and they are the two this game uses:
##
##   sounds/ui_move.wav    523 Hz, 122 ms — the one the take repeats, a menu being scrolled
##   sounds/ui_select.wav  262 Hz, 122 ms — the one it lands on at the end, the thing chosen
##
## Both are cut from the left channel, normalised from the take's -26 dBFS up to -3, and given a
## 1 ms fade in and an 8 ms fade out so they start and end on silence rather than on a click.
##
## ── Which control gets which ──
##
## Three roles out of those two sounds. BACK is SELECT a fourth lower, because a click that
## closes something should fall away rather than land:
##
##   MOVE    going somewhere — a sidebar page, a tab, a speed, a row, a picker. The default.
##   SELECT  doing something — building, launching, researching, trading, saving, confirming.
##   BACK    leaving — cancel, close, back, resume, dismiss.
##
## A control says which it is with `mark()`, and anything unmarked moves. The mark is looked up
## the ancestor chain, so marking a panel marks everything inside it and a button's own mark
## wins over the panel's.
##
## ── How a control gets connected ──
##
## Through `SceneTree.node_added`, once, rather than at the seventy-odd places a button is
## built. Half the buttons in this game are made in a rebuild — every recipe row, research node,
## cargo line and star-map entry is thrown away and made again whenever its panel refreshes — so
## a list of call sites would have been a list to keep up to date for ever. A control that
## enters the tree is wired; one that leaves and comes back is not wired twice.
##
## Nothing is connected to `mouse_entered` or `focus_entered`, and nothing should be: a menu
## that sounds when the pointer crosses it is a menu that sounds continuously.

## Going somewhere.
const MOVE: String = "move"
## Doing something.
const SELECT: String = "select"
## Leaving.
const BACK: String = "back"

## Where a control records its role, read up the ancestor chain by `role_of()`.
const META_ROLE: String = "ui_sound"
## Set on a control once it is connected, so a panel that is re-parented — which the planet
## tabs are, at startup — does not end up playing twice per press.
const META_WIRED: String = "ui_sound_wired"

const STREAM_MOVE: AudioStream = preload("res://sounds/ui_move.wav")
const STREAM_SELECT: AudioStream = preload("res://sounds/ui_select.wav")

## role -> [stream, pitch, volume in dB].
##
## MOVE sits lowest because it fires on nearly everything: it is the sound of using the game at
## all, and the one that would wear first. BACK is the SELECT sample at a fourth below (262 Hz
## down to 196), which is the whole of the difference between the two — there is no third
## sample, because there was no third sound in the file to cut one from.
const VOICES: Dictionary = {
	MOVE:   [STREAM_MOVE,   1.00, -14.0],
	SELECT: [STREAM_SELECT, 1.00, -10.0],
	BACK:   [STREAM_SELECT, 0.75, -12.0],
}

## role -> AudioStreamPlayer.  One each rather than one shared, so a press that closes one panel
## and opens another is two sounds instead of the second cutting the first off.
var _players: Dictionary = {}

## role -> how many times it has played.  For the tests: there is no way to ask the audio server
## what it heard, and in a headless run there is no audio server to ask.
var plays: Dictionary = {}


func _ready() -> void:
	# The pause menu is a menu too, and the game is paused behind it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for role: String in VOICES:
		var p := AudioStreamPlayer.new()
		p.name = "ui_%s" % role
		p.stream = VOICES[role][0]
		p.pitch_scale = float(VOICES[role][1])
		p.volume_db = float(VOICES[role][2])
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_players[role] = p
		plays[role] = 0
	get_tree().node_added.connect(_wire)


## Say what a control sounds like.  Takes a button or any ancestor of one: marking a panel marks
## every control in it, and a control's own mark wins over the panel's.
func mark(control: Node, role: String) -> void:
	if control != null:
		control.set_meta(META_ROLE, role)


## The role a control plays, nearest mark first, MOVE if nothing in its line says otherwise.
func role_of(control: Node) -> String:
	var n: Node = control
	while n != null:
		if n.has_meta(META_ROLE):
			return str(n.get_meta(META_ROLE))
		n = n.get_parent()
	return MOVE


## Play a role outright, for an action that is not a button press.
func play(role: String) -> void:
	var p: AudioStreamPlayer = _players.get(role)
	if p == null:
		return
	plays[role] = int(plays.get(role, 0)) + 1
	p.play()


## Connect anything that can be pressed, as it enters the tree.
##
## Three kinds, because three kinds of control in this game answer a click: buttons, the tab
## strip of a TabContainer, and the popup a dropdown opens.  A slider is deliberately not one of
## them — a sound per step of a drag is a machine gun.
func _wire(n: Node) -> void:
	if n.has_meta(META_WIRED):
		return
	if n is BaseButton:
		n.set_meta(META_WIRED, true)
		(n as BaseButton).pressed.connect(_on_pressed.bind(n))
	elif n is TabBar:
		# `tab_clicked`, not `tab_changed`: the game sets the current tab itself when it opens a
		# panel on the player's behalf, and that is not a click.
		n.set_meta(META_WIRED, true)
		(n as TabBar).tab_clicked.connect(func(_i: int) -> void: play(role_of(n)))
	elif n is PopupMenu:
		# Picking out of a dropdown settles something — a fuel, a recipe, a target — so it reads
		# as a choice rather than as navigation, whatever the button that opened it was.
		n.set_meta(META_WIRED, true)
		(n as PopupMenu).index_pressed.connect(func(_i: int) -> void: play(SELECT))


func _on_pressed(control: Node) -> void:
	play(role_of(control))
