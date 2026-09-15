extends CanvasLayer
class_name TradePanel

## The trade proposal window, opened by the Trade button on the star map.
##
## The player fills both sides — what this civilisation offers and what it asks for — with
## energy, science and any material, picks which world the goods leave from and arrive at, and
## sends the proposal.  It travels at light speed; the reply returns after the round trip (see
## Game.propose_trade and Game._resolve_trade).  Offered goods leave their stores when the
## proposal is sent and come back if it is refused.
##
## The panel shows the exchange as the partner will judge it (TradeData): both sides valued as
## embodied energy, the ratio the partner's standing requires, and whether the request fits what
## the partner is seen to be able to supply.  "Seen" matters: alignment may be unknown and the
## infrastructure is light-delayed, so the forecast can be wrong in exactly the ways the star
## map's intel can be wrong.
##
## Game remains the authority on stock: everything shown here comes from Game.trade_context and
## Game.trade_holdings, and Game.propose_trade re-validates before anything is spent.

const PANEL_SIZE: Vector2 = Vector2(1060, 700)
const COL_DIM: Color = Color(0.62, 0.68, 0.80)
const COL_GOOD: Color = Color(0.45, 0.88, 0.55)
const COL_WARN: Color = Color(1.0, 0.82, 0.35)
const COL_BAD: Color = Color(0.95, 0.45, 0.40)

var _game: Node = null
var _star: String = ""
var _ctx: Dictionary = {}
var _values: Dictionary = {}
var _world: String = "earth"
var _holdings: Dictionary = {}     # key → amount this civilisation can offer from the chosen world
var _offer: Dictionary = {}        # key → amount
var _request: Dictionary = {}

var _title: Label
var _info: Label
var _world_opt: OptionButton
var _sides: Dictionary = {}        # "offer" | "request" → { pick, amount, parsed, list, total }
var _verdict: RichTextLabel
var _error: Label
var _send: Button


func _ready() -> void:
	layer = 96
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("ui_overlay")         # the camera and galaxy map ignore their keys while open
	_build_ui()
	visible = false


func setup(game: Node) -> void:
	_game = game


## Open a fresh proposal to `star`.
func open(star: String) -> void:
	if _game == null or star == "":
		return
	_star = star
	_ctx = _game.trade_context(star)
	_values = _ctx.get("values", {})
	_offer = {}
	_request = {}
	_world_opt.clear()
	var worlds: Array = _ctx.get("worlds", [])
	for i in range(worlds.size()):
		_world_opt.add_item(str(worlds[i][0]), i)
		_world_opt.set_item_metadata(i, str(worlds[i][1]))
	_world = str(worlds[0][1]) if not worlds.is_empty() else "earth"
	_world_opt.select(0)
	_title.text = "Trade proposal — %s" % star
	_refresh_holdings()
	_fill_request_picker()
	_error.text = ""
	visible = true
	_refresh()


func close() -> void:
	visible = false


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


# ── State ─────────────────────────────────────────────────────────────────────

func _refresh_holdings() -> void:
	_holdings = _game.trade_holdings(_world)
	# Items held on the previous world may not be here; drop what can no longer be offered.
	for k: String in _offer.keys():
		if float(_holdings.get(k, 0.0)) < float(_offer[k]):
			_offer.erase(k)
	_fill_offer_picker()


func _on_world_selected(idx: int) -> void:
	_world = str(_world_opt.get_item_metadata(idx))
	_refresh_holdings()
	_refresh()


func _add(side: String) -> void:
	var w: Dictionary = _sides[side]
	var pick: OptionButton = w["pick"]
	if pick.selected < 0:
		return
	var key: String = str(pick.get_item_metadata(pick.selected))
	var amount: float = TradeData.parse_amount((w["amount"] as LineEdit).text)
	if amount <= 0.0:
		_error.text = "Enter an amount, e.g. 5e12, 5T or 5,000,000."
		return
	var bundle: Dictionary = _offer if side == "offer" else _request
	var total: float = float(bundle.get(key, 0.0)) + amount
	if side == "offer" and total > float(_holdings.get(key, 0.0)) * (1.0 + 1e-9):
		_error.text = "Only %s of %s is available to offer." % [
			TradeData.format_amount(key, float(_holdings.get(key, 0.0))), TradeData.display_name(key)]
		return
	bundle[key] = total
	(w["amount"] as LineEdit).text = ""
	_error.text = ""
	_refresh()


