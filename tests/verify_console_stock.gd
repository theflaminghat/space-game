extends SceneTree

## `stock` reads and sets the founding-population order from the console.
##
## The readout is the more useful half: an order means little without seeing what a ship leaving
## the world being viewed would actually carry, because that depends on the population it is
## drawn from and not only on what was ordered.

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
	var SD = load("res://stock_data.gd")
	var con: Node = null
	for c in g.get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("DevConsole.gd"):
			con = c
	if con == null:
		con = g.get_node_or_null("DevConsole")
	check(con != null, "the console is in the scene")
	if con == null:
		print("FAILS: %d" % fails)
		quit()
		return

	# ── It is a declared command with help, like every other one ──
	var found: Dictionary = {}
	for row: Dictionary in con.COMMANDS:
		found[str(row["name"])] = row
	check(found.has("stock"), "stock is in the command table")
	if found.has("stock"):
		var row: Dictionary = found["stock"]
		check(str(row.get("summary", "")) != "", "with a summary")
		check(str(row.get("detail", "")).length() > 80, "and a real explanation")
		check((row.get("aliases", []) as Array).has("founders"), "and the obvious alias")

	# ── Reading does not change anything ──
	var before: String = SD.describe(g.colony_stock)
	con._stock([])
	check(SD.describe(g.colony_stock) == before, "a bare read leaves the order alone")

	# ── Either part, in either order ──
	# The two id sets are disjoint, so there is nothing for the player to remember about
	# argument position.
	root.get_node("ResearchTree").force_unlock("synthetic_biology")
	con._stock(["broad"])
	check(str(g.colony_stock["founders"]) == "broad", "one argument sets the founder group")
	check((g.colony_stock["traits"] as Array).is_empty(), "and leaves the rest")
	con._stock(["longevity"])
	check((g.colony_stock["traits"] as Array) == ["longevity"], "one argument sets a trait")
	check(str(g.colony_stock["founders"]) == "broad", "and leaves the group")
	con._stock(["high_intelligence", "minimal"])
	check(str(g.colony_stock["founders"]) == "minimal", "both, reversed, still land")
	check((g.colony_stock["traits"] as Array) == ["high_intelligence"],
		"and naming traits REPLACES the set rather than adding to it: %s"
			% str(g.colony_stock["traits"]))
	con._stock(["longevity", "high_intelligence"])
	check((g.colony_stock["traits"] as Array).size() == 2, "several at once")
	con._stock(["none"])
	check((g.colony_stock["traits"] as Array).is_empty(), "and `none` clears them")
	con._stock(["BROAD"])
	check(str(g.colony_stock["founders"]) == "broad", "and case does not matter")

	# ── Nonsense is refused without changing the order ──
	con._stock(["longevity"])
	var held: String = SD.describe(g.colony_stock)
	con._stock(["enormous"])
	check(SD.describe(g.colony_stock) == held, "an unknown id changes nothing")
	con._stock(["broad", "immortal"])
	check(SD.describe(g.colony_stock) == held, "and nor does a half-valid pair")

	print("FAILS: %d" % fails)
	quit()
