class_name MissionData

# Launches now cost ROCKETS (the vehicle mass) plus FUEL (a propellant the player
# picks).  The chosen fuel's `accel` sets the transfer acceleration — and therefore
# the transit time via the brachistochrone — and that fuel is what gets consumed.
#
#   rockets  – base number of Rocket units (the launch vehicle) for a bare local
#              orbit insertion; scales up with the destination's Δv difficulty.
#   fuel     – base units of the selected propellant; scales with Δv difficulty and
#              the launch-window quality.
#
# Magnitudes mirror reality's ratios: a colony ship is a fleet of heavy-lift
# vehicles, a survey probe rides a single small rocket.
## One "Rocket" unit is a real launch vehicle, not an abstract token: ~500 t of stage hardware,
## tankage and structure — Falcon-9 through Saturn-V class.  Mission "rockets" counts VEHICLES;
## this converts the count into the grams of Rocket actually drawn from the origin's inventory.
## Grams of payload one deployable unit costs.  Without this a "satellite" cost a single gram,
## which made the largest structure a civilisation can build cheaper than a rivet.
const PAYLOAD_MASS_PER_UNIT: float = 1.0e13

## Grams of cargo one rocket can lift.  A Supply Run sized purely by its empty vehicle could
## carry a planet in the hold for free; this makes the manifest cost rockets in proportion to
## what is actually in it.
const CARGO_PER_ROCKET_G: float = 2.0e8

const ROCKET_UNIT_MASS_G: float = 5.0e8

## Energy a launch campaign expends per gram of vehicle put on a trajectory.  Low Earth orbit
## costs ~33 MJ per kg of specific orbital energy; a real stack burns several times that once
## gravity losses, drag and staging inefficiency are counted, so ~44 kJ/g.  Interplanetary
## injections cost more again — the Δv difficulty and window factors scale this up.
const LAUNCH_ENERGY_PER_GRAM: float = 4.4e4

# ── What may fly where ────────────────────────────────────────────────────────
## Every mission names the kind of body it can fly to, and every body has a kind — the same
## strings Game.PLANET_TYPES uses, with a moon counting as rocky.  Both panels and the launch
## itself ask the functions below, so the list a player can choose from and the rule the game
## enforces are one thing and cannot drift apart.
##
##   ANY      – anything in the system: you can look at, or ship cargo to, anywhere
##   WORLD    – anything but the star: people and colonies need somewhere to be
##   SURFACE  – something with ground: rocky bodies, moons and the belt
##   STAR     – the Sun alone: the carriers that service solar orbit
const TARGET_ANY:     String = "any"
const TARGET_WORLD:   String = "world"
const TARGET_SURFACE: String = "surface"
const TARGET_STAR:    String = "star"


## Whether a body of this kind has ground a craft could land on.
static func kind_has_surface(kind: String) -> bool:
	return kind == "rocky" or kind == "belt"


## Whether `mission` may fly to a body of this kind.
static func allows_target(mission: Dictionary, kind: String) -> bool:
	if kind == "":
		return false
	match str(mission.get("targets", TARGET_ANY)):
		TARGET_STAR:    return kind == "star"
		TARGET_SURFACE: return kind_has_surface(kind)
		TARGET_WORLD:   return kind != "star"
		_:              return true


## Whether a mission of this kind may arrive the given way.  Landing needs ground: a gas giant
## has none to reach and a star is not somewhere anything arrives at all.
static func allows_arrival(mission: Dictionary, kind: String, arrival: String) -> bool:
	if not allows_target(mission, kind):
		return false
	if arrival != "land":
		return true
	return kind_has_surface(kind)


## Why a combination is refused, in a few words for the panel to show.  "" when it is fine.
static func refusal(mission: Dictionary, kind: String, arrival: String) -> String:
	if not allows_target(mission, kind):
		match str(mission.get("targets", TARGET_ANY)):
			TARGET_STAR:    return "flies to the Sun only"
			TARGET_SURFACE: return "needs a surface to work on"
			TARGET_WORLD:   return "cannot be sent to a star"
	if not allows_arrival(mission, kind, arrival):
		return "nothing lands on a star" if kind == "star" else "no surface to land on"
	return ""


## The first mission that may fly to a body of this kind, or -1 if somehow none can.
static func first_valid_index(kind: String) -> int:
	for i in range(MISSION_TYPES.size()):
		if allows_target(MISSION_TYPES[i], kind):
			return i
	return -1