func _fill_all(side: String) -> void:
	var w: Dictionary = _sides[side]
	var pick: OptionButton = w["pick"]
	if pick.selected < 0:
		return
	var key: String = str(pick.get_item_metadata(pick.selected))
	var left: float = float(_holdings.get(key, 0.0)) - float(_offer.get(key, 0.0))
	(w["amount"] as LineEdit).text = "%s" % str(maxf(left, 0.0))
	_on_amount_changed("", side)


func _remove(side: String, key: String) -> void:
	(_offer if side == "offer" else _request).erase(key)
	_refresh()


func _on_amount_changed(_t: String, side: String) -> void:
	var w: Dictionary = _sides[side]
	var pick: OptionButton = w["pick"]
	var txt: String = (w["amount"] as LineEdit).text
	var v: float = TradeData.parse_amount(txt)
	var key: String = str(pick.get_item_metadata(pick.selected)) if pick.selected >= 0 else ""
	if txt.strip_edges() == "":
		(w["parsed"] as Label).text = ""
	elif v < 0.0:
		(w["parsed"] as Label).text = "not a number"
	else:
		(w["parsed"] as Label).text = "= %s  (worth %s)" % [TradeData.format_amount(key, v),
			Units.format_si(v * float(_values.get(key, 0.0)), "J")]


func _send_proposal() -> void:
	var err: String = _game.propose_trade(_star, _world, _offer, _request)
	if err != "":
		_error.text = err
		return
	close()


# ── Refresh ───────────────────────────────────────────────────────────────────

func _fill_offer_picker() -> void:
	var pick: OptionButton = _sides["offer"]["pick"]
	pick.clear()
	var keys: Array = _holdings.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		var ga: bool = a in TradeData.GLOBAL_KEYS
		var gb: bool = b in TradeData.GLOBAL_KEYS
		if ga != gb:
			return ga
		return TradeData.display_name(a).naturalnocasecmp_to(TradeData.display_name(b)) < 0)
	for k: String in keys:
		pick.add_item("%s — %s available" % [TradeData.display_name(k),
			TradeData.format_amount(k, float(_holdings[k]))])
		pick.set_item_metadata(pick.item_count - 1, k)
	if pick.item_count > 0:
		pick.select(0)


func _fill_request_picker() -> void:
	var pick: OptionButton = _sides["request"]["pick"]
	pick.clear()
	var keys: Array = _values.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		var ga: bool = a in TradeData.GLOBAL_KEYS
		var gb: bool = b in TradeData.GLOBAL_KEYS
		if ga != gb:
			return ga
		return TradeData.display_name(a).naturalnocasecmp_to(TradeData.display_name(b)) < 0)
	for k: String in keys:
		var unit: String = "J" if k == "energy" else ("FLOP" if k == "science" else "g")
		pick.add_item("%s — %s per %s" % [TradeData.display_name(k),
			Units.format_si(float(_values[k]), "J"), unit])
		pick.set_item_metadata(pick.item_count - 1, k)
	if pick.item_count > 0:
		pick.select(0)


