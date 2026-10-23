extends CanvasLayer
class_name DevConsole

## Developer console.  Toggle with the backtick (`) key.  Type `help` for commands.
## Wired to Game.gd so commands can trigger extinction events and other state.

var _game: Node = null

## Every command the console understands.  `help` prints this list and the encyclopedia builds
## its Console pages from it, so a command added here is documented in both places.  The
## behaviour itself is in _run().
const COMMANDS: Array = [
	{"name": "help", "aliases": [], "args": "",
		"summary": "list commands",
		"detail": "Prints every command with a one-line summary."},
	{"name": "impact", "aliases": [], "args": "",
		"summary": "trigger an asteroid impact now",
		"detail": "An asteroid strikes a random inhabited world in the Sol system immediately, with no warning dialog and no chance to intercept. The toll is rolled fresh: 50–85 % of that world's population, divided by the number of inhabited worlds in the system, less whoever its bunkers hold. Every structure there except bunkers and one Biomass Burner is destroyed."},
	{"name": "solar", "aliases": ["redgiant"], "args": "",
		"summary": "extinction: solar envelope expansion",
		"detail": "Ends the run immediately with the solar-envelope extinction screen, whatever the civilisation holds elsewhere."},
	{"name": "nebula", "aliases": [], "args": "",
		"summary": "extinction: planetary nebula",
		"detail": "Ends the run immediately with the planetary-nebula extinction screen, whatever the civilisation holds elsewhere."},
	{"name": "extinct", "aliases": [], "args": "[cause…]",
		"summary": "generic extinction with a custom cause",
		"detail": "Ends the run immediately. Any words after the command become the cause shown on the extinction screen; with none, the cause reads \"Console-triggered extinction\"."},
	{"name": "sandbox", "aliases": [], "args": "",
		"summary": "(re)write the god-mode sandbox save slot",
		"detail": "Writes the save slot \"sandbox_1945\": every research node unlocked, very large stockpiles of every material on every world, and every planet colonised in 1945. Load it from the start menu. The start menu also rewrites it every launch."},
	{"name": "shkadov", "aliases": ["thruster"], "args": "[multiplier]",
		"summary": "multiply the Shkadov thruster's acceleration",
		"detail": "Scales the star thruster's acceleration by the given factor, so the Sun's drift can be watched in a play session instead of over a hundred million years. A real full mirror shell on a 1 L\u2609 star accelerates it at about 1e-13 m/s\u00b2, which is the number the game runs on normally. With no argument, prints the current multiplier along with the mirror coverage, the speed and the distance travelled so far. Applied to the acceleration, not to the position, so the speed and the drift stay consistent with each other \u2014 it is a bigger engine, not a teleport. Not saved: a new or loaded run is back at 1."},
	{"name": "stock", "aliases": ["founders"], "args": "[founders] [strategy]",
		"summary": "read or set what the next colony ship carries",
		"detail": "The standing order for a colony's founding population: how many go, and which sequences are spliced into them before they leave. With no argument, prints the order, its effects, what a ship leaving the world being viewed would actually carry, and the stock of every inhabited world. With arguments, sets the order — the founder group and any number of traits, in any order, by id (minimal/standard/broad, and the trait ids the bare command lists). Naming any trait REPLACES the whole set; `none` clears it. A sequence the civilisation does not hold is refused, and no more than three fit in a genome. A small founder group carries less of its parent's variation and so expresses an edit less fully — that is the \"variation\" figure. Saved with the run."},
	{"name": "lineage", "aliases": ["traits"], "args": "[world] | [world] [trait]",
		"summary": "trade lineage data with your own colonies",
		"detail": "With no argument, lists what the archive holds, what is in flight, and which colonies hold a sequence worth asking for. With a world, requests that colony's sequence data — everything it has written comes back together, and the round trip is two years per light-year, so a colony four hundred light-years out answers in eight hundred years. With a world AND a trait, splices that sequence into the world's people, which takes a few decades. A colony only has something to send once it has been isolated long enough to be a lineage of its own and has had time to work something out; see the `stock` command for what each world currently carries."},
	{"name": "clear", "aliases": [], "args": "",
		"summary": "clear this log",
		"detail": "Clears the console's output log."},
	{"name": "close", "aliases": [], "args": "",
		"summary": "close the console",
		"detail": "Closes the console. The backtick key and Escape do the same."},
]

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
	# `verb`, not `name`: this extends CanvasLayer, and a local called `name` shadows Node.name.
	var verb := (parts[0] as String).to_lower()
	var args: Array = parts.slice(1)

	if _game == null and verb != "help":
		_err("game reference not set")
		return

	match verb:
		"help":
			_log("Commands:")
			for c: Dictionary in COMMANDS:
				var usage: String = " | ".join([str(c["name"])] + (c["aliases"] as Array))
				if str(c["args"]) != "":
					usage += " " + str(c["args"])
				_log("  [color=#ffd24a]%s[/color]  — %s" % [usage, str(c["summary"])])
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
		"shkadov", "thruster":
			_shkadov(args)
		"stock", "founders":
			_stock(args)
		"lineage", "traits":
			_lineage(args)
		"sandbox":
			SandboxSave.write()
			_ok("wrote sandbox save → load \"%s\" from the start menu" % SandboxSave.SLOT_NAME)
		"clear":
			_output.clear()
		"close":
			_set_open(false)
		_:
			_err("unknown command: %s  (type help)" % verb)

