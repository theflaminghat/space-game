extends SceneTree

## The page does not promise what the formulas do not do.
##
## ── What was wrong ──
##
## Tax Rate's description has said since it was written that high rates "stifle compute", and
## compute_mult never read tax_rate. The politics page is an instrument: a player moves a slider
## from what it says the slider does, so a sentence promising an output the simulation does not
## produce is a false reading in the one place the game cannot afford one. Nothing caught it
## because nothing had ever compared the prose to the arithmetic.
##
## Social Welfare went at the same time. It was the two policies either side of it at a smaller
## size — growth and capacity in natalism's 2:1 ratio, life expectancy on healthcare's
## matter-funded terms — and no cost of its own that those two did not already charge. A
## dominated policy is worse than no policy: it spends a row of the page on a decision that has
## already been made elsewhere.
##
## ── What is asserted ──
##
## PROMISES. Each entry names a phrase that is really in some policy's description and the output
## that phrase claims, and the output is MEASURED, with its direction, between the two ends of
## the policy. A rewording that drops the phrase fails here as well, which is deliberate: the
## words and the arithmetic are one object, and touching either should bring the author to the
## other.
##
## REACH. The whole set of outputs each policy moves, pinned per policy. This is the other
## direction — an effect nobody told the player about. A policy that quietly charged compute
## would satisfy every promise in the file and still be lying by omission.
##
## Mentioning an output is not promising it. Research Budget's description opens "Compute directed
## to structured science": compute is the input being spent, not an output being moved, and the
## reach table pins that it moves science and matter and nothing else. That distinction is why the
## promises are a curated list of phrases rather than a keyword scan.
##
## And then the two degenerate cases: no policy may reach nothing (a control wired to nothing at
## all), and no output may be reachable by nothing (a formula the page cannot influence).

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

## Every output a policy is allowed to move, by the short name the tables below use.
var OUT: Dictionary = {
	"autonomy": PoliticsData.ai_autonomy,
	"capacity": PoliticsData.pop_capacity_mult,
	"co2":      PoliticsData.co2_mult,
	"compute":  PoliticsData.compute_mult,
	"energy":   PoliticsData.energy_mult,
	"growth":   PoliticsData.pop_growth_mult,
	"life":     PoliticsData.life_expectancy_bonus,
	"matter":   PoliticsData.minerals_mult,
	"risk":     PoliticsData.existential_risk,
	"science":  PoliticsData.science_mult,
}

## policy id → every output it moves, sorted.  Adding a term to a formula means adding it here.
const REACH: Dictionary = {
	"tax_rate":             ["compute", "growth", "matter"],
	"industrial_intensity": ["capacity", "co2", "energy", "life", "matter"],
	"automation":           ["autonomy", "co2", "compute", "energy", "growth", "matter", "risk"],
	"research_budget":      ["matter", "science"],
	"ai_investment":        ["autonomy", "compute", "risk"],
	"ai_alignment":         ["compute", "risk"],
	"open_science":         ["autonomy", "compute", "risk", "science"],
	"healthcare":           ["life", "matter"],
	"natalism":             ["capacity", "compute", "growth"],
	"civil_liberties":      ["compute", "matter", "science"],
	"military_spending":    ["matter", "science"],
	"arms_control":         ["matter", "science"],
}

## [policy id, a phrase from its description, the output it claims, +1 if raising the policy
## raises that output].  For a toggle, "raising" is turning it on.
const PROMISES: Array = [
	["tax_rate",             "grow matter output",                            "matter",   1],
	["tax_rate",             "slow population growth",                        "growth",  -1],
	["tax_rate",             "stifle compute",                                "compute", -1],

	["industrial_intensity", "Raises matter and energy output",               "matter",   1],
	["industrial_intensity", "Raises matter and energy output",               "energy",   1],
	["industrial_intensity", "vents CO₂",                                     "co2",      1],
	["industrial_intensity", "shortens lives through pollution",              "life",    -1],

	["automation",           "+20% matter",                                   "matter",   1],
	["automation",           "+15% compute",                                  "compute",  1],
	["automation",           "−10% energy",                                   "energy",  -1],
	["automation",           "unemployment slows population growth",          "growth",  -1],
	["automation",           "feeds AI autonomy",                             "autonomy", 1],

	["research_budget",      "±40% science output",                           "science",  1],
	["research_budget",      "paid for by diverted matter",                   "matter",  -1],

	["ai_investment",        "accelerates compute",                           "compute",  1],
	["ai_investment",        "every point raises how capable the machines are", "autonomy", 1],

	["ai_alignment",         "it runs on the same compute as everything else", "compute", -1],
	["ai_alignment",         "Closes the gap",                                "risk",    -1],

	["open_science",         "+15% science",                                  "science",  1],
	["open_science",         "+10% compute",                                  "compute",  1],
	["open_science",         "including to the machines",                     "autonomy", 1],

	["healthcare",           "+25 years of life expectancy",                  "life",     1],
	["healthcare",           "paid for with matter",                          "matter",  -1],

	["natalism",             "speeds population growth",                      "growth",   1],
	["natalism",             "raises capacity",                               "capacity", 1],
	["natalism",             "lowers per-capita compute",                     "compute", -1],

	["civil_liberties",      "+10% science and +10% compute",                 "science",  1],
	["civil_liberties",      "+10% science and +10% compute",                 "compute",  1],
	["civil_liberties",      "−8% central economic efficiency",               "matter",  -1],

	["military_spending",    "up to +30% science",                            "science",  1],
	["military_spending",    "at a matter cost",                              "matter",  -1],

	["arms_control",         "paid for in inspection",                        "matter",  -1],
	["arms_control",         "the research the arms race was producing",       "science", -1],
]

