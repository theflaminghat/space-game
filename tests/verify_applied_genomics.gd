extends SceneTree

## Splicing a sequence into a population, from the Population tab.
##
## Until Synthetic Biology, the only sequences a civilisation has are the ones its colonies
## worked out over three hundred thousand years of isolation and sent home. Synthetic Biology is
## the difference between being given a sequence and writing one: any trait in the table can be
## written from first principles and put into any world, without waiting for somebody out in the
## dark to find it first.
##
## What it does not buy is instant people. The sequence is information; getting it into a living
## population is still a couple of generations of germ-line work — which is decades, because
## this is splicing. The slow part was never the writing.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(20261022)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var rt: Node = root.get_node("ResearchTree")
	var SD = load("res://stock_data.gd")
	var page = g._population_page
	check(page != null, "the Population tab exists")
	var want: String = "high_intelligence"

	# ── Before the research, there is nothing to write with ──
	check(not g.can_engineer_lineages(), "Synthetic Biology is not researched at the start")
	check(g.population_lineage_state("earth").is_empty(),
		"so the tab is given nothing to show")
	page.set_lineage(g.population_lineage_state("earth"))
	check(not page._bio_box.visible,
		"and the control is not there — not merely greyed")
	# And the action is refused with a reason that names both ways out.
	var why: String = g.splice_trait("earth", want)
	check(why != "", "splicing Earth is refused")
	check(why.find("Synthetic Biology") >= 0, "naming the research: %s" % why)
	check(why.to_lower().find("colony") >= 0, "and the other way to get one: %s" % why)

	# ── With it, any sequence can be written ──
	rt.force_unlock("synthetic_biology")
	check(g.can_engineer_lineages(), "the research unlocks it")
	var st: Dictionary = g.population_lineage_state("earth")
	check(not st.is_empty(), "the tab now has something to show")
	check(bool(st.get("unlocked", false)), "and says so")
	check(str(st.get("text", "")).to_lower().find("unedited") >= 0,
		"with what Earth\'s people currently are: %s" % st.get("text"))
	var ids: Array = []
	for t: Dictionary in (st["targets"] as Array):
		ids.append(str(t["id"]))
	check(ids.size() == SD.TRAITS.size(),
		"every sequence in the table, since Earth carries none: %s" % str(ids))
	check(g.lineage_archive.is_empty(),
		"and none of this needed the archive: %s" % str(g.lineage_archive))

	# ── The control offers exactly those, and choosing one reaches the simulation ──
	page.set_lineage(st)
	check(page._bio_box.visible, "the control appears")
	check(page._bio_opt.item_count == ids.size() + 1,
		"offering each of them under a prompt: %d" % page._bio_opt.item_count)
	check(page._bio_ids == ids, "and the ids line up with what Game offered")
	for i in range(1, page._bio_opt.item_count):
		check(page._bio_opt.get_item_tooltip(i).length() > 20,
			"option %d says what it trades" % i)
	var asked: Array = []
	page.lineage_direct_requested.connect(func(w: String, s: String): asked.append([w, s]))
	# A push must not read as the player choosing — the panel is rebuilt on every tick.
	page.set_lineage(st)
	check(asked.is_empty(), "rebuilding the control asks for nothing: %s" % str(asked))
	page._bio_opt.selected = 1
	page._bio_opt.item_selected.emit(1)
	check(asked.size() == 1, "choosing one asks once: %s" % str(asked))
	if asked.size() == 1:
		check(str((asked[0] as Array)[0]) == "earth", "for this world")
		check(SD.is_trait(str((asked[0] as Array)[1])), "naming a real sequence")

	# ── Written is not delivered, but it is not deep time either ──
	# Either this call starts it, or the control above already did — Game is connected to the
	# page's signal, so emitting it in this test really does reach the simulation.
	var err: String = g.splice_trait("earth", want)
	check(err == "" or err.find("already going in") >= 0,
		"Earth is put on the programme: %s" % err)
	var cur: Dictionary = g.stock_of("earth")
	check(str(cur.get("splice", "")) == want, "and the programme is recorded")
	check(not (cur["traits"] as Array).has(want), "but nobody carries it yet")
	var need: float = SD.splice_years_needed(cur)
	check(need > 1.0, "there are generations to run: %.1f yr" % need)
	check(need < 500.0,
		"and they are generations and not epochs — this is splicing: %.1f yr" % need)

	# And it does get there, in that time rather than in geological time.
	var took: float = 0.0
	for _i in range(400):
		if (g.stock_of("earth")["traits"] as Array).has(want):
			break
		g._advance_lineages(need / 20.0)
		took += need / 20.0
	check((g.stock_of("earth")["traits"] as Array).has(want),
		"and Earth carries it: %s" % str(g.stock_of("earth")["traits"]))
	check(took < need * 1.2, "in about what it said: %.1f vs %.1f yr" % [took, need])
	check(str(g.stock_of("earth").get("splice", "")) == "",
		"the programme is spent once it has been met")
	check(SD.compute_mult_of(g.stock_of("earth")) > 1.2,
		"and the population thinks differently for it: %.2f"
			% SD.compute_mult_of(g.stock_of("earth")))

	# ── What a world already carries is not offered ──
	var after: Dictionary = g.population_lineage_state("earth")
	var ids2: Array = []
	for t2: Dictionary in (after["targets"] as Array):
		ids2.append(str(t2["id"]))
	check(not ids2.has(want), "what it already has is no longer on offer: %s" % str(ids2))
	check(g.splice_trait("earth", want).find("already") >= 0,
		"and is refused if asked for anyway")

	# ── The genome stops taking them at the cap ──
	var put: int = 1
	for id: String in SD.trait_ids():
		if (g.stock_of("earth")["traits"] as Array).has(id):
			continue
		if g.splice_trait("earth", id) != "":
			continue
		for _i in range(400):
			if (g.stock_of("earth")["traits"] as Array).has(id):
				break
			g._advance_lineages(need / 10.0)
		put += 1
		if put >= SD.MAX_TRAITS:
			break
	check((g.stock_of("earth")["traits"] as Array).size() == SD.MAX_TRAITS,
		"Earth fills up: %s" % str(g.stock_of("earth")["traits"]))
	var full: Dictionary = g.population_lineage_state("earth")
	check((full["targets"] as Array).is_empty(),
		"and nothing more is offered: %s" % str(full["targets"]))
	check(str(full.get("text", "")).to_lower().find("will not hold") >= 0,
		"with the tab saying why: %s" % full.get("text"))
	var left: String = ""
	for id: String in SD.trait_ids():
		if not (g.stock_of("earth")["traits"] as Array).has(id):
			left = id
	check(left != "", "there is a sequence Earth does not carry")
	check(g.splice_trait("earth", left).find("genome") >= 0,
		"and it is refused for the reason it is refused: %s" % g.splice_trait("earth", left))

	print("FAILS: %d" % fails)
	quit()
