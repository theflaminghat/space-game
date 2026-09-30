extends SceneTree

## A cluster is not a star.
##
## It is a Voronoi territory of the home tile holding thousands of stars, too far to resolve one
## by one: settled a share at a time, inhabited a share at a time, and attacked a share at a
## time.  What follows from that is what may be DONE to one — there is no counterparty in a
## volume of space, so there is nobody to trade with or ally to.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(20260927)
	root.get_node("GameSession").should_load_on_start = false
	change_scene_to_file("res://node_3d.tscn")
	for _i in range(45): await process_frame
	var g: Node = current_scene
	var rt: Node = root.get_node("ResearchTree")
	var sm = g.sidebar.star_map
	var SM = load("res://StarMapPanel.gd")

	var target := ""
	var home := ""
	for c in SM.star_clusters():
		if bool(c.get("is_home", false)):
			home = str(c["name"])
		elif target == "":
			target = str(c["name"])
	check(target != "" and home != "", "there is a cluster to work with")

	# ── Told apart from stars ──
	check(g.is_cluster(target), "a cluster is a cluster")
	check(not g.is_cluster("Sirius"), "and a star is not")

	# ── Populated by aliens, per the setup's rules ──
	var share: float = g.cluster_alien_share(target)
	check(share > 0.0, "somebody lives in it: %.5f" % share)
	check(share < 1.0, "but not everywhere in it")
	check(g.cluster_alien_stars(target) > 0.0,
		"which is a count of systems: %s" % str(g.cluster_alien_stars(target)))
	check(is_equal_approx(g.cluster_alien_share(home), 0.0),
		"the home territory is ours, not theirs")
	# Deterministic: asking twice gives the same answer.
	check(is_equal_approx(g.cluster_alien_share(target), share), "and it does not drift")
	# "Alone" must mean alone.
	check(g.alien_density_scale() > 0.0, "the standard sky has neighbours")

	# ── No diplomacy with a volume of space ──
	g.sidebar.hide_all()
	sm.show()
	g.refresh_star_map()
	check(sm.focus_star(target), "the cluster can be selected")
	for _i in range(10): await process_frame
	check(sm.selected_star() == target, "and is what is selected")
	check(sm._trade_btn.disabled, "trade is refused")
	check(sm._ally_btn.disabled, "alliance is refused")
	check(sm._trade_btn.tooltip_text.contains("government")
			or sm._trade_btn.tooltip_text.contains("nobody"),
		"and says why: '%s'" % sm._trade_btn.tooltip_text)

	# ── Missiles take random systems out of it ──
	# Most of a cluster is empty rock, so most missiles find nothing — which is the honest
	# answer at this scale and is what the card says.
	g.cluster_aliens[target] = 0.5        # a thickly settled cluster, so a hit is likely
	var before: float = g.cluster_alien_stars(target)
	g._pending_event_notifications.clear()
	g.year += 1
	g._resolve_cluster_strike(target, "missile", 40)
	check(g.cluster_alien_stars(target) < before,
		"a heavy salvo into a settled cluster kills somebody: %s -> %s" % [
			str(before), str(g.cluster_alien_stars(target))])
	check(g._pending_event_notifications.size() == 1, "and reports once")
	check(str(g._pending_event_notifications[0]["desc"]).contains("systems struck"),
		"naming how many systems it struck")

	# ── Berserkers sterilise a share, rising with how many were sent ──
	var last: float = -1.0
	for n in [1, 5, 20, 80]:
		g.cluster_aliens[target] = 0.5
		g.cluster_colonized[target] = 0.30
		var b0: float = g.cluster_alien_stars(target)
		g.year += 1
		g._resolve_cluster_strike(target, "berserker", n)
		var killed: float = 1.0 - g.cluster_alien_stars(target) / maxf(b0, 1e-9)
		check(killed > last, "%d berserkers sterilise more than fewer did: %.3f" % [n, killed])
		check(killed < 1.0, "and never quite all of it: %.3f" % killed)
		last = killed
		# Indiscriminate — our own holdings in the same cluster burn with the rest.
		check(float(g.cluster_colonized.get(target, 1.0)) < 0.30,
			"our own share of it burns too: %.4f" % float(g.cluster_colonized.get(target, 0.0)))

	# ── It is all saved ──
	g.cluster_aliens[target] = 0.4242
	g.save_game("user://saves/clusters.json")
	g.cluster_aliens.clear()
	g.load_game("user://saves/clusters.json")
	for _i in range(6): await process_frame
	check(is_equal_approx(float(g.cluster_aliens.get(target, -1.0)), 0.4242),
		"the alien share survives a save: %s" % str(g.cluster_aliens.get(target, -1.0)))

	print("FAILS: %d" % fails)
	quit()
