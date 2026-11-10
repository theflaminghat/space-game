extends SceneTree

## Alignment Research, and the fourth way a run ends.
##
## ── What was wrong ──
##
## ai_investment was the strongest compute lever in the game and a one-way ratchet. Autonomy was
## a pure function of the policy sliders, so it had no memory: set a slider back and the risk
## vanished the same year. existential_risk was `autonomy x 0.6`, could not be driven to zero,
## and fed nothing but a happiness penalty and the pandemic odds. The three catastrophes are an
## asteroid, a plague and a war — so the number the game is named after could not end a run, and
## there was nothing on the other end of the decision.
##
## ── What it is now ──
##
## TWO STOCKS. _ai_capability closes on what the policy asks for; _ai_understood accumulates at
## whatever alignment is being spent. Both RATCHET: capability that exists does not stop
## existing, and understanding once had is kept. The exposure is the gap between them, and the
## per-check probability is that gap squared — flat where a civilisation is keeping up, steep
## where it is not, and EXACTLY zero when understanding is level, which is what makes this a
## threat the player can finish rather than a slot machine running across deep time.
##
## And it is the one ending holdings do not blunt. A war is fought between Earth powers, an
## impactor hits one world, a plague crosses on traffic — each is survived by being somewhere
## else. A system that improves itself has no blast radius to be outside of, so a civilisation
## across a hundred stars ends exactly as one on Earth does. Asserted, because the temptation to
## make it work like the other three is the temptation to make every risk have one answer.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

## Policy state with the named overrides on top of the defaults.
func _pol(over: Dictionary) -> Dictionary:
	var s: Dictionary = PoliticsData.default_state()
	for k: String in over:
		s[k] = over[k]
	return s


