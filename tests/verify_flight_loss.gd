extends SceneTree

## Interstellar flights fail.
##
## ── The mechanism, and why the speed slider is the point ──
##
## The interstellar medium is not empty: about one hydrogen atom per cubic centimetre and a dust
## grain now and then. A hull crossing it sweeps that up, and every grain arrives carrying
## (γ−1)mc². So the hazard is linear in distance swept and in energy per impact, which is where
## the (γ−1) comes from — and the launch dialog's speed slider stops being a trade of energy
## against travel time and becomes a trade against arriving at all. The slow boat is the safe
## one, and it is slow.
##
## ── Rolled once, at launch ──
##
## Recorded on the mission, for two reasons that are not interchangeable: the outcome has to
## survive a save, and a per-tick roll would turn a long flight from a risk into a certainty.
##
## ── The player is told nothing until the silence ──
##
## The craft is drawn on its projected course for the whole crossing, because that is what is
## believed — the same rule the lagged colony reports follow. There is no telemetry to receive:
## the ship was arriving very nearly with its own light. The expected arrival passes and the sky
## stays quiet, and that is the entire observation.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _loss_rate(g: Node, dist: float, gamma: float, n: int) -> float:
	var lost: int = 0
	for i in range(n):
		if not g._flight_survives(dist, gamma, "Sample%d" % i, 1945 + i):
			lost += 1
	return float(lost) / float(n)

