extends SceneTree

## One palette for the menus, and it is the statistics and politics pages'.
##
## There was no theme resource and no palette. Every page picked its colours at the point of
## use, so the same thing was spelled differently on every page: a dim explanatory line was
## written eleven ways, a good reading six, a bad one seven, and none of the differences meant
## anything. Everything nobody had styled by hand — every button, dropdown, field, list, slider
## and scrollbar, and the planet and launch panels themselves — was drawn in Godot's DEFAULT
## theme: translucent neutral greys you could read the solar system through.
##
## This checks three things, because each failed differently:
##
##  1. The source. No menu script carries a chrome colour of its own any more. A count per file
##     rather than a list, so a new literal fails even if it is a plausible-looking blue.
##  2. The panels. What each menu actually draws, measured off the live control.
##  3. The theme reaching the controls. A theme flows down the CONTROL tree and the whole UI
##     hangs off CanvasLayers, which are not Controls — so a theme set on the root window alone
##     reached almost nothing. That was a real bug on the way here, and it looked like success:
##     the Theme existed, it had the right styleboxes in it, and no control was using it.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)


## Scripts whose colours say what a THING IS, not what the window around it is painted: a star's
## spectral class, a world's crust, a compound, a polity's banner, the category hues the build
## menu, the policy page and the timeline sort by. Those are data and are not the palette's
## business. Everything else in the project is swept.
const DATA: Array = [
	"allegiance.gd", "asteroid_belt.gd", "buildings.gd", "compound_data.gd", "disassembly.gd",
	"events.gd", "init_planets.gd", "planet.gd", "politics_data.gd", "satellite.gd",
	"star_model.gd", "star_sky.gd", "stellar_evolution.gd", "stock_data.gd",
	"timeline_events.gd",
	# Two views that are mostly a drawn sky or a drawn galaxy: the stars, nebulae, galaxies and
	# diplomatic states they paint are data. Their CHROME — titles, hints, dialogs, backdrops,
	# the buttons down the side — is on the palette like everything else.
	"StarMapPanel.gd", "GalaxyDebugPanel.gd",
]

## What a file is still allowed to spell out, and why. A COUNT, so adding one more fails here
## even if it looks like something that belongs.
const KEPT: Dictionary = {
	# The extinction red and the cause orange: the one moment the UI is allowed to raise its
	# voice, and UIPalette.BAD is the colour of a reading going the wrong way, not of the end.
	"game_over_screen.gd": 2,
	# LAYER_COLOR: what a world is made of, down to the core. Data wearing a menu's clothes.
	"PlanetInfoPage.gd": 4,
	# The map's own: unsettled space, Sol, the galactic centre.
	"GalaxyMapPanel.gd": 3,
	# The flash when a research lands, which is brighter than white on purpose.
	"ResearchTreeUI.gd": 1,
}


func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_scan_source()
	await _check_panels()
	print("FAILS: %d" % fails)
	quit()


# ── 1. Nothing spells a chrome colour out any more ────────────────────────────

func _scan_source() -> void:
	var re := RegEx.new()
	re.compile("Color\\(\\s*([0-9][0-9.,\\s]*)\\)")
	var scanned: int = 0
	var literals: int = 0
	for f: String in DirAccess.get_files_at("res://"):
		if not f.ends_with(".gd") or f == "ui_palette.gd" or DATA.has(f):
			continue
		scanned += 1
		var text: String = FileAccess.get_file_as_string("res://" + f)
		var found: Array = []
		for m: RegExMatch in re.search_all(text):
			if _is_greyscale(m.get_string(1)):
				continue        # r == g == b is an opacity knob, not a colour
			found.append(m.get_string(0))
		literals += found.size()
		var allowed: int = int(KEPT.get(f, 0))
		check(found.size() == allowed,
			"%s spells out %d colours, not %d: %s" % [
				f, found.size(), allowed, str(found.slice(0, 4))])
	check(scanned > 40, "the sweep reached the scripts: %d" % scanned)
	print("scanned %d scripts, %d colours spelled out" % [scanned, literals])

	# And the palette does not say the same thing twice. Two roles that happen to be equal are
	# two names for one decision, which is how a palette comes apart again.
	var pal: Dictionary = load("res://ui_palette.gd").get_script_constant_map()
	var seen: Dictionary = {}
	var clashes: Array = []
	for name: String in pal:
		var v: Variant = pal[name]
		if not (v is Color):
			continue
		var key: String = str(v)
		# The amber a warning is written in IS the statistics page's compute series. One colour,
		# deliberately doing both jobs, and that is the only pair allowed to.
		if seen.has(key) and not ([name, seen[key]].has("WARN")):
			clashes.append("%s == %s" % [name, seen[key]])
		seen[key] = name
	check(clashes.is_empty(), "every role is its own colour: %s" % str(clashes))
	check(seen.size() >= 15, "the palette has its roles: %d" % seen.size())


