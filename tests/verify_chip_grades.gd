extends SceneTree

## Three microchip processes, researched at three depths, each producing ITS OWN ITEM — and the
## tiers of anything built from chips require the chip of their generation.
##
## So reaching the next rung costs a production line, not just a research node: an AI Research
## Hub III cannot be built out of CMOS parts however much silicon is on hand, and researching
## reversible logic pays nothing at all until reversible chips are actually being fabricated.
##
## The ladder is real physics: CMOS throws away of order 1e5 kT per logic transition, adiabatic
## logic recovers the charge and approaches the Landauer bound of kT ln 2, and reversible logic
## erases nothing so that bound does not apply.  What is NOT claimed is that grade 3 is a
## physical limit — a fabricated chip cannot reach one.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _chip_cost(b: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: String in (b.get("cost", {}) as Dictionary):
		if BuildingData.LEVEL_CHIP.has(k):
			out[k] = float((b["cost"] as Dictionary)[k])
	return out

func _run() -> void:
	seed(20260927)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(40): await process_frame
	var g: Node = current_scene
	var rt: Node = root.get_node("ResearchTree")

	# ── Three grades, three nodes, three depths ──
	check(g.CHIP_RESEARCH.size() == 3, "there are three chip processes")
	check(BuildingData.LEVEL_CHIP.size() == 3, "and a chip item per building tier")
	var cols: Array = []
	for id_v: Variant in g.CHIP_RESEARCH:
		var n: ResearchNode = rt.get_research_node(str(id_v))
		check(n != null, "%s is a real research node" % str(id_v))
		cols.append(roundf(n.position.x / 430.0))
	check(cols[0] < cols[1] and cols[1] < cols[2],
		"each is deeper in the tree than the last: columns %s" % str(cols))
	check(rt.get_research_node("reversible_computing").prerequisites.has("adiabatic_logic"),
		"the top process needs the middle one")
	check(g.chip_grade() == 1, "a fresh run is on CMOS")
	rt.force_unlock("reversible_computing")
	check(g.chip_grade() == 3, "the deepest process known sets the grade, in any order")

	# ── Each is a DIFFERENT ITEM, with its own recipe ──
	var items: Array = BuildingData.LEVEL_CHIP
	for it_v: Variant in items:
		var it: String = str(it_v)
		check(CompoundData.NAMES.has(it), "%s is a real compound" % it)
		check(CompoundData.DESCRIPTIONS.has(it), "and is described")
		check(str(CompoundData.CATEGORIES.get(it, "")) == "manufactured",
			"and is a manufactured good")
	check(items[0] != items[1] and items[1] != items[2] and items[0] != items[2],
		"and they are three distinct items: %s" % str(items))

	var made_by: Dictionary = {}
	for r: Dictionary in RecipeData.RECIPES:
		for k: String in (r.get("outputs", {}) as Dictionary):
			if items.has(k):
				check(not made_by.has(k), "%s is made by exactly one recipe" % k)
				made_by[k] = r
	check(made_by.size() == 3, "every grade has a way to be produced: %d" % made_by.size())
	for i in range(3):
		var it: String = str(items[i])
		var r: Dictionary = made_by[it]
		check(str(r.get("requires", "")) == str(g.CHIP_RESEARCH[i]),
			"%s is gated on %s" % [it, str(g.CHIP_RESEARCH[i])])
		check((r["outputs"] as Dictionary).size() == 1,
			"%s's recipe makes nothing else" % it)

	# Each process is cheaper per chip and higher-yielding than the last.
	var last_per: float = INF
	var last_yield: float = 0.0
	for it_v: Variant in items:
		var r: Dictionary = made_by[str(it_v)]
		var n: float = float((r["outputs"] as Dictionary)[str(it_v)])
		var per: float = float((r["inputs"] as Dictionary).get("energy", 0.0)) / n
		check(per < last_per, "%s costs less energy per chip: %.1f" % [str(it_v), per])
		check(n > last_yield, "and more dies off the same wafer: %.0f" % n)
		last_per = per
		last_yield = n

	# ── Levelling anything built from chips requires the chip of that tier ──
	var tiered := 0
	for b: Dictionary in BuildingData.all():
		var chips: Dictionary = _chip_cost(b)
		if chips.is_empty():
			continue
		var lv: int = int(b.get("level", 1))
		check(chips.size() == 1,
			"%s is built from one chip generation, not several" % str(b["name"]))
		var want: String = str(items[mini(lv, 3) - 1])
		check(chips.has(want),
			"%s (level %d) requires %s, got %s" % [str(b["name"]), lv, want, str(chips.keys())])
		if lv > 1:
			tiered += 1
	check(tiered > 0, "there are higher tiers needing the better chips: %d" % tiered)

	# Spelled out on the line where it matters most.
	for pair: Array in [["AI Research Hub", "Microchip"],
			["AI Research Hub II", "AdiabaticChip"],
			["AI Research Hub III", "ReversibleChip"]]:
		var b: Dictionary = g._find_building_def(str(pair[0]))
		check(not b.is_empty(), "%s exists" % str(pair[0]))
		check(_chip_cost(b).has(str(pair[1])),
			"%s is built from %s" % [str(pair[0]), str(pair[1])])

	# A building that never needed chips does not acquire them by being levelled.
	var mine2: Dictionary = g._find_building_def("Mine II")
	check(not mine2.is_empty(), "Mine II exists")
	check(_chip_cost(mine2).is_empty(), "and still needs no chips at all")

	# ── No grade is ever dead data ──
	# The base chip is still what craft, robots and probes are made of after reversible logic is
	# in hand, so the first fabrication line never stops being worth running.
	var base_users: Array = []
	for r: Dictionary in RecipeData.RECIPES:
		if (r.get("inputs", {}) as Dictionary).has("Microchip"):
			base_users.append(str(r["name"]))
	check(base_users.size() >= 5,
		"the base chip still has consumers of its own: %d" % base_users.size())

	# ── The research alone buys nothing ──
	# This is the whole point of making them items.  With every node in hand but no chips in
	# stock, the third tier cannot be built.
	for n2: ResearchNode in load("res://ResearchTreeData.gd").build():
		rt.force_unlock(str(n2.id))
	g.planet_buildings["earth"] = []
	g.build_queue.clear()
	var inv: Dictionary = g._planet_inv("earth")
	for it_v: Variant in items:
		inv.erase(str(it_v))
	root.get_node("ResearchTree").resources["energy"] = 1.0e30
	check(not g.try_build("earth", "AI Research Hub III"),
		"with the research but no reversible chips, the third tier cannot be built")

	# Give it exactly the wrong generation of chip: still refused.
	var need: Dictionary = (g._find_building_def("AI Research Hub III")["cost"] as Dictionary)
	for k: String in need:
		if k == "energy":
			continue
		g._add_stockpile(k if not items.has(k) else "Microchip",
			float(need[k]) * 2.0, "earth")
	check(not g.try_build("earth", "AI Research Hub III"),
		"and CMOS chips are not a substitute for them")

	# Now fabricate the right ones.
	g._add_stockpile("ReversibleChip", float(need.get("ReversibleChip", 0.0)) * 2.0, "earth")
	check(g.try_build("earth", "AI Research Hub III"),
		"with reversible chips in stock it builds")

	# ── And the payoff arrives through the tier, not from the grade itself ──
	var lv1: Dictionary = g._find_building_def("AI Research Hub")
	var lv3: Dictionary = g._find_building_def("AI Research Hub III")
	var c1: float = float((lv1.get("production", {}) as Dictionary).get("compute", 0.0))
	var c3: float = float((lv3.get("production", {}) as Dictionary).get("compute", 0.0))
	check(c1 > 0.0 and c3 > c1 * 10.0,
		"the third tier computes far more than the first: %s vs %s" % [
			Units.format_si(c1, "F"), Units.format_si(c3, "F")])

	print("FAILS: %d" % fails)
	quit()
