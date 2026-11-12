class_name ComputePanel
extends PanelContainer

## ComputePanel — where the civilisation's thinking is divided between finding things out and
## seeing what is coming, one simulation at a time.
##
## There are two pools, because the civilisation has two kinds of mind and they are not
## substitutable: HUMAN thinking grows with how many people there are, ARTIFICIAL thinking with
## what has been built for it.  Each can be pointed somewhere different, so the machines can be
## put on the future while the people stay on the tree, or the reverse.
##
## There are five places to point them: one simulation per catastrophe the forecast models, the
## standing medicine that answers the plague once it is loose, and the tree.  Looking for rocks
## and looking for plagues are not the same calculation, and neither is curing one — a
## civilisation can be excellent at any of them and helpless at the rest, which is the whole
## point of budgeting them separately.
##
## The sliders are WEIGHTS, not shares.  Raising one does not require hunting down another to pay
## for it; each pool is divided in proportion to what is pointed at it, and the row readouts show
## the share that came out.  Science keeps a floor of every pool whatever the weights say, so a
## civilisation cannot think itself into being unable to build what the forecast warned it about.
##
## Each simulation's foresight is a STOCK that its budget fills and the passing years drain, so a
## row shows both where its sight reaches now and where that budget is working towards.  Medicine
## is a stock for the same reason and reads the same way: nobody answers a pathogen in the week
## it arrives, so what matters is what was already standing when it did.
##
## Emits alloc_changed(track, pool, weight); Game owns the allocation and reads it back.

signal alloc_changed(track: String, pool: String, weight: float)

## The widest a single weight goes.  A ceiling at all is only so the slider has a scale; what
## matters is one weight against the others, and 100 against 100 is the same split as 1 against 1.
const WEIGHT_MAX: float = 100.0

## The two thinkers, in two of the palette's accents: the civilisation's own minds, and its
## machines. Nothing says green is people — it says only that these are two different pools, and
## that the colours saying so are the ones the rest of the UI already uses.
const COL_HUMAN: Color = UIPalette.SCIENCE
const COL_AI: Color = UIPalette.POPULATION

var _human_lbl: Label = null
var _ai_lbl: Label = null
var _locked_lbl: Label = null
var _note_lbl: Label = null
var _rows_box: VBoxContainer = null

## track → {"human": HSlider, "ai": HSlider, "share": Label, "sight": Label, "name": Label}
var _rows: Dictionary = {}

## Set by the refresh so moving a slider programmatically does not echo back to Game.
var _quiet: bool = false


func _ready() -> void:
	# A floor, not a width. Every other sidebar page fills the area right of the buttons, and
	# an opaque page that stops in the middle of the screen reads as a panel that failed to
	# load — which it did not, before the pages were opaque enough for anyone to notice.
	custom_minimum_size = Vector2(620, 520)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	PanelBackground.attach(self)
	_build_ui()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 16)
	add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	margin.add_child(vb)

	var title := Label.new()
	title.text = "Compute"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UIPalette.TITLE)
	vb.add_child(title)

	var pools := HBoxContainer.new()
	pools.add_theme_constant_override("separation", 18)
	vb.add_child(pools)
	_human_lbl = Label.new()
	_human_lbl.add_theme_color_override("font_color", COL_HUMAN)
	pools.add_child(_human_lbl)
	_ai_lbl = Label.new()
	_ai_lbl.add_theme_color_override("font_color", COL_AI)
	pools.add_child(_ai_lbl)

	_locked_lbl = Label.new()
	_locked_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_locked_lbl.add_theme_color_override("font_color", UIPalette.WARN)
	vb.add_child(_locked_lbl)

	vb.add_child(HSeparator.new())

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 10)
	vb.add_child(_rows_box)

	vb.add_child(HSeparator.new())

	_note_lbl = Label.new()
	_note_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note_lbl.add_theme_font_size_override("font_size", 11)
	_note_lbl.add_theme_color_override("font_color", UIPalette.DIM)
	_note_lbl.text = "Foresight accumulates: a budget pushes its frontier outward and it stays " \
		+ "there, while the present walks towards it — so a horizon held steady costs a year's " \
		+ "worth of compute every year, and closes at a year per year once you stop paying. " \
		+ "Pushing it further costs the SQUARE of the distance, and past the system's Lyapunov " \
		+ "time no amount of compute helps."
	vb.add_child(_note_lbl)


