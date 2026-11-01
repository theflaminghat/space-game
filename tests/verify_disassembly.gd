extends SceneTree

## Taking a planet apart.
##
## The pair to Star Lifting, and the cheap half of it: a planet's gravity well is four to five
## orders of magnitude shallower than its star's, which is why a civilisation that has run out
## of places to build eats the planets first.
##
## What has to hold:
##   the bill per gram is binding energy, and planets are far cheaper than Sol per kilogram
##   layers go outside in — you cannot reach a core through a mantle
##   what is removed is REMEMBERED, so a body can actually be exhausted
##   a world holds fewer people as it shrinks, and none when it is gone
##   mining and disassembly keep one ledger
##   the whole thing survives a save

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(20261024)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var rt: Node = root.get_node("ResearchTree")
	var DD = load("res://disassembly.gd")


	# ── The physics, before anything is built ──
	var merc: Dictionary = PlanetData.PLANETS["mercury"]
	var earth_pd: Dictionary = PlanetData.PLANETS["earth"]
	var m_per_kg: float = DD.binding_j_per_kg(
		float(merc["mass_kg"]), float(merc["radius_km"]))
	var e_per_kg: float = DD.binding_j_per_kg(
		float(earth_pd["mass_kg"]), float(earth_pd["radius_km"]))
	check(m_per_kg > 1.0e6 and m_per_kg < 1.0e7,
		"Mercury costs a few MJ/kg to lift: %s" % str(m_per_kg))
	check(e_per_kg > m_per_kg, "Earth is a deeper well than Mercury: %s" % str(e_per_kg))
	# The comparison the whole design rests on.
	check(StarModel.LIFT_ENERGY_PER_KG / m_per_kg > 1000.0,
		"and Sol is orders of magnitude dearer than either: %.0fx"
			% (StarModel.LIFT_ENERGY_PER_KG / m_per_kg))
	check(absf(DD.binding_j_per_gram(float(merc["mass_kg"]), float(merc["radius_km"]))
			- m_per_kg * 1.0e-3) < 1.0e-9, "grams and kilograms agree")
	check(DD.binding_j_per_kg(0.0, 100.0) == 0.0, "a massless body costs nothing")
	check(DD.binding_j_per_kg(1.0e24, 0.0) == 0.0, "and a radiusless one does not divide by zero")
	# Outside in.
	check(DD.LAYER_ORDER[0] == "atmosphere" and DD.LAYER_ORDER[-1] == "core",
		"layers run outside in: %s" % str(DD.LAYER_ORDER))


	# ── Nothing has been taken out of anything yet ──
	check(g._body_remaining_fraction("mercury") == 1.0, "Mercury is all there")
	check(g._next_layer("mercury") == "atmosphere",
		"and the first thing reachable is its atmosphere: %s" % g._next_layer("mercury"))


	# ── A world is taken apart by machinery standing on it ──
	for n: ResearchNode in load("res://ResearchTreeData.gd").build():
		rt.force_unlock(str(n.id))
	check(rt.is_unlocked("planetary_disassembly"), "the research exists and unlocks")
	var bd: Dictionary = g._find_building_def("Planetary Disassembler")
	check(not bd.is_empty(), "and there is a building for it")
	check(float(bd.get("disassembly_rate", 0.0)) > 0.0,
		"with a rate: %s g/day" % str(bd.get("disassembly_rate")))
	# Tiers scale it, like every other rated structure.
	var tiers: Array = []
	for b: Dictionary in load("res://buildings.gd").all():
		if str(b.get("base_name", b.get("name", ""))) == "Planetary Disassembler":
			tiers.append(float(b.get("disassembly_rate", 0.0)))
	check(tiers.size() > 1, "it comes in tiers: %d" % tiers.size())
	check(tiers.size() < 2 or tiers[-1] > tiers[0],
		"and a higher tier lifts more: %s" % str(tiers))

	g.planet_buildings["mercury"] = ["Planetary Disassembler"]
	rt.resources["energy"] = 1.0e40
	g._mark_prod_dirty("mercury")
	g._recompute_production_cache()
	var st: Dictionary = g.disassembly_state("mercury")
	check(float(st["rate"]) > 0.0, "the production cache carries the rate: %s" % str(st["rate"]))
	check(float(st["years"]) > 1000.0,
		"one unit is a project measured in deep time: %.0f yr" % float(st["years"]))


	# ── It eats outside in, and remembers ──
	g._run_disassembly(1.0)
	check(not g._body_removed.get("mercury", {}).is_empty(),
		"a tick removes something and writes it down: %s"
			% str((g._body_removed.get("mercury", {}) as Dictionary).keys()))
	var merc_led: Dictionary = g._body_removed.get("mercury", {})
	check(merc_led.has("atmosphere"), "the atmosphere first")
	check(not merc_led.has("core"),
		"and nothing out of the core while there is anything above it")
	check(float((g.compound_inventory.get("mercury", {}) as Dictionary).size()) > 0,
		"what came up is in the body's own stores")

	# Energy is charged at the binding energy of what moved.
	#
	# A reserve the same ORDER as the bill, deliberately: against 1e40 W·d a charge of 1e20
	# disappears into the rounding of a 64-bit float and the test reads as "nothing was paid"
	# when the simulation paid correctly.
	rt.resources["energy"] = 1.0e24
	var e0: float = float(rt.resources["energy"])
	var before_frac: float = g._body_remaining_fraction("mercury")
	var rate_g: float = float(g.disassembly_state("mercury")["rate"])
	g._run_disassembly(10.0)
	var spent_wd: float = e0 - float(rt.resources["energy"])
	var want_wd: float = rate_g * 10.0 * DisassemblyData.binding_j_per_gram(
		float(merc["mass_kg"]), float(merc["radius_km"])) / g.DAY_SECONDS
	check(spent_wd > 0.0, "and the energy is paid for: %s W·d" % str(spent_wd))
	check(absf(spent_wd - want_wd) <= want_wd * 1.0e-6,
		"at exactly the binding energy of what moved: %s vs %s" % [str(spent_wd), str(want_wd)])
	check(g._body_remaining_fraction("mercury") < before_frac, "the body shrinks")

	# Short of energy, it takes proportionally less rather than refusing outright.
	rt.resources["energy"] = 0.0
	var frac_broke: float = g._body_remaining_fraction("mercury")
	g._run_disassembly(100.0)
	check(absf(g._body_remaining_fraction("mercury") - frac_broke) < 1.0e-12,
		"with no energy nothing moves at all")
	rt.resources["energy"] = 1.0e40


	# ── Mining and disassembly keep ONE ledger ──
	# The old readout worked out what was left from what the player was HOLDING, so spending
	# the ore grew the crust back. This is that bug, asserted as behaviour.
	g.planet_buildings["mars"] = ["Mine", "Mine", "Mine"]
	g._mark_prod_dirty("mars")
	g._recompute_production_cache()
	g._accumulate_compounds(500.0)
	var mars_removed: float = 0.0
	var mars_crust: Dictionary = (g._body_removed.get("mars", {}) as Dictionary).get("crust", {})
	for c: String in mars_crust:
		mars_removed += float(mars_crust[c])
	check(mars_removed > 0.0, "mining writes to the ledger too: %s g" % str(mars_removed))
	var mars_left_before: float = g._layer_mass_left("mars", "crust")
	# Spend everything the world is holding; the crust must NOT grow back.
	g.compound_inventory["mars"] = {}
	check(absf(g._layer_mass_left("mars", "crust") - mars_left_before) < 1.0,
		"and emptying the stores does not put the crust back: %s vs %s" % [
			str(g._layer_mass_left("mars", "crust")), str(mars_left_before)])


	# ── A shrinking world holds fewer people ──
	g.colonized_planets.append("mercury")
	g._colonized_year["mercury"] = g.year
	var k_full: float = g._world_capacity("mercury")
	# Strip it to a tenth by hand, which is far faster than running the machinery there.
	var comp: Dictionary = g._body_composition("mercury")
	for layer: String in comp:
		for compound: String in (comp[layer] as Dictionary):
			g._record_removed("mercury", layer, compound,
				float((comp[layer] as Dictionary)[compound]) * 0.9)
	g._pop_cap_mult_cache = -1.0
	var k_tenth: float = g._world_capacity("mercury")
	check(g._body_remaining_fraction("mercury") < 0.2,
		"a tenth of a world is left: %.3f" % g._body_remaining_fraction("mercury"))
	check(k_tenth < k_full * 0.5 + 1.0,
		"and it holds far fewer people: %s vs %s" % [str(k_tenth), str(k_full)])


	# ── The last layer takes the world with it ──
	g.world_pop["mercury"] = 1000.0
	(g.compound_inventory["mercury"] as Dictionary)["Fe"] = 5.0e15
	var home_fe: float = float((g.compound_inventory.get("earth", {}) as Dictionary).get("Fe", 0.0))
	for layer: String in comp:
		for compound: String in (comp[layer] as Dictionary):
			g._record_removed("mercury", layer, compound,
				float((comp[layer] as Dictionary)[compound]))
	check(g._next_layer("mercury") == "", "nothing reachable is left")
	g._run_disassembly(1.0)
	check(g._disassembled.has("mercury"), "so the world stops existing")
	check(not g.colonized_planets.has("mercury"), "it is not a colony any more")
	check(not g.world_pop.has("mercury"), "nobody lives there")
	check(not g.planet_buildings.has("mercury"), "and nothing stands on it")
	check(g._world_capacity("mercury") == 0.0, "it holds nobody at all")
	check(float((g.compound_inventory.get("earth", {}) as Dictionary).get("Fe", 0.0))
			>= home_fe + 5.0e15 - 1.0,
		"what was still in its stores came home: %s" % str(
			(g.compound_inventory.get("earth", {}) as Dictionary).get("Fe", 0.0)))
	# Idempotent: a second pass over a world that is gone does nothing and crashes nothing.
	g._run_disassembly(1.0)
	check(g._disassembled.has("mercury"), "and running again is harmless")


	# ── It survives a save ──
	g.save_game("user://saves/disasm.json")
	g._body_removed = {}
	g._disassembled = {}
	g.load_game("user://saves/disasm.json")
	check(g._disassembled.has("mercury"), "a disassembled world stays disassembled")
	check(not g._body_removed.get("mars", {}).is_empty(),
		"and the ledger comes back: %s" % str(g._body_removed.keys()))
	var mars_after: float = 0.0
	var mars_crust2: Dictionary = (g._body_removed.get("mars", {}) as Dictionary).get("crust", {})
	for c: String in mars_crust2:
		mars_after += float(mars_crust2[c])
	check(absf(mars_after - mars_removed) <= mars_removed * 1.0e-6,
		"to the gram: %s vs %s" % [str(mars_after), str(mars_removed)])
	# Junk in the file does not become junk in the ledger.
	g._body_removed = {}
	g.load_game("user://saves/disasm.json")
	var f := FileAccess.open("user://saves/disasm.json", FileAccess.READ)
	var raw: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	raw["body_removed"] = {"venus": {"crust": {"Fe": "not a number"}}, "mars": "nonsense"}
	var f2 := FileAccess.open("user://saves/disasm_bad.json", FileAccess.WRITE)
	f2.store_string(JSON.stringify(raw))
	f2.close()
	g.load_game("user://saves/disasm_bad.json")
	check(g._body_removed.get("mars", null) == null or g._body_removed["mars"] is Dictionary,
		"a hand-edited ledger loads without poisoning anything")
	check(g._layer_mass_left("venus", "crust") > 0.0, "and Venus still has a crust")

	# ── The planet panel says so, and keeps saying so as the world shrinks ──
	# Composition used to be rebuilt only when the SELECTED planet changed, on the grounds that
	# what a body is made of does not move. Disassembly makes that false.
	# Named outright. Hunting for it and skipping the section when it is not found is how a
	# whole block of assertions silently stops running — this one did, and passed with the
	# thing it covers reverted.
	var page = g.planet_info_page
	check(page != null, "the planet panel is in the scene")
	if page != null:
		g.planet_buildings["venus"] = ["Planetary Disassembler"]
		g._mark_prod_dirty("venus")
		g._recompute_production_cache()
		var d1: Dictionary = g.get_planet_data("venus")
		check((d1.get("disassembly", {}) as Dictionary).has("fraction"),
			"the panel is given a disassembly block")
		page.set_planet_info(d1)
		check(page._disasm_label != null and page._disasm_label.visible,
			"and shows the line while a world is being lifted")
		var f1: float = page._last_fraction
		# Take a real bite, then push again: the composition list must rebuild.
		var vcomp: Dictionary = g._body_composition("venus")
		for layer: String in vcomp:
			for compound: String in (vcomp[layer] as Dictionary):
				g._record_removed("venus", layer, compound,
					float((vcomp[layer] as Dictionary)[compound]) * 0.5)
		page.set_planet_info(g.get_planet_data("venus"))
		check(page._last_fraction < f1 - 0.1,
			"and the list follows the world down: %.3f -> %.3f" % [f1, page._last_fraction])

	print("FAILS: %d" % fails)
	quit()
