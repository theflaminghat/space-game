extends SceneTree

## Trading with your own interstellar colonies.
##
## They could not be traded with at all: the Trade button was greyed for anything colonised, and
## there was nothing on the other side of a trade anyway — a colony held no inventory and
## produced nothing, and trade_holdings() hands back the civilisation-wide energy and science
## pools for every world, so a "trade" would have moved a number to itself.
##
## So a colony has an economy now. It mines its own system without being asked, because a world
## four hundred light-years out cannot be managed — the round trip is eight centuries — only
## traded with. What it has when a request arrives is whatever it has been doing since anyone
## last looked.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(20261016)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene

	var w: String = "Alpha Centauri A"
	check(not g.is_own_colony(w), "nothing of ours is out there yet")
	g.colonized_stars.append(w)
	g._col_star_set[w] = true
	g._colony_year[w] = g.year
	g.world_pop[w] = 1.0e8
	check(g.is_own_colony(w), "and now there is")

	# ── A colony's exports are its own, and always the same ──
	var ex: Array = g.colony_exports(w)
	check(ex.size() == g.COLONY_EXPORT_KINDS,
		"it yields %d materials: %s" % [g.COLONY_EXPORT_KINDS, str(ex)])
	check(g.colony_exports(w) == ex, "asked twice, the same answer")
	var seen: Dictionary = {}
	for k in ex:
		check(not seen.has(k), "no material twice: %s" % str(ex))
		check(g.COLONY_EXPORTS.has(str(k)), "and each is a real material: %s" % str(k))
		seen[k] = true
	# Different systems yield different things, or there would be no reason to shop around.
	var other: Array = g.colony_exports("Barnard's Star")
	check(ex != other, "a different system yields something else: %s vs %s" % [str(ex), str(other)])

	# ── A new colony produces nothing; a built-up one produces ──
	check(g.colony_maturity(w) <= 0.01, "a colony founded today has built nothing")
	check(g.colony_output(w) <= 0.0, "so it yields nothing")
	g._colony_year[w] = g.year - 2 * int(g.COLONY_DYSON_YEARS)   # long since enclosed its star
	check(g.colony_maturity(w) >= 0.99, "an old colony has enclosed its star")
	check(g.colony_output(w) > 0.0, "and mines: %s g/yr" % g.colony_output(w))

	check(g._planet_inv(w).is_empty(), "its stores start empty")
	for _i in range(4):
		g._advance_colony_economy(100.0)
	var inv: Dictionary = g._planet_inv(w)
	check(not inv.is_empty(), "after four centuries it is holding something: %s" % str(inv.keys()))
	for k in ex:
		check(float(inv.get(str(k), 0.0)) > 0.0, "including %s" % str(k))
	var total: float = 0.0
	for k2: String in inv:
		total += float(inv[k2])
	check(absf(total - g.colony_output(w) * 400.0) < total * 0.02,
		"and the amount is its output over the span: %s vs %s" % [
			total, g.colony_output(w) * 400.0])

	# ── The trade path accepts it as a partner ──
	var ctx: Dictionary = g.trade_context(w)
	check(bool(ctx.get("own_colony", false)), "the trade panel is told whose it is")
	check(str(ctx.get("alignment", "")) == "ours", "there is no alignment to guess at")
	check(float(ctx.get("reply_years", 0.0)) > 1.0,
		"and it is still light-years away: %.1f yr round trip" % float(ctx["reply_years"]))
	check(not (ctx.get("holdings", {}) as Dictionary).is_empty(),
		"the panel can see what the colony holds")

	# ── Mass costs energy to move, which is what stops this being teleportation ──
	# A message is cheap; a consignment is kinetic energy per gram at a fraction of c. The
	# consequence worth keeping is that bulk trade between stars is unaffordable on a planetary
	# grid and ordinary once a star has been enclosed.
	check(g.consignment_energy(w, {"energy": 1.0e9, "science": 1.0e9}) == 0.0,
		"energy and science weigh nothing and are already paid for as a transmission")
	var one_g: float = g.consignment_energy(w, {"Fe": 1.0})
	check(one_g > 0.0, "a gram of iron costs something to fly: %s" % one_g)
	check(g.consignment_energy(w, {"Fe": 1000.0}) > one_g * 999.0,
		"and a kilogram costs a thousand times as much")
	check(g.consignment_energy("Barnard's Star", {"Fe": 1.0}) > one_g,
		"and the same gram costs more to a star further off")
	# Asked for as a REQUEST, not an offer: an offer is checked against what the origin holds
	# first, so it would be refused for the wrong reason and the freight never reached.
	check(g.propose_trade(w, "earth", {}, {"Fe": 1.0e18}).find("Not enough energy") >= 0,
		"a consignment the grid cannot lift is refused: %s"
			% g.propose_trade(w, "earth", {}, {"Fe": 1.0e18}))

	# ── A consignment goes out and comes back ──
	root.get_node("ResearchTree").resources["energy"] = 1.0e30   # a star-enclosing grid
	var want_key: String = str(ex[0])
	var had: float = float(g._planet_inv(w).get(want_key, 0.0))
	g._add_stockpile("Steel", 5.0e9, "earth")
	var before_earth: float = float(g._planet_inv("earth").get(want_key, 0.0))
	var err: String = g.propose_trade(w, "earth", {"Steel": 1.0e9}, {want_key: had * 0.5})
	check(err == "", "the consignment is accepted for despatch: %s" % err)
	check(g.outgoing_messages.size() == 1, "and is in flight")
	# Escrowed at once: the goods have left.
	check(float(g._planet_inv("earth").get("Steel", 0.0)) < 5.0e9,
		"what was sent has left Earth's stores")

	var due: float = float((g.outgoing_messages[0] as Dictionary)["end_year"])
	g.year = int(ceil(due))
	g._check_message_arrivals()
	check(g.outgoing_messages.is_empty(), "the round trip completes")
	check(float(g._planet_inv("earth").get(want_key, 0.0)) > before_earth,
		"and %s arrives at Earth: %s" % [want_key,
			float(g._planet_inv("earth").get(want_key, 0.0))])
	check(float(g._planet_inv(w).get("Steel", 0.0)) > 0.0,
		"while the Steel is unloaded at the colony")
	check(float(g._planet_inv(w).get(want_key, 0.0)) < had,
		"out of a store that is correspondingly lighter")

	# ── Asking for more than it has is filled as far as it goes ──
	# Nobody over there decided anything: a colony that has been shipping elsewhere simply has
	# less, and refusing outright would be stranger than a short delivery.
	var left: float = float(g._planet_inv(w).get(want_key, 0.0))
	check(g.propose_trade(w, "earth", {}, {want_key: left * 100.0}) == "",
		"an over-large request is still despatched")
	g.year = int(ceil(float((g.outgoing_messages[0] as Dictionary)["end_year"])))
	g._check_message_arrivals()
	check(float(g._planet_inv(w).get(want_key, 0.0)) < left * 0.01,
		"the colony sends what it has: %s left" % float(g._planet_inv(w).get(want_key, 0.0)))

	# ── A colony that no longer exists returns the consignment ──
	g._add_stockpile("Steel", 2.0e9, "earth")
	check(g.propose_trade(w, "earth", {"Steel": 1.0e9}, {}) == "", "another goes out")
	var held_steel: float = float(g._planet_inv("earth").get("Steel", 0.0))
	g.colonized_stars.erase(w)
	g._col_star_set.erase(w)
	g.year = int(ceil(float((g.outgoing_messages[0] as Dictionary)["end_year"])))
	g._check_message_arrivals()
	check(float(g._planet_inv("earth").get("Steel", 0.0)) > held_steel,
		"and the cargo comes home rather than vanishing")

	print("FAILS: %d" % fails)
	quit()
