extends PanelContainer

## Population-statistics tab of the merged planet panel.  Fed by Game each tick (while its
## tab is visible) via set_stats — a flat, instrument-style readout of the species' numbers,
## and, once Synthetic Biology is in, the one place a world's own people can be rewritten.

## The player asked for a sequence to be spliced into this world's population.  Game is the
## authority (see splice_block_reason) and pushes the accepted state back.
signal lineage_direct_requested(world: String, trait_id: String)

var _value_labels: Dictionary = {}   # row key → value Label

# ── Engineering this world's people ──────────────────────────────────────────
## Hidden until Synthetic Biology is researched.  Before that the only sequences a civilisation
## has are the ones its colonies wrote and sent home, and the place to ask is the star map — and a
## control that is permanently greyed teaches that less well than one that is not there yet.
var _bio_box:     VBoxContainer = null
var _bio_opt:     OptionButton  = null
var _bio_status:  Label         = null
var _bio_ids:     Array         = []
var _bio_world:   String        = ""
var _bio_quiet:   bool          = false

## Swallow scroll-wheel so hovering this tab doesn't zoom the 3-D camera behind it.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index in [
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		accept_event()

## The rows shown, in order: [display key].  Values are pushed by set_stats().
const ROWS: Array = [
	"Current population",
	"Carrying capacity",
	"  natural",
	"  built",
	"Growth rate",
	"Life expectancy",
	"Happiness",
]

func _ready() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Population"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0))
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	vbox.add_child(grid)

	for key: String in ROWS:
		var k := Label.new()
		k.text = key
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		k.add_theme_color_override("font_color", Color(0.72, 0.78, 0.9))
		grid.add_child(k)
		var v := Label.new()
		v.text = "-"
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(v)
		_value_labels[key] = v

	_build_bio_ui(vbox)


## The splicing control: what this world's people carry, and what could be written into them.
func _build_bio_ui(parent: Control) -> void:
	_bio_box = VBoxContainer.new()
	_bio_box.add_theme_constant_override("separation", 3)
	_bio_box.hide()
	parent.add_child(HSeparator.new())
	parent.add_child(_bio_box)

	var title := Label.new()
	title.text = "Applied genomics"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.72, 0.90, 0.80))
	title.tooltip_text = "Synthetic Biology writes a sequence from first principles rather than waiting for a colony to work one out. It does not deliver people: the sequence is information, and getting it into a living population is still a couple of generations of germ-line work."
	_bio_box.add_child(title)

	_bio_status = Label.new()
	_bio_status.add_theme_font_size_override("font_size", 11)
	_bio_status.modulate = Color(0.75, 0.82, 0.95)
	_bio_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bio_box.add_child(_bio_status)

	_bio_opt = OptionButton.new()
	_bio_opt.fit_to_longest_item = false
	_bio_opt.clip_text = true
	_bio_opt.item_selected.connect(func(i: int) -> void:
		if _bio_quiet or i <= 0 or _bio_world == "" or i - 1 >= _bio_ids.size():
			return
		lineage_direct_requested.emit(_bio_world, str(_bio_ids[i - 1])))
	_bio_box.add_child(_bio_opt)


## Game's answer about this world's lineage and what may be done to it.
##
## Everything comes from Game: which sequences can go in here, what the population
## currently is, and how far any programme has to run.  The panel shows what comes back and
## nothing it was not given, so an option it offers is one the simulation will accept.
func set_lineage(state: Dictionary) -> void:
	if _bio_box == null:
		return
	if state.is_empty() or not bool(state.get("unlocked", false)):
		_bio_box.hide()
		return
	_bio_box.show()
	_bio_world = str(state.get("world", ""))
	_bio_status.text = str(state.get("text", ""))
	var targets: Array = state.get("targets", []) as Array
	_bio_quiet = true
	_bio_opt.clear()
	_bio_ids = []
	_bio_opt.add_item("Splice in…")
	for t: Dictionary in targets:
		_bio_opt.add_item(str(t["label"]))
		_bio_opt.set_item_tooltip(_bio_ids.size() + 1, str(t.get("blurb", "")))
		_bio_ids.append(str(t["id"]))
	_bio_opt.selected = 0
	_bio_opt.disabled = targets.is_empty()
	_bio_quiet = false

## Push the current figures.  `data` keys mirror ROWS' meaning:
##   population, capacity, life_expectancy, worlds, star_systems, ever_lived
func set_stats(data: Dictionary) -> void:
	var inhabited: bool = bool(data.get("inhabited", true))
	_set_row("Current population", _fmt_pop(float(data.get("population", 0.0))))
	_set_row("Carrying capacity", _fmt_pop(float(data.get("capacity", 0.0))))
	# Split out what the world supports on its own from what has been built for it — off Earth
	# the first number is zero, and seeing that is the point.
	_set_row("  natural",    _fmt_pop(float(data.get("natural_capacity", 0.0))))
	_set_row("  built",      _fmt_pop(float(data.get("artificial_capacity", 0.0))))
	# Growth / life expectancy / happiness are species-wide — only meaningful where people live.
	if not inhabited:
		for k: String in ["Growth rate", "Life expectancy", "Happiness"]:
			_set_row(k, "—")
			_tint(k, Color(0.6, 0.6, 0.66))
		return
	var growth: float = float(data.get("growth", 0.0))
	_set_row("Growth rate", "%+.2f%%/yr" % growth)
	_tint("Growth rate", Color(0.5, 0.9, 0.6) if growth >= 0.0 else Color(0.95, 0.55, 0.4))
	_set_row("Life expectancy", "%d yr" % int(round(float(data.get("life_expectancy", 0.0)))))
	_tint("Life expectancy", Color(1, 1, 1))
	var happy: float = float(data.get("happiness", 0.0))
	_set_row("Happiness", "%d%%" % int(round(happy)))
	_tint("Happiness", Color(0.5, 0.9, 0.6) if happy >= 60.0 \
		else (Color(0.9, 0.8, 0.4) if happy >= 35.0 else Color(0.95, 0.55, 0.4)))

func _tint(key: String, color: Color) -> void:
	if _value_labels.has(key):
		(_value_labels[key] as Label).modulate = color

func _set_row(key: String, text: String) -> void:
	if _value_labels.has(key):
		(_value_labels[key] as Label).text = text

## Compact SI-ish population string.
func _fmt_pop(v: float) -> String:
	if v >= 1.0e18: return "%.2f Qi" % (v * 1.0e-18)
	if v >= 1.0e15: return "%.2f Qa" % (v * 1.0e-15)
	if v >= 1.0e12: return "%.2f T"  % (v * 1.0e-12)
	if v >= 1.0e9:  return "%.2f B"  % (v * 1.0e-9)
	if v >= 1.0e6:  return "%.2f M"  % (v * 1.0e-6)
	if v >= 1.0e3:  return "%.1f K"  % (v * 1.0e-3)
	return "%d" % int(v)