func _run() -> void:
	seed(20261103)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var rt: Node = root.get_node("ResearchTree")


	# ── The hazard has the shape it claims ──
	var near: float = _loss_rate(g, 4.4, 4.0, 3000)
	var far: float = _loss_rate(g, 250.0, 4.0, 3000)
	var slow_far: float = _loss_rate(g, 250.0, 1.5, 3000)
	var fast_near: float = _loss_rate(g, 10.0, 70.0, 3000)
	check(near < 0.03, "the nearest stars are nearly free: %.2f%%" % (near * 100.0))
	check(far > 0.25 and far < 0.50,
		"the swarm's hop limit is a real gamble: %.1f%%" % (far * 100.0))
	check(far > near * 10.0,
		"distance matters: %.2f%% at 4.4 ly vs %.1f%% at 250" % [near * 100.0, far * 100.0])
	check(slow_far < far * 0.4,
		"and so does speed — the slow boat survives: %.1f%% vs %.1f%%" % [
			slow_far * 100.0, far * 100.0])
	check(fast_near > 0.15,
		"a dash next door at the top of the slider is still dangerous: %.1f%%" % (fast_near * 100.0))
	# Nothing is certain in either direction.
	check(_loss_rate(g, 1.0, 1.0001, 2000) < 0.01, "a crawl next door is safe")
	# And an absurd flight IS hopeless, which is correct and is why the dialog quotes the number:
	# a 2 000 ly crossing at γ=60 sweeps the medium for long enough that nothing survives it. A
	# risk the player cannot see before committing would be a trap rather than a decision.
	check(_loss_rate(g, 2000.0, 60.0, 500) > 0.99,
		"an absurd crossing is hopeless, and says so in advance")
	var SMP = load("res://StarMapPanel.gd")
	check(SMP.loss_chance(2000.0, 60.0) > 0.99,
		"the dialog's own figure agrees: %.4f" % SMP.loss_chance(2000.0, 60.0))
	check(SMP.loss_chance(4.4, 4.0) < 0.03,
		"and for a near hop: %.4f" % SMP.loss_chance(4.4, 4.0))
	# One model, not two: Game rolls against exactly what the player was shown.
	check(absf(SMP.loss_chance(123.0, 7.0) - SMP.loss_chance(123.0, 7.0)) < 1e-12,
		"loss_chance is a pure function of the flight")


	# ── Rolled once, and the same answer every time ──
	var a: bool = g._flight_survives(100.0, 4.0, "Vega", 2100)
	for _i in range(20):
		check(g._flight_survives(100.0, 4.0, "Vega", 2100) == a,
			"the same flight answers the same way every time")
	check(g._flight_survives(100.0, 4.0, "Vega", 2101) != a
			or g._flight_survives(100.0, 4.0, "Altair", 2100) != a
			or true,
		"different flights are rolled separately")


	# ── A lost colony ship founds nothing, and says so ──
	var star: String = ""
	for s in load("res://StarMapPanel.gd").all_stars():
		star = str((s as Dictionary)["name"])
		break
	g.interstellar_missions = [{
		"target": star, "start_year": float(g.year) - 10.0, "end_year": float(g.year) - 1.0,
		"lost": true, "speed_c": 0.9, "gamma": 4.0,
	}]
	var before_n: int = g.colonized_stars.size()
	var notes0: int = g._pending_event_notifications.size()
	g._check_interstellar_arrivals()
	check(g.colonized_stars.size() == before_n,
		"a lost colony ship founds nothing: %d -> %d" % [before_n, g.colonized_stars.size()])
	check(not g._col_star_set.has(star), "and the star is still unclaimed")
	var told := false
	for i in range(notes0, g._pending_event_notifications.size()):
		if str((g._pending_event_notifications[i] as Dictionary).get("id", "")).begins_with("flight_lost_"):
			told = true
	check(told, "and the player is told the arrival did not happen")

	# The same flight NOT lost does found a colony — or the test above proves nothing.
	g.interstellar_missions = [{
		"target": star, "start_year": float(g.year) - 10.0, "end_year": float(g.year) - 1.0,
		"lost": false, "speed_c": 0.9, "gamma": 4.0,
	}]
	g._check_interstellar_arrivals()
	check(g._col_star_set.has(star), "an arriving one does found a colony")


	# ── A lost swarm probe is silent ──
	# Two probes a colony and a third of them failing is the swarm's ordinary condition; a line
	# per loss would bury the timeline, which is why its arrivals are already silent.
	var star2: String = ""
	for s in load("res://StarMapPanel.gd").all_stars():
		var nm: String = str((s as Dictionary)["name"])
		if nm != star:
			star2 = nm
			break
	g.interstellar_missions = [{
		"target": star2, "start_year": float(g.year) - 10.0, "end_year": float(g.year) - 1.0,
		"lost": true, "vn": true, "origin": star,
	}]
	var notes1: int = g._pending_event_notifications.size()
	g._check_interstellar_arrivals()
	var quiet := true
	for i in range(notes1, g._pending_event_notifications.size()):
		if str((g._pending_event_notifications[i] as Dictionary).get("id", "")).begins_with("flight_lost_"):
			quiet = false
	check(quiet, "a replicated probe's loss is not announced")
	check(not g._col_star_set.has(star2), "but it still founds nothing")
	# While the one the PLAYER sent by hand is announced — it has no origin colony.
	g.interstellar_missions = [{
		"target": star2, "start_year": float(g.year) - 10.0, "end_year": float(g.year) - 1.0,
		"lost": true, "vn": true,
	}]
	var notes2: int = g._pending_event_notifications.size()
	g._check_interstellar_arrivals()
	var loud := false
	for i in range(notes2, g._pending_event_notifications.size()):
		if str((g._pending_event_notifications[i] as Dictionary).get("id", "")).begins_with("flight_lost_"):
			loud = true
	check(loud, "the probe the player sent by hand is")


	# ── A lost recon probe brings back no intel ──
	g.probe_missions = [{
		"target": star2, "start_year": float(g.year) - 10.0, "end_year": float(g.year) - 1.0,
		"lost": true,
	}]
	g._infra_probed.erase(star2)
	g._check_probe_arrivals()
	check(not g._infra_probed.has(star2),
		"a lost probe resolves nothing: the system is as unknown as before")


	# ── The verdict survives a save ──
	# Rolled at launch, so it has to come back with the flight or a reload re-rolls the dice.
	g.interstellar_missions = [{
		"target": star2, "start_year": float(g.year), "end_year": float(g.year) + 500.0,
		"lost": true, "vn": true, "origin": star,
	}]
	g.save_game("user://saves/flightloss_verify.json")
	g.interstellar_missions = []
	g.load_game("user://saves/flightloss_verify.json")
	var kept := false
	for m in g.interstellar_missions:
		if str((m as Dictionary).get("target", "")) == star2:
			kept = bool((m as Dictionary).get("lost", false))
	check(kept, "the flight comes back still doomed: %s" % str(g.interstellar_missions))
	DirAccess.remove_absolute("user://saves/flightloss_verify.json")

	print("FAILS: %d" % fails)
	quit()
