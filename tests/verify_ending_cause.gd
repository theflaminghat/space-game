extends SceneTree

## The extinction screen says what ended the run.
##
## The three catastrophes have no ending of their own. An asteroid, a plague and a nuclear war
## each kill a great many people, and the run ends later when there is nobody left — under one
## cause, with one description. So a war, a rock and a plague all produced the same six words:
## "No humans remain on any world."
##
## _last_catastrophe records what landed and when, and _collapse_ending names it. The INTERVAL
## is reported rather than elided, because a collapse three centuries after a war is a different
## fact from one in the same year, and stating the number is the whole of the difference —
## VOICE.md: report, do not narrate.
##
## The window lives in one place. The screen and the achievement both ask _recent_catastrophe(),
## and a window that drifted between them would name a war on the extinction screen and not in
## the record — the kind of disagreement nobody notices until two runs are compared.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(20261101)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	g.year = 2400


	# ── Each one is named ──
	for spec: Array in [["nuclear", "Nuclear war", "Exchange"],
			["asteroid", "Impact", "Impactor"], ["pandemic", "Pandemic", "Outbreak"]]:
		g._last_catastrophe = {"kind": str(spec[0]), "year": 2300}
		var e: Array = g._collapse_ending()
		check(str(e[0]) == str(spec[1]),
			"%s is named on the screen: %s" % [str(spec[0]), str(e[0])])
		check(str(e[1]).find(str(spec[2])) >= 0,
			"and the mechanism is in the description: %s" % str(e[1]))
		check(str(e[1]).find("Inhabited worlds: 0") >= 0,
			"without losing what the old line said")
		check(str(e[1]).find("Interval to collapse: 100 years") >= 0,
			"and the interval is stated: %s" % str(e[1]))

	# Same year reads as such rather than as "0 years".
	g._last_catastrophe = {"kind": "nuclear", "year": 2400}
	check(g._collapse_ending()[1].find("same year") >= 0,
		"a collapse in the same year says so: %s" % str(g._collapse_ending()[1]))
	check(g._collapse_ending()[1].find("0 year") < 0, "rather than an interval of zero")
	# And one year is not "1 years".
	g._last_catastrophe = {"kind": "nuclear", "year": 2399}
	check(g._collapse_ending()[1].find("1 year.") >= 0,
		"a single year is singular: %s" % str(g._collapse_ending()[1]))


	# ── Nothing recent is blamed on nothing ──
	g._last_catastrophe = {}
	var plain: Array = g._collapse_ending()
	check(str(plain[0]) == "Population collapse",
		"a quiet collapse keeps the plain cause: %s" % str(plain[0]))
	check(str(plain[1]) == "No humans remain on any world. Inhabited worlds: 0.",
		"and the plain description: %s" % str(plain[1]))
	# A war long past did not do it.
	g._last_catastrophe = {"kind": "nuclear", "year": 2400 - g.CATASTROPHE_BLAME_WINDOW_YEARS - 1}
	check(str(g._collapse_ending()[0]) == "Population collapse",
		"a war outside the window is not blamed: %s" % str(g._collapse_ending()[0]))
	# An unrecognised kind falls back rather than producing a blank header.
	g._last_catastrophe = {"kind": "something_new", "year": 2399}
	check(str(g._collapse_ending()[0]) == "Population collapse",
		"an unknown kind falls back: %s" % str(g._collapse_ending()[0]))


	# ── The screen and the record cannot disagree ──
	# Both ask _recent_catastrophe(), so one window moves both.
	g._last_catastrophe = {"kind": "nuclear", "year": 2300}
	check(g._recent_catastrophe() == "nuclear", "the window is open at 100 years")
	g.achievements_earned = {}
	g.game_over = false
	g._grant_ending_achievement("Population collapse")
	check(g.achievements_earned.has("canticle"),
		"the record names the war when the screen does")
	g._last_catastrophe = {"kind": "nuclear", "year": 2400 - g.CATASTROPHE_BLAME_WINDOW_YEARS - 1}
	check(g._recent_catastrophe() == "", "and shut outside it")
	g.achievements_earned = {}
	g._grant_ending_achievement("Population collapse")
	check(not g.achievements_earned.has("canticle"),
		"and neither names it when the screen does not")


	# ── It survives a save ──
	# Reloading from the wrong side of a war would otherwise leave the screen unable to say
	# there had been one.
	g._last_catastrophe = {"kind": "asteroid", "year": 2390}
	g.save_game("user://saves/ending_verify.json")
	g._last_catastrophe = {}
	g.load_game("user://saves/ending_verify.json")
	check(str(g._last_catastrophe.get("kind", "")) == "asteroid",
		"the cause comes back: %s" % str(g._last_catastrophe))
	check(int(g._last_catastrophe.get("year", 0)) == 2390,
		"with its year: %s" % str(g._last_catastrophe))
	DirAccess.remove_absolute("user://saves/ending_verify.json")


	# ── The collapse itself uses it ──
	# Everything above tests _collapse_ending() in isolation, which is worth nothing if the place
	# that ends the run does not call it: reverting the trigger site to its old hard-coded cause
	# passed every assertion above. So drive a real collapse and read what the screen was given.
	g.year = 2400
	g._last_catastrophe = {"kind": "nuclear", "year": 2380}
	g.game_over = false
	# The ROSTER is emptied, not set to zero: a world left in world_pop at zero people has a
	# carrying capacity and grows back out of it, so the population bottoms out around a million
	# and climbs. Nothing to grow is the only way to reach nobody left.
	g.world_pop = {}
	g._regions = {}                      # the galaxy's statistical population counts too
	g.colonized_planets = []
	g.colonized_stars = []
	g._col_star_set = {}
	# Enough ticks for a population CYCLE to close: the headcount is delta-tracked and only
	# published whole when the slice cursor comes round, so one tick leaves the old total
	# standing and nothing collapses.
	for _i in range(20):
		g._update_population(1.0)
		if g.game_over:
			break
	check(g.game_over, "an empty galaxy ends the run")
	check(g.game_over_screen._cause_label.text == "Nuclear war",
		"and the screen is given the named cause, not the generic one: %s" % \
			g.game_over_screen._cause_label.text)
	check(g.game_over_screen._desc_label.text.find("Exchange: year 2380") >= 0,
		"with the mechanism: %s" % g.game_over_screen._desc_label.text)


	# ── Voice ──
	g._last_catastrophe = {"kind": "nuclear", "year": 2300}
	var text: String = str(g._collapse_ending()[1])
	for banned: String in ["doomed", "fragile", "inevitable", "ashes", "tragic", "devastat",
			"you ", "your ", "!"]:
		check(text.to_lower().find(banned) < 0,
			"the ending reports rather than narrates: found '%s' in %s" % [banned, text])

	print("FAILS: %d" % fails)
	quit()
