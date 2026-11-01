extends SceneTree

## What a run is remembered for.
##
## Two halves that fail in different ways. The DATA has to be well-formed — an id typo makes an
## achievement that can never be granted and never appears, and nothing else would notice. The
## GRANTS have to fire from the real events, not from a test poking the record directly, which
## is the only part that proves the feature exists at all.
##
## And the hidden ones have to stay hidden. The game springs an asteroid, a pandemic and a war
## on the player; listing those in advance turns each from an event into a countdown, and the
## count at the top of the page would quietly say how many ways there are to lose.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(20261031)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var AD = load("res://achievements.gd")
	# Autoload IDENTIFIERS do not resolve in a SceneTree script; the live nodes do.
	var rt: Node = root.get_node("ResearchTree")
	var ss: Node = root.get_node("SolarSystem")


	# ── The table is well-formed ──
	var seen: Dictionary = {}
	for a: Dictionary in AD.ACHIEVEMENTS:
		var id: String = str(a.get("id", ""))
		check(id != "", "every achievement has an id: %s" % str(a))
		check(not seen.has(id), "and it is unique: %s" % id)
		seen[id] = true
		check(str(a.get("name", "")) != "", "%s has a name" % id)
		check(str(a.get("desc", "")) != "", "%s says what earns it" % id)
		var grp: String = str(a.get("group", ""))
		check(AD.GROUP_ORDER.has(grp), "%s is in a known group: %s" % [id, grp])
		check(AD.GROUP_LABELS.has(grp), "and that group has a label: %s" % grp)
	for grp: String in AD.GROUP_ORDER:
		check(not AD.in_group(grp).is_empty(), "no empty group: %s" % grp)
	check(AD.exists("we_are_bob"), "the one that was asked for is there")
	check(AD.name_of("we_are_bob") == "We Are Bob",
		"by its name: %s" % AD.name_of("we_are_bob"))


	# ── Granting ──
	g.achievements_earned = {}
	g.year = 2001
	check(g.grant_achievement("small_step"), "a first grant takes")
	check(not g.grant_achievement("small_step"), "a second does not")
	check(int(g.achievements_earned.get("small_step", -1)) == 2001,
		"and it records the YEAR, not a flag: %s" % str(g.achievements_earned.get("small_step")))
	check(not g.grant_achievement("no_such_achievement_id"),
		"an unknown id is refused rather than recorded")
	check(not g.achievements_earned.has("no_such_achievement_id"), "and leaves nothing behind")
	# It is announced, which is the only way the player finds out.
	var told := false
	for n in g._pending_event_notifications:
		if str((n as Dictionary).get("id", "")) == "ach_small_step":
			told = true
	check(told, "earning one is announced")


	# ── The real triggers, driven the way the game drives them ──
	g.achievements_earned = {}

	# We Are Bob: the first von Neumann probe.
	var star: String = ""
	for s in load("res://StarMapPanel.gd").all_stars():
		star = str((s as Dictionary)["name"])
		break
	check(star != "", "a star to send one to")
	rt.resources["energy"] = 1.0e40
	# The probe path is gated on research; open the gate rather than skipping the hook.
	rt.force_unlock("relativistic_navigation")
	rt.force_unlock("self_replicating_industry")
	# The real call site, with its real signature: _vn_launch(target, from_pos, ...). Going
	# through it is the whole point — poking achievements_earned would prove nothing about
	# whether the hook is wired.
	var launched: bool = g._vn_launch(star, ss.sol_position())
	check(launched, "a probe can be sent (research gate open?): %s" % star)
	check(g.achievements_earned.has("we_are_bob"),
		"the first von Neumann probe earns We Are Bob")

	# Foothold: a star becomes ours.
	g.achievements_earned.erase("foothold")
	g._colonize_star("Verify Star A")
	check(g.achievements_earned.has("foothold"), "settling a star earns Foothold")

	# The Moon Is a Harsh Mistress — on the NEWS, not on the event. The colony stops being ours
	# immediately; the player does not find out until the light arrives, and an achievement
	# fired at the moment of secession would be the announcement the lag exists to withhold.
	g.achievements_earned.erase("harsh_mistress")
	g.achievements_earned.erase("no_reply")
	g.colony_loyalty["Verify Star A"] = 1.0
	g._secede_colony("Verify Star A")
	check(not g.achievements_earned.has("harsh_mistress"),
		"seceding alone tells the player nothing")
	# Wait out the crossing and tick the post.
	var news_dist: float = 900.0
	var rec0: Dictionary = g._colony_news.get("Verify Star A", {})
	rec0["tx"] = float(g.year)
	rec0["tx_gone"] = true
	g._colony_news["Verify Star A"] = rec0
	g.year += int(news_dist) + 1
	g._tick_colony_news("Verify Star A", news_dist, 0.0, true)
	check(g.achievements_earned.has("harsh_mistress"),
		"hearing about it earns The Moon Is a Harsh Mistress")
	check(g.achievements_earned.has("no_reply"),
		"and news that stale is also No Reply")
	g.year = 2001


	# ── The sweep: thresholds, not moments ──
	g.achievements_earned = {}
	ss.star_drift_dist_ly = 2.0
	g._check_achievements()
	check(g.achievements_earned.has("wandering_sun"),
		"a Sun that has moved a light-year earns The Wandering Sun")
	check(not g.achievements_earned.has("caravan"), "but not yet Caravan")
	ss.star_drift_dist_ly = 150.0
	g._check_achievements()
	check(g.achievements_earned.has("caravan"), "a hundred light-years does")
	ss.star_drift_dist_ly = 0.0

	g.achievements_earned = {}
	g.year = int(g.ACH_TAU_ZERO_YEAR) + 1
	g._check_achievements()
	check(g.achievements_earned.has("tau_zero"), "surviving to the end of star formation counts")
	check(not g.achievements_earned.has("last_question"), "heat death is further off than that")
	g.year = 2001


	# ── Endings ──
	# Every ending goes through trigger_game_over, and the three catastrophes do not have endings
	# of their own — they kill people and the run ends as a collapse — so the cause has to be
	# remembered or the ending cannot say what did it.
	g.achievements_earned = {}
	g.game_over = false
	g._last_catastrophe = {"kind": "nuclear", "year": g.year - 10}
	g._grant_ending_achievement("Population collapse")
	check(g.achievements_earned.has("canticle"),
		"a collapse just after a war is A Canticle for Leibowitz")
	check(g.achievements_earned.has("last_man"), "and is also The Last Man")
	# A war a hundred thousand years ago did not do it.
	g.achievements_earned = {}
	g._last_catastrophe = {"kind": "nuclear", "year": g.year - 100000}
	g._grant_ending_achievement("Population collapse")
	check(not g.achievements_earned.has("canticle"),
		"but an ancient one is not blamed: %s" % str(g.achievements_earned.keys()))
	check(g.achievements_earned.has("last_man"), "the collapse still counts")
	# Nothing ever reached orbit.
	check(g.achievements_earned.has("dont_go_extinct"),
		"a run that never launched earns the title the wrong way")
	g.achievements_earned = {}
	g.grant_achievement("small_step")
	g._grant_ending_achievement("Population collapse")
	check(not g.achievements_earned.has("dont_go_extinct"),
		"a run that did launch does not")
	g._last_catastrophe = {}


	# ── The record survives a save ──
	g.achievements_earned = {"we_are_bob": 1987, "foothold": 2450}
	g.save_game("user://saves/ach_verify.json")
	g.achievements_earned = {}
	g.load_game("user://saves/ach_verify.json")
	check(int(g.achievements_earned.get("we_are_bob", -1)) == 1987,
		"the record comes back with its years: %s" % str(g.achievements_earned))
	check(int(g.achievements_earned.get("foothold", -1)) == 2450, "both of them")
	DirAccess.remove_absolute("user://saves/ach_verify.json")


	# ── The page ──
	var page = g.sidebar.achievements_page
	check(page != null, "there is a page")
	check(g.sidebar.get_node_or_null("sidebar/achievements") != null, "and a button for it")
	g.achievements_earned = {"we_are_bob": 1990}
	page.show()
	g._push_achievements()
	for _i in range(3): await process_frame
	# Hidden rows are not counted until earned, or the total says how many ways there are to lose.
	var hidden_n: int = 0
	for a: Dictionary in AD.ACHIEVEMENTS:
		if bool(a.get("hidden", false)):
			hidden_n += 1
	check(hidden_n > 0, "there are hidden ones to hide: %d" % hidden_n)
	check(page._summary.text == "1 of %d" % (AD.ACHIEVEMENTS.size() - hidden_n),
		"the count leaves them out: %s" % page._summary.text)
	# And none of their names is on screen.
	var shown: String = _all_text(page._list)
	for a: Dictionary in AD.ACHIEVEMENTS:
		if bool(a.get("hidden", false)):
			check(shown.find(str(a["name"])) < 0,
				"an unearned hidden one is not named: %s" % str(a["name"]))
	check(shown.find("We Are Bob") >= 0, "an earned one is named")
	check(shown.find("Foothold") >= 0, "an unearned VISIBLE one is named too — the list is a guide")
	# The nod is only shown once earned, or it gives the condition away.
	check(shown.find("Dennis E. Taylor") >= 0, "an earned one carries its reference")

	# Earning a hidden one reveals it, and the total moves with it.
	g.grant_achievement("last_man")
	for _i in range(3): await process_frame
	check(page._summary.text == "2 of %d" % (AD.ACHIEVEMENTS.size() - hidden_n + 1),
		"earning a hidden one adds it to the total: %s" % page._summary.text)
	check(_all_text(page._list).find("The Last Man") >= 0, "and names it")

	print("FAILS: %d" % fails)
	quit()


## Every piece of text under a node, for asking what the page actually shows.
func _all_text(n: Node) -> String:
	var out: String = ""
	if n is Label:
		out += (n as Label).text + "\n"
	for c in n.get_children():
		out += _all_text(c)
	return out
