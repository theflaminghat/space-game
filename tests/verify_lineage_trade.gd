extends SceneTree

## Trading sequence data with your own colonies, and splicing it into people.
##
## A colony four hundred light-years out is yours on the map and autonomous in every way that
## matters — the round trip is eight hundred years. What can usefully cross that gap is not ore
## but information, which has no mass and is the whole of what a written sequence is.
##
## The four things that have to hold:
##   a colony must WRITE something, or there is nothing to trade — isolation and time do it
##   the data must cross at light speed, so distance is the price
##   a held sequence goes into a population in DECADES, because this is splicing and not a
##     breeding programme — that timing is the point of the system
##   nothing can be spliced that nobody holds

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
	var SD = load("res://stock_data.gd")


	# ── Nothing is held at the start, and nothing is on offer ──
	check(g.lineage_archive.is_empty(), "the archive starts empty")
	check(g.lineage_transfers.is_empty(), "with nothing in flight")
	check(g.lineage_offers().is_empty(),
		"and no colony has anything to send: %s" % str(g.lineage_offers()))


	# ── Splicing is DECADES, and that is the whole point ──
	# The system this replaced moved a population by selection, which took two million years —
	# a run measured in millions could do it perhaps twice. A written sequence goes through a
	# population in a couple of generations, so it is something the player does and then sees.
	check(SD.SPLICE_YEARS < 500.0,
		"a rollout is lifetimes, not epochs: %.0f yr" % SD.SPLICE_YEARS)
	check(SD.splice_years_needed(SD.baseline()) < 500.0,
		"even worked out against a real stock: %.0f yr" % SD.splice_years_needed(SD.baseline()))
	# And it is far quicker than a colony working the sequence out for itself, which is the
	# trade's whole reason to exist.
	check(SD.DISCOVER_YEARS > 100.0 * SD.SPLICE_YEARS,
		"writing one from scratch out in the dark is not: %s yr" % SD.DISCOVER_YEARS)
	# A varied population takes an edit more evenly, so the rollout finishes sooner.
	var thin_stock: Dictionary = SD.found("minimal", [], SD.baseline())
	check(SD.splice_years_needed(thin_stock) > SD.splice_years_needed(SD.baseline()),
		"a thin population takes longer to splice: %.1f vs %.1f" % [
			SD.splice_years_needed(thin_stock), SD.splice_years_needed(SD.baseline())])


	# ── Variation recovers, but only over geological time ──
	var thin: float = SD.diversity_for("minimal")
	check(SD.recovered_diversity(thin, 0.0) == thin, "no time, no recovery")
	check(SD.recovered_diversity(thin, 1000.0) < thin + 0.01,
		"a thousand years is nothing: %.4f" % SD.recovered_diversity(thin, 1000.0))
	check(SD.recovered_diversity(thin, 1.0e7) > 0.95,
		"ten million years nearly restores it: %.3f" % SD.recovered_diversity(thin, 1.0e7))
	check(SD.recovered_diversity(1.0, 1.0e9) <= 1.0, "and it never exceeds a native population")


	# ── A colony left alone for long enough writes something of its own ──
	# Built rather than waited for: a world is given an age and a population, so that what is
	# tested is the code and not the run.
	var w: String = "Alpha Centauri A"
	g.colonized_stars.append(w)
	g._col_star_set[w] = true
	g._colony_year[w] = g.year
	g._world_stock[w] = SD.found("standard", [], SD.baseline())
	g.world_pop[w] = g.COLONY_HABITAT_K
	check(not g._lineage_distinct(w), "a colony founded today is not yet its own lineage")
	check(g.request_lineage(w).to_lower().find("isolated") >= 0,
		"and cannot be asked for anything: %s" % g.request_lineage(w))
	g._colony_year[w] = g.year - 2_000_000          # old enough to have diverged
	check(g._lineage_distinct(w), "two million years on, it is a lineage of its own")
	# Matched case-insensitively: this is a sentence shown to the player, and which word it
	# starts with is a wording decision rather than behaviour worth pinning a test to.
	check(g.request_lineage(w).to_lower().find("unedited") >= 0,
		"but an unedited population still has nothing to teach: %s" % g.request_lineage(w))

	# Enough passes to cover the isolation it is owed. _advance_lineages credits each world with
	# the whole gap between its visits, so one pass over a short roster is one span.
	for _i in range(20):
		g._advance_lineages(SD.DISCOVER_YEARS / 10.0)
	var wrote: Array = g.stock_of(w)["traits"] as Array
	check(wrote.size() >= 1,
		"left alone with its own laboratories, it writes a sequence: %s" % str(g.stock_of(w)))
	# Written without indexing, so that a colony which wrote NOTHING fails this rather than
	# aborting _run on wrote[0] — the harness turns an abort into a TIMEOUT, which says far
	# less than the list of failures does.
	var all_real: bool = not wrote.is_empty()
	for id in wrote:
		if not SD.is_trait(str(id)):
			all_real = false
	check(all_real, "and they are real ones: %s" % str(wrote))
	check(SD.diversity_of(g.stock_of(w)) > SD.diversity_for("standard"),
		"and the isolation has recovered its variation: %.3f" % SD.diversity_of(g.stock_of(w)))
	# A genome will not take more than it holds, however long the colony sits there.
	for _i in range(200):
		g._advance_lineages(SD.DISCOVER_YEARS / 2.0)
	check((g.stock_of(w)["traits"] as Array).size() <= SD.MAX_TRAITS,
		"and never writes past the cap: %s" % str(g.stock_of(w)["traits"]))


	# ── Now it has something, and distance is the price ──
	var offers: Array = g.lineage_offers()
	check(offers.size() == 1, "exactly one colony is worth asking: %d" % offers.size())
	if offers.size() == 1:
		var o: Dictionary = offers[0]
		check(str(o["world"]) == w, "and it is the one that wrote something")
		check((o["traits"] as Array) == (g.stock_of(w)["traits"] as Array),
			"offering everything it has: %s" % str(o["traits"]))
		check(float(o["dist_ly"]) > 1.0, "at a real distance: %.2f ly" % float(o["dist_ly"]))
		check(absf(float(o["years"]) - 2.0 * float(o["dist_ly"])) < 1.0e-6,
			"and the wait is the round trip at light speed")

	var asked: Array = (g.stock_of(w)["traits"] as Array).duplicate()
	check(g.request_lineage(w) == "", "the request goes out")
	check(g.lineage_transfers.size() == 1, "and is in flight")
	# Everything past here indexes `asked` and `lineage_transfers`, so if the colony wrote
	# nothing or the request did not go out, the rest of this run would abort _run before
	# quit() — which the harness reports as a TIMEOUT rather than as the failures it is. Bail
	# with the count instead: a test should fail legibly when what it covers is broken.
	if asked.is_empty() or g.lineage_transfers.is_empty():
		print("FAILS: %d" % maxi(fails, 1))
		quit()
		return
	check(g.request_lineage(w).find("already in flight") >= 0, "once, not twice")
	check(g.lineage_offers().is_empty(), "and it stops being offered while it is coming")
	check(g.lineage_archive.is_empty(), "nothing is held until it arrives")

	# It does not arrive early.
	var due: float = float((g.lineage_transfers[0] as Dictionary)["end_year"])
	g.year = int(floor(due)) - 1
	g._check_lineage_transfers()
	check(g.lineage_archive.is_empty(),
		"a year short of the round trip, the data is still in flight")
	g.year = int(ceil(due))
	g._check_lineage_transfers()
	for id: String in asked:
		check(g.lineage_archive.has(id), "and on time %s is in the archive" % id)
	check(g.lineage_transfers.is_empty(), "with the request cleared")
	check(g.lineage_offers().is_empty(), "and nothing left to ask that colony for")


	# ── Holding a sequence is what makes it orderable, and splicable ──
	var held: String = str(asked[0])
	check(not g.can_engineer_lineages(), "nothing here can write a sequence from scratch")
	check(g.set_colony_stock("broad", [held]) == "",
		"but a ship can be founded carrying the one that came back")
	check((g.founding_stock("earth")["traits"] as Array) == [held],
		"and it is what leaves: %s" % str(g.founding_stock("earth")["traits"]))
	# Nothing else, though. The archive holds what it holds.
	var unheld: String = ""
	for id: String in SD.trait_ids():
		if not g.lineage_archive.has(id):
			unheld = id
	check(unheld != "", "there is a sequence nobody holds")
	check(g.set_colony_stock("broad", [unheld]) != "", "and it cannot be ordered")
	check(g.splice_trait("earth", unheld) != "", "nor spliced into anybody")
	check((g.stock_of("earth")["traits"] as Array).is_empty(), "and nothing moved")


	# ── A settled world takes the sequence in a human lifetime or two ──
	check(g.splice_trait("earth", held) == "", "Earth is put on the programme")
	check(str(g.stock_of("earth")["splice"]) == held, "and knows it")
	check((g.stock_of("earth")["traits"] as Array).is_empty(), "nobody carries it yet")
	var need: float = SD.splice_years_needed(g.stock_of("earth"))
	# Advanced in small steps, so that what is measured is when it FINISHES and not the size of
	# the step it finished inside.
	var took: float = 0.0
	for _i in range(400):
		if (g.stock_of("earth")["traits"] as Array).has(held):
			break
		g._advance_lineages(need / 20.0)
		took += need / 20.0
	check((g.stock_of("earth")["traits"] as Array).has(held),
		"and everyone born there carries it: %s" % str(g.stock_of("earth")))
	check(took < need * 1.2, "in about the time it said: %.1f vs %.1f yr" % [took, need])
	check(took < 1000.0, "which is a historical span, not a geological one: %.0f yr" % took)
	check(str(g.stock_of("earth")["splice"]) == "", "the programme is finished with")
	check(g.splice_block_reason("earth", held).find("already") >= 0,
		"and splicing it again is refused: %s" % g.splice_block_reason("earth", held))


	# ── It survives a save ──
	g._world_stock[w]["splice"] = unheld
	g._world_stock[w]["splice_done"] = 12.0
	g.save_game("user://saves/lineage.json")
	g.lineage_archive = {}
	g.lineage_transfers = [{"world": "x", "traits": ["longevity"], "end_year": 1.0}]
	g._world_stock = {}
	g.load_game("user://saves/lineage.json")
	check(g.lineage_archive.has(held), "the archive survives the round trip")
	check(g.lineage_transfers.is_empty(), "and so does an empty flight list")
	check(absf(float(g.stock_of(w).get("splice_done", 0.0)) - 12.0) < 1.0,
		"a rollout in progress is not thrown away on load: %s"
			% str(g.stock_of(w).get("splice_done")))
	check(str(g.stock_of(w).get("splice", "")) == unheld, "nor what is going in")
	check((g.stock_of("earth")["traits"] as Array).has(held),
		"and a world keeps what was written into it")

	print("FAILS: %d" % fails)
	quit()
