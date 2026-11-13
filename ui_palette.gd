class_name UIPalette

## Every colour the menus are drawn in.
##
## There was no theme resource and no palette: each page picked its own colours at the point of
## use, so the same thing was spelled a different way on every page. A dim explanatory line was
## written eleven ways (0.62,0.62,0.70 · 0.62,0.68,0.80 · 0.65,0.65,0.72 · 0.68,0.72,0.78 ·
## 0.70,0.72,0.78 · 0.70,0.75,0.85 · 0.72,0.76,0.84 · 0.74,0.78,0.88 · 0.75,0.75,0.75 ·
## 0.60,0.66,0.76 · 0.6,0.6,0.66), a good reading six, a bad one seven. None of those differences
## meant anything — no page chose its grey to say something another page's grey did not — and
## several of them are below the threshold where a player could see the difference anyway. What
## they produced was a UI that looked assembled rather than designed.
##
## The values here are not new. They are the ones the statistics and politics pages were already
## using, which is where the look the rest is being brought to came from; the roles are named
## after what those two pages use them FOR, so a page that needs "the colour of an explanatory
## line" asks for DIM rather than inventing a grey.
##
## Colour that carries meaning is a different thing and is not here: a star's spectral class, a
## planet's albedo, a polity's banner, the category hues in BuildingData, PoliticsData and
## GameEvents. Those are data about the thing being drawn. These are the colours of the window
## it is drawn in.

# ── Surfaces ──────────────────────────────────────────────────────────────────
# From PanelBackground, which is what the statistics, politics, records, compute, timeline and
# research pages are already drawn on, and from the "Current Effects" box inside politics.

## A page or panel's backing: the deep navy every menu opens as.
const SURFACE: Color = Color(0.05, 0.06, 0.10)
## A box INSIDE a page — politics' effects summary, a row backing, a card. One step up from the
## page it sits on, so it reads as a thing on a surface rather than a hole in it.
const RAISED: Color = Color(0.10, 0.11, 0.15)
## The line around a panel, and the only light-coloured chrome in the UI.
const BORDER: Color = Color(0.35, 0.45, 0.65)
## A hairline inside a panel: a separator, the edge of a row.
const RULE: Color = Color(0.35, 0.45, 0.65, 0.35)
## The lines a graph is read against. Present enough to measure by, faint enough that the data
## is what you see.
const GRID: Color = Color(0.35, 0.45, 0.65, 0.12)
## The dimming a modal draws over the game behind it.
const SHADE: Color = Color(0.0, 0.0, 0.0, 0.55)
## No surface at all: for a panel that sits on top of another one and should let it through.
const CLEAR: Color = Color(0.0, 0.0, 0.0, 0.0)

# ── Text ──────────────────────────────────────────────────────────────────────
# From the politics page, which has the fullest set: a title, a row name, a figure, a label and
# an explanatory line, each a different weight of the same blue-white.

## A page title, and the name of a row the player acts on.
const TITLE: Color = Color(0.95, 0.95, 1.00)
## A figure the player is reading off: a slider's value, a total, a rate.
const VALUE: Color = Color(0.90, 0.90, 1.00)
## An ordinary label beside a figure.
const TEXT: Color = Color(0.80, 0.80, 0.88)
## A section heading, and anything flagged as changed from its natural state.
const HEADER: Color = Color(0.70, 0.80, 0.95)
## The explanatory line under a control: present, but not competing with it.
const DIM: Color = Color(0.62, 0.62, 0.70)
## Something that cannot be used yet — a locked record, a structure you lack the research for.
## DIM, a quarter darker; still legible, plainly inert.
const DISABLED: Color = Color(0.47, 0.47, 0.53)

# ── Readings ──────────────────────────────────────────────────────────────────
# From the politics page's effect summary, which is the one place in the game that already had a
# full good / neutral / bad set. The amber it has no use for is the statistics page's own.

## A reading in the direction the player wants.
const GOOD: Color = Color(0.45, 0.85, 0.55)
## A reading that is not yet a problem but is heading for one: a store nearly full, a budget at
## its cap, a shortage about to bite.
const WARN: Color = Color(0.90, 0.80, 0.20)
## A reading in the wrong direction: a shortfall, a loss, a risk.
const BAD: Color = Color(0.90, 0.55, 0.45)
## A reading at rest — no change either way.
const NEUTRAL: Color = Color(0.72, 0.72, 0.78)