## `stock [founders] [strategy]` — read or set the founding-population order.
##
## Either part may be given alone and in either order: the two id sets are disjoint, so there is
## nothing to disambiguate and nothing for the player to remember about argument position.
##
## With no argument this is a readout, and the readout is the more useful half — an order means
## little without seeing what a ship leaving THIS world would actually carry, which depends on
## the population it is drawn from, and without seeing what the worlds already settled are.
func _stock(args: Array) -> void:
	var g: Node = _game
	if g == null:
		_err("Game not found")
		return
	if args.is_empty():
		var order: Dictionary = StockData.normalise(g.colony_stock)
		_ok("order: %s" % StockData.describe(order))
		var here: String = str(g.current_planet)
		var ship: Dictionary = g.founding_stock(here)
		_log("a ship leaving %s carries %s" % [here, StockData.describe(ship)])
		_log("  %s" % StockData.effects_text(ship))
		if StockData.diversity_of(ship) < StockData.diversity_for(str(order["founders"])):
			_log("  (a thinner sample than %s carries)" % here)
		for w: String in g._inhabited_worlds():
			_log("%-14s %s" % [w, StockData.describe(g.stock_of(w))])
		_log("founders: %s" % ", ".join(StockData.founders_ids()))
		_log("traits:   %s" % ", ".join(StockData.trait_ids()))
		return
	var order2: Dictionary = StockData.normalise(g.colony_stock)
	var f: String = str(order2["founders"])
	# Traits are listed, not toggled: naming any of them replaces the whole set, so `stock
	# broad` keeps the order's traits and `stock broad high_intelligence` sets exactly that one.
	var named: Array = []
	for a in args:
		var id: String = str(a).to_lower()
		if StockData.is_founders(id):
			f = id
		elif StockData.is_trait(id):
			named.append(id)
		elif id == "none":
			named = []
		else:
			_err("not a founder group or a trait: %s" % id)
			_log("founders: %s" % ", ".join(StockData.founders_ids()))
			_log("traits:   %s" % ", ".join(StockData.trait_ids()))
			return
	var want: Array = named if not named.is_empty() or _names_traits(args) \
		else (order2["traits"] as Array)
	var err: String = g.set_colony_stock(f, want)
	if err != "":
		_err(err)
		return
	_ok("order: %s" % StockData.describe(g.colony_stock))
	_log("  %s" % StockData.effects_text(g.founding_stock(str(g.current_planet))))


