extends SceneTree

## What makes an engineered plague likely.
##
## The old model was base x (1 + 0.4 x biotech_nodes) x (1 + 2 x ai) x (2 / (1 + worlds))
## x (BASE_LE / le), and four things were wrong with it:
##
##   - `2 / (1 + worlds)` divided the ODDS by the colony count while _trigger_pandemic was
##     already dividing the TOLL by it. At five worlds that is 0.33 x 0.2 — expected losses fell
##     about fifteenfold for settling the system. The direction was wrong anyway: more settled
##     worlds trading and travelling is more coupling, not less.
##   - Population never appeared. Two billion and twenty billion gave identical odds.
##   - Life expectancy stood in for public health, but `le` here is driven by the longevity
##     splice — so engineering people to live longer made them less likely to catch a plague.
##   - A count of unlocked research nodes never falls, so a civilisation that learned
##     bioengineering once was as exposed as one editing genomes this year.
##
## Every term now is something the game already simulates, and three are things the player is
## doing rather than things they once learned. Measured over the solar system, because that is
## where a plague spreads: _trigger_pandemic reaches Earth and the in-system colonies and leaves
## the interstellar ones alone.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(20261103)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(50): await process_frame
	var g: Node = current_scene
	var rt: Node = root.get_node("ResearchTree")
	var SD = load("res://stock_data.gd")


	# ── The capability gate ──
	check(g.pandemic_probability() == 0.0,
		"no engineered plague before the engineering: %f" % g.pandemic_probability())
	for n in g.PANDEMIC_BIOTECH:
		rt.force_unlock(str(n))
	var base: float = g.pandemic_probability()
	check(base > 0.0, "and a real risk once it exists: %f" % base)
	# Not a wild rate: this fires on a schedule of 800-2500 years, so the per-check figure is
	# the chance that a scheduled opportunity becomes an outbreak.
	check(base < 0.25, "but not a coin flip: %f" % base)


	# ── Genetic uniformity ──
	# The strongest term, and the one the rest of the game builds toward: a population spliced
	# into one optimised genome is a monoculture, and a monoculture is what a pathogen is for.
	g._world_stock["earth"] = SD.found("broad", [], SD.baseline())
	var broad: float = g.pandemic_probability()
	g._world_stock["earth"] = SD.found("minimal", [], SD.baseline())
	var minimal: float = g.pandemic_probability()
	check(minimal > broad * 1.5,
		"a narrow founding is markedly more exposed: %f vs %f" % [minimal, broad])
	g._world_stock["earth"] = SD.found("standard", [], SD.baseline())
	var standard: float = g.pandemic_probability()
	check(standard > broad and standard < minimal,
		"and standard sits between: %f, %f, %f" % [broad, standard, minimal])


	# ── Active editing, not a research count ──
	g._world_stock["earth"] = SD.found("broad", [], SD.baseline())
	var quiet: float = g.pandemic_probability()
	var st: Dictionary = g.stock_of("earth")
	st["splice"] = "longevity"
	g._world_stock["earth"] = st
	var editing: float = g.pandemic_probability()
	check(editing > quiet,
		"a splice IN PROGRESS raises it: %f vs %f" % [editing, quiet])
	st["splice"] = ""
	g._world_stock["earth"] = st
	check(absf(g.pandemic_probability() - quiet) < 1.0e-9,
		"and finishing it puts the risk back down")


	# ── Hosts, and how crowded they are ──
	var pop0: float = float(g.world_pop.get("earth", 0.0))
	var sparse: float = g.pandemic_probability()
	g.world_pop["earth"] = pop0 * 4.0
	check(g.pandemic_probability() > sparse,
		"more people on the same ground is more risk: %f vs %f" % [
			g.pandemic_probability(), sparse])
	g.world_pop["earth"] = pop0


	# ── Traffic between worlds ──
	var still: float = g.pandemic_probability()
	for _i in range(40):
		g.active_launches.append({"status": "active"})
	check(g.pandemic_probability() > still,
		"flights couple the worlds together: %f vs %f" % [g.pandemic_probability(), still])
	g.active_launches = []


	# ── Colonies no longer divide the odds ──
	# They divide the TOLL, in _trigger_pandemic, and doing it in both places made settling the
	# system cut expected losses about fifteenfold.
	var alone: float = g.pandemic_probability()
	g.colonized_planets = ["mars", "venus", "luna"]
	for w in g.colonized_planets:
		g.world_pop[str(w)] = 1.0e9
		g._world_stock[str(w)] = SD.found("broad", [], SD.baseline())
	var settled: float = g.pandemic_probability()
	check(settled >= alone,
		"settling the system does not make an outbreak less likely: %f vs %f" % [settled, alone])
	# And the toll still falls with world count, which is where dilution belongs.
	var src: String = FileAccess.get_file_as_string("res://Game.gd")
	var at: int = src.find("func _trigger_pandemic")
	check(at > 0 and src.substr(at, 1400).find("/ float(inhabited)") >= 0,
		"the TOLL is still divided across worlds")
	g.colonized_planets = []
	for w in ["mars", "venus", "luna"]:
		g.world_pop.erase(w)


	# ── Life expectancy is out of it ──
	# It was a public-health proxy, but in this game it is driven by the longevity splice.
	var before_le: float = g.pandemic_probability()
	g._pop_weighted_life = 3.0            # a much longer-lived civilisation
	check(absf(g.pandemic_probability() - before_le) < 1.0e-9,
		"engineered longevity is not sanitation: %f vs %f" % [
			g.pandemic_probability(), before_le])
	g._pop_weighted_life = 1.0


	# ── Surveillance is a lever, not just foresight ──
	# "Epidemiological modelling" bought a warning and nothing else: the player could watch an
	# outbreak coming and do nothing about it.
	rt.force_unlock(g.FORECAST_RESEARCH)
	var unwatched: float = g.pandemic_probability()
	check(g.track_compute("pandemic") <= 0.0, "nothing is pointed at it yet")
	for t: String in g.COMPUTE_TRACKS:
		g.compute_alloc[t] = {"human": 1.0 if t == "pandemic" else 0.0,
			"ai": 1.0 if t == "pandemic" else 0.0}
	g._mark_prod_dirty()
	var watch: float = g.track_compute("pandemic")
	check(watch > 0.0, "now it is: %s FLOP/s" % str(watch))
	var watched: float = g.pandemic_probability()
	check(watched < unwatched,
		"watching for it reduces the odds: %f vs %f" % [watched, unwatched])
	# Worth a real fraction, or the slider is decorative.
	check(watched < unwatched * 0.8,
		"and by enough to be worth the compute: x%.3f" % (watched / maxf(unwatched, 1e-12)))
	# But never to zero: something always gets out.
	check(watched > 0.0, "and never to nothing: %f" % watched)

	print("FAILS: %d" % fails)
	quit()