# ── The things the game measures ──────────────────────────────────────────────
# The statistics page's series colours, verbatim. They are here so that a resource is the same
# colour wherever it is named: science was green on the graph, one blue in the research tree,
# another blue in the build panel and a third in the timeline.

const POPULATION: Color = Color(0.30, 0.70, 1.00)
const COMPUTE: Color = Color(0.90, 0.80, 0.20)
const SCIENCE: Color = Color(0.40, 0.90, 0.60)
const MATTER: Color = Color(0.90, 0.50, 0.20)
const ENERGY: Color = Color(0.90, 0.90, 0.30)
const COLONIES: Color = Color(0.50, 0.90, 0.80)
const LIFE: Color = Color(0.95, 0.60, 0.75)


## The backing for a panel that opens against the 3-D view: opaque SURFACE, and SQUARE.
##
## Square because the chrome it opens inside is: the top bar and the sidebar run into the
## window's own corners, where a radius reads as a nick out of the frame rather than as a
## rounded panel, so they are square and everything that butts up against them follows.
static func panel(bordered: bool = true) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = SURFACE
	s.set_corner_radius_all(0)
	if bordered:
		s.set_border_width_all(1)
		s.border_color = BORDER
	return s


## The backing for a box INSIDE a page. No border: the panel around it already has one, and a
## second line 8px inside the first reads as a mistake.
static func inset() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = RAISED
	s.set_corner_radius_all(0)
	return s


## Recolour whatever `ctrl` already draws for `what`, WITHOUT moving anything.
##
## The panels that still take their backing from Godot's default theme cannot be handed a fresh
## stylebox: the theme's carries the content margins that space the panel's children, and a new
## StyleBoxFlat has none, so every page inside one would lose its padding. The margins are read
## off the original and written back explicitly, which also pins them against the border added
## below — a StyleBoxFlat with no content margin of its own derives one from its border width.
##
## On a DUPLICATE, as an override on this one control. The stylebox the theme hands back is
## shared by every PanelContainer in the game, down to the row backings inside the pages, and
## writing to it in place would repaint all of them from whichever panel asked first.
static func repaint(ctrl: Control, what: String, bg: Color, bordered: bool) -> void:
	if ctrl == null:
		return
	var flat := ctrl.get_theme_stylebox(what) as StyleBoxFlat
	if flat == null:
		return
	var own := flat.duplicate() as StyleBoxFlat
	var margins: Array[float] = []
	for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		margins.append(flat.get_margin(side))
	own.bg_color = bg
	own.set_corner_radius_all(0)
	own.set_border_width_all(1 if bordered else 0)
	if bordered:
		own.border_color = BORDER
	for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		own.set_content_margin(side, margins[side])
	ctrl.add_theme_stylebox_override(what, own)