## True when the arguments mention traits at all — which is how "stock standard none" is told
## apart from "stock standard", the first clearing the order's traits and the second keeping
## them.
func _names_traits(args: Array) -> bool:
	for a in args:
		var id: String = str(a).to_lower()
		if StockData.is_trait(id) or id == "none":
			return true
	return false


## `lineage [world] [trait]` — the archive, a request, or a splice.
##
## The readout is the useful half again: what is worth asking for depends on which of your
## colonies have been out there long enough to have become something, and that is not visible
## anywhere else.
func _lineage(args: Array) -> void:
	var g: Node = _game
	if g == null:
		_err("Game not found")
		return
	if args.is_empty():
		var held: Array = (g.lineage_archive.keys() as Array)
		_ok("archive: %s" % ("empty" if held.is_empty() else ", ".join(held)))
		for t in g.lineage_transfers:
			var m: Dictionary = t
			_log("  in flight: %s from %s, back in %d yr" % [
				", ".join(m.get("traits", []) as Array),
				str(m.get("world", "")), int(float(m.get("end_year", 0)) - float(g.year))])
		var offers: Array = g.lineage_offers()
		if offers.is_empty():
			_log("no colony holds a sequence the archive does not — see `stock`")
		for o: Dictionary in offers.slice(0, 12):
			_log("  %-20s %-11s %8.1f ly  round trip %d yr" % [str(o["world"]),
				str(o["label"]), float(o["dist_ly"]), int(float(o["years"]))])
		return
	var world: String = str(args[0])
	if args.size() == 1:
		var err: String = g.request_lineage(world)
		if err != "":
			_err(err)
			return
		_ok("requested — %s" % world)
		return
	var want: String = str(args[1]).to_lower()
	var err2: String = g.splice_trait(world, want)
	if err2 != "":
		_err(err2)
		return
	_ok("%s is being spliced for %s" % [world, want])


## `shkadov [multiplier]` — read or set the thruster's acceleration multiplier.
##
## With no argument this is a status readout, which is the more useful half: a multiplier means
## nothing without knowing whether any mirrors are actually standing, and a thruster with no
## coverage and no aim does nothing however large the number is.
func _shkadov(args: Array) -> void:
	var sol: Node = _game.get_node_or_null("/root/SolarSystem")
	if sol == null:
		_err("SolarSystem not found")
		return
	if not args.is_empty():
		var raw: String = str(args[0])
		if not raw.is_valid_float():
			_err("not a number: %s" % raw)
			return
		var m: float = maxf(raw.to_float(), 0.0)
		sol.star_thrust_mult = m
		_ok("thruster acceleration x%s" % _fmt(m))
	# Always the state, set or not: what the engine is doing matters more than the factor.
	var cov: float = float(sol.star_mirror_coverage)
	_log("  multiplier      x%s" % _fmt(float(sol.star_thrust_mult)))
	_log("  mirror coverage %.4f%s" % [cov,
		"" if cov > 0.0 else "   [color=#e0a84a](no mirrors — the thruster is inert)[/color]"])
	var aim: String = str(sol.star_thrust_target)
	var aimed: bool = (sol.star_thrust_dir as Vector3).length_squared() > 0.0
	_log("  aim             %s" % (
		(aim if aim != "" else "a bare heading") if aimed
		else "[color=#e0a84a]none — aim it from the star map[/color]"))
	_log("  speed           %s" % Units.format_si(float(sol.star_velocity_ms), "m/s"))
	_log("  travelled       %s" % Units.format_si(float(sol.star_drift_dist_ly), "ly"))


## A multiplier without a trailing ".0" on the whole numbers anyone will actually type.
func _fmt(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, floorf(v)) and absf(v) < 1.0e15 else str(v)


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
