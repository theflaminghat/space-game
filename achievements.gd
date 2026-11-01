class_name AchievementData

## What a run is remembered for.
##
## ── Why these and not a score ──
##
## The game already produces the only numbers worth comparing — how far into deep time you got,
## how much of the galaxy you took before somebody else's probes arrived, how much of it you
## still held at the end. An achievement list is not a substitute for those; it is the record of
## which *shapes* a run had, so that two runs that reached the same year can still be told apart.
##
## ── Visible and hidden ──
##
## MILESTONES are visible from the first minute. They are the only place the game says out loud
## what it expects you to do — settle, replicate, enclose a star, take a planet apart — and a
## player reading the list before touching anything should come away knowing what the game is.
##
## ENDINGS are visible too, deliberately: knowing heat death is reachable is the point of
## playing toward it.
##
## FAILURES are hidden until earned. The game springs an asteroid, a pandemic and a war on you,
## and listing them in advance turns each one from an event into a countdown.
##
## ── Names ──
##
## Most are references, and they are references to the thing the mechanic actually is rather than
## decoration: a von Neumann probe really is Bob's problem, a colony four hundred light-years out
## declaring for itself really is Heinlein's, and a relativistic bombardment really is the one
## book written about relativistic bombardment. Where a reference would have been a stretch, the
## plain name is used instead.

const GROUP_ORDER: Array[String] = [
	"first", "swarm", "stellar", "unmaking", "neighbours", "front", "people", "deep", "failure",
]

const GROUP_LABELS: Dictionary = {
	"first":      "First Steps",
	"swarm":      "The Swarm",
	"stellar":    "Stellar Engineering",
	"unmaking":   "Taking Worlds Apart",
	"neighbours": "Neighbours",
	"front":      "The Rival Front",
	"people":     "Your Own People",
	"deep":       "Deep Time",
	"failure":    "How It Ended",
}