## One Theme for the whole game, built from the palette.
##
## There is no theme resource in the project, so every control that nobody had styled by hand —
## every button, dropdown, text field, list, slider, scrollbar and dialog — was drawn in Godot's
## default theme: translucent neutral greys. On a navy UI they read as grey-brown boxes you can
## see the solar system through, which is most of what made the menus look assembled rather than
## designed. Game applies this to the root Window (GameSession._ready), so it reaches every
## scene, including the start menu and the setup screen.
##
## Every box is a RECOLOURED DUPLICATE of the default theme's, so the margins, border widths and
## sizes that lay the controls out are exactly what they were: the only thing that changes is
## the colour. Two surfaces do nearly all of it — RAISED for a thing you press, SURFACE for a
## thing you type in or read a list out of, with a faint edge so it is visible on a page of the
## same colour.
static func theme() -> Theme:
	var t := Theme.new()
	var base: Theme = ThemeDB.get_default_theme()
	var press := RAISED                  # a button at rest
	var hover := RAISED.lightened(0.12)  # ... under the cursor
	var sunk := SURFACE                  # a field, a list, a slider track
	var edge := Color(BORDER, 0.45)      # the outline that makes a sunk thing visible
	var grab := Color(BORDER, 0.9)       # a scrollbar's thumb, a slider's filled part

	# [stylebox, fill, border, border width]. A box the default theme does not have is skipped,
	# so a name that moves between Godot versions costs nothing.
	var skin: Dictionary = {
		"Button": [
			["normal", press, edge, 1], ["hover", hover, edge, 1],
			["pressed", sunk, BORDER, 1], ["disabled", sunk, edge, 1],
			["focus", CLEAR, HEADER, 1]],
		"OptionButton": [
			["normal", press, edge, 1], ["hover", hover, edge, 1],
			["pressed", sunk, BORDER, 1], ["disabled", sunk, edge, 1],
			["focus", CLEAR, HEADER, 1],
			["normal_mirrored", press, edge, 1], ["hover_mirrored", hover, edge, 1],
			["pressed_mirrored", sunk, BORDER, 1], ["disabled_mirrored", sunk, edge, 1]],
		"LineEdit": [
			["normal", sunk, edge, 1], ["focus", CLEAR, HEADER, 1],
			["read_only", sunk, Color(BORDER, 0.2), 1]],
		"TextEdit": [
			["normal", sunk, edge, 1], ["focus", CLEAR, HEADER, 1],
			["read_only", sunk, Color(BORDER, 0.2), 1]],
		"SpinBox": [
			["up_background_hovered", hover, CLEAR, 0], ["up_background_pressed", sunk, CLEAR, 0],
			["down_background_hovered", hover, CLEAR, 0], ["down_background_pressed", sunk, CLEAR, 0]],
		"Tree": [
			["panel", sunk, edge, 1], ["focus", CLEAR, HEADER, 1],
			["hovered", Color(BORDER, 0.18), CLEAR, 0],
			["hovered_dimmed", Color(BORDER, 0.10), CLEAR, 0],
			["selected", Color(BORDER, 0.45), CLEAR, 0],
			["selected_focus", Color(BORDER, 0.45), CLEAR, 0],
			["hovered_selected", Color(BORDER, 0.55), CLEAR, 0],
			["hovered_selected_focus", Color(BORDER, 0.55), CLEAR, 0],
			["cursor", CLEAR, HEADER, 1], ["cursor_unfocused", CLEAR, Color(BORDER, 0.6), 1],
			["button_hover", hover, CLEAR, 0], ["button_pressed", sunk, CLEAR, 0],
			["title_button_normal", press, edge, 1], ["title_button_hover", hover, edge, 1],
			["title_button_pressed", sunk, edge, 1],
			["custom_button", press, edge, 1], ["custom_button_hover", hover, edge, 1],
			["custom_button_pressed", sunk, edge, 1]],
		"ItemList": [
			["panel", sunk, edge, 1], ["focus", CLEAR, HEADER, 1],
			["hovered", Color(BORDER, 0.18), CLEAR, 0],
			["selected", Color(BORDER, 0.45), CLEAR, 0],
			["selected_focus", Color(BORDER, 0.45), CLEAR, 0],
			["hovered_selected", Color(BORDER, 0.55), CLEAR, 0],
			["hovered_selected_focus", Color(BORDER, 0.55), CLEAR, 0],
			["cursor", CLEAR, HEADER, 1], ["cursor_unfocused", CLEAR, Color(BORDER, 0.6), 1]],
		"PopupMenu": [["panel", RAISED, BORDER, 1], ["hover", hover, CLEAR, 0]],
		"ProgressBar": [["background", sunk, edge, 1], ["fill", grab, CLEAR, 0]],
		"HSlider": [
			["slider", sunk, edge, 1], ["grabber_area", grab, CLEAR, 0],
			["grabber_area_highlight", HEADER, CLEAR, 0]],
		"VSlider": [
			["slider", sunk, edge, 1], ["grabber_area", grab, CLEAR, 0],
			["grabber_area_highlight", HEADER, CLEAR, 0]],
		"HScrollBar": [
			["scroll", sunk, CLEAR, 0], ["grabber", grab, CLEAR, 0],
			["grabber_highlight", HEADER, CLEAR, 0], ["grabber_pressed", HEADER, CLEAR, 0]],
		"VScrollBar": [
			["scroll", sunk, CLEAR, 0], ["grabber", grab, CLEAR, 0],
			["grabber_highlight", HEADER, CLEAR, 0], ["grabber_pressed", HEADER, CLEAR, 0]],
		# A box inside a page, which is what a bare PanelContainer nearly always is. The pages
		# and the panels THEMSELVES are repainted to SURFACE on top of this, one by one, by
		# Game._restyle_menu_panels.
		"PanelContainer": [["panel", RAISED, CLEAR, 0]],
		"Panel": [["panel", RAISED, CLEAR, 0]],
		"TabContainer": [
			["panel", SURFACE, BORDER, 1], ["tab_selected", SURFACE, CLEAR, 0],
			["tab_unselected", RAISED, CLEAR, 0], ["tab_hovered", hover, CLEAR, 0],
			["tab_disabled", sunk, CLEAR, 0], ["tab_focus", CLEAR, HEADER, 1]],
		"TabBar": [
			["tab_selected", SURFACE, CLEAR, 0], ["tab_unselected", RAISED, CLEAR, 0],
			["tab_hovered", hover, CLEAR, 0], ["tab_disabled", sunk, CLEAR, 0],
			["tab_focus", CLEAR, HEADER, 1]],
		"AcceptDialog": [["panel", SURFACE, BORDER, 1]],
		"Window": [["embedded_border", SURFACE, BORDER, 1],
			["embedded_unfocused_border", SURFACE, Color(BORDER, 0.5), 1]],
	}
	for type: String in skin:
		for row: Array in (skin[type] as Array):
			var src := base.get_stylebox(str(row[0]), type) as StyleBoxFlat
			if src == null:
				continue
			t.set_stylebox(str(row[0]), type, _skin(src, row[1], row[2], int(row[3])))

	# The ink. Same roles, same names, and no control left reading in Godot's off-white.
	var ink: Dictionary = {
		"Button": {"font_color": TEXT, "font_hover_color": TITLE, "font_pressed_color": TITLE,
			"font_focus_color": TITLE, "font_hover_pressed_color": TITLE,
			"font_disabled_color": DISABLED},
		"OptionButton": {"font_color": TEXT, "font_hover_color": TITLE,
			"font_pressed_color": TITLE, "font_focus_color": TITLE,
			"font_disabled_color": DISABLED},
		"CheckBox": {"font_color": TEXT, "font_hover_color": TITLE, "font_pressed_color": TITLE,
			"font_disabled_color": DISABLED},
		"CheckButton": {"font_color": TEXT, "font_hover_color": TITLE,
			"font_pressed_color": TITLE, "font_disabled_color": DISABLED},
		"Label": {"font_color": TEXT},
		"LineEdit": {"font_color": VALUE, "font_placeholder_color": DISABLED,
			"font_uneditable_color": DISABLED, "caret_color": HEADER,
			"selection_color": Color(BORDER, 0.5)},
		"TextEdit": {"font_color": VALUE, "font_placeholder_color": DISABLED,
			"caret_color": HEADER, "selection_color": Color(BORDER, 0.5)},
		"Tree": {"font_color": TEXT, "font_selected_color": TITLE,
			"font_hovered_color": TITLE, "font_disabled_color": DISABLED,
			"title_button_color": TEXT, "guide_color": GRID,
			"relationship_line_color": GRID, "parent_hl_line_color": RULE,
			"children_hl_line_color": RULE},
		"ItemList": {"font_color": TEXT, "font_selected_color": TITLE,
			"font_hovered_color": TITLE, "guide_color": GRID},
		"PopupMenu": {"font_color": TEXT, "font_hover_color": TITLE,
			"font_disabled_color": DISABLED, "font_accelerator_color": DIM,
			"font_separator_color": DIM},
		"TabContainer": {"font_selected_color": TITLE, "font_unselected_color": DIM,
			"font_hovered_color": TEXT, "font_disabled_color": DISABLED},
		"TabBar": {"font_selected_color": TITLE, "font_unselected_color": DIM,
			"font_hovered_color": TEXT, "font_disabled_color": DISABLED},
		"ProgressBar": {"font_color": TITLE},
		"HSeparator": {}, "VSeparator": {},
	}
	for type: String in ink:
		for what: String in (ink[type] as Dictionary):
			t.set_color(what, type, (ink[type] as Dictionary)[what])
	# The separators between sections, which the default theme draws as a grey line.
	for type: String in ["HSeparator", "VSeparator"]:
		var line := base.get_stylebox("separator", type) as StyleBoxLine
		if line != null:
			var own := line.duplicate() as StyleBoxLine
			own.color = RULE
			t.set_stylebox("separator", type, own)
	t.default_font = font()
	return t