func _run() -> void:
	seed(20261110)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene


	# ── The policy is there, and it is a Science policy ──
	var found: Dictionary = {}
	for p: Dictionary in PoliticsData.POLICIES:
		if str(p["id"]) == "ai_alignment":
			found = p
	check(not found.is_empty(), "there is an ai_alignment policy")
	check(str(found.get("category", "")) == "Science",
		"and it sits with the other AI policy: %s" % str(found.get("category", "")))
	check(PoliticsData.default_state().has("ai_alignment"),
		"and a fresh state carries it")
	check(float(found.get("default", -1.0)) == 0.0,
		"starting at nothing, which is where 1945 is: %s" % str(found.get("default")))


	# ── It is paid for in thinking ──
	# The whole point of the policy: the only way to buy understanding is with compute that was
	# going somewhere else, so maximum investment AND maximum safety is not maximum compute.
	var none: float = PoliticsData.compute_mult(_pol({"ai_alignment": 0.0}))
	var full: float = PoliticsData.compute_mult(_pol({"ai_alignment": 100.0}))
	check(full < none - 0.01, "alignment costs compute: %f -> %f" % [none, full])
	var hot: float = PoliticsData.compute_mult(_pol({"ai_investment": 100.0, "ai_alignment": 0.0}))
	var safe: float = PoliticsData.compute_mult(_pol({"ai_investment": 100.0, "ai_alignment": 100.0}))
	check(safe < hot and safe > 1.0,
		"a civilisation doing both still gains, but less: %f vs %f" % [safe, hot])


	# ── Alignment does not make the machines less capable ──
	# They are separate quantities. Subtracting safety work from capability would have made the
	# slider a way to un-build what was built, which is the thing this model exists to deny.
	check(is_equal_approx(PoliticsData.ai_autonomy(_pol({"ai_investment": 100.0, "ai_alignment": 0.0})),
			PoliticsData.ai_autonomy(_pol({"ai_investment": 100.0, "ai_alignment": 100.0}))),
		"alignment leaves capability alone: %f vs %f" % [
			PoliticsData.ai_autonomy(_pol({"ai_investment": 100.0, "ai_alignment": 0.0})),
			PoliticsData.ai_autonomy(_pol({"ai_investment": 100.0, "ai_alignment": 100.0}))])


	# ── The risk is the GAP, and it reaches a true zero ──
	var exposed: float = PoliticsData.existential_risk(_pol({"ai_investment": 100.0, "ai_alignment": 0.0}))
	var covered: float = PoliticsData.existential_risk(_pol({"ai_investment": 100.0, "ai_alignment": 100.0}))
	check(exposed > 0.5, "racing with no safety work is exposed: %f" % exposed)
	check(covered <= 0.0, "and keeping up is a true zero, not a small number: %f" % covered)
	check(PoliticsData.existential_risk(_pol({"ai_investment": 0.0, "automation": false,
			"open_science": false, "ai_alignment": 0.0})) <= 0.11,
		"a civilisation building nothing has only its baseline")


	# ── Both stocks ratchet ──
	g.year = 2000
	g._ai_capability = 0.0
	g._ai_understood = 0.0
	g.policies = _pol({"ai_investment": 100.0, "ai_alignment": 0.0})
	var climb: Array = []
	for i in range(6):
		g._next_ai_year = g.year
		g._ai_cooldown_ms = 0
		g.year += 50
		g._check_ai_runaway()
		climb.append(g._ai_capability)
	check(climb[0] > 0.0 and climb[5] > climb[0], "capability climbs: %s" % str(climb))
	check(climb[5] > 0.75, "and gets most of the way at full investment: %f" % climb[5])
	check(g._ai_understood <= 0.0, "with no understanding bought: %f" % g._ai_understood)

	# Cutting the budget stops the climb. It does not undo it.
	var peak: float = g._ai_capability
	g.policies = _pol({"ai_investment": 0.0, "automation": false, "open_science": false,
		"ai_alignment": 0.0})
	for i in range(6):
		g._next_ai_year = g.year
		g._ai_cooldown_ms = 0
		g.year += 50
		g._check_ai_runaway()
	check(g._ai_capability >= peak - 1.0e-6,
		"capability does not fall when the budget is cut: %f -> %f" % [peak, g._ai_capability])

	# Understanding accumulates with the slider, and is likewise kept.
	g.policies = _pol({"ai_investment": 0.0, "ai_alignment": 100.0})
	for i in range(8):
		g._next_ai_year = g.year
		g._ai_cooldown_ms = 0
		g.year += 50
		g._check_ai_runaway()
	var understood: float = g._ai_understood
	check(understood > 0.3, "understanding accumulates: %f" % understood)
	g.policies = _pol({"ai_alignment": 0.0})
	for i in range(4):
		g._next_ai_year = g.year
		g._ai_cooldown_ms = 0
		g.year += 50
		g._check_ai_runaway()
	check(g._ai_understood >= understood - 1.0e-6,
		"and is not forgotten when the budget is cut: %f -> %f" % [understood, g._ai_understood])


	# ── Understanding is the slower of the two ──
	# Which is what makes racing ahead the default failure rather than an unlucky one: the same
	# number of checks buys far more capability than it buys understanding.
	g._ai_capability = 0.0
	g._ai_understood = 0.0
	g.policies = _pol({"ai_investment": 100.0, "ai_alignment": 100.0})
	for i in range(4):
		g._next_ai_year = g.year
		g._ai_cooldown_ms = 0
		g.year += 50
		g._check_ai_runaway()
	check(g._ai_capability > g._ai_understood,
		"capability outruns understanding at equal budgets: %f vs %f" % [
			g._ai_capability, g._ai_understood])


	# ── The probability ──
	g._ai_capability = 0.9
	g._ai_understood = 0.9
	check(g.ai_exposure() <= 0.0, "level stocks are no exposure: %f" % g.ai_exposure())
	check(g.ai_runaway_probability() == 0.0,
		"and exactly no risk: %f" % g.ai_runaway_probability())
	# Under the floor is exactly none, not a small number. Measured a hair inside it rather than
	# on it: the floor is a float subtraction and the boundary itself lands either side by error.
	g._ai_understood = 0.9 - g.AI_EXPOSURE_FLOOR + 0.01
	check(g.ai_exposure() < g.AI_EXPOSURE_FLOOR, "a gap under the floor: %f" % g.ai_exposure())
	check(g.ai_runaway_probability() == 0.0,
		"is still none: %f" % g.ai_runaway_probability())
	g._ai_understood = 0.0
	var wide: float = g.ai_runaway_probability()
	check(wide > 0.0, "a wide gap is a real chance: %f" % wide)
	# Squared: flat where a civilisation is roughly keeping up, steep where it is not.
	# CONVEX, not straight: three evenly spaced gaps, and the odds have to bend upward across
	# them. Asserted as a second difference rather than as a ratio between two points, because
	# a ratio only discriminates for one particular floor and base — move either and a linear
	# curve passes it. The claim is the shape, so the shape is what is measured.
	var bend: Array = []
	for e: float in [0.5, 0.7, 0.9]:
		g._ai_capability = e
		g._ai_understood = 0.0
		bend.append(g.ai_runaway_probability())
	var second: float = float(bend[2]) - 2.0 * float(bend[1]) + float(bend[0])
	var span: float = float(bend[2]) - float(bend[0])
	check(span > 0.0 and second > span * 0.1,
		"the curve bends upward rather than running straight: %s" % str(bend))
	g._ai_capability = 0.9
	g._ai_understood = 0.0

	# Asking must not answer. The lesson nuclear_probability already carries: a forecast that
	# ratchets the thing it forecasts is not a forecast.
	g._ai_understood = 0.0
	var cap_before: float = g._ai_capability
	var und_before: float = g._ai_understood
	for i in range(5):
		g.ai_runaway_probability()
		g.ai_exposure()
	check(is_equal_approx(g._ai_capability, cap_before) and is_equal_approx(g._ai_understood, und_before),
		"asking for the odds does not move either stock: %f/%f" % [
			g._ai_capability, g._ai_understood])


	# ── Nothing is rolled while understanding is level ──
	g.year = 3000
	g._ai_capability = 0.9
	g._ai_understood = 0.9
	g.policies = _pol({"ai_investment": 0.0, "automation": false, "open_science": false,
		"ai_alignment": 0.0})
	g.game_over = false
	for i in range(40):
		g._next_ai_year = g.year
		g._ai_cooldown_ms = 0
		g.year += 50
		g._check_ai_runaway()
		if g.game_over:
			break
	check(not g.game_over,
		"forty checks at zero exposure end nothing (year %d)" % g.year)


	# ── It fires, and it ends the run ──
	# A year whose roll lands under the odds, found rather than forced, so the path under test is
	# the real one: the schedule, the ratchets and _roll, not a hand call to the trigger.
	g.game_over = false
	g._ai_capability = 0.95
	g._ai_understood = 0.0
	g.policies = _pol({"ai_investment": 100.0, "ai_alignment": 0.0})
	var p_now: float = g.ai_runaway_probability()
	check(p_now > 0.0, "the odds are open: %f" % p_now)
	var hit_year: int = -1
	for y in range(3000, 40000):
		if g._roll("ai_runaway", y) < p_now:
			hit_year = y
			break
	check(hit_year > 0, "some year in the next 37 000 rolls under %f" % p_now)
	# Hold it on a wide gap: the stocks turn before the roll, so a policy that closes the gap
	# would change the odds the roll is compared against.
	g.year = hit_year
	g._next_ai_year = hit_year
	g._ai_cooldown_ms = 0
	# A civilisation that is not on one world, and is no longer on Earth at all — so the figure
	# on the screen has to come off the roster rather than from "Earth plus the colonies", which
	# would report one world more than there is.
	g.world_pop = {"mars": 4.0e8, "europa": 1.2e8}
	g.colonized_planets = ["mars", "europa"]
	g.colonized_stars = ["Alpha Centauri A", "Tau Ceti", "Epsilon Eridani"]
	g._col_star_set = {"Alpha Centauri A": true, "Tau Ceti": true, "Epsilon Eridani": true}
	g.achievements_earned = {}
	g._check_ai_runaway()
	check(g.game_over, "the roll lands and the run ends")
	check(g.game_over_screen._cause_label.text == "Loss of control",
		"named on the screen: %s" % g.game_over_screen._cause_label.text)
	var desc: String = g.game_over_screen._desc_label.text
	check(desc.find("Capability:") >= 0 and desc.find("Understood:") >= 0,
		"with both figures: %s" % desc)
	check(desc.find("Settled worlds at the threshold: 2") >= 0,
		"counting the worlds that were actually inhabited: %s" % desc)
	check(desc.find("Settled stars: 3") >= 0,
		"and the stars held at the threshold: %s" % desc)
	check(desc.find("Inhabited worlds: 0") >= 0,
		"without losing what every other ending's line says: %s" % desc)
	check(str(g._last_catastrophe.get("kind", "")) == "ai",
		"the cause is recorded: %s" % str(g._last_catastrophe))
	check(g.achievements_earned.has("no_mouth"),
		"and the record names it: %s" % str(g.achievements_earned.keys()))
	# Distance is no defence. Four settled stars and two worlds did not blunt it, which is the
	# whole reason this threat exists beside the other three.
	check(g._total_population() <= 0.0,
		"nobody is left anywhere: %f" % g._total_population())
	check(g.colonized_stars.is_empty(), "including the stars")


	# ── Voice ──
	for banned: String in ["doomed", "fragile", "inevitable", "ashes", "tragic", "devastat",
			"rogue", "you ", "your ", "!"]:
		check(desc.to_lower().find(banned) < 0,
			"the ending reports rather than narrates: found '%s' in %s" % [banned, desc])


	# ── Both stocks and the schedule survive a save ──
	# A run reloaded from the wrong side of a century of AI investment would otherwise come back
	# with nothing built and nothing understood, which is a free reset of the only threat here
	# that accumulates.
	g.game_over = false
	g._ai_capability = 0.73
	g._ai_understood = 0.41
	g._next_ai_year = 4242
	g.save_game("user://saves/ai_verify.json")
	g._ai_capability = 0.0
	g._ai_understood = 0.0
	g._next_ai_year = 0
	g.load_game("user://saves/ai_verify.json")
	check(absf(g._ai_capability - 0.73) < 1.0e-5,
		"capability comes back: %f" % g._ai_capability)
	check(absf(g._ai_understood - 0.41) < 1.0e-5,
		"understanding comes back: %f" % g._ai_understood)
	check(g._next_ai_year == 4242, "with its schedule: %d" % g._next_ai_year)
	DirAccess.remove_absolute("user://saves/ai_verify.json")


	# ── Reachable from the clock a run actually spends its deep time on ──
	# Invariant 1 in ARCHITECTURE: anything that lives only in advance_day() never runs in fast
	# mode, which starts at 1000x. Three bugs have had this exact shape.
	# Read as BODIES, not as offsets into the file: searching forward from the fast-mode function
	# finds the check's own definition further down and passes whether or not it is called.
	var src: String = FileAccess.get_file_as_string("res://Game.gd")
	for fn: String in ["advance_day", "_on_years_advanced_fast"]:
		var start: int = src.find("\nfunc %s(" % fn)
		check(start > 0, "%s is there to look at" % fn)
		if start < 0:
			continue
		var stop: int = src.find("\nfunc ", start + 8)
		var body: String = src.substr(start, (stop if stop > start else src.length()) - start)
		check(body.find("_check_ai_runaway()") >= 0,
			"%s calls the check" % fn)
		check(body.find("_check_nuclear_war()") >= 0,
			"%s calls the one it is modelled on too" % fn)

	print("FAILS: %d" % fails)
	quit()