## The policy as it is at one end: a slider's limit, or a toggle's position.
func _end(p: Dictionary, top: bool) -> Dictionary:
	var s: Dictionary = PoliticsData.default_state()
	if str(p["type"]) == "toggle":
		s[p["id"]] = top
	else:
		s[p["id"]] = float(p["max"] if top else p["min"])
	return s

func _policy(id: String) -> Dictionary:
	for p: Dictionary in PoliticsData.POLICIES:
		if str(p["id"]) == id:
			return p
	return {}


func _run() -> void:
	# ── Every policy is on the page, exactly once, under a heading that exists ──
	# The page walks CATEGORIES and filters POLICIES by category, so a policy filed under a
	# category that is not in that list is invisible while still sitting in every saved state.
	var seen: Dictionary = {}
	for p: Dictionary in PoliticsData.POLICIES:
		var id: String = str(p["id"])
		check(not seen.has(id), "%s is listed once" % id)
		seen[id] = true
		check(PoliticsData.CATEGORIES.has(str(p["category"])),
			"%s is filed under a heading the page draws: %s" % [id, str(p["category"])])
	for cat: String in PoliticsData.CATEGORIES:
		var n: int = 0
		for p: Dictionary in PoliticsData.POLICIES:
			if str(p["category"]) == cat:
				n += 1
		check(n >= 2, "%s has policies to compare: %d" % [cat, n])
	check(PoliticsData.default_state().size() == PoliticsData.POLICIES.size(),
		"and a fresh state is exactly the policy list")


	# ── Social Welfare is gone, and a save that carries it is still read ──
	check(_policy("welfare").is_empty(), "there is no welfare policy")
	check(not PoliticsData.default_state().has("welfare"), "and no fresh state carries it")
	var plain: Dictionary = PoliticsData.default_state()
	var stray: Dictionary = PoliticsData.default_state()
	stray["welfare"] = 50.0
	for key: String in OUT:
		var f: Callable = OUT[key]
		check(is_equal_approx(float(f.call(plain)), float(f.call(stray))),
			"a retired welfare key moves nothing: %s" % key)


	# ── The promises ──
	for row: Array in PROMISES:
		var id: String = str(row[0])
		var phrase: String = str(row[1])
		var out: String = str(row[2])
		var sign_: int = int(row[3])
		var p: Dictionary = _policy(id)
		check(not p.is_empty(), "%s is a policy" % id)
		if p.is_empty():
			continue
		check(str(p["desc"]).find(phrase) >= 0,
			"%s still says \"%s\"" % [id, phrase])
		var f: Callable = OUT[out]
		var lo: float = float(f.call(_end(p, false)))
		var hi: float = float(f.call(_end(p, true)))
		check((hi - lo) * float(sign_) > 0.0,
			"%s: \"%s\" moves %s the way it says (%.3f → %.3f)" % [id, phrase, out, lo, hi])


	# ── The reach: nothing happens that the page did not say would happen ──
	var measured: Dictionary = {}
	for p: Dictionary in PoliticsData.POLICIES:
		var id: String = str(p["id"])
		var moved: Array = []
		for key: String in OUT:
			var f: Callable = OUT[key]
			if not is_equal_approx(float(f.call(_end(p, false))), float(f.call(_end(p, true)))):
				moved.append(key)
		moved.sort()
		measured[id] = moved
		check(REACH.has(id), "%s has a pinned reach" % id)
		if not REACH.has(id):
			continue
		var want: Array = (REACH[id] as Array).duplicate()
		want.sort()
		check(moved == want,
			"%s moves what it is pinned to move: %s vs %s" % [id, str(moved), str(want)])
		check(not moved.is_empty(), "%s does something" % id)

	# And from the other side: a formula no policy can reach is a formula the page cannot steer.
	# Read off the MEASURED sets, not the pinned table — a table checking itself asserts nothing.
	for key: String in OUT:
		var reached: bool = false
		for id: String in measured:
			if (measured[id] as Array).has(key):
				reached = true
		check(reached, "%s is reachable from the page" % key)


	# ── The promises that are kept outside this file ──
	# Military Spending's description promises geopolitical tension and a risk of nuclear war, and
	# Arms Control's promises safeguards on the fuel cycle and a standoff that unwinds. Both are
	# Game's, not PoliticsData's. Asserted at the source, because the alternative is a whole scene
	# to establish that a word is read at all.
	#
	# The means term is one function with two callers, and the pair is the point: a forecast that
	# computes the odds from different arithmetic than the simulation is an instrument that lies.
	var src: String = FileAccess.get_file_as_string("res://Game.gd")
	var reads: Dictionary = {
		"_geopolitical_tension": ["military_spending"],
		"_nuclear_means":        ["military_spending", "arms_safeguards"],
		"_check_nuclear_war":    ["_nuclear_means()", "arms_safeguards"],
		"nuclear_probability":   ["_nuclear_means()"],
	}
	for fn: String in reads:
		var start: int = src.find("func %s(" % fn)
		check(start >= 0, "%s is there to look at" % fn)
		if start < 0:
			continue
		var stop: int = src.find("\nfunc ", start + 8)
		var body: String = src.substr(start, (stop if stop > start else src.length()) - start)
		for want: String in (reads[fn] as Array):
			check(body.find(want) >= 0, "%s reads %s" % [fn, want])

	print("FAILS: %d" % fails)
	quit()
