extends SceneTree

## The lineage trade, in the star map's info box.
##
## The offer belongs on the system itself, next to the distance that prices it: a request is two
## years per light-year, out and back at the speed of light, so the wait is on the button rather
## than in a tooltip.
##
## Game is the authority for both halves. The panel only asks, and shows whatever comes back —
## so an offer the simulation would refuse must never be clickable in the first place, and the
## reason it would refuse is what the button says instead.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _select(sm, star: String) -> void:
	for i in range(sm.all_stars().size()):
		if str(sm.all_stars()[i]["name"]) == star:
			sm.set("_selected", i)
			sm.set("_selected_cluster", -1)
			return

func _run() -> void:
	seed(20261015)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var sm = g.sidebar.star_map
	var SD = load("res://stock_data.gd")
	g.sidebar.hide_all()
	sm.show()
	for _i in range(4): await process_frame

	check(sm._lineage_label != null, "the info box has a lineage line")
	check(sm._lineage_btn != null, "and a request button")
	check(sm._breed_opt != null, "and a breeding selector")

	# ── Nothing of ours selected: the block stays out of the way ──
	var plain: String = str(sm.all_stars()[1]["name"])
	_select(sm, plain)
	g._on_star_selected_lineage(plain)
	check(not sm._lineage_label.visible, "an uncolonised star shows no lineage line")
	check(not sm._lineage_btn.visible, "and no request button")

	# ── A colony that has not been out there long has nothing to send ──
	var w: String = "Alpha Centauri A"
	g.colonized_stars.append(w)
	g._col_star_set[w] = true
	g._colony_year[w] = g.year
	g._world_stock[w] = SD.found("standard", [], SD.baseline())
	g.world_pop[w] = g.COLONY_HABITAT_K
	g.refresh_star_map()
	_select(sm, w)
	g._on_star_selected_lineage(w)
	check(sm._lineage_label.visible, "a colony of ours shows its lineage")
	check(sm._lineage_label.text.to_lower().find("unedited") >= 0,
		"saying what its people are: %s" % sm._lineage_label.text)
	check(sm._lineage_btn.visible, "with the request button present")
	check(sm._lineage_btn.disabled, "but greyed")
	check(sm._lineage_btn.text.find("lineage of its own") >= 0,
		"and saying why: %s" % sm._lineage_btn.text)
	check(not sm._breed_opt.visible, "and nothing to splice into it yet")

	# ── Once it has written something, the offer appears with its price on it ──
	g._colony_year[w] = g.year - 3_000_000
	for _i in range(30):
		g._advance_lineages(SD.DISCOVER_YEARS / 8.0)
	var wrote: Array = g.stock_of(w)["traits"] as Array
	check(wrote.size() >= 1,
		"the colony has worked something out: %s" % str(g.stock_of(w)))
	var held: String = str(wrote[0]) if wrote.size() >= 1 else ""
	g._on_star_selected_lineage(w)
	check(not sm._lineage_btn.disabled, "the request is now offered")
	check(sm._lineage_btn.text.find("yr") >= 0,
		"and the button carries the wait: %s" % sm._lineage_btn.text)
	var dist: float = g._star_distance_ly(w)
	check(sm._lineage_btn.text.find("round trip") >= 0, "named as a round trip")
	check(dist > 1.0, "which is a real distance: %.2f ly" % dist)

	# ── Pressing it goes through Game, and the button follows the answer ──
	sm._lineage_btn.emit_signal("pressed")
	check(g.lineage_transfers.size() == 1,
		"the press reaches the simulation: %d in flight" % g.lineage_transfers.size())
	check(str((g.lineage_transfers[0] as Dictionary)["world"]) == w, "for the right colony")
	check(sm._lineage_btn.disabled, "and the button greys itself")
	check(sm._lineage_btn.text.find("transit") >= 0,
		"saying it is on its way: %s" % sm._lineage_btn.text)
	# Pressing again while it is out changes nothing — Game refuses and the panel shows that.
	sm._lineage_btn.emit_signal("pressed")
	check(g.lineage_transfers.size() == 1, "a second press sends nothing more")

	# ── When it lands, the offer is gone and the world can be bred ──
	g.year = int(ceil(float((g.lineage_transfers[0] as Dictionary)["end_year"])))
	g._check_lineage_transfers()
	g._on_star_selected_lineage(w)
	check(g.lineage_archive.has(held), "the data is in the archive")
	check(sm._lineage_btn.disabled, "and there is nothing left to request here")
	check(sm._lineage_btn.text.find("already holds") >= 0,
		"which the button says: %s" % sm._lineage_btn.text)

	# A world is never offered what it already carries.
	var own: Array = []
	for t0: Dictionary in (g.lineage_ui_state(w)["targets"] as Array):
		own.append(str(t0["id"]))
	check(not own.has(held),
		"this colony already carries %s, so it is not offered it back: %s" % [held, str(own)])

	# Earth does not carry it, so Earth is offered it.
	_select(sm, "")
	g._on_star_selected_lineage("earth")
	var st: Dictionary = g.lineage_ui_state("earth")
	check(not (st.get("targets", []) as Array).is_empty(),
		"Earth can be spliced for what the archive holds: %s" % str(st.get("targets")))
	var ids: Array = []
	for t: Dictionary in (st["targets"] as Array):
		ids.append(str(t["id"]))
	check(ids.has(held), "including the one that came back: %s" % str(ids))
	# Exactly what the archive holds and nothing besides — without Synthetic Biology the
	# archive is the whole of what can be written into anybody.
	check(ids.size() == g.lineage_archive.size(),
		"and exactly the archive, no more: %s vs %s" % [str(ids), str(g.lineage_archive.keys())])
	for id: String in ids:
		check(g.lineage_archive.has(id), "%s is held" % id)

	# ── Choosing one splices the world, through Game ──
	g._on_lineage_direct_requested("earth", held)
	check(str(g.stock_of("earth").get("splice", "")) == held,
		"Earth is being spliced for %s" % held)
	check(g.lineage_ui_state("earth")["text"].find("going into its people") >= 0,
		"and the info box says so: %s" % g.lineage_ui_state("earth")["text"])
	# A sequence Game would refuse leaves everything alone.
	var unheld: String = ""
	for id: String in SD.trait_ids():
		if not g.lineage_archive.has(id):
			unheld = id
	check(unheld != "", "there is a sequence nobody holds")
	g._on_lineage_direct_requested("earth", unheld)
	check(str(g.stock_of("earth").get("splice", "")) == held,
		"one the archive does not hold is refused, and changes nothing")

	print("FAILS: %d" % fails)
	quit()