## The fonts the symbols come from, in order, when the UI font does not have them.
##
## Today's picks, named outright: every arrow, triangle, star, tick and cross the menus use comes
## from DejaVu Sans, and the one chain glyph from Noto Sans Symbols2 — which is exactly what the
## per-text system search was choosing, so nothing looks different.  The Windows and macOS names
## after them are there for a port; the game exports to Linux only.
const SYMBOL_FONTS: Array = [
	["DejaVu Sans", "Segoe UI Symbol", "Apple Symbols"],
	["Noto Sans Symbols2", "Noto Sans Symbols 2", "Symbola", "Segoe UI Symbol", "Apple Symbols"],
]

## The UI font: Godot's own (Open Sans), given the symbol fonts above as FIXED fallbacks.
##
## Without them, opening the Infrastructure tab froze the game for two seconds.  Open Sans has no
## arrows, triangles, ⚙ or ✕, and for every piece of text containing one, Godot asked the
## operating system which installed font had it — afresh each time, at about five milliseconds a
## label.  A building level carries three "↑" upgrade buttons and every card a "▶" toggle and a
## "⚙" badge, so a tab of a hundred-odd levels spent nearly all of its two seconds asking the same
## question.  Named fallbacks are consulted before that search is ever reached, and a symbol drawn
## from one costs what plain text does.
##
## Done to the ENGINE's font, in place, not to a copy handed to the theme.  A control lays its
## text out once as it enters the tree, before its theme reaches it, and that pass uses the
## engine's font — so a themed copy fixed the second layout and left the first, which was the slow
## one.  Everything without a theme (a Label3D) gets the same fallbacks the menus do.
##
## The system search itself is left ON, as the last resort: a character in neither Open Sans nor
## a fallback is still found, only slowly.  tests/verify_ui_font.gd checks every symbol in the
## source is covered, so that the slow path is one nothing in the game takes.
static func font() -> Font:
	var f: Font = ThemeDB.fallback_font
	if f.fallbacks.is_empty():
		var chain: Array[Font] = []
		for names: Array in SYMBOL_FONTS:
			var sym := SystemFont.new()
			sym.font_names = PackedStringArray(names)
			chain.append(sym)
		f.fallbacks = chain
	return f


## A recoloured copy of one of the default theme's boxes, keeping everything that positions it.
static func _skin(src: StyleBoxFlat, bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var own := src.duplicate() as StyleBoxFlat
	var margins: Array[float] = []
	for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		margins.append(src.get_margin(side))
	own.bg_color = bg
	own.draw_center = bg.a > 0.0
	own.set_corner_radius_all(0)
	own.set_border_width_all(width)
	own.border_color = border
	for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		own.set_content_margin(side, margins[side])
	return own


## Hand `t` to every Control that has nothing above it to inherit from.
##
## A theme flows down the CONTROL tree. The whole game UI hangs off CanvasLayers, and a
## CanvasLayer is not a Control, so it cuts that chain: a theme set on the root Window reaches a
## Control parented straight to the window and nothing else — measured, not assumed. This gives
## the theme to each Control whose parent is NOT a Control, which is the root of every island,
## and everything inside an island inherits from it as usual.
##
## A Control that already carries a theme of its own is left alone.
static func dress(node: Node, t: Theme) -> void:
	if node is Control:
		if node.get_parent() is Control:
			return      # inherits from its parent; so does everything under it
		if (node as Control).theme == null:
			(node as Control).theme = t
		return
	for child: Node in node.get_children():
		dress(child, t)