func _refresh() -> void:
	# Context line.
	var align: String = str(_ctx.get("alignment", "unknown"))
	var status: String = str(_ctx.get("status", ""))
	_info.text = "%.1f ly · reply in ~%s (round trip at light speed) · relations: %s · alignment: %s · their supply capacity ≈ %s (light-delayed estimate) · transmission %s" % [
		float(_ctx.get("dist_ly", 0.0)), Units.format_si(float(_ctx.get("reply_years", 0.0)), "yr"),
		status if status != "" else "none", align,
		Units.format_si(float(_ctx.get("capacity", 0.0)), "J"),
		Units.format_si(float(_ctx.get("transmit_cost", 0.0)), "J")]

	for side: String in ["offer", "request"]:
		var w: Dictionary = _sides[side]
		var list: VBoxContainer = w["list"]
		for c in list.get_children():
			c.queue_free()
		var bundle: Dictionary = _offer if side == "offer" else _request
		if bundle.is_empty():
			var none := Label.new()
			none.text = "Nothing added."
			none.modulate = COL_DIM
			list.add_child(none)
		for k: String in bundle:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var name_l := Label.new()
			name_l.text = TradeData.display_name(k)
			name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_l)
			var amt_l := Label.new()
			amt_l.text = TradeData.format_amount(k, float(bundle[k]))
			amt_l.custom_minimum_size = Vector2(110, 0)
			amt_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(amt_l)
			var val_l := Label.new()
			val_l.text = Units.format_si(float(bundle[k]) * float(_values.get(k, 0.0)), "J")
			val_l.custom_minimum_size = Vector2(100, 0)
			val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			val_l.modulate = COL_DIM
			row.add_child(val_l)
			var rm := Button.new()
			rm.text = "×"
			rm.flat = true
			rm.pressed.connect(_remove.bind(side, k))
			row.add_child(rm)
			list.add_child(row)
		(w["total"] as Label).text = "Value: %s" % Units.format_si(TradeData.bundle_value(bundle, _values), "J")

	# The forecast, from what is known of the partner.
	var ov: float = TradeData.bundle_value(_offer, _values)
	var rv: float = TradeData.bundle_value(_request, _values)
	var assumed: String = "peaceful" if align == "unknown" else align
	var v: Dictionary = TradeData.assess(ov, rv, status, assumed, float(_ctx.get("capacity", 0.0)))
	var lines: Array = []
	if align == "unknown":
		lines.append("[color=#ffd24a]Alignment unknown. A hostile civilisation refuses every proposal; the forecast below assumes a peaceful one.[/color]")
	match str(v["reason"]):
		"hostile":
			lines.append("[color=#f07366]Hostile civilisation: the proposal will be refused and the offered goods returned.[/color]")
		"war":
			lines.append("[color=#f07366]At war: the proposal will be refused and the offered goods returned.[/color]")
		"capacity":
			lines.append("[color=#f07366]The request (%s) exceeds their estimated supply capacity (%s). Likely refused.[/color]" % [
				Units.format_si(rv, "J"), Units.format_si(float(_ctx.get("capacity", 0.0)), "J")])
		"gift":
			if ov > 0.0:
				lines.append("[color=#74e08c]Nothing is requested: a gift. A peaceful civilisation accepts it.[/color]")
		"terms":
			var ok: bool = bool(v["accept"])
			lines.append("Offer is worth [b]%d %%[/b] of the request. At standing \"%s\" they accept at %d %% or more. [color=%s]%s[/color]" % [
				int(round(float(v["ratio"]) * 100.0)), status if status != "" else "none",
				int(round(float(v["need"]) * 100.0)), "#74e08c" if ok else "#f07366",
				"Likely accepted." if ok else "Likely refused."])
	lines.append("[color=#9ea8bd]Value is embodied energy: what each good costs to produce. Offered goods leave %s's stores when the proposal is sent and return if it is refused; what is received arrives there with the reply. Energy above storage capacity is lost.[/color]" % _world_display())

	# Can it be sent?  The reason it can't is shown with the forecast, not as an error.
	var energy_need: float = float(_ctx.get("transmit_cost", 0.0)) + float(_offer.get("energy", 0.0))
	var reason: String = ""
	if bool(_ctx.get("in_transit", false)):
		reason = "A message to %s is already in transit; a new proposal can be sent once its reply arrives." % _star
	elif _offer.is_empty() and _request.is_empty():
		reason = "Add something to either side."
	elif float(_holdings.get("energy", 0.0)) < energy_need:
		reason = "Not enough energy for the transmission and the energy offered (%s needed)." % Units.format_si(energy_need, "J")
	if reason != "":
		lines.append("[color=#ffd24a]%s[/color]" % reason)
	_verdict.text = "\n".join(lines)
	_send.disabled = reason != ""
	_send.tooltip_text = reason