## True for Color(x, x, x) and Color(x, x, x, a): a brightness or an opacity, not a hue.
func _is_greyscale(args: String) -> bool:
	var parts: PackedStringArray = args.split(",", false)
	if parts.size() < 3:
		return false
	var r: float = float(parts[0].strip_edges())
	var g: float = float(parts[1].strip_edges())
	var b: float = float(parts[2].strip_edges())
	return is_equal_approx(r, g) and is_equal_approx(g, b)


# ── 2. and 3. What the menus actually draw ────────────────────────────────────

func _check_panels() -> void:
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var pal: Script = load("res://ui_palette.gd")
	var surface: Color = pal.SURFACE
	var border: Color = pal.BORDER
	var raised: Color = pal.RAISED

	# Every full-area page, the planet panel and the launch panel: the deep navy of the
	# statistics and politics pages, with the one light-blue line around it.
	var outer: Array = []
	for n: Node in g.sidebar.get_children():
		if n is Control and str(n.name) != "sidebar":
			outer.append(n)
	check(outer.size() >= 8, "the sidebar holds its pages: %d" % outer.size())
	outer.append(g._planet_tabs)
	outer.append(g.launch_panel)
	# Measured on the thing that actually PAINTS. A page carries its backing one of two ways —
	# a PanelBackground behind a plain Control, or the control's own themed panel — and a plain
	# Control with neither draws nothing at all, so reading a stylebox off one would pass on a
	# box no one renders. Those are collected by name instead and named below.
	var wrong: Array = []
	var self_painted: Array = []
	for n: Node in outer:
		var c := n as Control
		var box: StyleBoxFlat = null
		var bg := c.get_node_or_null("PanelBackground") as Control
		if bg != null:
			box = bg.get_theme_stylebox("panel") as StyleBoxFlat
		elif c is PanelContainer or c is TabContainer or c is Panel:
			box = c.get_theme_stylebox("panel") as StyleBoxFlat
		else:
			self_painted.append(c.get_script().resource_path.get_file())
			continue
		if box == null:
			wrong.append("%s draws no panel" % str(c.name))
		elif not box.bg_color.is_equal_approx(surface):
			wrong.append("%s fill %s" % [str(c.name), str(box.bg_color)])
		elif not box.border_color.is_equal_approx(border) or box.border_width_left < 1:
			wrong.append("%s edge %s/%d" % [
				str(c.name), str(box.border_color), box.border_width_left])
	check(wrong.is_empty(), "every menu panel is the palette's surface and edge: %s" % str(wrong))
	# The four that fill themselves in _draw, and nothing else. Their colours come from
	# UIPalette too — the source sweep above is what holds them there — except the star map's
	# sky, which is deliberately BLACK rather than SURFACE, because it is a view of the sky.
	self_painted.sort()
	check(self_painted == ["EvolutionTreeUI.gd", "GalaxyDebugPanel.gd", "GalaxyMapPanel.gd",
			"StarMapPanel.gd"],
		"only the drawn views paint their own background: %s" % str(self_painted))

	# The tab pages are CLEAR: each covers the wrapper's whole content area, so painted they
	# hide its outline and bordered they would draw that outline once per tab.
	var painted: Array = []
	for n: Node in g._planet_tabs.get_children():
		if not (n is Control):
			continue
		var box := (n as Control).get_theme_stylebox("panel") as StyleBoxFlat
		if box == null or box.bg_color.a > 0.0 or box.border_width_left > 0:
			painted.append(str((n as Control).name))
	check(painted.is_empty(), "the tab pages let the wrapper through: %s" % str(painted))
	# And the wrapper's frame goes round the whole thing — the strip carries the top, the page
	# below it carries the bottom, and the seam where they meet is the edge neither draws.
	var strip := g._planet_tabs.get_theme_stylebox("tabbar_background") as StyleBoxFlat
	var body := g._planet_tabs.get_theme_stylebox("panel") as StyleBoxFlat
	check(strip != null and strip.border_width_top == 1 and strip.border_width_bottom == 0,
		"the tab strip carries the top of the frame and not its bottom")
	check(body != null and body.border_width_top == 0 and body.border_width_bottom == 1,
		"and the page below it carries the bottom and not the top")

	# The theme crossed the CanvasLayer. Checked on a button nobody styled by hand, which is the
	# whole point: before this, every such control was Godot's grey.
	var btn: Button = g.get_node("main_ui/VBoxContainer3/HBoxContainer2/sidebar/research")
	var normal := btn.get_theme_stylebox("normal") as StyleBoxFlat
	check(normal != null and normal.bg_color.is_equal_approx(raised),
		"a plain button is the palette's: %s" % (str(normal.bg_color) if normal else "none"))
	check(btn.get_theme_color("font_color").is_equal_approx(pal.TEXT),
		"and reads in it: %s" % str(btn.get_theme_color("font_color")))
	# Deep inside a page too, so it is inheritance and not one lucky node.
	var deep: Control = _first_of(g.sidebar.politics_page, "HSlider")
	check(deep != null, "the politics page has its sliders")
	if deep != null:
		var track := deep.get_theme_stylebox("slider") as StyleBoxFlat
		check(track != null and track.bg_color.is_equal_approx(surface),
			"a slider five levels down is too: %s" % (str(track.bg_color) if track else "none"))

	# The two pages the palette came FROM are still drawn in it, which is what makes the rest
	# matching them mean anything.
	var pol: Control = g.sidebar.politics_page
	var effects: Control = _first_of(pol, "PanelContainer")
	check(effects != null, "the politics page still has its effects box")
	if effects != null:
		var box := effects.get_theme_stylebox("panel") as StyleBoxFlat
		check(box != null and box.bg_color.is_equal_approx(raised),
			"and it is the palette's RAISED: %s" % (str(box.bg_color) if box else "none"))
	var metrics: Array = load("res://statistics_page.gd").get_script_constant_map()["GRAPH_METRICS"]
	var series: Array = []
	for m: Dictionary in metrics:
		series.append(str(m["color"]))
	check(series.has(str(pal.SCIENCE)) and series.has(str(pal.ENERGY)),
		"the statistics page's series are the palette's: %s" % str(series.slice(0, 3)))

	# And the legend shows a series' colour while that series is ON the graph. The two
	# overrides were the wrong way round: every toggle starts pressed, pressed was white and
	# unpressed was the series colour, so the legend was blank until you switched a line OFF
	# — the one moment its colour meant nothing, because the line was no longer drawn.
	var stats: Control = g.sidebar.statistics
	var backwards: Array = []
	for m: Dictionary in metrics:
		var b: Button = stats._toggle_buttons.get(str(m["key"])) as Button
		if b == null:
			backwards.append("%s has no toggle" % str(m["key"]))
		elif not b.get_theme_color("font_pressed_color").is_equal_approx(m["color"]):
			backwards.append("%s drawn in %s, not %s" % [str(m["key"]),
				str(b.get_theme_color("font_pressed_color")), str(m["color"])])
		elif not b.get_theme_color("font_color").is_equal_approx(pal.DISABLED):
			backwards.append("%s switched off reads %s" % [
				str(m["key"]), str(b.get_theme_color("font_color"))])
	check(backwards.is_empty(), "a series wears its own colour while it is drawn: %s" % str(backwards))


## The first descendant of `node` whose class is `cls`, depth first.
func _first_of(node: Node, cls: String) -> Control:
	for c: Node in node.get_children():
		if c.is_class(cls):
			return c as Control
		var deeper: Control = _first_of(c, cls)
		if deeper != null:
			return deeper
	return null
