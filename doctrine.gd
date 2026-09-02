class_name DoctrineData

## Standing instructions: what a probe is sent to DO, and how it behaves toward whoever it
## meets.  Both travel with the probe, and because a von Neumann probe copies itself, they
## travel into every probe it builds — orders given once, executed for ever.
##
## ── What a probe is sent to do ───────────────────────────────────────────────
## A self-replicating machine is not inherently a colonist.  The same hardware surveys, relays,
## or settles depending on what it was told before it left, and only one of those three claims
## anything.  Cheaper missions replicate faster because they carry less.
const PROBE_MISSIONS: Array = [
	{
		"id": "recon",
		"name": "Reconnaissance",
		"desc": "Survey the system and move on. Claims nothing.",
		"detail": "Resolves the system's infrastructure in full and passes the report home, then builds copies that fan out to the next unsurveyed stars. The cheapest way to learn what is out there — and the only one that commits you to nothing.",
		"mass_frac": 0.012, "replicates": true, "claims": false,
	},
	{
		"id": "comms",
		"name": "Communication Relay",
		"desc": "Build a relay station and extend the network outward.",
		"detail": "Each relay is another aperture listening from somewhere that is not here, so the network sees further than any telescope at home can. Relays claim nothing and threaten no one, which makes them the one thing safe to put in a neighbour's sky.",
		"mass_frac": 0.02, "replicates": true, "claims": false,
	},
	{
		"id": "colonize",
		"name": "Colonisation",
		"desc": "Settle the system, then seed the next ones.",
		"detail": "The full von Neumann article: it lands, builds an industry, founds a colony, and launches fresh probes onward. One launch eventually reaches everything, which is the point and the danger.",
		"mass_frac": 0.03, "replicates": true, "claims": true,
	},
]

const DEFAULT_MISSION: String = "recon"

static func get_mission(id: String) -> Dictionary:
	for m: Dictionary in PROBE_MISSIONS:
		if str(m["id"]) == id:
			return m
	return get_mission(DEFAULT_MISSION)

## Fraction of a flight plan's energy the probe's mass actually costs — a surveyor is far
## lighter than something carrying a colony's worth of industry.
static func mission_mass_frac(id: String) -> float:
	return float(get_mission(id).get("mass_frac", 0.03))

## Whether this mission settles the system it reaches.
static func mission_claims(id: String) -> bool:
	return bool(get_mission(id).get("claims", false))

## ── How this civilisation answers contact with another ──────────────────────
##
## The alien systems in the star map are a repeated game, not a scripted one: each has a true
## alignment (aggressive or peaceful), each can strike, and each strike is observed.  A doctrine
## is the player's standing rule for that game — the strategy they commit to in advance and
## cannot quietly abandon the moment it costs something.
##
## Every entry carries the same four levers:
##   provocation  – multiplier on how often hostiles choose to strike the player.  Posture is
##                  read from across light-years: a civilisation that shoots first is one worth
##                  shooting first.
##   retaliate    – salvo size sent back per attack received, in missiles.  0 never answers.
##   first_strike – open fire on a system merely for being detected and aggressive.
##   forgives     – whether retaliation stops once the other side does.  A strategy that never
##                  forgives is stable but can never de-escalate.
const DOCTRINES: Array = [
	{
		"id": "appeasement",
		"name": "Appeasement",
		"desc": "Never answer an attack. Nothing you build is aimed at anyone, and everyone can see it.",
		"detail": "Least provocative posture there is, and the cheapest — no magazine to keep. It also means every hostile that decides to fire faces no cost for it.",
		"provocation": 0.55, "retaliate": 0, "first_strike": false, "forgives": true,
	},
	{
		"id": "tit_for_tat",
		"name": "Tit for Tat",
		"desc": "Never strike first. Answer every attack once, in kind. Stop the moment they do.",
		"detail": "The strategy that wins repeated games: nice, retaliatory, forgiving, and legible. It cannot be exploited, and it cannot start a war it did not want.",
		"provocation": 1.0, "retaliate": 1, "first_strike": false, "forgives": true,
	},
	{
		"id": "grim_trigger",
		"name": "Grim Trigger",
		"desc": "Never strike first. Answer the first attack with everything, for ever.",
		"detail": "Maximum deterrence at the price of any way back: one strike converts you into a permanent enemy of that system, whatever it does afterwards.",
		"provocation": 0.85, "retaliate": 3, "first_strike": false, "forgives": false,
	},
	{
		"id": "preemption",
		"name": "Pre-emption",
		"desc": "Fire on any hostile system the moment it is detected, before it can decide anything.",
		"detail": "Removes threats while they are still cheap to remove. It also tells every telescope in range exactly what you are, and they are watching.",
		"provocation": 1.9, "retaliate": 2, "first_strike": true, "forgives": false,
	},
]

const DEFAULT_ID: String = "tit_for_tat"

static func get_doctrine(id: String) -> Dictionary:
	for d: Dictionary in DOCTRINES:
		if str(d["id"]) == id:
			return d
	return get_doctrine(DEFAULT_ID)

## Multiplier on hostile aggression toward the player.
static func provocation(id: String) -> float:
	return float(get_doctrine(id).get("provocation", 1.0))

## Missiles sent back per attack received (0 = never answer).
static func retaliation(id: String) -> int:
	return int(get_doctrine(id).get("retaliate", 0))

static func strikes_first(id: String) -> bool:
	return bool(get_doctrine(id).get("first_strike", false))

static func forgives(id: String) -> bool:
	return bool(get_doctrine(id).get("forgives", true))
