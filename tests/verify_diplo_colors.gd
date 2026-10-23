extends SceneTree

## The star map colours a star by WHO IS THERE, and past STATUS_COLOR_LY (100 ly) that colour is
## all it says — so the colour has to be right for distant systems, which is every seeded
## civilisation in a fresh run.  Diplomatic standing is the one fact that does not decay with
## range, so it outranks alignment: allies and trade partners are friendly blue at any distance,
## and anyone we are at war with is hostile red even if we never confirmed what they were.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(20260927)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(40): await process_frame
	var g: Node = current_scene
	var panel = g.sidebar.star_map

	var civs: Array = (g.star_factions as Dictionary).keys()
	check(civs.size() >= 4, "the run seeded enough civilisations to test with")

	# This has to be a test about DISTANT stars rather than about the nearest handful, so most of
	# the seeded civilisations must be past the status-colour cutoff — but not necessarily all
	# of them.  Where they land depends on the home cell, and the cell shrank when the cluster
	# shell was made denser: one civ now sits at 98.8 ly, just inside the line.
	var far: int = 0
	for c in civs:
		if g._star_distance_ly(str(c)) > panel.STATUS_COLOR_LY:
			far += 1
	check(far >= civs.size() - 2,
		"nearly all the seeded civilisations are beyond the status-colour cutoff: %d of %d" % [
			far, civs.size()])
	check(far > 0, "and at least one is, so the distant path is exercised")

	var det: Dictionary = g.get("_detected_aliens")
	var known: Dictionary = g.get("_known_alignments")
	var diplo: Dictionary = g.get("_diplo_status")
	for c in civs:
		det[str(c)] = true

	# Pick one peaceful and one aggressive civilisation to work with.
	var peaceful := ""
	var aggressive := ""
	for c in civs:
		var a: String = str(g.star_factions[str(c)])
		if a == "peaceful" and peaceful == "":
			peaceful = str(c)
		elif a == "aggressive" and aggressive == "":
			aggressive = str(c)
	check(peaceful != "", "found a peaceful civilisation")

	# ── Undetermined: detected but unconfirmed is still yellow ──
	var disp: Dictionary = g._displayed_factions()
	check(str(disp.get(peaceful, "")) == "unknown",
		"an unconfirmed civilisation reads unknown")
	check(panel._status_color_of(false, "unknown") == panel.STATUS_COL_UNKNOWN,
		"unknown maps to the yellow swatch")

	# ── Allied: blue, with alignment still unconfirmed ──
	diplo[peaceful] = "allied"
	disp = g._displayed_factions()
	check(str(disp.get(peaceful, "")) == "peaceful", "an ally reads peaceful")
	check(panel._status_color_of(false, str(disp[peaceful])) == panel.STATUS_COL_PEACEFUL,
		"an ally is drawn in the friendly blue")
	check(not known.has(peaceful),
		"the ally's alignment was never revealed, so standing alone carried the colour")

	# ── Trading: also blue ──
	diplo[peaceful] = "trading"
	disp = g._displayed_factions()
	check(str(disp.get(peaceful, "")) == "peaceful", "a trade partner reads peaceful")

	# ── War with a peaceful civilisation: red, not blue ──
	# This is the case a first strike ordered by doctrine creates.
	diplo[peaceful] = "war"
	known[peaceful] = true
	disp = g._displayed_factions()
	check(str(disp.get(peaceful, "")) == "aggressive",
		"a peaceful civilisation we are at war with reads hostile")
	check(panel._status_color_of(false, str(disp[peaceful])) == panel.STATUS_COL_HOSTILE,
		"it is drawn in the hostile red")

	# ── War without ever confirming alignment: still red ──
	known.erase(peaceful)
	disp = g._displayed_factions()
	check(str(disp.get(peaceful, "")) == "aggressive",
		"war outranks an unconfirmed alignment")

	# ── A colony outranks everything: it is ours ──
	check(panel._status_color_of(true, "aggressive") == panel.STATUS_COL_HUMAN,
		"our own holding stays green whatever the standing")

	# ── Undetected civilisations are still hidden entirely ──
	diplo[peaceful] = "allied"
	det.erase(peaceful)
	disp = g._displayed_factions()
	check(not disp.has(peaceful),
		"an undetected ally is not shown at all")

	# ── The map is actually told about it ──
	det[peaceful] = true
	# refresh_star_map() skips the rebuild while the panel is closed, so it has to be open for
	# the push to happen at all.
	g.sidebar.hide_all()
	panel.show()
	g.refresh_star_map()
	for _i in range(4): await process_frame
	var pushed: Dictionary = panel.get("_factions")
	check(str(pushed.get(peaceful, "")) == "peaceful",
		"the colour reaches the star map through refresh_star_map")

	print("FAILS: %d" % fails)
	quit()
