extends SceneTree

## Colonies are founded by a POPULATION, and which one it was has consequences.
##
## Every lineage used to be identical — EvolutionTreeData handed each diverged world the same
## COMPUTE_PER_INDIVIDUAL, so a civilisation of ten thousand colonies was one population in ten
## thousand places and had one survival number. A stock is how many founders went (a shipping
## cost against genetic variation) and which sequences have been spliced into them.
##
## What is worth holding onto:
##   - the trait table is a trade, not a ladder: nothing is ahead of everything
##   - a genome holds MAX_TRAITS and no more, which is what stops the answer being "all of them"
##   - a sequence nobody holds cannot be ordered — splicing needs something to splice
##   - a colony's stock depends on WHERE ITS SETTLERS CAME FROM, not only on what was ordered
##   - a von Neumann probe carries the stock of the lineage that launched it
##   - the effects reach the figures they claim to: growth, thinking, life, room, divergence
##   - none of it changes anything for a run that never touches it

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

	# ── The tables are trade-offs, not ladders ──
	# If one option were better on every axis the mechanic would have a dominant choice and the
	# diversity it exists to create would never happen.
	for row: Dictionary in SD.FOUNDERS:
		var other_cheaper: bool = false
		var other_broader: bool = false
		for o: Dictionary in SD.FOUNDERS:
			if str(o["id"]) == str(row["id"]):
				continue
			if float(o["mass_mult"]) < float(row["mass_mult"]):
				other_cheaper = true
			if float(o["diversity"]) > float(row["diversity"]):
				other_broader = true
		check(other_cheaper or other_broader,
			"founder group %s is not dominated on both cost and variation" % row["id"])
	var prev_pop: float = -1.0
	var prev_mass: float = -1.0
	var prev_div: float = -1.0
	for row: Dictionary in SD.FOUNDERS:
		check(float(row["pop"]) > prev_pop, "founder sizes ascend: %s" % row["id"])
		check(float(row["mass_mult"]) > prev_mass, "and so does what they cost: %s" % row["id"])
		check(float(row["diversity"]) > prev_div, "and the variation they carry: %s" % row["id"])
		prev_pop = float(row["pop"])
		prev_mass = float(row["mass_mult"])
		prev_div = float(row["diversity"])
	# EVERY trait pays for itself somewhere. Stated over all four axes rather than one pair,
	# because a trait that was merely not-worse would still be a free upgrade.
	var axes: Array = ["growth", "life", "compute", "capacity"]
	for row: Dictionary in SD.TRAITS:
		var gain: bool = false
		var cost: bool = false
		for f: String in axes:
			if float(row[f]) > 1.0:
				gain = true
			if float(row[f]) < 1.0:
				cost = true
		check(gain, "%s is worth having" % row["id"])
		check(cost, "and %s costs something for it" % row["id"])
		for o: Dictionary in SD.TRAITS:
			if str(o["id"]) == str(row["id"]):
				continue
			var strictly_better: bool = true
			for f: String in axes:
				if float(o[f]) < float(row[f]):
					strictly_better = false
			check(not strictly_better,
				"%s is not simply beaten by %s on every axis" % [row["id"], o["id"]])
	check(absf(SD.pop_of(SD.baseline()) - g.COLONY_SEED_POP) < 1.0,
		"the standard group is the colony seed population the rest of the game uses: %s vs %s" % [
			SD.pop_of(SD.baseline()), g.COLONY_SEED_POP])

	# ── A run that never touches it is the run that always was ──
	check(str(g.colony_stock["founders"]) == SD.BASELINE_FOUNDERS, "the order starts standard")
	check((g.colony_stock["traits"] as Array).is_empty(), "and unedited")
	var earth: Dictionary = g.stock_of("earth")
	check(SD.diversity_of(earth) == 1.0,
		"1945 Earth is the full-variation baseline: %s" % SD.diversity_of(earth))
	for f: String in axes:
		check(absf(float(SD.mults_for("")[f]) - 1.0) < 1.0e-9,
			"an unedited genome multiplies %s by exactly one" % f)
	check(absf(SD.growth_mult_of(earth) - 1.0) < 1.0e-9, "so Earth grows at the base rate")
	check(absf(SD.compute_mult_of(earth) - 1.0) < 1.0e-9, "and thinks at the base rate")
	check(absf(SD.life_mult_of(earth) - 1.0) < 1.0e-9, "and lives the base span")
	check(absf(SD.capacity_mult_of(earth) - 1.0) < 1.0e-9, "and holds what its ground holds")
	# An unrecorded world reads as baseline, which is every world of an older save.
	check(SD.diversity_of(g.stock_of("nowhere_at_all")) == 1.0,
		"a world with no record is the baseline, not a zero")

	# ── Nothing can be spliced that nobody holds ──
	check(g.set_colony_stock("broad", ["longevity"]) != "",
		"a sequence nobody has written cannot be ordered")
	check((g.colony_stock["traits"] as Array).is_empty(), "and the order is unchanged")
	rt.force_unlock("synthetic_biology")
	check(g.can_engineer_lineages(), "Synthetic Biology writes sequences from first principles")
	check(g.set_colony_stock("broad", ["longevity"]) == "", "and now the order takes")

	# ── A genome holds MAX_TRAITS and no more ──
	var all_ids: Array = SD.trait_ids()
	check(all_ids.size() > SD.MAX_TRAITS, "there are more traits than any one genome holds")
	check(g.set_colony_stock("broad", all_ids.slice(0, SD.MAX_TRAITS)) == "",
		"the cap itself is orderable")
	check(g.set_colony_stock("broad", all_ids.slice(0, SD.MAX_TRAITS + 1)) != "",
		"one past it is refused")
	check((g.colony_stock["traits"] as Array).size() == SD.MAX_TRAITS,
		"and the refused order changed nothing: %s" % str(g.colony_stock["traits"]))
	check(SD.canon_traits(all_ids).size() == SD.MAX_TRAITS,
		"canon_traits is the backstop for anything that gets past the check")
	# The same set in a different order is the SAME set — the key a stock caches its multipliers
	# under cannot depend on which order the player ticked the boxes in.
	var fwd: Array = ["high_intelligence", "longevity"]
	var back: Array = ["longevity", "high_intelligence"]
	check(SD.tkey_for(SD.canon_traits(fwd)) == SD.tkey_for(SD.canon_traits(back)),
		"trait order does not make a different stock")
	check(SD.canon_traits(["high_intelligence", "high_intelligence"]).size() == 1,
		"and a repeat is one trait")
	check(SD.canon_traits(["not_a_trait"]).is_empty(), "an unknown id is dropped")

	# ── Traits stack, and the stack is the product ──
	var both: Dictionary = SD.found("broad", fwd, SD.baseline())
	var want_c: float = float(SD.trait_row("high_intelligence")["compute"]) \
		* float(SD.trait_row("longevity")["compute"])
	check(absf(SD.compute_mult_of(both) - want_c) < 1.0e-9,
		"two traits multiply: %.4f vs %.4f" % [SD.compute_mult_of(both), want_c])
	var want_g: float = float(SD.trait_row("high_intelligence")["growth"]) \
		* float(SD.trait_row("longevity")["growth"])
	check(absf(SD.growth_mult_of(both) - want_g) < 1.0e-9, "on every axis, including the costs")
	check(SD.growth_mult_of(both) < 1.0,
		"so a mind bred twice over breeds slowly: %.3f" % SD.growth_mult_of(both))
	# Every legal set is in the warmed table, because the population loop reads it by key and
	# would silently use baseline multipliers for any set that was missing.
	var tbl: Dictionary = SD.mult_table()
	var n_sets: int = 0
	for a in range(all_ids.size()):
		for b in range(a + 1, all_ids.size()):
			for c in range(b + 1, all_ids.size()):
				var key: String = SD.tkey_for(SD.canon_traits([all_ids[a], all_ids[b], all_ids[c]]))
				check(tbl.has(key), "the table holds %s" % key)
				n_sets += 1
	check(n_sets == 20, "all twenty three-trait sets were checked: %d" % n_sets)

	# ── Settlers are drawn from the origin, so the origin decides what they carry over ──
	check(g.set_colony_stock("broad", ["longevity"]) == "", "the order can be set")
	var from_earth: Dictionary = g.founding_stock("earth")
	check((from_earth["traits"] as Array) == ["longevity"], "a ship from Earth carries the order")
	check(absf(SD.diversity_of(from_earth) - SD.diversity_for("broad")) < 1.0e-9,
		"splicing the founders costs no variation — they are edited, not filtered: %s"
			% SD.diversity_of(from_earth))
	# Variation cannot be conjured out of a parent that does not have it: the group is a SAMPLE.
	g._world_stock["luna"] = SD.found("minimal", [], SD.baseline())
	var from_luna: Dictionary = g.founding_stock("luna")
	check(SD.diversity_of(from_luna) <= SD.diversity_of(g.stock_of("luna")) + 1.0e-9,
		"a broad group drawn from a thin population is still thin: %s vs %s" % [
			SD.diversity_of(from_luna), SD.diversity_of(g.stock_of("luna"))])

	# ── Bad input is refused, and refusing says what is allowed ──
	check(g.set_colony_stock("enormous", []) != "", "an unknown founder group is refused")
	check(g.set_colony_stock("standard", ["immortality"]) != "", "and an unknown trait")
	check(str(g.colony_stock["founders"]) == "broad", "a refused order changes nothing")
	check(SD.normalise({"founders": "enormous", "traits": ["immortality"]})["founders"]
			== SD.BASELINE_FOUNDERS,
		"and a nonsense stock normalises to the baseline rather than crashing an accessor")
	# The life histories this replaced are not traits and have no equivalent, so a save that
	# names one comes back unedited rather than carrying something arbitrary.
	var old: Dictionary = SD.normalise({"founders": "broad", "strategy": "enduring"})
	check((old["traits"] as Array).is_empty(),
		"a pre-trait record loads unedited: %s" % str(old["traits"]))
	check(str(old["tkey"]) == "", "with the cache key to match")

	# ── The effects reach the figures ──
	# Measured against the game's own numbers rather than the table's, because a multiplier that
	# is never applied is the failure this is for.
	var quick: Dictionary = SD.found("broad", ["rapid_maturation"], SD.baseline())
	var clever: Dictionary = SD.found("broad", ["high_intelligence"], SD.baseline())
	check(SD.growth_mult_of(quick) > SD.growth_mult_of(clever),
		"a fast-maturing stock grows faster than a clever one: %.3f vs %.3f" % [
			SD.growth_mult_of(quick), SD.growth_mult_of(clever)])
	check(SD.compute_mult_of(clever) > SD.compute_mult_of(quick),
		"and the clever one thinks more per head: %.3f vs %.3f" % [
			SD.compute_mult_of(clever), SD.compute_mult_of(quick)])

	# Life expectancy is one civilisation-wide figure, weighted by who holds which stock.
	var long_lived: Dictionary = SD.found("broad", ["longevity"], SD.baseline())
	var base_le: float = g._life_expectancy()
	g._pop_weighted_life = SD.life_mult_of(long_lived)
	check(g._life_expectancy() > base_le,
		"a long-lived civilisation lives longer: %.1f vs %.1f" % [g._life_expectancy(), base_le])
	g._pop_weighted_life = SD.life_mult_of(quick)
	check(g._life_expectancy() < base_le, "and a fast-maturing one does not")
	g._pop_weighted_life = 1.0

	# Human compute is the population weighted by what each stock gets out of a life, so the
	# same headcount thinks differently depending on who it is.
	g._recompute_production_cache()
	g._combine_production()
	var head: float = float(g.stats.get("current_population", 0))
	check(head > 0.0, "there are people to think")
	var plain_compute: float = g._cached_compute_human
	g._pop_weighted_compute = head * SD.compute_mult_of(clever)
	g._combine_production()
	check(g._cached_compute_human > plain_compute * 1.05,
		"the same headcount of clever stock thinks more: %s vs %s" % [
			g._cached_compute_human, plain_compute])
	g._pop_weighted_compute = head * SD.compute_mult_of(quick)
	g._combine_production()
	check(g._cached_compute_human < plain_compute * 0.95, "and of fast-maturing stock thinks less")
	g._pop_weighted_compute = 0.0

	# ── Room is a property of the people as well as the ground ──
	var star: String = "Tau Ceti"
	g.colonized_stars.append(star)
	g._col_star_set[star] = true
	g._world_stock[star] = SD.found("broad", [], SD.baseline())
	var plain_k: float = g._world_capacity(star)
	g._world_stock[star] = SD.found("broad", ["vacuum_adapted"], SD.baseline())
	var roomy_k: float = g._world_capacity(star)
	check(roomy_k > plain_k * 1.1,
		"a vacuum-tolerant population fits more of itself on the same rock: %s vs %s" % [
			roomy_k, plain_k])
	check(absf(roomy_k / plain_k - SD.capacity_mult_of(g.stock_of(star))) < 1.0e-6,
		"by exactly what the stock claims: %.4f vs %.4f" % [
			roomy_k / plain_k, SD.capacity_mult_of(g.stock_of(star))])

	# ── Divergence follows variation ──
	# A thin founder group drifts into its own lineage sooner, which is the other half of
	# shipping light: cheap, and it buys the diversity a monoculture has none of.
	var thin: Dictionary = SD.found("minimal", [], SD.baseline())
	var full: Dictionary = SD.baseline()
	check(g._stock_split_threshold("probe_world", thin)
			< g._stock_split_threshold("probe_world", full),
		"a thin stock diverges sooner: %d vs %d yr" % [
			g._stock_split_threshold("probe_world", thin),
			g._stock_split_threshold("probe_world", full)])
	check(g._stock_split_threshold("probe_world", full) > 400_000,
		"and a full one still takes the deep time it always did")

	# ── A von Neumann probe carries the lineage that launched it ──
	# This is what makes the swarm's genetic geography follow the shape of the expansion rather
	# than a menu, and it is the only way the mechanic reaches the tens of thousands of colonies
	# the player never sees.
	check(g.set_colony_stock("minimal", ["rapid_maturation"]) == "", "set a frontier order")
	g._world_stock["Procyon"] = SD.found("broad", ["longevity"], SD.baseline())
	var from_procyon: Dictionary = g.founding_stock("Procyon")
	check(str(from_procyon["founders"]) == "minimal", "the order decides how many go")
	check((from_procyon["traits"] as Array) == ["rapid_maturation"], "and what is written in")
	var settled: Dictionary = g._settle_stock("new_world", "Procyon")
	check(SD.diversity_of(g.stock_of("new_world")) == SD.diversity_of(settled),
		"settling records the stock")
	check((g.stock_of("new_world")["traits"] as Array) == ["rapid_maturation"], "as ordered")

	# ── It survives a save ──
	g.set_colony_stock("broad", ["longevity", "high_intelligence"])
	g._world_stock["mars"] = SD.found("minimal", ["rapid_maturation"], SD.baseline())
	var want_mars: String = SD.describe(g.stock_of("mars"))
	var want_order: String = SD.describe(g.colony_stock)
	g.save_game("user://saves/stocks.json")
	g.colony_stock = {"founders": "minimal", "traits": []}
	g._world_stock = {}
	g.load_game("user://saves/stocks.json")
	check(SD.describe(g.stock_of("mars")) == want_mars,
		"a world's stock survives the round trip: %s vs %s" % [
			SD.describe(g.stock_of("mars")), want_mars])
	check(SD.describe(g.colony_stock) == want_order, "and so does the standing order")
	check(str(g.stock_of("mars")["tkey"]) == SD.tkey_for(g.stock_of("mars")["traits"]),
		"with the cache key rebuilt to match the traits it came back with")
	check(g._world_stock.has("earth"), "and Earth always has one")

	# A file from before any of this loads as the baseline everywhere, which is what it was.
	var f2 := FileAccess.open("user://saves/stocks.json", FileAccess.READ)
	var raw: Dictionary = JSON.parse_string(f2.get_as_text())
	f2.close()
	raw.erase("world_stock")
	raw.erase("colony_stock")
	var f3 := FileAccess.open("user://saves/stocks_old.json", FileAccess.WRITE)
	f3.store_string(JSON.stringify(raw))
	f3.close()
	g.load_game("user://saves/stocks_old.json")
	check(SD.diversity_of(g.stock_of("earth")) == 1.0,
		"an older save loads Earth as the full-variation baseline")
	check(SD.diversity_of(g.stock_of("mars")) == 1.0, "and every colony with it")
	check(str(g.colony_stock["founders"]) == SD.BASELINE_FOUNDERS,
		"and the order back to standard")
	check((g.colony_stock["traits"] as Array).is_empty(), "carrying nothing written")

	print("FAILS: %d" % fails)
	quit()
