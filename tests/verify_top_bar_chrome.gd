extends SceneTree

## The chrome across the top and down the left: its border, and the four resource readouts.
##
## ── The border ──
##
## The top bar and the sidebar are plain containers, so each is drawn over an opaque backing
## Panel whose StyleBoxFlat supplies the light-blue outline. A StyleBoxFlat draws its border at
## the panel's own edges, and both bars sit flush against the window edge — so growing their
## rects by the backing margin put the top bar's left, top and right edges and the sidebar's
## left and bottom edges OUTSIDE the viewport. What was left visible was the top bar's bottom
## border and the sidebar's right border: two lines through the middle of the screen rather than
## an outline around anything.
##
## Clamping brings them back, but that alone is not enough: the TimeBox and the sidebar buttons
## paint their own opaque styleboxes flush at x = 0, straight over a border drawn at the same
## pixel. The bar stack is inset by the margin so the content sits INSIDE the frame.
##
## ── The readouts ──
##
## Four PanelContainers packed against the speed buttons, each as wide as its text. So they read
## as four sunken boxes bolted onto a bar that is already a panel, they left the right half of
## the bar empty, and every one of them jumped sideways whenever a figure crossed an SI prefix —
## on a bar across the top of the screen, which is the last thing that should move.

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
	var view: Rect2 = g.get_viewport().get_visible_rect()


	# ── Every edge of both backings is on screen ──
	var top_bar: Control = g.get_node_or_null("main_ui/VBoxContainer3/HBoxContainer")
	var side: Control = g.get_node_or_null("main_ui/VBoxContainer3/HBoxContainer2/sidebar")
	check(top_bar != null and side != null, "the two bars are there")
	for pair: Array in [["top bar", g._top_bar_bg, top_bar], ["sidebar", g._side_bar_bg, side]]:
		var what: String = str(pair[0])
		var bg: Panel = pair[1]
		var bar: Control = pair[2]
		check(bg != null, "%s has a backing panel" % what)
		if bg == null:
			continue
		var r := Rect2(bg.global_position, bg.size)
		var off: Array = []
		if r.position.x < view.position.x: off.append("left")
		if r.position.y < view.position.y: off.append("top")
		if r.end.x > view.end.x:           off.append("right")
		if r.end.y > view.end.y:           off.append("bottom")
		check(off.is_empty(),
			"%s: no edge of the border falls outside the viewport — %s is outside %s (%s)" % [
				what, str(r), str(view), str(off)])
		# And it still surrounds its bar rather than merely overlapping it.
		var b := Rect2(bar.global_position, bar.size)
		check(r.encloses(b) or r.intersects(b),
			"%s: the backing still covers the bar" % what)
		# The content is held OFF the border on the two sides where the bar is flush with the
		# window and its children paint opaquely. Right and bottom are not asserted: the top
		# bar's children are left-aligned and the sidebar's buttons stop well short of the
		# bottom, so nothing paints over the border there and the bar is free to reach the edge.
		check(b.position.x > r.position.x,
			"%s: content starts right of the border (%f vs %f)" % [
				what, b.position.x, r.position.x])
		check(b.position.y > r.position.y,
			"%s: content starts below the border (%f vs %f)" % [
				what, b.position.y, r.position.y])

	# The clamp itself, on a bar that pokes out of a small viewport in every direction.
	var probe := Panel.new()
	g.add_child(probe)
	g._fit_bar_bg(probe, Rect2(0, 0, 100, 20), Rect2(0, 0, 100, 100))
	var pr := Rect2(probe.global_position, probe.size)
	check(pr.position.x >= 0.0 and pr.position.y >= 0.0 and pr.end.x <= 100.0,
		"a bar flush with the viewport keeps its whole border inside it: %s" % str(pr))
	check(pr.position.x < 1.0 and pr.end.x > 99.0,
		"and still spans it: %s" % str(pr))
	g._fit_bar_bg(probe, Rect2(20, 20, 40, 40), Rect2(0, 0, 200, 200))
	var pr2 := Rect2(probe.global_position, probe.size)
	check(pr2.position.x < 20.0 and pr2.end.x > 60.0,
		"a bar with room to spare still gets its full margin: %s" % str(pr2))
	probe.queue_free()


	# ── Square corners, because these two run into the window's own ──
	for pair: Array in [["top bar", g._top_bar_bg], ["sidebar", g._side_bar_bg]]:
		var sb: StyleBox = (pair[1] as Panel).get_theme_stylebox("panel")
		check(sb is StyleBoxFlat, "%s's backing is a StyleBoxFlat" % str(pair[0]))
		if sb is StyleBoxFlat:
			var f: StyleBoxFlat = sb
			check(f.corner_radius_top_left == 0 and f.corner_radius_top_right == 0
					and f.corner_radius_bottom_left == 0 and f.corner_radius_bottom_right == 0,
				"%s has square corners: %d/%d/%d/%d" % [str(pair[0]),
					f.corner_radius_top_left, f.corner_radius_top_right,
					f.corner_radius_bottom_left, f.corner_radius_bottom_right])


	# ── The sidebar's border lines up with the right edge of the clock above it ──
	var clock: Control = g.get_node_or_null("main_ui/VBoxContainer3/HBoxContainer/TimeBox")
	check(clock != null, "the clock panel is there")
	if clock != null and g._side_bar_bg != null:
		var sb_right: float = g._side_bar_bg.global_position.x + g._side_bar_bg.size.x
		var clock_right: float = clock.global_position.x + clock.size.x
		check(absf(sb_right - clock_right) <= 0.5,
			"the sidebar's border meets the clock's right edge: %f vs %f" % [
				sb_right, clock_right])


	# ── The planet panel keeps one margin from the chrome on both sides ──
	check(g._planet_tabs != null, "the planet tabs exist")
	if g._planet_tabs != null:
		var pt := Rect2(g._planet_tabs.global_position, g._planet_tabs.size)
		var right_gap: float = view.end.x - pt.end.x
		var top_gap: float = pt.position.y - (g._top_bar_bg.global_position.y + g._top_bar_bg.size.y)
		check(absf(right_gap - g.PLANET_PANEL_GAP) <= 0.5,
			"it hangs off the right edge by the set gap: %f vs %f" % [
				right_gap, g.PLANET_PANEL_GAP])
		check(absf(top_gap - right_gap) <= 0.5,
			"and sits below the top bar by the same: %f below vs %f right" % [top_gap, right_gap])
		# Moving the top down must not eat the panel's height. Measured by MOVING it: the panel
		# is pushed down by the bar, so the bar is made taller and the panel has to follow at the
		# same size. Comparing a height against itself cannot catch this — the loss happens once,
		# when the top moves, and a panel that settled 14px short stays 14px short for ever.
		var h0: float = g._planet_tabs.offset_bottom - g._planet_tabs.offset_top
		var y0: float = g._planet_tabs.offset_top
		check(h0 > 100.0, "the panel has a height: %f" % h0)
		g._top_bar_bg.size.y += 20.0
		g._layout_menu_panels()
		check(absf(g._planet_tabs.offset_top - (y0 + 20.0)) <= 0.5,
			"a taller bar pushes the panel down: %f -> %f" % [y0, g._planet_tabs.offset_top])
		# The launch panel opens beside it, is anchored to the same corner, and carried the same
		# stale offset of 52. It is placed off the same measurement now, so it moves with it.
		check(absf(g.launch_panel.offset_top - g._planet_tabs.offset_top) <= 0.5,
			"the launch panel's top is the planet panel's: %f vs %f" % [
				g.launch_panel.offset_top, g._planet_tabs.offset_top])
		check(absf((g._planet_tabs.offset_bottom - g._planet_tabs.offset_top) - h0) <= 0.5,
			"and it keeps its height on the way: %f -> %f" % [
				h0, g._planet_tabs.offset_bottom - g._planet_tabs.offset_top])
		g._top_bar_bg.size.y -= 20.0
		g._layout_menu_panels()
		check(absf(g._planet_tabs.offset_top - y0) <= 0.5, "and comes back: %f" % g._planet_tabs.offset_top)
		check(absf(g.launch_panel.offset_top - y0) <= 0.5,
			"and the launch panel with it: %f" % g.launch_panel.offset_top)

		# And re-laying out does not eat a little more each pass.
		for _p in range(3):
			g._layout_bar_backgrounds()
		await process_frame
		check(absf((g._planet_tabs.offset_bottom - g._planet_tabs.offset_top) - h0) <= 0.5,
			"laying out again does not shrink it: %f -> %f" % [
				h0, g._planet_tabs.offset_bottom - g._planet_tabs.offset_top])
		# The sidebar width is written from inside the layout pass, which re-enters it. It has to
		# settle rather than creep.
		var sw: float = g.get_node("main_ui/VBoxContainer3/HBoxContainer2/sidebar").size.x
		for _p in range(3):
			g._layout_bar_backgrounds()
		for _p in range(3):
			await process_frame
		check(absf(g.get_node("main_ui/VBoxContainer3/HBoxContainer2/sidebar").size.x - sw) <= 0.5,
			"the sidebar width settles instead of creeping: %f -> %f" % [
				sw, g.get_node("main_ui/VBoxContainer3/HBoxContainer2/sidebar").size.x])


	# ── The readouts have no background of their own ──
	var keys: Array = ["minerals", "energy", "compute", "heat"]
	var boxes: Array = []
	for k: String in keys:
		check(g._res_boxes.has(k), "there is a %s readout" % k)
		var l: Label = g._res_boxes[k]["value"]
		var box: Control = l.get_parent().get_parent()
		boxes.append(box)
		check(not (box is PanelContainer),
			"%s does not sit in a panel: %s" % [k, box.get_class()])
		# Belt and braces: whatever the node is, it must not be painting a styled box.
		check(box.get_theme_stylebox("panel") == null or not (box is PanelContainer),
			"%s draws no background" % k)


	# ── They are evenly spaced, and the same width as each other ──
	var widths: Array = []
	var lefts: Array = []
	for b: Control in boxes:
		widths.append(b.size.x)
		lefts.append(b.global_position.x)
	for i in range(1, widths.size()):
		check(absf(float(widths[i]) - float(widths[0])) <= 1.0,
			"all four are the same width: %s" % str(widths))
	var gaps: Array = []
	for i in range(1, lefts.size()):
		gaps.append(float(lefts[i]) - float(lefts[i - 1]))
	for gp: float in gaps:
		check(absf(gp - float(gaps[0])) <= 1.0,
			"and evenly spaced: starts %s, gaps %s" % [str(lefts), str(gaps)])
	# Spread across the bar rather than bunched against the speed buttons: the four together
	# reach most of the way to the clock.
	var span: float = float(lefts[3]) + float(widths[3]) - float(lefts[0])
	check(span > top_bar.size.x * 0.5,
		"and they span the bar rather than bunching: %f of %f" % [span, top_bar.size.x])


	# ── And a change of TEXT cannot move any of them ──
	# The failure this is here for: a figure crossing into another SI prefix is a longer string,
	# a Label reports a minimum size that fits its string, and the container honours it.
	var before_w: Array = widths.duplicate()
	var before_x: Array = lefts.duplicate()
	g._set_res_box("energy", "999.9999 QJ / 123456.7890 YJ", "+1234.5678 YW")
	g._set_res_box("compute", "8", "")
	g._set_res_box("heat", "0.0000001 pW / 99999999.9 YW", "")
	for _i in range(4): await process_frame
	for i in range(boxes.size()):
		var b: Control = boxes[i]
		check(absf(b.size.x - float(before_w[i])) <= 1.0,
			"%s keeps its width through a text change: %f -> %f" % [
				keys[i], float(before_w[i]), b.size.x])
		check(absf(b.global_position.x - float(before_x[i])) <= 1.0,
			"%s does not move: %f -> %f" % [
				keys[i], float(before_x[i]), b.global_position.x])
	# Measured at the mechanism, because the assertions above cannot fail at this window size:
	# the row is wide enough that an equal quarter of it (~478 px at 1920) exceeds anything a
	# figure can spell, so the boxes stay equal on expansion alone. On a narrow window the share
	# drops below the text and the MINIMUM is what decides — so that is what must not know about
	# the text.
	for k: String in keys:
		var vl: Label = g._res_boxes[k]["value"]
		var vbox: Control = vl.get_parent().get_parent()
		check(vl.clip_text, "%s's value label is clipped rather than sizing to its text" % k)
		vl.text = "8"
		await process_frame
		var short_l: float = vl.get_combined_minimum_size().x
		var short_b: float = vbox.get_combined_minimum_size().x
		vl.text = "999.9999 QJ / 123456.7890 YJ / 0.00001 pJ"
		await process_frame
		var long_l: float = vl.get_combined_minimum_size().x
		var long_b: float = vbox.get_combined_minimum_size().x
		check(absf(long_l - short_l) < 1.0,
			"%s's label asks for the same width either way: %f vs %f" % [k, short_l, long_l])
		check(absf(long_b - short_b) < 1.0,
			"so the box does too: %f vs %f" % [short_b, long_b])
		check(absf(short_b - g.RES_BOX_MIN_W) < 1.0,
			"and that width is the floor the code sets, not the text: %f vs %f" % [
				short_b, g.RES_BOX_MIN_W])


	# ── Every menu panel is square, and opens clear of the sidebar ──
	#
	# Three different things carry a panel: a plain Control with a PanelBackground behind it, a
	# PanelContainer, and the planet panel's TabContainer. Only the first was square — the other
	# two take their backing from Godot's default theme, which rounds it by 3px — so the UI was
	# square around the outside and rounded everywhere inside it.
	#
	# Swept over whatever the sidebar holds rather than over a list of names, because that is how
	# Game._restyle_menu_panels works: a page added later has to come out square without this
	# test being told it exists.
	var pages: Array = []
	for n: Node in g.sidebar.get_children():
		if n is Control and str(n.name) != "sidebar":
			pages.append(n)
	check(pages.size() >= 8, "the sidebar holds its pages: %d" % pages.size())
	var panels: Array = pages.duplicate()
	panels.append(g._planet_tabs)
	for n: Node in g._planet_tabs.get_children():
		if n is Control:
			panels.append(n)
	panels.append(g.launch_panel)
	var rounded: Array = []
	for n: Node in panels:
		var c := n as Control
		for r: int in _radii(c, "panel"):
			if r != 0:
				rounded.append("%s %s: %d" % [c.get_class(), str(c.name), r])
		var bg := c.get_node_or_null("PanelBackground") as Control
		if bg != null:
			for r2: int in _radii(bg, "panel"):
				if r2 != 0:
					rounded.append("%s's backing: %d" % [str(c.name), r2])
	check(rounded.is_empty(), "every menu panel is square: %s" % str(rounded.slice(0, 6)))
	print("squared %d menu panels" % panels.size())

	# Every page MEETS the sidebar: its own left border lands on the sidebar's right one, so the
	# two share a single line.
	#
	# The pages are siblings of the button strip in an HBox, and the strip's BACKING — the thing
	# carrying the border — hangs BAR_BG_PAD.x further right than the strip itself. On the
	# container's default separation of 4 every page opened 2px inside that border, drawn over
	# the middle of it; at the overhang exactly it would start one pixel PAST the border, which
	# now that every page draws a border of its own is two parallel lines a pixel apart.
	#
	# One at a time, because an HBoxContainer skips hidden children: a page that is not showing
	# keeps whatever rect it last had, so sweeping them all at once measures the layout of the
	# previous frame rather than where each one actually opens.
	#
	# And every page FILLS what is left of the window. The compute and automation pages set a
	# minimum size and no expand flag, so the HBox gave them their minimum — 620 and 820 of a
	# 1920 window — and they stopped two fifths of the way across. That was invisible while the
	# pages were translucent and read as a panel that had failed to load once they were not.
	var side_right: float = g._side_bar_bg.global_position.x + g._side_bar_bg.size.x
	var adrift: Array = []
	var short_pages: Array = []
	for n: Node in pages:
		var c := n as Control
		g.sidebar.hide_all()
		c.show()
		for _i in range(3): await process_frame
		if absf(c.global_position.x - (side_right - 1.0)) > 0.5:
			adrift.append("%s at %.1f" % [str(c.name), c.global_position.x])
		if view.end.x - (c.global_position.x + c.size.x) > 0.5:
			short_pages.append("%s ends at %.0f" % [
				str(c.name), c.global_position.x + c.size.x])
	g.sidebar.hide_all()
	await process_frame
	check(adrift.is_empty(),
		"every page's border lands on the sidebar's, at %.1f: %s" % [
			side_right - 1.0, str(adrift.slice(0, 6))])
	check(short_pages.is_empty(),
		"and every page reaches the far edge at %.0f: %s" % [
			view.end.x, str(short_pages.slice(0, 6))])

	# ── A page's text does not run into the panel's own border ──
	#
	# Three panels in node_3d.tscn wrap their contents in a MarginContainer and set no margins
	# on it, so the container did nothing and every line started at the panel's own border: the
	# body's Info page (its name, every key and value in the stat grid, every composition row)
	# and the Infrastructure and Launch titles. The pages built in code — Population, Inventory,
	# Extraction, Production — all set their own, which is what made the ones that did not look
	# like a mistake rather than a style. Statistics builds its whole
	# layout in code and the MarginContainer the scene wraps it in holds nothing, so its padding
	# is in statistics_page.gd rather than the scene.
	#
	# Measured as the gap between a page's edge and the nearest visible label's BOX, which is
	# where a left-aligned label's text starts.
	const PAD_MIN: float = 8.0
	# The body's pages have to be FILLED before they are measured: an Info page nobody has handed
	# a planet to has no text on it, and a page with nothing written on it passes anything.
	g.planet_info_page.set_planet_info(g.get_planet_data("earth"))
	var tabs2 = g._planet_tabs
	# Every ancestor too: the checks above hide pages to measure the frame, and a label whose
	# PARENT is hidden reports is_visible_in_tree() false — which skipped every page in silence
	# and passed this whole section however the panels were laid out.
	var anc: Node = tabs2
	while anc != null:
		if anc is CanvasItem:
			(anc as CanvasItem).visible = true
		anc = anc.get_parent()
	var padded_pages: Array = []
	for t2 in range(tabs2.get_tab_count()):
		tabs2.current_tab = t2
		for _i in range(8): await process_frame
		padded_pages.append(tabs2.get_tab_control(t2))
	check(padded_pages.size() >= 6, "every body page is measured: %d" % padded_pages.size())
	# Build and Info live in the tabs above, having been re-parented there at startup; these two
	# are still where the scene put them.
	for extra: String in ["main_ui/VBoxContainer3/HBoxContainer2/StatisticsPage",
			"main_ui/LaunchPanel"]:
		var e: Control = g.get_node_or_null(extra) as Control
		check(e != null, "%s is where it is looked for" % extra)
		if e != null:
			e.visible = true
			for _i in range(8): await process_frame
			padded_pages.append(e)
	var measured: int = 0
	for pg: Control in padded_pages:
		var l_gap: float = 1.0e9
		var r_gap: float = 1.0e9
		var who: String = ""
		for n: Node in pg.find_children("*", "Label", true, false):
			var lab := n as Label
			if not lab.visible or lab.text == "":
				continue
			var lg: float = lab.global_position.x - pg.global_position.x
			if lg < l_gap:
				l_gap = lg
				who = lab.text.substr(0, 24)
			r_gap = minf(r_gap, (pg.global_position.x + pg.size.x)
				- (lab.global_position.x + lab.size.x))
		if l_gap > 1.0e8:
			continue        # a page with nothing written on it yet
		measured += 1
		check(l_gap >= PAD_MIN, "%s insets its text from the left: %.1f px (\"%s\")" % [
			str(pg.name), l_gap, who])
		check(r_gap >= PAD_MIN, "%s insets its text from the right: %.1f px" % [
			str(pg.name), r_gap])
	# A page with no text on it is skipped above, so the count is asserted: the first version of
	# this check measured nothing at all and passed.
	check(measured >= 7, "every page with text on it was measured: %d" % measured)

	print("FAILS: %d" % fails)
	quit()


## Corner radii of the panel `ctrl` draws, clockwise from the top left — empty if it draws none.
func _radii(ctrl: Control, what: String) -> Array:
	if ctrl == null:
		return []
	var f := ctrl.get_theme_stylebox(what) as StyleBoxFlat
	if f == null:
		return []
	return [f.corner_radius_top_left, f.corner_radius_top_right,
		f.corner_radius_bottom_right, f.corner_radius_bottom_left]