## id, name, desc, group, hidden.
##
## `desc` is what the player is told BEFORE earning it, so it has to describe the condition
## without giving away a number they would then play toward mechanically. `note` is the nod, and
## is only shown once it is earned.
const ACHIEVEMENTS: Array[Dictionary] = [
	# ── First steps ────────────────────────────────────────────────────────────
	{"id": "small_step", "group": "first", "name": "A Small Step",
	 "desc": "Put something in orbit and have it arrive.", "note": ""},
	{"id": "foothold", "group": "first", "name": "Foothold",
	 "desc": "Settle a world around another star.", "note": ""},
	{"id": "the_expanse", "group": "first", "name": "The Expanse",
	 "desc": "Settle every world in the solar system.", "note": "after James S. A. Corey"},
	{"id": "mostly_harmless", "group": "first", "name": "Mostly Harmless",
	 "desc": "Make contact with somebody who is not hostile.",
	 "note": "after Douglas Adams"},

	# ── The swarm ──────────────────────────────────────────────────────────────
	{"id": "we_are_bob", "group": "swarm", "name": "We Are Bob",
	 "desc": "Send the first von Neumann probe.",
	 "note": "after Dennis E. Taylor, We Are Legion (We Are Bob)"},
	{"id": "we_are_legion", "group": "swarm", "name": "We Are Legion",
	 "desc": "Have a thousand probes in flight at once.", "note": "after Dennis E. Taylor"},
	{"id": "star_maker", "group": "swarm", "name": "Star Maker",
	 "desc": "Hold a thousand stars.", "note": "after Olaf Stapledon"},
	{"id": "deepness", "group": "swarm", "name": "A Deepness in the Sky",
	 "desc": "Settle a star outside the charted neighbourhood.",
	 "note": "after Vernor Vinge"},

	# ── Stellar engineering ────────────────────────────────────────────────────
	{"id": "wandering_sun", "group": "stellar", "name": "The Wandering Sun",
	 "desc": "Move the Sun a light-year.",
	 "note": "after Liu Cixin, The Wandering Earth"},
	{"id": "caravan", "group": "stellar", "name": "Caravan",
	 "desc": "Move the Sun a hundred light-years.", "note": ""},
	{"id": "stealing_fire", "group": "stellar", "name": "Stealing Fire",
	 "desc": "Lift a tenth of the Sun's mass.", "note": "after Prometheus"},
	{"id": "accelerando", "group": "stellar", "name": "Accelerando",
	 "desc": "Enclose the Sun.", "note": "after Charles Stross"},

	# ── Taking worlds apart ────────────────────────────────────────────────────
	{"id": "core_sample", "group": "unmaking", "name": "Core Sample",
	 "desc": "Mine a world down to its mantle.", "note": ""},
	{"id": "all_these_worlds", "group": "unmaking", "name": "All These Worlds Are Yours",
	 "desc": "Take every planet in the solar system apart.",
	 "note": "after Arthur C. Clarke, 2010: Odyssey Two"},
	{"id": "except_europa", "group": "unmaking", "name": "…Except Europa",
	 "desc": "Take every world apart but leave Europa whole.",
	 "note": "after Arthur C. Clarke"},
	{"id": "pale_blue_dot", "group": "unmaking", "name": "Pale Blue Dot",
	 "desc": "Take Earth apart.", "note": "after Carl Sagan"},
	{"id": "pulling_up_ladder", "group": "unmaking", "name": "Pulling Up the Ladder",
	 "desc": "Begin taking apart a world you are still living on.", "note": ""},

	# ── Neighbours ─────────────────────────────────────────────────────────────
	{"id": "dark_forest", "group": "neighbours", "name": "The Dark Forest",
	 "desc": "Be fired on by somebody you never spoke to.", "note": "after Liu Cixin"},
	{"id": "killing_star", "group": "neighbours", "name": "The Killing Star",
	 "desc": "Survive a relativistic bombardment.",
	 "note": "after Pellegrino & Zebrowski"},
	{"id": "deterrence", "group": "neighbours", "name": "Deterrence",
	 "desc": "Hold an orbital array that somebody else has to take seriously.", "note": ""},
	{"id": "rendezvous", "group": "neighbours", "name": "Rendezvous",
	 "desc": "Complete a trade with another civilisation.",
	 "note": "after Arthur C. Clarke"},

	# ── The rival front ────────────────────────────────────────────────────────
	{"id": "something_replicating", "group": "front", "name": "Something Else Is Replicating",
	 "desc": "See the front for the first time.", "note": ""},
	{"id": "first_come", "group": "front", "name": "First Come",
	 "desc": "Take a star in a volume the front had already entered.", "note": ""},
	{"id": "boxed_in", "group": "front", "name": "Boxed In",
	 "desc": "Have the front close the space around you.", "note": ""},

	# ── Your own people ────────────────────────────────────────────────────────
	{"id": "harsh_mistress", "group": "people", "name": "The Moon Is a Harsh Mistress",
	 "desc": "Lose a colony to its own government.", "note": "after Robert A. Heinlein"},
	{"id": "foundation", "group": "people", "name": "Foundation",
	 "desc": "Lose half of what you held to secession.", "note": "after Isaac Asimov"},
	{"id": "beggars_in_spain", "group": "people", "name": "Beggars in Spain",
	 "desc": "Splice long life and high intelligence into one population.",
	 "note": "after Nancy Kress"},
	{"id": "homo_superior", "group": "people", "name": "Homo Superior",
	 "desc": "Carry a full set of engineered traits.", "note": ""},
	{"id": "no_reply", "group": "people", "name": "No Reply",
	 "desc": "Learn that a colony was lost long after it happened.", "note": ""},

	# ── Deep time ──────────────────────────────────────────────────────────────
	{"id": "deep_thought", "group": "deep", "name": "Deep Thought",
	 "desc": "Build a civilisation that thinks on a scale nobody designed for.",
	 "note": "after Douglas Adams"},
	{"id": "permutation_city", "group": "deep", "name": "Permutation City",
	 "desc": "Think more with machines than with people.", "note": "after Greg Egan"},
	{"id": "tau_zero", "group": "deep", "name": "Tau Zero",
	 "desc": "Survive to the end of the age of stars.", "note": "after Poul Anderson"},
	{"id": "city_and_stars", "group": "deep", "name": "The City and the Stars",
	 "desc": "Survive to the degenerate era.", "note": "after Arthur C. Clarke"},
	{"id": "last_question", "group": "deep", "name": "The Last Question",
	 "desc": "Still be here at the heat death of the universe.",
	 "note": "after Isaac Asimov"},

	# ── How it ended (hidden) ──────────────────────────────────────────────────
	{"id": "lucifers_hammer", "group": "failure", "name": "Lucifer's Hammer",
	 "desc": "Ended by an impactor.", "note": "after Niven & Pournelle", "hidden": true},
	{"id": "canticle", "group": "failure", "name": "A Canticle for Leibowitz",
	 "desc": "Ended by nuclear war.", "note": "after Walter M. Miller Jr.", "hidden": true},
	{"id": "last_man", "group": "failure", "name": "The Last Man",
	 "desc": "Ended by running out of people.", "note": "after Mary Shelley", "hidden": true},
	{"id": "time_machine", "group": "failure", "name": "The Time Machine",
	 "desc": "Still in this system when the Sun left the main sequence.",
	 "note": "after H. G. Wells", "hidden": true},
	{"id": "dont_go_extinct", "group": "failure", "name": "Don't Go Extinct",
	 "desc": "Ended before anything of yours ever reached orbit.",
	 "note": "the title, earned the wrong way", "hidden": true},
]


static var _by_id: Dictionary = {}

## id → record, built once.
static func by_id(id: String) -> Dictionary:
	if _by_id.is_empty():
		for a: Dictionary in ACHIEVEMENTS:
			_by_id[str(a["id"])] = a
	return _by_id.get(id, {})


static func exists(id: String) -> bool:
	return not by_id(id).is_empty()


static func name_of(id: String) -> String:
	return str(by_id(id).get("name", id))


static func is_hidden(id: String) -> bool:
	return bool(by_id(id).get("hidden", false))


## Every achievement in a group, in declaration order.
static func in_group(group: String) -> Array:
	var out: Array = []
	for a: Dictionary in ACHIEVEMENTS:
		if str(a.get("group", "")) == group:
			out.append(a)
	return out