func _world_display() -> String:
	return _world_opt.get_item_text(_world_opt.selected) if _world_opt.selected >= 0 else _world.capitalize()


# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP     # modal: the map behind takes no input
	root.add_child(backdrop)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(centre)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = PANEL_SIZE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.10, 0.98)
	sb.border_color = Color(0.35, 0.45, 0.65)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	centre.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	col.add_child(_title)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_font_size_override("font_size", 12)
	_info.modulate = COL_DIM
	col.add_child(_info)

	var world_row := HBoxContainer.new()
	world_row.add_theme_constant_override("separation", 8)
	var wl := Label.new()
	wl.text = "Trade through:"
	world_row.add_child(wl)
	_world_opt = OptionButton.new()
	_world_opt.custom_minimum_size = Vector2(220, 0)
	_world_opt.tooltip_text = "Offered goods leave this world's stores; what is received arrives here."
	_world_opt.item_selected.connect(_on_world_selected)
	world_row.add_child(_world_opt)
	col.add_child(world_row)

	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 16)
	sides.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sides)
	_sides["offer"] = _build_side(sides, "You offer", "offer")
	sides.add_child(VSeparator.new())
	_sides["request"] = _build_side(sides, "You request", "request")

	_verdict = RichTextLabel.new()
	_verdict.bbcode_enabled = true
	_verdict.fit_content = true
	_verdict.scroll_active = false
	_verdict.add_theme_font_size_override("normal_font_size", 13)
	_verdict.add_theme_font_size_override("bold_font_size", 13)
	col.add_child(_verdict)

	_error = Label.new()
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.add_theme_color_override("font_color", COL_BAD)
	col.add_child(_error)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(110, 34)
	cancel.pressed.connect(close)
	buttons.add_child(cancel)
	_send = Button.new()
	_send.text = "Send proposal"
	_send.custom_minimum_size = Vector2(160, 34)
	_send.pressed.connect(_send_proposal)
	buttons.add_child(_send)
	col.add_child(buttons)


## One side of the exchange: a picker, an amount field, an Add button, and the list so far.
func _build_side(parent: Control, heading: String, side: String) -> Dictionary:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	parent.add_child(box)
	var h := Label.new()
	h.text = heading
	h.add_theme_font_size_override("font_size", 16)
	box.add_child(h)

	var pick := OptionButton.new()
	pick.fit_to_longest_item = false
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.item_selected.connect(func(_i: int) -> void: _on_amount_changed("", side))
	box.add_child(pick)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var amount := LineEdit.new()
	amount.placeholder_text = "amount — e.g. 5e12, 5T, 5,000,000"
	amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	amount.text_changed.connect(_on_amount_changed.bind(side))
	amount.text_submitted.connect(func(_t: String) -> void: _add(side))
	row.add_child(amount)
	if side == "offer":
		var all := Button.new()
		all.text = "All"
		all.tooltip_text = "Everything of this kind still available to offer."
		all.pressed.connect(_fill_all.bind(side))
		row.add_child(all)
	var add := Button.new()
	add.text = "Add"
	add.pressed.connect(_add.bind(side))
	row.add_child(add)
	box.add_child(row)

	var parsed := Label.new()
	parsed.add_theme_font_size_override("font_size", 11)
	parsed.modulate = COL_DIM
	box.add_child(parsed)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 220)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var total := Label.new()
	total.add_theme_font_size_override("font_size", 14)
	box.add_child(total)
	return {"pick": pick, "amount": amount, "parsed": parsed, "list": list, "total": total}
