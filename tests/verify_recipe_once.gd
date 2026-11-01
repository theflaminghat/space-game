extends SceneTree

## A recipe already in production on a world cannot be started there a second time.
##
## Two copies of a line was never two production lines — it was one recipe listed twice, each
## with its own rate slider, competing for the same inputs. Taking it off the list makes it
## selectable again, and the greyed menu entry is what says so.
##
## PER WORLD, which is the part worth pinning: the same recipe running on Mars says nothing
## about whether Earth may start it.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()


## Is `recipe_name` greyed in the picker?  Walks the category submenus, which is where the
## entries actually live.
func _is_greyed(panel, recipe_name: String) -> bool:
	for sm in panel._cat_submenus:
		var menu := sm as PopupMenu
		if menu == null:
			continue
		for i in range(menu.item_count):
			var idx: int = menu.get_item_id(i)
			if idx < 0 or idx >= panel._all_recipes.size():
				continue
			if str(panel._all_recipes[idx]["name"]) == recipe_name:
				return menu.is_item_disabled(i)
	return false


func _count_jobs(panel, planet: String, recipe_name: String) -> int:
	var n: int = 0
	for j: Dictionary in panel._jobs:
		if str(j.get("planet", "earth")).to_lower() == planet \
				and str(j.get("recipe", "")) == recipe_name:
			n += 1
	return n


func _run() -> void:
	seed(20261030)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var rt: Node = root.get_node("ResearchTree")
	for n: ResearchNode in load("res://ResearchTreeData.gd").build():
		rt.force_unlock(str(n.id))
	var p = g.production_panel
	check(p != null, "the production panel is in the scene")
	if p == null:
		print("FAILS: %d" % maxi(fails, 1))
		quit()
		return
	p.refresh_recipes(rt.completed if rt.get("completed") != null else {})
	for _i in range(4): await process_frame
	check(p._all_recipes.size() > 2,
		"there are recipes to choose from: %d" % p._all_recipes.size())

	p.set_planet("earth")
	for _i in range(2): await process_frame
	# Chosen from what Earth is NOT already making: a 1945 start comes with farms on the list,
	# so the first two entries in the catalogue are not safe to assume idle.
	var free: Array = []
	for r: Dictionary in p._all_recipes:
		if not p._recipe_running_here(str(r["name"])):
			free.append(str(r["name"]))
	check(free.size() >= 2, "Earth is not already making everything: %d free" % free.size())
	if free.size() < 2:
		print("FAILS: %d" % maxi(fails, 1))
		quit()
		return
	var target: String = str(free[0])
	var other: String = str(free[1])

	# ── Before it is running, it is offered ──
	check(not _is_greyed(p, target), "%s starts out selectable" % target)
	check(not p._add_button.disabled, "and the Add button is live")
	check(not p._recipe_running_here(target), "nothing is running it yet")

	# ── Add it: it stops being offered ──
	p._selected_recipe_name = target
	p._on_add_pressed()
	for _i in range(2): await process_frame
	check(_count_jobs(p, "earth", target) == 1,
		"adding it makes one job: %d" % _count_jobs(p, "earth", target))
	check(p._recipe_running_here(target), "which the panel knows about")
	check(_is_greyed(p, target), "and the menu entry is greyed")
	check(not _is_greyed(p, other), "while everything else stays selectable")

	# ── Pressing Add again does nothing, even with the selection forced back ──
	p._selected_recipe_name = target
	p._on_add_pressed()
	check(_count_jobs(p, "earth", target) == 1,
		"a second Add is refused: %d jobs" % _count_jobs(p, "earth", target))

	# ── The selection moves on rather than sitting behind a dead button ──
	p._selected_recipe_name = target
	p._refresh_recipe_availability()
	check(p._selected_recipe_name != target,
		"the picker moves off a recipe that has just gone into production: %s"
			% p._selected_recipe_name)
	check(not p._recipe_running_here(p._selected_recipe_name),
		"onto one that can actually be started: %s" % p._selected_recipe_name)

	# ── Another world is unaffected ──
	p.set_planet("mars")
	for _i in range(2): await process_frame
	check(not _is_greyed(p, target),
		"%s is selectable on Mars, which is not making it" % target)
	check(not p._recipe_running_here(target), "because the rule is per world")
	p._selected_recipe_name = target
	p._on_add_pressed()
	check(_count_jobs(p, "mars", target) == 1, "so Mars can start it")
	check(_count_jobs(p, "earth", target) == 1, "without touching Earth's")
	check(_is_greyed(p, target), "and now Mars has it greyed too")

	# ── Taking it off puts it back on the menu ──
	var mars_id: int = -1
	for j: Dictionary in p._jobs:
		if str(j.get("planet", "")) == "mars" and str(j.get("recipe", "")) == target:
			mars_id = int(j["id"])
	check(mars_id >= 0, "Mars's job has an id")
	p._on_remove_pressed(mars_id)
	for _i in range(2): await process_frame
	check(_count_jobs(p, "mars", target) == 0, "removing it clears the job")
	check(not _is_greyed(p, target),
		"and the recipe is selectable again — which is the whole of the rule")
	check(not p._add_button.disabled or p._selected_recipe_name != target,
		"with the Add button usable again")
	check(_is_greyed(p, target) == false and _count_jobs(p, "earth", target) == 1,
		"Earth's copy is still running and unaffected by Mars removing hers")

	# ── A loaded save greys what it loaded ──
	p.set_planet("earth")
	for _i in range(2): await process_frame
	check(_is_greyed(p, target), "back on Earth it is greyed again")
	var saved: Array = p.get_jobs()
	p.load_jobs([])
	for _i in range(2): await process_frame
	check(not _is_greyed(p, target), "an empty job list greys nothing")
	p.load_jobs(saved)
	for _i in range(2): await process_frame
	check(_is_greyed(p, target),
		"and loading the jobs back greys what is in them")

	print("FAILS: %d" % fails)
	quit()