## One budget row: the name, a slider per pool, and what the result buys.
func _build_row(track: String, label_text: String, note: String) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_rows_box.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	var name_lbl := Label.new()
	name_lbl.text = label_text
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_lbl)
	var sight := Label.new()
	sight.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(sight)

	var note_lbl := Label.new()
	note_lbl.text = note
	note_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_lbl.add_theme_font_size_override("font_size", 10)
	note_lbl.add_theme_color_override("font_color", UIPalette.DIM)
	box.add_child(note_lbl)

	var sliders := {}
	for pool: String in ["human", "ai"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		box.add_child(row)
		var tag := Label.new()
		tag.text = "Human" if pool == "human" else "AI"
		tag.custom_minimum_size = Vector2(52, 0)
		tag.add_theme_font_size_override("font_size", 11)
		tag.add_theme_color_override("font_color",
			COL_HUMAN if pool == "human" else COL_AI)
		row.add_child(tag)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = WEIGHT_MAX
		sl.step = 1.0
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.value_changed.connect(_on_slider.bind(track, pool))
		row.add_child(sl)
		sliders[pool] = sl

	var share := Label.new()
	share.add_theme_font_size_override("font_size", 11)
	share.add_theme_color_override("font_color", UIPalette.TEXT)
	box.add_child(share)

	_rows[track] = {"human": sliders["human"], "ai": sliders["ai"],
		"share": share, "sight": sight, "name": name_lbl}


func _on_slider(v: float, track: String, pool: String) -> void:
	if _quiet:
		return
	alloc_changed.emit(track, pool, v / WEIGHT_MAX)


## Push the live figures.  `state` is Game.compute_panel_state() — see there for the keys; all of
## the arithmetic happens on that side so this panel and the simulation cannot disagree.
func set_state(state: Dictionary) -> void:
	if _rows_box == null:
		return
	var unlocked: bool = bool(state.get("unlocked", false))
	# Each pool's size AND what a unit of it is worth as research.  A machine starts at a
	# quarter of a person and ends at better than twice one, so the totals on their own do not
	# say which pool is the better place to put the tree.
	_human_lbl.text = "Human thinking: %s  (research x%.2f)" % [
		Units.format_si(float(state.get("human", 0.0)), "FLOP/s"),
		float(state.get("human_efficiency", 1.0))]
	_ai_lbl.text = "Machine thinking: %s  (research x%.2f)" % [
		Units.format_si(float(state.get("ai", 0.0)), "FLOP/s"),
		float(state.get("ai_efficiency", 1.0))]

	# What cannot be budgeted yet, named rather than described. The tracks no longer unlock
	# together — forecasting and medicine sit in different parts of the tree — so one sentence
	# about one of them was going to be wrong about the other.
	var waiting: Array = []
	for row: Dictionary in (state.get("tracks", []) as Array):
		if not bool(row.get("available", true)):
			waiting.append(str(row.get("label", row.get("track", ""))))
	_locked_lbl.visible = not waiting.is_empty()
	if not waiting.is_empty():
		_locked_lbl.text = "Not researched yet: %s. Every FLOP pointed at one of those goes " \
			% ", ".join(PackedStringArray(waiting)) \
			+ "to the tree instead, whatever its sliders are set to."

	var lyap: float = float(state.get("lyapunov", 0.0))
	for row: Dictionary in (state.get("tracks", []) as Array):
		var track: String = str(row.get("track", ""))
		if not _rows.has(track):
			_build_row(track, str(row.get("label", track)), str(row.get("note", "")))
		var ui: Dictionary = _rows[track]
		var forecast: bool = bool(row.get("forecast", false))
		var weights: Dictionary = row.get("weights", {})

		_quiet = true
		for pool: String in ["human", "ai"]:
			var sl: HSlider = ui[pool]
			sl.value = clampf(float(weights.get(pool, 0.0)) * WEIGHT_MAX, 0.0, WEIGHT_MAX)
			# A track's sliders are dead weight until there is machinery to run it, and the
			# tracks do not all unlock together — so this is the row's own flag, not one gate
			# over the whole page.
			sl.editable = bool(row.get("available", true))
		_quiet = false

		var shares: Dictionary = row.get("shares", {})
		(ui["share"] as Label).text = "%d%% of human  ·  %d%% of machine  ·  %s" % [
			int(round(float(shares.get("human", 0.0)) * 100.0)),
			int(round(float(shares.get("ai", 0.0)) * 100.0)),
			Units.format_si(float(row.get("flops", 0.0)), "FLOP/s")]

		var sight: Label = ui["sight"]
		if track == "medicine":
			if not bool(row.get("available", true)):
				sight.text = "locked"
				sight.add_theme_color_override("font_color", UIPalette.DISABLED)
				continue
			var cut: float = float(row.get("toll_cut", 0.0))
			var cut_to: float = float(row.get("toll_cut_settles", 0.0))
			var gain: float = float(row.get("life_gain", 0.0))
			if cut <= 0.0005 and cut_to <= 0.0005:
				sight.text = "nothing standing"
				sight.add_theme_color_override("font_color", UIPalette.WARN)
				continue
			# What it takes off a toll now and where this budget is taking that, in the same
			# shape as a forecast row — a stock that is still filling cannot be read from one
			# number. The years are what it is worth in the meantime.
			var trend: String = "holding"
			if cut_to > cut * 1.02:
				trend = "rising towards %d%%" % int(round(cut_to * 100.0))
			elif cut_to < cut * 0.98:
				trend = "falling towards %d%%" % int(round(cut_to * 100.0))
			sight.text = "answers %d%% of a toll — %s  ·  +%.1f yr" % [
				int(round(cut * 100.0)), trend, gain]
			sight.add_theme_color_override("font_color", UIPalette.GOOD)
			continue
		if not forecast:
			sight.text = "%s of science" % Units.format_si(
				float(row.get("science_rate", 0.0)), "FLOP/s")
			sight.add_theme_color_override("font_color", UIPalette.SCIENCE)
			continue
		if not unlocked:
			sight.text = "locked"
			sight.add_theme_color_override("font_color", UIPalette.DISABLED)
			continue
		var h: float = float(row.get("horizon", 0.0))
		var settles: float = float(row.get("settles", 0.0))
		if h <= 0.0 and settles <= 0.0:
			sight.text = "blind"
			sight.add_theme_color_override("font_color", UIPalette.WARN)
			continue
		# Both numbers, because a stock that is still filling cannot be read from one of them:
		# where the sight reaches now, and where this budget is taking it.
		if lyap > 0.0 and h >= lyap * 0.999:
			sight.text = "sees %s — at the Lyapunov wall" % Units.format_si(h, "yr")
		elif settles > h * 1.02:
			sight.text = "sees %s — rising towards %s" % [
				Units.format_si(h, "yr"), Units.format_si(settles, "yr")]
		elif settles < h * 0.98:
			sight.text = "sees %s — closing towards %s" % [
				Units.format_si(h, "yr"), Units.format_si(settles, "yr")]
		else:
			sight.text = "sees %s — holding" % Units.format_si(h, "yr")
		sight.add_theme_color_override("font_color", UIPalette.GOOD)
