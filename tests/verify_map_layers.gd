extends SceneTree

## The star map's layer filter: what it draws, and which stars.
##
## The map is colour-coded by what is in a system, and the filter's classes ARE those colours —
## the checkbox list doubles as the legend, so the two must be the same list rather than two
## lists that happen to agree today.
##
## A hidden object must also be unclickable. Filtering the draw alone leaves a star that can be
## selected out of apparently empty space, and the launch panel then opens on a target that is
## not on screen — which is worse than not having the filter.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

## Where a star projects to on the panel right now.
func _screen_of(sm, pos: Vector3) -> Vector2:
	var center: Vector2 = sm.size * 0.5
	return sm._project(sm._rel(pos), sm._view_basis(), center, sm._fit_scale(center))

func _run() -> void:
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var sm = g.sidebar.star_map
	g.sidebar.hide_all()
	sm.show()
	for _i in range(6): await process_frame

	# ── Everything is on, which is the map as it always was ──
	for id: String in ["stars", "clusters", "galaxies"]:
		check(sm.layer_shown(id), "%s starts shown" % id)
	for c: Dictionary in sm.STAR_CLASSES:
		check(sm.star_class_shown(str(c["id"])), "%s stars start shown" % c["id"])

	# ── The checkbox list is the legend ──
	# Every class names a colour, and it is the SAME colour the map paints that star — the two
	# used to be one match statement and are now one table, which is the whole point.
	check(sm.STAR_CLASSES.size() == 5, "five classes: %d" % sm.STAR_CLASSES.size())
	check(sm._status_color_of(true, "") == sm._class_color(sm.STAR_CLASS_HUMAN),
		"a colonised star is drawn in the Human colour")
	check(sm._status_color_of(false, "aggressive") == sm._class_color(sm.STAR_CLASS_HOSTILE),
		"and an aggressive one in the Aggressive colour")
	check(sm._status_color_of(false, "peaceful") == sm._class_color(sm.STAR_CLASS_FRIENDLY),
		"a peaceful neighbour is what the panel calls Friendly")
	check(sm._status_color_of(false, "unknown") == sm._class_color(sm.STAR_CLASS_UNKNOWN),
		"and an unconfirmed one Unknown")
	check(sm._status_color_of(false, "") == sm._class_color(sm.STAR_CLASS_EMPTY),
		"and an empty system Uninhabited")
	# Colonised beats whoever else is claimed to be there, in both.
	check(sm.star_class(true, "aggressive") == sm.STAR_CLASS_HUMAN,
		"ours is ours even where somebody hostile is also recorded")
	var seen: Dictionary = {}
	for c2: Dictionary in sm.STAR_CLASSES:
		check(not seen.has(str(c2["color"])), "class %s has a colour of its own" % c2["id"])
		seen[str(c2["color"])] = true

	# ── A control for every one of them ──
	for id2: String in ["stars", "clusters", "galaxies"]:
		check(sm._layer_boxes.has(id2), "there is a checkbox for %s" % id2)
	for c3: Dictionary in sm.STAR_CLASSES:
		check(sm._class_boxes.has(str(c3["id"])), "and one for %s stars" % c3["id"])
	check(sm._layer_ui != null and sm._layer_ui.get_parent() == sm,
		"the filter is docked in the map")

	# ── Turning a layer off takes it off the map ──
	sm.queue_redraw()
	await process_frame
	var clusters_drawn: int = (sm.get("_cl_pts") as PackedVector2Array).size()
	check(clusters_drawn > 0, "clusters are drawn to begin with: %d" % clusters_drawn)
	sm.set_layer_shown("clusters", false)
	sm.queue_redraw()
	await process_frame
	check((sm.get("_cl_pts") as PackedVector2Array).is_empty(),
		"and gone when the layer is off: %d" % (sm.get("_cl_pts") as PackedVector2Array).size())
	check(not sm._cluster_pickable(1), "a hidden cluster is not clickable either")
	sm.set_layer_shown("clusters", true)
	sm.queue_redraw()
	await process_frame
	check((sm.get("_cl_pts") as PackedVector2Array).size() > 0, "and back when it is on again")

	# ── A hidden star cannot be clicked ──
	# Measured by clicking where one actually is, because that is the failure: filtering the
	# draw and not the pick selects something invisible.
	var stars: Array = sm.all_stars()
	check(stars.size() > 10, "there is a catalogue: %d" % stars.size())
	var target: int = -1
	for i in range(stars.size()):
		var p: Vector2 = _screen_of(sm, (stars[i] as Dictionary)["pos"] as Vector3)
		if p.x > 40.0 and p.y > 40.0 and p.x < sm.size.x - 40.0 and p.y < sm.size.y - 40.0:
			target = i
			break
	check(target >= 0, "and one of them is on screen to click")
	if target >= 0:
		var at: Vector2 = _screen_of(sm, (stars[target] as Dictionary)["pos"] as Vector3)
		sm._try_select(at)
		check(sm.get("_selected") >= 0, "clicking a star selects it: %d" % sm.get("_selected"))
		# Nothing is colonised or claimed in a fresh run, so every star is Uninhabited.
		sm.set_star_class_shown(sm.STAR_CLASS_EMPTY, false)
		sm._try_select(at)
		check(sm.get("_selected") == -1, "and with its class hidden the same click selects nothing")
		sm.set_star_class_shown(sm.STAR_CLASS_EMPTY, true)
		sm._try_select(at)
		check(sm.get("_selected") >= 0, "turning the class back on makes it clickable again")

		# ── Hiding the class a selected star belongs to drops the selection ──
		# A ring around a star nobody can see, with the launch panel open on it, is a ghost.
		check(sm.get("_selected") >= 0, "something is selected to begin with")
		sm.set_layer_shown("stars", false)
		check(sm.get("_selected") == -1, "turning the whole layer off clears the selection")
		sm.set_layer_shown("stars", true)

	# ── The sub-options go dead while the layer above them is off ──
	sm.set_layer_shown("stars", false)
	for c4: Dictionary in sm.STAR_CLASSES:
		check((sm._class_boxes[str(c4["id"])] as CheckBox).disabled,
			"%s is greyed while Stars is off" % c4["id"])
		check(not sm.star_class_shown(str(c4["id"])),
			"and no %s star is shown" % c4["id"])
	sm.set_layer_shown("stars", true)
	for c5: Dictionary in sm.STAR_CLASSES:
		check(not (sm._class_boxes[str(c5["id"])] as CheckBox).disabled,
			"%s is live again" % c5["id"])

	# ── Setting a layer from outside moves its checkbox ──
	# The console and a test both go through set_layer_shown; a panel that did not follow would
	# show a filter the map is not using.
	sm.set_layer_shown("galaxies", false)
	check(not (sm._layer_boxes["galaxies"] as CheckBox).button_pressed,
		"the Galaxies box follows the state")
	sm.set_layer_shown("galaxies", true)
	check((sm._layer_boxes["galaxies"] as CheckBox).button_pressed, "and back")
	sm.set_layer_shown("nonsense", false)
	check(true, "an unknown layer id is ignored rather than fatal")

	print("FAILS: %d" % fails)
	quit()
