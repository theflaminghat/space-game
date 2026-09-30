class_name ComputePanel
extends PanelContainer

## ComputePanel — where the civilisation's thinking is divided between finding things out and
## seeing what is coming.
##
## Compute is one pool: population's own thinking plus whatever machines have been built for it.
## Research spends it on the tree; forecasting spends it on the future.  The same FLOP cannot do
## both, so this panel is the trade, and the readouts are there to make the trade legible rather
## than a number the player twiddles blindly — each side shows what its share actually BUYS.
##
## Emits share_changed(share: float); Game stores it and both systems read it back.

signal share_changed(share: float)

var _total_lbl: Label = null
var _slider: HSlider = null
var _pct_lbl: Label = null
var _research_lbl: Label = null
var _forecast_lbl: Label = null
var _horizon_lbl: Label = null
var _note_lbl: Label = null
var _locked_lbl: Label = null

## Set by the refresh so moving the slider programmatically does not echo back to Game.
var _quiet: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(520, 380)
	PanelBackground.attach(self)
	_build_ui()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 16)
	add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)

	var title := Label.new()
	title.text = "Compute"
	title.add_theme_font_size_override("font_size", 18)
	vb.add_child(title)

	_total_lbl = Label.new()
	_total_lbl.add_theme_color_override("font_color", Color(0.75, 0.80, 0.90))
	vb.add_child(_total_lbl)

	_locked_lbl = Label.new()
	_locked_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_locked_lbl.add_theme_color_override("font_color", Color(0.80, 0.65, 0.35))
	_locked_lbl.text = "Forecasting needs Predictive Modeling. Until it is researched every FLOP goes to the tree."
	vb.add_child(_locked_lbl)

	vb.add_child(HSeparator.new())

	# ── The split ──
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)

	var slider_lbl := Label.new()
	slider_lbl.text = "To forecasting"
	row.add_child(slider_lbl)

	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 90.0
	_slider.step = 1.0
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.value_changed.connect(_on_slider)
	row.add_child(_slider)

	_pct_lbl = Label.new()
	_pct_lbl.custom_minimum_size = Vector2(48, 0)
	_pct_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_pct_lbl)

	vb.add_child(HSeparator.new())

	# ── What each share buys ──
	_research_lbl = Label.new()
	_research_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_research_lbl.add_theme_color_override("font_color", Color(0.45, 0.75, 1.00))
	vb.add_child(_research_lbl)

	_forecast_lbl = Label.new()
	_forecast_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_forecast_lbl.add_theme_color_override("font_color", Color(0.95, 0.55, 0.45))
	vb.add_child(_forecast_lbl)

	_horizon_lbl = Label.new()
	_horizon_lbl.add_theme_font_size_override("font_size", 16)
	vb.add_child(_horizon_lbl)

	vb.add_child(HSeparator.new())

	_note_lbl = Label.new()
	_note_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note_lbl.add_theme_font_size_override("font_size", 11)
	_note_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.72))
	_note_lbl.text = "Foresight costs the SQUARE of the horizon: seeing twice as far takes four " \
		+ "times the compute, and past the system's Lyapunov time no amount of it helps. " \
		+ "Scheduled impacts are certain; plagues and exchanges are reported at today's odds, " \
		+ "which your own choices move."
	vb.add_child(_note_lbl)


func _on_slider(v: float) -> void:
	if _quiet:
		return
	share_changed.emit(v / 100.0)


## Push the live figures.  `unlocked` is whether forecasting is available at all; the rest are
## read straight off Game so this panel never does the arithmetic twice.
func set_state(total_flops: float, share: float, unlocked: bool,
		science_rate: float, horizon_years: float, lyapunov_years: float) -> void:
	if _total_lbl == null:
		return
	_locked_lbl.visible = not unlocked
	_slider.editable = unlocked

	_quiet = true
	_slider.value = clampf(share * 100.0, 0.0, 90.0)
	_quiet = false
	_pct_lbl.text = "%d%%" % int(round(share * 100.0))

	_total_lbl.text = "Total thinking: %s" % Units.format_si(total_flops, "FLOP/s")

	var to_forecast: float = total_flops * (share if unlocked else 0.0)
	var to_research: float = total_flops - to_forecast
	_research_lbl.text = "Research — %s  ·  %s of science" % [
		Units.format_si(to_research, "FLOP/s"), Units.format_si(science_rate, "FLOP/s")]
	_forecast_lbl.text = "Forecasting — %s" % Units.format_si(to_forecast, "FLOP/s")

	if not unlocked:
		_horizon_lbl.text = "Foresight: none"
		_horizon_lbl.add_theme_color_override("font_color", Color(0.60, 0.60, 0.66))
	elif horizon_years <= 0.0:
		_horizon_lbl.text = "Foresight: none — nothing is assigned to it"
		_horizon_lbl.add_theme_color_override("font_color", Color(0.80, 0.65, 0.35))
	else:
		var wall: String = "  (at the Lyapunov wall)" \
			if horizon_years >= lyapunov_years * 0.999 else ""
		_horizon_lbl.text = "Foresight: %s ahead%s" % [
			Units.format_si(horizon_years, "yr"), wall]
		_horizon_lbl.add_theme_color_override("font_color", Color(0.95, 0.80, 0.45))
