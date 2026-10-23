extends SceneTree

## Which stars get a name on the star map.
##
## A label is earned the same way whatever is living there: the frame's chosen set — the name
## range, the inner band and STAR_NAME_BUDGET — or the selection, or a known alien civilisation,
## of which there are a handful.
##
## Settling a star used to exempt it from all three, on the reasoning that you cannot act on a
## system you cannot identify. That stops holding the moment the von Neumann swarm has settled
## tens of thousands of systems: every one of them labelled at every zoom and every distance
## buries the map under its own labels, including the few that were worth reading. So the cutoff
## that applies to a star BEFORE it is colonised applies to it after.

var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var SM = load("res://StarMapPanel.gd")

	# ── Nothing about who is there can change the answer ──
	# Not asserted by varying it — there is nothing to vary, which is the point. The rule is
	# given neither a colonised flag nor a faction, so the guarantee is the signature, and what
	# a test can add is to pin the rule EXACTLY: see the specification check below, which fixes
	# the answer for every input rather than sampling it.

	# ── The frame's chosen set, and only within the detail band ──
	check(SM._star_label_shown(false, true, 0.5), "a star in the frame's set is named")
	check(not SM._star_label_shown(false, false, 0.5),
		"one outside it is not, however bright")
	check(not SM._star_label_shown(false, true, 0.0),
		"and one faded out of the band is not named even if it was chosen")

	# ── The selection is named whatever the band says ──
	# The escape hatch the whole rule needs: a star outside the name range has no label now, so
	# clicking it has to produce one or there is no telling which dot the info box describes.
	check(SM._star_label_shown(true, false, 0.0),
		"the selected star is named wherever it is")
	check(SM._star_label_shown(true, true, 1.0), "and in the band as well, obviously")

	# ── An empty system, a colony and a civilisation are all named the same way ──
	# This used to be three different answers: a colony and a known civilisation were each
	# exempt from the range, the band and the budget, and an empty system was not. There is now
	# one answer, and the test can only state that by noting there is nothing to vary.
	# Specified exactly, not sampled: for an unselected star the answer IS "in the chosen set
	# and inside the band", for every combination of the two. There is no room left in that for
	# an exemption to hide in.
	for in_set: bool in [true, false]:
		for a: float in [0.0, 0.001, 0.4, 1.0]:
			check(SM._star_label_shown(false, in_set, a) == (in_set and a > 0.0),
				"unselected, set %s, alpha %.3f: named iff chosen and in the band"
					% [str(in_set), a])
			check(SM._star_label_shown(true, in_set, a),
				"and selected, set %s, alpha %.3f: named regardless" % [str(in_set), a])

	# ── The budget is what bounds it ──
	check(SM.STAR_NAME_BUDGET > 0 and SM.STAR_NAME_BUDGET <= 64,
		"the label budget is a small number: %d" % SM.STAR_NAME_BUDGET)
	check(SM.NAME_RANGE_LY > 0.0, "and there is a range beyond which nothing is named")

	print("FAILS: %d" % fails)
	quit()