const MISSION_TYPES := [
	# Small interplanetary probe on a single rocket.
	{"name": "Survey",          "rockets": 1,  "fuel": 8,  "targets": TARGET_ANY},
	# Robotic prospecting hardware + lander — heavy-lift class.
	{"name": "Mining Ops",      "rockets": 6,  "fuel": 80, "targets": TARGET_SURFACE},
	# Crewed habitat + life support + ISRU — by far the largest.
	{"name": "Colony Ship",     "rockets": 30, "fuel": 500, "targets": TARGET_WORLD},
	# Instrument-laden science probe.
	{"name": "Research Probe",  "rockets": 2,  "fuel": 16, "targets": TARGET_ANY},
	# Cargo resupply to an established colony.
	# Supply Run — the only mission that moves MATTER between worlds.  The player picks what
	# goes in the hold and how much of each; the rockets and fuel below are the empty vehicle,
	# and the cargo's own mass is charged on top (see Game._on_launch_requested).
	{"name": "Supply Run",      "rockets": 4,  "fuel": 50, "cargo": true, "targets": TARGET_ANY},
	# Carrier that ferries one collector array to the Sun and slots it into the swarm.  Only
	# valid with the Sun as target, and one array per launch, so the swarm is built out a piece
	# at a time — 1 409 launches for a complete ring.
	#
	# What is launched is a SEED, not the finished article: PAYLOAD_MASS_PER_UNIT grams of
	# self-replicating machinery that arrives, mines the inner system, and grows itself into a
	# shell segment of ~2e10 collectors (Game.SWARM_COLLECTORS_PER_PANEL).  That is the only way
	# a megastructure is ever built, and it is why the launched mass is merely industrial while
	# the deployed area is stellar.
	{"name": "Solar Deployment", "rockets": 2, "fuel": 20,
		"payload": "SolarSatellite", "payload_per_launch": 1, "sun_only": true,
		"targets": TARGET_STAR},

	# ── Prefabricated structures flown to the Sun ─────────────────────────────
	# Solar orbit is a build site with no industry of its own: it has the baseline manufacturing
	# capacity every body has and nothing else, and the first structure that would fix that is
	# exactly the one it cannot build in reasonable time.  These two break that circle by flying
	# the thing out whole, assembled on a world that does have industry.
	#
	# "structure" names a building: its full bill of materials is charged at the ORIGIN when the
	# launch goes up, and the finished structure is added to the Sun's roster when it arrives —
	# no construction queue at the far end, because there is nothing out there to build with.
	# Heavy-lift class: a shipyard is not a satellite.
	{"name": "Construction Station", "rockets": 20, "fuel": 320,
		"structure": "Orbital Construction Station", "sun_only": true, "targets": TARGET_STAR},
	{"name": "Vault Delivery",       "rockets": 10, "fuel": 140,
		"structure": "Orbital Vault", "sun_only": true, "targets": TARGET_STAR},
]

# Selectable propellants.  The player chooses one per launch; its `accel` (m/s²) drives
# the brachistochrone transit time, and `id` is the compound (from recipes.gd) that is
# consumed.  Higher-acceleration fuels are gated behind propulsion research and are far
# costlier to manufacture, so speed is paid for in precious fuel.
## "energy_density" is the usable energy a gram of the propellant delivers to the vehicle (J/g).
## A launch consumes exactly the mass needed to supply its energy requirement — nothing else is
## expended — so this is what makes an advanced propellant transformative rather than merely
## faster: the same trajectory that burns thousands of tonnes of chemical fuel takes grams of
## fusion fuel.  Values are real: LOX/RP-1 ≈ 10 MJ/kg, D-T fusion ≈ 340 TJ/kg, antimatter
## annihilation ≈ 90 PJ/kg after realistic capture losses.
const FUELS := [
	{"id": "Propellant", "name": "Chemical Propellant", "accel": 1.0e-2, "energy_density": 1.0e4,  "requires": "early_rocketry"},
	{"id": "He3",        "name": "Helium-3",            "accel": 1.0,    "energy_density": 3.4e11, "requires": "fusion_engineering"},
	{"id": "Antimatter", "name": "Antimatter",          "accel": 5.0e1,  "energy_density": 9.0e13, "requires": "antimatter_handling"},
]

## Usable energy per gram for a fuel id (0 when unknown).
static func fuel_energy_density(fuel_id: String) -> float:
	for f: Dictionary in FUELS:
		if str(f["id"]) == fuel_id:
			return float(f.get("energy_density", 0.0))
	return 0.0

const START_OFFSETS := [
	{"label": "Now",       "days": 0},
	{"label": "+1 Month",  "days": 30},
	{"label": "+3 Months", "days": 90},
	{"label": "+6 Months", "days": 180},
	{"label": "+1 Year",   "days": 365},
]

const DURATIONS := [
	{"label": "30 days",  "days": 30},
	{"label": "90 days",  "days": 90},
	{"label": "180 days", "days": 180},
	{"label": "1 year",   "days": 365},
	{"label": "2 years",  "days": 730},
	{"label": "5 years",  "days": 1825},
]
