extends Node

# ── Timescale constants ────────────────────────────────────────────────────────
## Real seconds per in-game day at the very start of the game.
const TIMESCALE_INIT:  float = 0.25
## Exponential decay rate — each elapsed year multiplies speed by e^(-DECAY).
const TIMESCALE_DECAY: float = 0.04
## Minimum seconds per day (maximum speed).  At 1e-9, ~2.74M game-years/real-sec.
const TIMESCALE_MIN:   float = 1e-9
## Below this threshold switch from day-by-day to year-based fast mode.
const FAST_THRESHOLD:  float = 5e-4

# ── Planet type lookup ────────────────────────────────────────────────────────
## Maps each planet name to the type string used by BuildingData.allowed_types.
const PLANET_TYPES: Dictionary = {
	"sun":     "star",
	"mercury": "rocky",  "venus":   "rocky",    "earth":   "rocky",   "mars":    "rocky",
	"jupiter": "gas_giant", "saturn": "gas_giant", "uranus": "gas_giant", "neptune": "gas_giant",
}

## Cosmetic moons (spawned in planet.gd as "<planet>_moon_<n>") are also buildable, rocky
## bodies.  Display names by node id; unnamed indices fall back to "<Planet> moon N".
const MOON_NAMES: Dictionary = {
	"earth_moon_0": "Luna",
	"mars_moon_0": "Phobos",   "mars_moon_1": "Deimos",
	"jupiter_moon_0": "Io",     "jupiter_moon_1": "Europa",
	"jupiter_moon_2": "Ganymede","jupiter_moon_3": "Callisto",
	"saturn_moon_0": "Titan",   "saturn_moon_1": "Rhea",
	"saturn_moon_2": "Iapetus", "saturn_moon_3": "Dione",
	"uranus_moon_0": "Titania", "uranus_moon_1": "Oberon", "uranus_moon_2": "Miranda",
	"neptune_moon_0": "Triton", "neptune_moon_1": "Proteus",
}
## Generic anorthositic-regolith crust (grams) so a moon's mines yield the same ores a
## rocky planet does.  Shared by every moon (they have no individual PlanetData entry).
const MOON_COMPOSITION: Dictionary = {
	"crust": {
		"SiO2":  4.5e24, "Al2O3": 2.6e24, "CaO":   1.6e24, "FeO":  1.5e24,
		"MgO":   6.0e23, "TiO2":  3.0e23, "Na2O":  1.0e23, "UO2":  1.0e19, "ThO2": 3.0e19,
		# Four billion years of solar wind, implanted grain by grain into an airless regolith and
		# never blown away: ~10 ppb, which is why the Moon is the place you go for fusion fuel.
		"He3":   1.0e17,
	},
}

# ── Extinction-event thresholds ────────────────────────────────────────────────
## Year the Sun reaches Earth's orbit at RGB tip — used for the HUD warning only.
## Actual extinction is driven by dynamic engulfment in _check_extinction_events.
const SUN_RED_GIANT_YEAR:    int = 7_590_000_000
## HUD warning starts this many years before Earth is engulfed.
const SUN_WARNING_YEAR:      int = SUN_RED_GIANT_YEAR - 1_000_000
## After this year the Sun has ejected its envelope; all solar-system life ends.
const PLANETARY_NEBULA_YEAR: int = 8_210_000_000

## Orbital semi-major axes (AU) for each planet — used to determine engulfment order.
const PLANET_ORBIT_AU: Dictionary = {
	"mercury": 0.387, "venus":   0.723, "earth":   1.000, "mars":    1.524,
	"jupiter": 5.203, "saturn":  9.537, "uranus": 19.191, "neptune": 30.069,
}
## Physical radius of the present-day Sun in AU.
const SUN_RADIUS_BASE_AU: float = 0.00465

# ── Population model ────────────────────────────────────────────────────────────
# Population follows logistic growth toward a carrying capacity (K) that is set by
# the resources actually available.  Earth's biosphere provides a fixed natural
# capacity; every colonized world adds habitat that must be sustained by energy
# and mineral output (Liebig's law of the minimum — the scarcer one caps it).
# The step is integrated analytically on the game-day clock so it stays exact and
# stable whether a frame covers one day or millions of years.
const POP_GROWTH_PER_YEAR: float = 0.03      # intrinsic logistic growth rate
const EARTH_NATURAL_K:     float = 1.0e10    # people Earth supports unconditionally
const COLONY_HABITAT_K:    float = 5.0e9     # max people one fully-supplied colony houses
const ENERGY_PER_CAPITA:   float = 200.0     # Watts of output per sustained off-world person
const MINERALS_PER_CAPITA: float = 0.5 * Units.MASS_SCALE   # grams/s per sustained off-world person
const MIN_POPULATION:      float = 1.0e5     # floor short of outright extinction
const COLONY_SEED_POP:     float = 1.0e6     # founding population of a new (or re-settled) colony
const COLONY_FULL_POWER:   float = 2.0e11    # local power (W) that fully supplies a colony's habitat
## Per-world population: world_name → people.  "earth" always present; colonies added on
## arrival, removed when destroyed.  stats["current_population"] mirrors the sum of these.
var world_pop: Dictionary = {"earth": 2_300_000_000.0}
## Climate: accumulated atmospheric CO₂ deterministically lowers Earth's carrying
## capacity (no hidden risk roll — just a shrinking ceiling).  CO2_K_HALF is the CO₂
## mass that halves it; CO₂ also naturally sequesters, so cutting emissions lets the
## climate (and the population ceiling) recover.
const CO2_K_HALF:            float = 2.0e19
const CO2_SEQUESTRATION_DAYS: float = 80_000.0   # carbon-cycle time constant (~150 yr half-life)

var year: int = 2026
var month: int = 0
var day: int = 0
var time_accum: float = 0.0
var days_per_month: Array[int] = [31,28,31,30,31,30,31,31,30,31,30,31]
var stats := {
	"year": 1945,
	"current_population": 2_300_000_000,
	"ai_autonomy": 0.2,
	"existential_risk": 0.12,
	"colony_count": 0
}
var planet_buildings: Dictionary = {}
## Buildings under construction, per planet: planet → Array of {building, work, progress}.
## Construction advances at the planet's Manufacturing Capacity (work-units/day), so a
## world's industrial power sets how fast it can raise new structures.  Materials are
## paid when a build is queued; the structure appears only when its work is complete.
var build_queue: Dictionary = {}
var current_planet: String = ""
var science_multiplier: float = 1.0   # science produced per compute per second
var policies: Dictionary = {}         # policy_id -> bool or float
var active_launches: Array = []
var _next_launch_id: int = 1
var _launch_satellites: Dictionary = {}
## Solar Satellites that have arrived at the Sun and joined the Dyson swarm.  The
## swarm renderer (init_planets.gd) reads this to light up one collector each.
var solar_satellites_deployed: int = 0
## Swarm geometry (KEEP IN SYNC with init_planets.gd).  Collectors fill the swarm lane by
## lane, innermost first; each lane fits as many panels as its circumference allows.
const SWARM_LANES:    int   = 18
const SWARM_INNER_AU: float = 0.10   # lanes hug the Sun, inside Mercury's orbit
const SWARM_OUTER_AU: float = 0.26
const SWARM_ORBIT_MULT: float = 32.0   # log-radius scale (mirror init_planets ORBIT_RADIUS_MULT)
const SWARM_PANEL_ARC:  float = 0.30 * 1.4   # arc length per panel (PANEL_W × 1.4)
## Solar Satellites launched toward the swarm but not yet arrived — so each new launch
## reserves the next free slot for its rocket to fly to.
var _pending_swarm: int = 0
# An inner-lane collector beams back ~100 GW; solar flux falls as 1/r², so each lane
# outward delivers proportionally less — the swarm's power grows with diminishing returns.
const SWARM_SAT_POWER: float = 1.0e11          # watts from an innermost-lane collector

## Orbital radius (AU) of swarm lane `lane` (0 = innermost).
func _swarm_lane_au(lane: int) -> float:
	if SWARM_LANES <= 1:
		return SWARM_INNER_AU
	return lerpf(SWARM_INNER_AU, SWARM_OUTER_AU, float(lane) / float(SWARM_LANES - 1))

## How many panels lane `lane` fits without overlap (circumference ÷ panel arc).
func _swarm_lane_cap(lane: int) -> int:
	var rv: float = log(_swarm_lane_au(lane) + 1.0) * SWARM_ORBIT_MULT
	return maxi(1, int(TAU * rv / SWARM_PANEL_ARC))

## Total collector slots across all lanes (the swarm cap).
func _swarm_max() -> int:
	var total: int = 0
	for lane in range(SWARM_LANES):
		total += _swarm_lane_cap(lane)
	return total

## Universe background temperature (K) at the current year — falls as cosmic expansion
## stretches the CMB (T ∝ 1/scale).  A colder sink lets radiators shed heat more easily.
func _universe_temperature() -> float:
	return maxf(CMB_TEMP_2026 / _cosmic_scale(), 1.0e-12)

## Radiating-capacity multiplier from the cold of space: grows slowly as the universe
## cools, so deep-time civilisations can shed far more heat than a 2026 one.
func _thermal_coldness() -> float:
	return maxf(1.0, sqrt(_cosmic_scale()))

## Usable fraction of generated power given the heat it makes and what can be radiated.
## At or under capacity everything is usable; over it, the surplus is curtailed on a
## diminishing curve (never below a floor, so the grid never fully collapses from heat).
func _thermal_efficiency(load: float, capacity: float) -> float:
	if load <= capacity or load <= 0.0:
		return 1.0
	return maxf(THERMAL_EFF_FLOOR, sqrt(capacity / load))

## Accumulate entropy exported to the cold universe: dS = Q / T, where Q is the heat
## actually radiated this slice and T the (falling) universe temperature.  A pure counter.
func _accumulate_entropy(delta_days: float) -> void:
	if delta_days <= 0.0:
		return
	var radiated_w: float = minf(float(_cached_prod.get("energy", 0.0)), _cached_radiator_cap)
	if radiated_w <= 0.0:
		return
	var joules: float = radiated_w * delta_days * DAY_SECONDS
	entropy_exported += joules / _universe_temperature()

## One-shot notices (VOICE: report the numbers, no editorial) when the grid runs hot or the
## labour force can no longer staff built industry.  Each fires once, then re-arms on recovery.
func _check_thermal_labor_alerts() -> void:
	var cap: float = _cached_radiator_cap
	var raw_load: float = _thermal_ratio * cap
	if _thermal_ratio > 1.15:
		if not _heat_alerted:
			_heat_alerted = true
			var usable_pct: int = int(round(_thermal_efficiency(raw_load, cap) * 100.0))
			_announce("Thermal limit",
				"Power draw %s exceeds radiating capacity %s. Usable output curtailed to %d%%." % [
					Units.format_si_verbose(raw_load, "Watts"),
					Units.format_si_verbose(cap, "Watts"), usable_pct],
				"heat_%d" % year)
	elif _thermal_ratio < 1.02:
		_heat_alerted = false

	var staffing: float = _mc_staffing()
	if staffing < 0.6:
		if not _labor_alerted:
			_labor_alerted = true
			_announce("Labour shortfall",
				"Labour force staffs %d%% of built manufacturing capacity. Remainder idle." % \
					int(round(staffing * 100.0)),
				"labor_%d" % year)
	elif staffing > 0.8:
		_labor_alerted = false

## Total power the swarm beams to the grid.  Collectors fill lane by lane (inner first),
## and flux ∝ 1/r², so each successive lane contributes less than the one inside it.  The whole
## yield scales with the Sun's CURRENT luminosity — SWARM_SAT_POWER is calibrated to today's
## 1 L☉, so a swelling red giant (~2700 L☉ at the tip, ~4000 on the AGB) is a colossal windfall,
## and the output collapses again after the helium flash and the final envelope ejection.
func _swarm_power() -> float:
	var total: float = 0.0
	var remaining: int = solar_satellites_deployed
	for lane in range(SWARM_LANES):
		if remaining <= 0:
			break
		var n: int = mini(remaining, _swarm_lane_cap(lane))
		total += float(n) * SWARM_SAT_POWER * pow(SWARM_INNER_AU / _swarm_lane_au(lane), 2.0)
		remaining -= n
	return total * Planet.sun_luminosity_lsun(year)
var colonized_planets: Array = []     # planets that have received a completed Colony Ship

## Interstellar colonies and in-flight colony ships (from the star map).
## colonized_stars: [star_name…];  interstellar_missions: [{target, start_year, end_year, speed_c}]
var colonized_stars: Array = []
var interstellar_missions: Array = []
## Founding year of each interstellar colony (star name → year), for its deterministic
## infrastructure growth (see _colony_infra_at).
var _colony_year: Dictionary = {}

## ── Autonomous von Neumann colonisation ──────────────────────────────────────
## A self-replicating colony probe: on arrival it colonises the star (the normal arrival path)
## and, if replication is unlocked, launches fresh probes to nearby uncolonised stars — spreading
## hands-free.  Probes ride in `interstellar_missions` tagged {"vn": true} so they render and
## resolve like colony ships; only the replication + hands-free seeding are extra.
var _vn_enabled: bool = false                # the AutomationPanel directive (seeds new swarms)
## Von Neumann colonisation is autonomous and prolific, so its individual colony/region events are
## NOT put on the timeline (that flooded it).  Instead we announce only when the grand total of
## settled systems + regions crosses a milestone.  _vn_milestone_idx = how many we've passed.
var _vn_milestone_idx: int = 0
const VN_MILESTONES: Array = [5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000, 25000]
const VN_MAX_INFLIGHT:   int   = 12          # cap probes in flight (bounds work + growth rate)
const VN_MAX_COLONIES:   int   = 200         # stop replicating past this many colonies (sim cost)
const VN_REPLICATE_COUNT: int  = 2           # probes launched per successful arrival
const VN_GAMMA:          float = 4.0         # cruise Lorentz factor for auto-probes (~0.97c)
const VN_ACCEL:          float = 1.0         # m/s² acceleration for the flight plan
const VN_MASS_FRAC:      float = 0.05        # probes are light — a fraction of a colony ship's energy

## ── Statistical galaxy regions (frontier aggregation) ────────────────────────
## Colonies within DETAILED_RADIUS_LY of Sol are simulated individually (world_pop, the detailed
## path).  Beyond it, colonisation is aggregated into REGION cells — each cell holds a colonised
## count and a total population that grow by cheap closed-form steps and diffuse to neighbours, so
## the galaxy can fill hands-free without a per-colony cost explosion.  _regions: cell id → record.
var _regions: Dictionary = {}
var _region_last_year: float = 2026.0
const DETAILED_RADIUS_LY:   float = 2500.0   # inside this radius = individual colonies; outside = regions
const HEX_HEIGHT_LY:        float = 6000.0   # prism height (ly): one tile spans the galaxy's full thickness
## Hex circumradius.  Sized so BOTH landmarks land on tile centres: the lattice is anchored on
## the galactic centre (tile "0,0"), and Sol lies SOL_GC_LY away along the +x galactic axis where
## centres fall every 3*HEX_SIZE — so 26 000 / (3 x 4) puts Sol exactly on tile "-8,4".
## 2166.67 rather than a round 2000 is the closest such size; tiles are ~4333 ly corner-to-corner
## and 3753 ly flat-to-flat.
const HEX_SIZE:             float = 2166.666667
const HEX_SQRT3:            float = 1.7320508
const HEX_AREA_LY2:         float = 1.5 * HEX_SQRT3 * HEX_SIZE * HEX_SIZE   # flat-top hex face area (ly²)
const GALAXY_STAR_DENSITY:  float = 0.065    # stars per ly³ per unit galactic density (~150 billion galaxy)
## Hex neighbours: the 6 flat-top in-plane hex directions (q,r).  A tile is a single tall prism —
## no vertical stacking — so there are no layer neighbours.
const HEX_DIRS: Array = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]
const REGION_STARS_PER_CELL: float = 2.0e6   # colonisable stars in a full-density cell (real-galaxy scale)
const REGION_SATURATE_RATE: float = 4.0e-6   # per-year rate a region colonises its own remaining stars
const REGION_SPREAD_RATE:   float = 2.5e-5   # per-year chance (× colonised fraction) a region seeds a neighbour
## How many hex rings out from the GALACTIC CENTRE the grid covers.  Hexes are 3 753 ly
## centre-to-centre and the disk runs to DISK_MAX_LY = 60 000 ly, so 16 rings reach the rim and
## 17 takes it with one to spare.  Measuring from the centre rather than from Sol covers the
## whole disk in ~900 cells instead of the ~2 100 an off-centre origin needed.
const REGION_GRID_RADIUS:   int   = 17
var _region_grid_cache: Array = []           # cached [{id, center, density}] of non-void cells near Sol
var _gal_basis: Array = []                   # cached galactic basis [gx, gy, gz] (equatorial frame)

## Galactic basis (cached), so the hex tiling lies flat in the galactic plane.
func _gal_axes() -> Array:
	if _gal_basis.is_empty():
		_gal_basis = StarMapPanel.galactic_basis()
	return _gal_basis
## In-flight weapon strikes on star systems: [{target, kind:"laser"|"berserker",
## start_year, end_year}].  Laser pulses cross at light speed; berserkers crawl sub-light.
var interstellar_attacks: Array = []
## Alien presence at stars: star_name → "aggressive" | "peaceful" (the TRUE alignment).
## Seeded per game.  Hidden from the player until its signature is detected — see below.
var star_factions: Dictionary = {}
## Which alien systems' alignments the player has discovered (via colony contact).  A
## detected-but-unvisited system shows "unknown" (yellow); contact reveals red/blue.
var _known_alignments: Dictionary = {}
## Year each alien system began emitting (its signature epoch).  A civilisation is only
## detectable once its light has crossed the distance to Sol: year ≥ _alien_since + dist_ly.
var _alien_since: Dictionary = {}
## Alien systems whose signature the player's telescopes have picked up.  EMPTY at game
## start — every alien civilisation is hidden until detected.  Only these appear on the map.
var _detected_aliens: Dictionary = {}
## Last year _process_aliens ran, so detection/expansion can batch across fast-forwarded time.
var _alien_last_year: float = 2026.0
## Consumable munitions each aggressive system has spent: star → {"missiles": n, "berserkers": n}.
## Subtracted from the age-derived stockpile in _alien_infra_at, so a hostile that empties its
## magazine goes quiet until it manufactures more (its production still ticks up with age).
var _alien_fired: Dictionary = {}
## Detection & expansion tuning.
const ALIEN_DETECT_BASE:  float = 2.0e-3   # per-year detect chance at 1 ly with base optics
const ALIEN_SPREAD_RATE:  float = 3.0e-4   # per-year chance each alien system founds another
const TELESCOPE_BASE_POWER: float = 1.0    # naked-eye/base astronomy every civilisation has

## Hostile aggression: aggressive systems fling relativistic kinetic missiles (RKKVs) at
## human worlds.  Rare per-system, cruising near light-speed, they arrive with only their
## light-travel time as warning and gut whatever they hit — the pressure that makes spreading
## across many systems worthwhile.  incoming_attacks: [{source, target, start_year, end_year}].
var incoming_attacks: Array = []
var _rkkv_notice_year: float = -1.0e18        # last year an "inbound" launch notice fired
var _deterrent_active: bool = false           # are hostiles currently deterred by the player's berserkers?
const ALIEN_AGGRESSION_RATE: float = 9.0e-5   # per aggressive system per year, chance to launch
const DETERRENCE_MULT:      float = 0.12      # aggression multiplier at one berserker (deterrence strength 1)
const DETERRENCE_STACK:     float = 0.82      # each extra unit of arsenal multiplies the aggression further
const DETERRENCE_FLOOR:     float = 0.02      # strongest possible deterrence — never fully stops attacks
const MISSILE_DETER_WEIGHT: float = 0.25      # a stockpiled missile deters a quarter as much as a berserker
const RKKV_BETA:            float = 0.95      # relativistic missile cruise speed (fraction of c)
const RKKV_HOME_SURVIVAL:   float = 0.10      # fraction of population that survives a Sol strike
## Anti-flood caps: bound the concurrent missiles (keeps the array + per-tick work small),
## the number of systems whose count feeds the launch rate (late-game spread fills the map),
## and how often a launch is announced (impacts are always reported, but coalesced per tick).
const RKKV_MAX_INFLIGHT:    int   = 6
const RKKV_ATTACKER_CAP:    float = 4.0
const RKKV_LAUNCH_NOTICE_GAP: float = 150.0   # min game-years between "inbound" notices

## ── Alien infrastructure (deterministic from a system's age) ─────────────────────
## Rather than storing/ticking per-system economies, each civilisation's build-out is a pure
## function of how long it has existed.  The player observes the LIGHT-DELAYED state (what it
## looked like `distance` years ago), resolved in detail only as far as telescopes allow.
const ALIEN_DYSON_YEARS:   float = 2.0e6   # years for a civilisation to complete a Dyson swarm
const ALIEN_TELESCOPE_YEARS: float = 6.0e4 # years per orbital telescope it fields
const ALIEN_LASER_YEARS:   float = 9.0e4   # years per orbital laser (aggressive systems only)
const ALIEN_MISSILE_YEARS:   float = 4.0e4 # years per relativistic missile stockpiled (aggressive)
const ALIEN_BERSERKER_YEARS: float = 1.5e5 # years per berserker seed stockpiled (aggressive)
const INFRA_DETAIL_REACH:  float = 3.0     # telescope-power ÷ (this × ly) → 0..1 resolution

## Player interstellar colonies develop infrastructure over time the same deterministic way alien
## colonies do — a Dyson swarm, orbital telescopes, and defensive lasers, all functions of how
## long the colony has stood.  A touch faster than the aliens (it's the player's own tech).
const COLONY_DYSON_YEARS:        float = 1.5e6   # years to complete a colony Dyson swarm
const COLONY_TELESCOPE_YEARS:    float = 5.0e4   # years per orbital telescope a colony fields
const COLONY_LASER_YEARS:        float = 1.0e5   # years per defensive orbital laser
const COLONY_TELESCOPE_REACH_LY: float = 1500.0  # observation-range reach added per colony telescope
var _infra_probed: Dictionary = {}         # star → true: a probe returned full, current intel

## ── Diplomacy ───────────────────────────────────────────────────────────────────
## Messages crawl at light speed and the reply crawls back, so a round trip is 2×distance
## years.  outgoing_messages: [{target, kind, start_year, end_year}].  _diplo_status: star →
## "contact" | "allied" | "trading" | "war".
var outgoing_messages: Array = []
var _diplo_status: Dictionary = {}
const MSG_ALLY_ENERGY:  float = 5.0e7      # a trade/alliance overture costs a transmitter burst
## Lightweight recon probes to other stars (cheaper than a colony ship); on arrival they
## resolve that system's full current intel.  probe_missions: [{target, start_year, end_year}].
var probe_missions: Array = []
const PROBE_ENERGY_PER_LY: float = 4.0e6   # probe launch cost scales with distance

## Berserker seed launch cost (energy) and cruise speed (fraction of c).
const BERSERKER_ENERGY: float = 5.0e6
const BERSERKER_BETA: float = 0.3
## Year each populated world's clock started — Earth at game start, each colony when
## settled.  Used for the evolutionary divergence timer.
var _colonized_year: Dictionary = {}
## Per-world random threshold (500 000 – 1 000 000 years) before its population
## diverges into a distinct planetary lineage in the evolution tree.
var _split_thresholds: Dictionary = {}
## world → the world it was settled from (its colony ship's origin).  Determines
## which population a lineage descends from.  Earth has no parent.
var _colony_parent: Dictionary = {}
## world → parent world ("" = baseline), recorded when the world diverges.  Doubles
## as the set of worlds that have already diverged; insertion order = lineage order,
## which the save/load path replays to rebuild the tree.
var _variant_parent: Dictionary = {}

## Bodies that have been surveyed: Earth (home) plus any body a Survey probe has been
## sent to.  Keyed by lower-case body name.  Persisted across saves.
var surveyed_planets: Array = ["earth"]

## Per-resource global storage caps (minerals, energy); recomputed whenever
## _prod_dirty is set.  Science is never capped (knowledge needs no tank).
## Default gives Earth's base allocation before the first production tick.
var _cached_storage_caps: Dictionary = {"minerals": 100_000.0, "energy": 100_000.0}

## True once an extinction event fires — blocks further game logic.
var game_over: bool = false
## Set to true (by future interstellar mission logic) to survive the red-giant event.
var has_left_solar_system: bool = false
## User-chosen speed multiplier (slow / normal / fast buttons).
var _user_speed_mult: float = 1.0
## Last year we pushed a stats snapshot (used to throttle in fast mode).
var _last_snapshot_year: int = 2026
## Cumulative number of humans ever born (Population Reference Bureau-style estimate)
## shown on the game-over screen.  Seeded with the ~85 billion who had already lived
## by 1945, then grows with births each tick.
const PEOPLE_EVER_LIVED_1945: float = 8.5e10
var _people_ever_lived: float = PEOPLE_EVER_LIVED_1945

## Life expectancy (years).  A 1945 baseline raised by medical research and lowered by
## pollution from a CO2-emitting power grid.  It governs population turnover — births
## per year ≈ population ÷ life expectancy — so a longer life expectancy means fewer
## new people are born, slowing the growth of the "people ever lived" total.
const BASE_LIFE_EXPECTANCY: float = 52.0
const MIN_LIFE_EXPECTANCY:  float = 20.0
const POLLUTION_LE_PENALTY: float = 6.0   # years lost when the grid is fully CO2-emitting
## Medical-lane research nodes → years of life expectancy each adds when unlocked.
const MEDICAL_RESEARCH: Dictionary = {
	"modern_medicine":                  22.0,   # antibiotics, vaccines, sanitation
	"advanced_biomedical_engineering":   8.0,
	"medical_informatics":               5.0,
	"bioinformatics":                    5.0,
	"genome_engineering":               12.0,   # gene therapy
	"synthetic_biology":                10.0,
	"human_adaptation_systems":         15.0,
	"longevity_engineering":            60.0,   # explicit life-extension
	"synthetic_biosphere_engineering":   8.0,
	"post_biological_transition":     5000.0,   # uploaded minds: effective immortality
}
## Accumulated real seconds since the last autosave.
var _autosave_accum: float = 0.0

## Panel-refresh throttle: the planet-info/build panels refresh at this cadence instead of
## every frame, and build-roster changes coalesce into one rebuild per tick (see _process).
const UI_REFRESH_SEC: float = 0.25
var _ui_refresh_accum: float = 0.0
var _build_ui_dirty: bool = false

# ── Game events ───────────────────────────────────────────────────────────────
## IDs of GameEvents.EVENTS that have already fired — prevents re-triggering.
var _fired_events: Array = []
## Maps event ID → game year it fired; used to place timeline cards correctly on load.
var _fired_event_years: Dictionary = {}
## Queue of event dicts waiting to be shown as notifications.
var _pending_event_notifications: Array = []

## ── Asteroid impacts ──────────────────────────────────────────────────────────
## Major impacts are scheduled (not rolled per frame): each strike sets the game
## year of the next, so deep fast-forward can't spam them.  A real-time cooldown
## further caps how often one can fire while skipping eons.
const IMPACT_GAP_MIN: int = 15_000   # min game-years between impacts
const IMPACT_GAP_MAX: int = 100_000  # max game-years between impacts
const IMPACT_REAL_COOLDOWN_MS: int = 5_000   # never more than one per 5 real seconds
var _next_impact_year: int = 0
var _impact_cooldown_ms: int = 0     # Time.get_ticks_msec() floor before next impact

## ── Engineered pandemics ──────────────────────────────────────────────────────
## A scheduled roll whose probability rises with bioengineering capability and AI
## (which accelerates pathogen design), is amplified by a population packed onto few
## worlds, and worsened by poor public health.  Gated on having any bioengineering
## research — there is no engineered-pandemic risk before the capability exists.
const PANDEMIC_GAP_MIN: int = 800
const PANDEMIC_GAP_MAX: int = 2_500
const PANDEMIC_BASE: float  = 0.03
const PANDEMIC_BIOTECH: Array = [
	"advanced_biomedical_engineering", "bioinformatics", "genome_engineering", "synthetic_biology",
]
var _next_pandemic_year: int = 0
var _pandemic_cooldown_ms: int = 0

## ── Nuclear war ───────────────────────────────────────────────────────────────
## A tempting gamble: military spending accelerates research (the arms race drove the
## space race), but while humanity is single-world it stokes geopolitical tension, and
## a sustained high-military / high-tension standoff compounds the chance of a nuclear
## exchange.  Tension — and the risk — collapse as you spread off-world, so the player
## races to escape the cradle before the gamble catches up with them.
const NUCLEAR_GAP_MIN: int = 25
const NUCLEAR_GAP_MAX: int = 120
const NUCLEAR_BASE: float = 0.04
const NUCLEAR_STRAIN_DECAY: float = 0.6   # how much standoff pressure carries between checks
## Civilian fission and weapons share a fuel cycle: each Nuclear Plant adds latent
## arsenal (fissile material + expertise) to the war-risk "means" term.  The effect
## saturates — this is the plant count at which proliferation reaches half its ceiling.
const NUCLEAR_PROLIF_HALF: float = 12.0
var _next_nuclear_year: int = 0
var _nuclear_cooldown_ms: int = 0
var _arms_strain: float = 0.0             # compounding pressure from a sustained arms race

## The CanvasLayer that hosts notification cards.
var _event_notif_layer: CanvasLayer = null
## VBoxContainer inside the layer where cards are stacked.
var _event_notif_vbox: VBoxContainer = null

# ── Production cache ──────────────────────────────────────────────────────────
## True whenever buildings, research, or policies have changed and the cached
## production totals must be recomputed before next use.
var _prod_dirty: bool = true
var _cached_compute: float = 0.0
var _cached_prod: Dictionary = {"science": 0.0, "minerals": 0.0, "energy": 0.0}
## Building-derived raw sums, recomputed ONLY when the building roster changes (_prod_dirty).
## The per-frame combine (population + boosts) reads these so it never re-loops the buildings —
## that per-building sweep every frame was what made a heavily-built game stutter.
var _bld_compute:  float = 0.0
var _bld_minerals: float = 0.0
var _bld_energy:   float = 0.0   # ALWAYS-ON energy: fuel-free buildings + swarm (pre-boost, pre-thermal)
var _bld_radiator: float = 0.0

# ── Fuel-burning plants ───────────────────────────────────────────────────────
## Buildings with a "consumption" block draw fuel from their world's inventory each game-day.
## Their energy is held apart from _bld_energy so it can be scaled by how well they were
## actually fed this tick: a starved plant produces less power and vents less CO₂.
## Demand is tracked per FUEL (so plants sharing a fuel compete for one pool) and output is
## tracked per BUILDING TYPE (so an exhausted fuel idles only the plants that burn it — running
## out of oil must not shut down coal plants standing beside them).
var _cached_planet_fuel:   Dictionary = {}   # planet → { fuel → total grams/game-day demanded }
var _cached_planet_plants: Dictionary = {}   # planet → { building → {"energy": W, "fuel": {f: rate}} }
var _fuel_factor:          Dictionary = {}   # planet → { building → 0..1 share of its fuel met }
var _live_fossil_energy:   float = 0.0       # fuel-burning energy actually running this tick

# ── Manufacturing Capacity (MC) ───────────────────────────────────────────────
## Industrial throughput is per-planet: each world can only run so much manufacturing
## at once.  Its capacity = a manual base (cottage industry) + the factories built on
## it, multiplied by automation, then scaled by how well the civilisation's one finite
## labour force can staff all that capacity.  See _process_production.
## A "work unit" is material throughput, so manufacturing capacity is a MASS-like quantity and
## rides Units.MASS_SCALE with everything else.  Without this the rescale left capacity a million
## times too small for the throughput it gates, and every production line ran at ~0.04%.
const BASE_MC: float       = 5000.0 * Units.MASS_SCALE   # manual industry every world has, work/day
## Labour is people per work-unit, so it scales INVERSELY — the same population staffs the same
## real industry, just expressed in bigger units.
const LABOR_PER_CAP: float = 2000.0 / Units.MASS_SCALE
## planet → Σ factory mc_capacity, refreshed in _recompute_production_cache.
var _cached_planet_built_mc: Dictionary = {}
## planet → roster-derived sums the per-frame passes read instead of re-walking every building:
## { mine, atmo, co2_base, co2_fuel{}, e_total, e_dirty, e_fuel_dirty{} }.  Rebuilt only when
## the roster changes — at ~10 000 structures, doing this per frame was the dominant tick cost.
var _cached_planet_stats: Dictionary = {}
## Civilisation-wide roster sums, likewise refreshed only on a roster change.
var _cached_detection: float = 0.0
var _cached_nuclear:   float = 0.0
## Total running cost (J/game-day) of every building currently switched on.
var _bld_upkeep: float = 0.0
## planet → { building → standing count }, tallied in the roster pass and reused by the UI.
var _cached_planet_counts: Dictionary = {}

## Nothing runs for free: a building draws maintenance power in proportion to how much structure
## it is — 0.02 J per game-day per gram of the bill of materials.  Derived rather than authored,
## so every building (and every generated tier) carries a running cost automatically and the
## whole system has one number to tune.  This is what gives the active-count slider its teeth:
## idle a mine and you stop paying for it.
const UPKEEP_J_PER_GRAM: float = 0.02
## ...weighted by what the structure actually does with that mass.  A warehouse mostly sits
## there; a mine runs heavy machinery around the clock.  Mass alone put the storage fleet's
## running cost above the entire power fleet's, which is plainly wrong.  Unlisted = 1.0.
const UPKEEP_CATEGORY_MULT: Dictionary = {
	"storage":     0.10,   # passive volume — lighting, pumps, inventory control
	"power":       0.50,   # parasitic station load
	"observation": 0.30,
	"habitation":  0.30,
	"support":     0.30,
	"defense":     0.30,
}

## planet → { building → how many are switched on }.  Absent means all of them.
var active_buildings: Dictionary = {}

## Switch `count` of `building_name` on at `planet_name` (clamped to what is standing).
func set_active_count(planet_name: String, building_name: String, count: int) -> void:
	var standing: int = _count_building(planet_name, building_name)
	var m: Dictionary = active_buildings.get(planet_name, {})
	if count >= standing:
		m.erase(building_name)          # "all of them" is the absence of an entry
	else:
		m[building_name] = maxi(0, count)
	if m.is_empty():
		active_buildings.erase(planet_name)
	else:
		active_buildings[planet_name] = m
	_mark_prod_dirty()

## How many of `building_name` are switched on at `planet_name`.
func active_count(planet_name: String, building_name: String) -> int:
	var standing: int = _count_building(planet_name, building_name)
	return clampi(int((active_buildings.get(planet_name, {}) as Dictionary)
		.get(building_name, standing)), 0, standing)
## planet → { "capacity": work/day, "demand": work/day } from the last production tick,
## pushed to the ProductionPanel for its capacity readout.
var _last_mc_state: Dictionary = {}

## Manufacturing capacity a world has left after its running recipes — construction draws
## on this, so factories and building sites compete for one finite industrial base.
func _planet_free_mc(planet: String) -> float:
	var cap: float = _planet_mc_capacity(planet)
	var demand: float = float((_last_mc_state.get(planet, {}) as Dictionary).get("demand", 0.0))
	return maxf(0.0, cap - demand)

# ── Waste heat / thermodynamics ───────────────────────────────────────────────
## Every watt the civilisation uses ends as heat that must be radiated to the cold
## universe.  Radiating capacity is a manual/biosphere base plus Thermal Radiators, and
## rises as cosmic expansion cools the sink.  Power drawn beyond it is curtailed (you can't
## use energy you can't shed), so megastructures like the Dyson swarm demand radiators.
const BASE_RADIATOR_W: float   = 8.0e12    # heat the base grid+biosphere sheds unaided (8 TW)
const CMB_TEMP_2026:   float   = 2.725     # K, universe background temperature at epoch 2026
const THERMAL_EFF_FLOOR: float = 0.30      # usable-power floor even when badly over capacity
const DAY_SECONDS:     float   = 86_400.0  # simulated seconds per game-day (for J = W·s)
## Cumulative entropy (J/K) exported to the universe — a counter that only ever grows.
var entropy_exported: float = 0.0
## Radiating capacity (W) and load/capacity ratio from the last production recompute.
var _cached_radiator_cap: float = BASE_RADIATOR_W
var _thermal_ratio: float = 0.0            # raw power draw ÷ radiating capacity
var _heat_alerted: bool = false            # so the overheating notice fires once per episode
var _labor_alerted: bool = false           # likewise for the labour-shortage notice

## Accumulated mass of each crust compound extracted by all mines, in grams.
var compound_inventory: Dictionary = {}

## Grams of CO₂ vented into each planet's atmosphere by combustion power plants,
## on top of its natural baseline.  planet_name → grams.
var atmospheric_co2: Dictionary = {}

## Active manufacturing jobs from the Production panel.
## Each entry: { "id": int, "recipe": String, "planet": String, "rate": float }
var _production_jobs: Array = []

## Standing automation rules from the Automation panel — build/launch orders the game
## carries out on its own each frame.  See _process_automation.
var _automation_rules: Array = []

# ── Building-def lookup cache ─────────────────────────────────────────────────
## name → BuildingData entry.  Populated once at startup so every call to
## _find_building_def() is O(1) instead of O(n).
var _bdef_cache: Dictionary = {}
## name → RecipeData entry, same idea for _find_recipe_by_name (hot in _process_production).
var _recipe_cache: Dictionary = {}

@onready var science_label: Label = $main_ui/VBoxContainer3/HBoxContainer/ScienceLabel
@onready var research_ui: Control = $main_ui/VBoxContainer3/HBoxContainer2/research_tree
## Per-resource top-bar readout boxes: key → { "value": Label, "rate": Label }.
var _res_boxes: Dictionary = {}
@onready var time_label: Label = $main_ui/VBoxContainer3/HBoxContainer/TimeBox/time
@onready var statistics_page: Control = $main_ui/VBoxContainer3/HBoxContainer2/StatisticsPage
@onready var planet_info_page: PanelContainer = $main_ui/PlanetInfoPage
@onready var build_panel: PanelContainer = $main_ui/BuildPanel
@onready var launch_panel: PanelContainer = $main_ui/LaunchPanel
## Merged planet panel: the info page, build panel, and population stats become tabs of one
## TabContainer (built in _setup_planet_tabs).  Game shows/hides the wrapper; tabs switch views.
var _planet_tabs: TabContainer = null
var _population_page: Control = null
var _inventory_page: Control = null
var _extraction_page: Control = null
var _manufacturing_tab_index: int = -1   # index of the Manufacturing tab within _planet_tabs
@onready var sidebar: SidebarControl     = $main_ui/VBoxContainer3/HBoxContainer2
@onready var launches_button: Button     = $main_ui/VBoxContainer3/HBoxContainer2/sidebar/launches
@onready var timeline_panel: Control    = $main_ui/VBoxContainer3/HBoxContainer2/TimelinePanel
@onready var politics_page: Control     = $main_ui/VBoxContainer3/HBoxContainer2/PoliticsPage
@onready var evolution_ui: Control      = $main_ui/VBoxContainer3/HBoxContainer2/EvolutionTreeUI
## Template satellite node kept in the scene but hidden; arc satellites are
## created via Satellite.new() so this is only used to keep the scene valid.
@onready var sattelite: Satellite = $WorldRoot/Planets/earth/Node3D
@onready var game_over_screen = $GameOverScreen
@onready var settings_menu = $SettingsMenu
@onready var production_panel: PanelContainer = $main_ui/ProductionPanel

## Plays once when an extinction event ends the game.

func is_leap(y: int) -> bool:
	return (y % 4 == 0 and y % 100 != 0) or (y % 400 == 0)

func _input(event: InputEvent) -> void:
	if game_over:
		return   # game over screen handles its own input
	if event.is_action_pressed("escape"):
		_prepare_snap_year()
		SolarSystem.toggle_ui_pause()
		get_tree().paused = SolarSystem.ui_paused

	if event.is_action_pressed("pause"):
		_prepare_snap_year()
		SolarSystem.toggle_pause()
		get_viewport().set_input_as_handled()

## Choose the year the frozen planets snap to when a pause reveals them.  Anchored
## to the planet the player is currently viewing so that body keeps its exact
## position (no camera jump); the rest fall into their relative places for that year.
func _prepare_snap_year() -> void:
	if SolarSystem.solar_system_active:
		SolarSystem.snap_year = float(year)
		return
	# Anchor to the planet being viewed.  Until the player picks one, current_planet
	# is "" but the camera still defaults to Earth (camera_pivot.gd), so fall back to
	# Earth here too — otherwise the homeworld jumps on the first post-cutoff pause.
	var anchor: String = current_planet if current_planet != "" else "earth"
	var p := get_node_or_null("WorldRoot/Planets/" + anchor) as Planet
	SolarSystem.snap_year = p.compute_anchor_year() if p else float(year)

func start_new_game() -> void:
	ResearchTree.load_tree(ResearchTreeData.build())
	ResearchTree.resources = {
		"science": 0.0,
		"minerals": 50.0 * Units.MASS_SCALE,
		"energy": 20.0
	}

	year = 1945
	month = 0
	day = 0
	stats["current_population"] = 2_300_000_000.0   # world population in 1945
	world_pop = {"earth": 2_300_000_000.0}          # per-world population; only Earth at the start
	_engulfed_planets = {}                          # no planets destroyed yet
	time_accum = 0.0
	active_launches = []
	_next_launch_id = 1
	solar_satellites_deployed = 0
	_pending_swarm = 0
	colonized_planets = []
	colonized_stars = []
	interstellar_missions = []
	_colony_year = {}
	_vn_enabled = false
	_vn_milestone_idx = 0
	_regions = {}
	_region_last_year = float(year)
	interstellar_attacks = []
	incoming_attacks = []
	outgoing_messages = []
	probe_missions = []
	_diplo_status = {}
	_infra_probed = {}
	_rkkv_notice_year = -1.0e18
	_deterrent_active = false
	_seed_star_factions()
	# Earth's population starts diverging from the 1945 baseline immediately; after
	# its random threshold it becomes "H. sapiens terran".
	_colonized_year   = {"earth": year}
	_split_thresholds = {"earth": int(randf_range(500_000.0, 1_000_000.0))}
	_colony_parent    = {}
	_variant_parent   = {}
	compound_inventory = {}
	atmospheric_co2 = {}
	# Earth's 1945 starting infrastructure: a fleet of regional power stations
	# (10 biomass + 10 coal + 5 oil ≈ 3.17 TW, a 40/40/20 split), fuel/ore mines,
	# and a research lab.  Demolishable as the player modernises, except the
	# Biomass Burner (min 1) which guarantees baseline power.
	# Catalogue entries are single buildings now, so the historical fleet is expressed in real
	# station counts: the same 3.3 TW as before, just as ~5 500 power stations rather than 25
	# abstractions.  Counts are scaled by the same factor BuildingData divided each entry by,
	# so the starting grid is unchanged to the watt.
	var earth_buildings: Array = []
	# 2 000 mines ≈ 20 Mt/day of extraction against the fossil fleet's real 15.9 Mt/day
	# coal-and-oil habit needs, so the opening is a live allocation problem in the Extraction tab
	# rather than an immediate shortfall: point too little at coal and the grid starts eating
	# its reserve, point it all at coal and nothing is left for construction materials.
	for _i in range(2000): earth_buildings.append("Mine")
	# Depots scale with the mines they bank for; at 15 Mt/day a handful would cap out in hours
	# and the Matter readout would sit pinned at its ceiling from the first minute.
	for _i in range(2500): earth_buildings.append("Matter Depot")
	# Pumped storage — the only grid-scale energy buffer that actually existed in 1945, and the
	# reason the civilisation can bank a launch campaign's worth of power instead of spending
	# every Joule the moment it is generated.
	for _i in range(6): earth_buildings.append("Pumped Hydro Storage")
	for spec: Array in [["Biomass Burner", 10], ["Coal Plant", 10], ["Oil Plant", 5]]:
		var bname: String = str(spec[0])
		for _i in range(int(spec[1]) * BuildingData.units(bname)):
			earth_buildings.append(bname)
	earth_buildings.append("Research Lab")
	planet_buildings = {"earth": earth_buildings}
	# A starter buffer, not a reserve: roughly 90 days of the fossil fleet's full burn — about 1 %
	# of the stockpile this replaced.  Long enough to notice the grid draining and find the
	# Extraction tab, short enough that the answer is still "point the mines at coal" rather than
	# "coast for two decades".  Once it runs dry the stations burn only what is dug that day, and
	# the fuel-free Biomass Burners hold the floor under the grid.
	_add_stockpile("Coal",    1.1e15, "earth")   # ~90 days for 2 000 coal stations
	_add_stockpile("FuelOil", 3.0e14, "earth")   # ~90 days for 1 500 oil stations
	_add_stockpile("Oil",     1.0e13, "earth")   # crude for the still to work while mining ramps
	build_queue = {}   # nothing under construction at the start
	# The 1945 mining industry is already pointed at what the grid burns, not at whatever the
	# ground happens to hold: nearly all of it goes to coal and oil, because that is what 3 500
	# fossil stations demand.  Coal gets its full requirement; oil runs a touch under, so its
	# stations sit at ~98 % and the buffer drains very slowly.  The half-percent left over is
	# still ~60× what the seven starting production lines actually consume — ore is not the
	# constraint here, fuel is.  Reallocating this is the central early decision: every point
	# taken off coal is a point of the grid going dark, and every point left on it is uranium,
	# copper and construction ore you are not digging.
	extraction_focus = {"earth": {
		"Coal":   0.6250,   # 2 000 stations at 6.25e9 g/day each
		"Oil":    0.3700,   # crude for the still; 45 % of the barrel comes out as fuel oil
		"Fe2O3":  0.0020,
		"CaCO3":  0.0010,
		"SiO2":   0.0010,
		"FeS2":   0.0005,
		"CuFeS2": 0.0003,
		"Al2O3":  0.0002,
	}}
	active_buildings = {}   # everything the player owns starts switched on
	entropy_exported = 0.0
	_heat_alerted = false
	_labor_alerted = false
	# Starter production: a working industrial base in the production menu —
	# quicklime → concrete, the foundation for expanding the operation.
	# Rates are normalised (1× = 1 g of product/day), so these read directly as grams:
	# 9 g/day of quicklime feeding 8 g/day of concrete — the same throughput as before.
	# A 1945 civilisation already has a metals industry running — it is not waiting for the
	# player to switch on iron.  Rates are grams of product per day (1× = 1 g), sized so the
	# whole slate draws well under one world's manufacturing capacity and inside what 2 000
	# mines yield at default (crustal-abundance) extraction.  Iron feeds Steel; Lime feeds
	# Concrete; both metals feed the building bills of materials.
	_production_jobs = [
		{"id": 1, "recipe": "Lime Production",     "planet": "earth", "rate": 3.0e8},
		{"id": 2, "recipe": "Concrete Production", "planet": "earth", "rate": 2.5e8},
		{"id": 3, "recipe": "Iron Smelting",       "planet": "earth", "rate": 3.0e8},
		{"id": 4, "recipe": "Pyrite Smelting",     "planet": "earth", "rate": 1.0e8},
		# No Wüstite line: it reduces FeO, which Earth's crust doesn't carry.  The recipe stays
		# available for when the player is mining Venus, where FeO is the dominant iron ore.
		{"id": 5, "recipe": "Steel Making",        "planet": "earth", "rate": 2.5e8},
		{"id": 6, "recipe": "Copper Smelting",     "planet": "earth", "rate": 5.0e7},
		{"id": 7, "recipe": "Oil Refining",        "planet": "earth", "rate": 1.0e8},
	]
	if production_panel:
		production_panel.load_jobs(_production_jobs)
	_automation_rules = []
	if sidebar and sidebar.automation_panel:
		sidebar.automation_panel.load_rules([])
	policies = PoliticsData.default_state()
	game_over              = false
	has_left_solar_system  = false
	_user_speed_mult       = settings_menu.get_default_speed_mult() if settings_menu else 1.0
	_autosave_accum        = 0.0
	_last_snapshot_year    = 1945
	_people_ever_lived     = PEOPLE_EVER_LIVED_1945
	_fired_events          = []
	_fired_event_years     = {}
	_pending_event_notifications = []
	_next_impact_year      = year + randi_range(IMPACT_GAP_MIN, IMPACT_GAP_MAX)
	_impact_cooldown_ms    = 0
	_next_pandemic_year    = year + randi_range(PANDEMIC_GAP_MIN, PANDEMIC_GAP_MAX)
	_pandemic_cooldown_ms  = 0
	_next_nuclear_year     = year + randi_range(NUCLEAR_GAP_MIN, NUCLEAR_GAP_MAX)
	_nuclear_cooldown_ms   = 0
	_arms_strain           = 0.0
	surveyed_planets       = ["earth"]   # home world is always accessible
	_mark_prod_dirty()
	_cached_storage_caps = _compute_storage_caps()   # set caps before first _process tick
	SolarSystem.paused     = true
	SolarSystem.set_solar_system_active(true)
	_update_timescale()
	if game_over_screen:
		game_over_screen.visible = false
	if evolution_ui:
		evolution_ui.reset_to_baseline()
	if statistics_page:
		statistics_page.clear_history()
		_refresh_stats()
		statistics_page.push_snapshot(year, stats)

func _ready() -> void:
	_init_building_cache()

	# Developer console (toggle with the backtick key) — can trigger extinction events.
	var console := DevConsole.new()
	add_child(console)
	console.setup(self)

	# Endgame music player — keeps playing while the game-over screen is up, so it
	# must ignore the tree pause that trigger_game_over() sets.
	if not ResearchTree.research_completed.is_connected(_on_research_completed):
		ResearchTree.research_completed.connect(_on_research_completed)

	build_panel.build_requested.connect(_on_build_requested)
	build_panel.demolish_requested.connect(_on_demolish_requested)
	build_panel.upgrade_requested.connect(_on_upgrade_requested)
	build_panel.active_changed.connect(_on_active_changed)
	launch_panel.launch_requested.connect(_on_launch_requested)
	production_panel.production_changed.connect(_on_production_changed)
	if sidebar and sidebar.automation_panel:
		sidebar.automation_panel.automation_changed.connect(_on_automation_changed)
		sidebar.automation_panel.vn_colonization_changed.connect(_on_vn_colonization_changed)
	if sidebar and sidebar.star_map:
		sidebar.star_map.colonize_requested.connect(_on_colonize_requested)
		sidebar.star_map.laser_requested.connect(_on_laser_requested)
		sidebar.star_map.berserker_requested.connect(_on_berserker_requested)
		sidebar.star_map.missile_requested.connect(_on_missile_requested)
		sidebar.star_map.probe_requested.connect(_on_probe_requested)
		sidebar.star_map.message_requested.connect(_on_message_requested)
	politics_page.policy_changed.connect(_on_policy_changed)
	game_over_screen.restart_requested.connect(_on_restart_requested)
	settings_menu.closed.connect(_on_settings_closed)

	_setup_event_notifications()
	_setup_bar_backgrounds()
	_setup_resource_boxes()
	_setup_realtime_clock()
	_setup_body_picker()
	_setup_planet_tabs()

	if GameSession.should_load_on_start and GameSession.current_save_path != "":
		load_game(GameSession.current_save_path)
	else:
		start_new_game()

	politics_page.load_policies(policies)
	_check_extinction_events()   # hides planets immediately if year ≥ ORBIT_FREEZE_YEAR
	_check_population_splits()
	production_panel.refresh_recipes(_completed_research_map())
	_refresh_launch_access()   # hide Launches until Early Rocketry is researched
	_refresh_automation_access()   # hide Automation until Industrial AI is researched
	_refresh_stats()
	_update_hud()
	_setup_satellite()

func _setup_satellite() -> void:
	sattelite.visible = false

# ── Planet-bar gating ─────────────────────────────────────────────────────────

## Cache the planet-bar buttons by body name (run once in _ready).
## Backing panels drawn behind the top bar and the sidebar button strip (plain HBox/
## VBox containers can't take a background stylebox), so those bars read clearly over
## the 3D scene.  They follow the bars' rects (set on layout + viewport resize).
var _top_bar_bg:  Panel = null
var _side_bar_bg: Panel = null
## Real-world clock shown on the right of the top bar.
var _realtime_label: Label = null

## Build one boxed readout per top-bar resource — a title over a current-amount line over the
## accumulation (rate) line — replacing the old single packed label.  Populated by _update_hud.
func _setup_resource_boxes() -> void:
	var top_bar := get_node_or_null("main_ui/VBoxContainer3/HBoxContainer") as HBoxContainer
	if top_bar == null:
		return
	if science_label:
		science_label.hide()   # its readout is now split across the per-resource boxes below
	for spec: Array in [["minerals", "Matter"], ["energy", "Energy"],
			["compute", "Compute"], ["heat", "Heat"]]:
		top_bar.add_child(_make_res_box(str(spec[0]), str(spec[1])))

## One resource box: a PanelContainer holding a dim title, the current amount, and (underneath)
## its accumulation rate.  Stores the value/rate labels in _res_boxes[key] for _update_hud.
func _make_res_box(key: String, title: String) -> PanelContainer:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(132, 0)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_bottom", 2)
	box.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	margin.add_child(col)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 10)
	t.add_theme_color_override("font_color", Color(0.62, 0.70, 0.84))
	col.add_child(t)
	var value := Label.new()
	value.text = "—"
	value.add_theme_font_size_override("font_size", 13)
	col.add_child(value)
	var rate := Label.new()
	rate.text = ""
	rate.add_theme_font_size_override("font_size", 10)
	rate.add_theme_color_override("font_color", Color(0.45, 0.85, 0.55))
	col.add_child(rate)
	_res_boxes[key] = {"value": value, "rate": rate}
	return box

## Push text into a resource box; an empty rate hides the accumulation line (for rate-only or
## instantaneous readouts like Compute and Heat).
func _set_res_box(key: String, value_text: String, rate_text: String) -> void:
	if not _res_boxes.has(key):
		return
	var b: Dictionary = _res_boxes[key]
	(b["value"] as Label).text = value_text
	var rl: Label = b["rate"]
	rl.text = rate_text
	rl.visible = rate_text != ""

## Add a wall-clock readout to the right end of the top bar (updated in _process).
func _setup_realtime_clock() -> void:
	var top_bar := get_node_or_null("main_ui/VBoxContainer3/HBoxContainer") as Control
	if top_bar == null:
		return
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL   # pushes the clock to the right
	top_bar.add_child(spacer)
	_realtime_label = Label.new()
	_realtime_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_realtime_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_realtime_label.custom_minimum_size = Vector2(96, 0)
	_realtime_label.add_theme_color_override("font_color", Color(0.8, 0.86, 0.95))
	top_bar.add_child(_realtime_label)
	# Small trailing spacer so the clock sits a little left of the top-bar's right edge.
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(8, 0)
	top_bar.add_child(pad)
	_update_realtime_clock()

func _update_realtime_clock() -> void:
	if _realtime_label == null:
		return
	var t: Dictionary = Time.get_time_dict_from_system()   # local {hour, minute, second}
	var h24: int = int(t.get("hour", 0))
	var minute: int = int(t.get("minute", 0))
	var suffix: String = "AM" if h24 < 12 else "PM"
	var h12: int = h24 % 12
	if h12 == 0:
		h12 = 12                                          # midnight/noon read as 12, not 0
	_realtime_label.text = "%d:%02d %s" % [h12, minute, suffix]

## Overlay that highlights the planet/moon/sun under the cursor with a white ring and
## focuses the camera on it when clicked.  Sits behind the UI so panels occlude the ring.
func _setup_body_picker() -> void:
	var picker: Control = load("res://body_picker.gd").new()
	$main_ui.add_child(picker)
	$main_ui.move_child(picker, 0)   # behind the bars/panels (they draw over it)

## Fold the planet-info page, build panel, and a new population-stats page into one tabbed
## panel.  The two existing scene panels are reparented as tab pages (their references stay
## valid); the TabContainer manages which is shown, and Game shows/hides the whole wrapper.
func _setup_planet_tabs() -> void:
	var tabs := TabContainer.new()
	tabs.name = "PlanetTabs"
	# Top-right, below the top bar (where the info page used to sit), sized for the build list.
	tabs.anchor_left = 1.0
	tabs.anchor_right = 1.0
	tabs.offset_left = -728.0
	tabs.offset_right = -8.0
	tabs.offset_top = 52.0
	tabs.offset_bottom = 732.0
	tabs.visible = false

	planet_info_page.get_parent().remove_child(planet_info_page)
	planet_info_page.name = "Info"
	tabs.add_child(planet_info_page)

	build_panel.get_parent().remove_child(build_panel)
	build_panel.name = "Infrastructure"
	tabs.add_child(build_panel)

	_population_page = load("res://PopulationStatsPage.gd").new()
	_population_page.name = "Population"
	tabs.add_child(_population_page)

	_inventory_page = load("res://InventoryPage.gd").new()
	_inventory_page.name = "Inventory"
	_inventory_page.dump_requested.connect(_on_inventory_dump)
	tabs.add_child(_inventory_page)

	_extraction_page = load("res://ExtractionPage.gd").new()
	_extraction_page.name = "Extraction"
	_extraction_page.focus_changed.connect(_on_extraction_focus_changed)
	tabs.add_child(_extraction_page)

	# Manufacturing is now a per-body tab (no in-panel planet picker): it targets whichever
	# planet or moon the tabs are showing.
	production_panel.get_parent().remove_child(production_panel)
	production_panel.name = "Manufacturing"
	tabs.add_child(production_panel)
	_manufacturing_tab_index = production_panel.get_index()

	$main_ui.add_child(tabs)
	_planet_tabs = tabs
	tabs.tab_changed.connect(func(_i): _refresh_planet_tabs())
	# Swallow scroll-wheel over the tab bar so it doesn't zoom the 3-D camera behind the panel
	# (each content page already does the same in its own _gui_input).
	tabs.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index in [
				MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
				MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			tabs.accept_event())
	if sidebar:
		sidebar.planet_tabs = tabs   # so hide_all() can close the whole wrapper

## Repopulate whichever planet tab is currently active (called on select + tab switch).
func _refresh_planet_tabs() -> void:
	if _planet_tabs == null or not _planet_tabs.visible or current_planet == "":
		return
	if planet_info_page.visible:
		planet_info_page.set_planet_info(get_planet_data(current_planet))
	if build_panel.visible:
		build_panel.set_planet(current_planet, _get_catalog_for_display())
	if _population_page and _population_page.visible:
		_population_page.set_stats(_population_stats(current_planet))
	if _inventory_page and _inventory_page.visible:
		_inventory_page.set_inventory(current_planet, get_planet_data(current_planet))
	if production_panel and production_panel.visible:
		production_panel.set_planet(current_planet)
		production_panel.set_mc_state(_last_mc_state)

## Population figures for the stats tab.
## Population stats for a SPECIFIC body.  The species population is one global pool, so it's
## distributed across inhabited worlds by their carrying-capacity share (uninhabited bodies —
## the Sun, un-colonised planets, moons — show zero).  Growth/life/happiness are species-wide.
## Per-world population stats for the population tab.  Each inhabited world tracks its OWN
## population (world_pop) growing toward its OWN carrying capacity; growth/happiness are
## computed from that world's headroom.  Uninhabited bodies report zero.
func _population_stats(body: String) -> Dictionary:
	var k: float = _world_capacity(body)
	var inhabited: bool = _is_inhabited(body)
	var pop: float = float(world_pop.get(body, 0.0)) if inhabited else 0.0
	return {
		"population":      pop,
		"capacity":        k,
		"life_expectancy": _life_expectancy(),
		"growth":          _growth_rate_pct(pop, k),
		"happiness":       _happiness(pop, k),
		"inhabited":       inhabited,
	}

## Every world that currently holds people: home + in-system colonies + interstellar colonies,
## minus any planet the Sun has swallowed.
func _inhabited_worlds() -> Array:
	var out: Array = []
	if not _engulfed_planets.has("earth"):
		out.append("earth")
	for cp in colonized_planets:
		if not _engulfed_planets.has(str(cp)):
			out.append(str(cp))
	for cs in colonized_stars:
		out.append(str(cs))   # interstellar — never engulfed by Sol
	return out

## True if `body` is an inhabited world (has a tracked population) and not Sun-destroyed.
func _is_inhabited(body: String) -> bool:
	if _engulfed_planets.has(body):
		return false
	return body == "earth" or colonized_planets.has(body) or colonized_stars.has(body)

## Sum of all worlds' populations — the global headcount used everywhere `current_population`
## is read (compute rate, labour, HUD…).
func _total_population() -> float:
	var t: float = 0.0
	for w: String in world_pop:
		t += float(world_pop[w])
	return t

## Carrying capacity of a SINGLE world.  Earth = its (climate-limited) biosphere; an interstellar
## colony = a self-sufficient habitat; an in-system colony = a habitat limited by the life support
## (energy + minerals) its OWN infrastructure produces.
func _world_capacity(world: String) -> float:
	var policy: float = PoliticsData.pop_capacity_mult(policies)
	if world == "earth":
		return EARTH_NATURAL_K * _climate_capacity_factor() * policy
	if colonized_stars.has(world):
		return COLONY_HABITAT_K * policy   # interstellar colony: self-sufficient
	if colonized_planets.has(world):
		# In-system colony: the full habitat, scaled by how well its OWN power grid supplies
		# life support (floored so a fledgling colony survives; more power just fills it out).
		var supply: float = clampf(_planet_power(world) / COLONY_FULL_POWER, 0.05, 1.0)
		return COLONY_HABITAT_K * policy * supply
	return 0.0

## A single planet's own energy output (W) from its buildings, with tech/policy multipliers.
func _planet_power(planet: String) -> float:
	var energy: float = 0.0
	for b_name: String in planet_buildings.get(planet, []):
		energy += float((_bdef_cache.get(b_name, {}) as Dictionary).get("production", {}).get("energy", 0.0))
	return energy * (1.0 + ResearchTree.get_boost("energy_production")) * _policy_energy_mult()

## Instantaneous net growth rate (%/yr) for a world at population `pop` and capacity `k`.
func _growth_rate_pct(pop: float, k: float) -> float:
	if k <= 0.0:
		return 0.0
	var r: float = POP_GROWTH_PER_YEAR * PoliticsData.pop_growth_mult(policies)
	return r * (1.0 - pop / k) * 100.0

## Happiness (0–100%) for a world with population `pop` and capacity `k`: comfortable with
## slack below capacity and good life expectancy; dragged down by crowding and existential risk.
func _happiness(pop: float, k: float) -> float:
	var strain: float = pop / maxf(k, 1.0)
	var comfort: float = clampf(1.0 - maxf(0.0, strain - 0.9) * 1.5, 0.0, 1.0)
	var life: float = clampf(_life_expectancy() / 85.0, 0.0, 1.0)
	var risk: float = clampf(PoliticsData.existential_risk(policies), 0.0, 1.0)
	return clampf((0.55 * comfort + 0.45 * life) * (1.0 - 0.4 * risk), 0.0, 1.0) * 100.0

func _setup_bar_backgrounds() -> void:
	var canvas := $main_ui
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.10, 1.0)
	style.set_corner_radius_all(4)
	style.set_border_width_all(1)
	style.border_color = Color(0.35, 0.45, 0.65, 1.0)   # opaque border

	_top_bar_bg = Panel.new()
	_top_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_bar_bg.add_theme_stylebox_override("panel", style)
	canvas.add_child(_top_bar_bg)
	canvas.move_child(_top_bar_bg, 0)   # behind the bars (and everything else in main_ui)

	_side_bar_bg = Panel.new()
	_side_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_side_bar_bg.add_theme_stylebox_override("panel", style.duplicate())
	canvas.add_child(_side_bar_bg)
	canvas.move_child(_side_bar_bg, 0)

	var top_bar := get_node_or_null("main_ui/VBoxContainer3/HBoxContainer") as Control
	var side_strip := get_node_or_null("main_ui/VBoxContainer3/HBoxContainer2/sidebar") as Control
	if top_bar:
		top_bar.resized.connect(_layout_bar_backgrounds)
	if side_strip:
		side_strip.resized.connect(_layout_bar_backgrounds)
	get_viewport().size_changed.connect(_layout_bar_backgrounds)
	call_deferred("_layout_bar_backgrounds")   # after the first layout pass

## Match each backing panel to its bar's current rect (with a small margin).
func _layout_bar_backgrounds() -> void:
	var pad := Vector2(6, 4)
	var top_bar := get_node_or_null("main_ui/VBoxContainer3/HBoxContainer") as Control
	if _top_bar_bg and top_bar:
		_top_bar_bg.global_position = top_bar.global_position - pad
		_top_bar_bg.size = top_bar.size + pad * 2.0
	var side_strip := get_node_or_null("main_ui/VBoxContainer3/HBoxContainer2/sidebar") as Control
	if _side_bar_bg and side_strip:
		_side_bar_bg.global_position = side_strip.global_position - pad
		_side_bar_bg.size = side_strip.size + pad * 2.0

## Mark a body as surveyed (called when a Survey mission is launched to it).
## No-op if already surveyed.
func _mark_surveyed(body: String) -> void:
	if body == "" or surveyed_planets.has(body):
		return
	surveyed_planets.append(body)

## Research node that unlocks spaceflight; the Launches sidebar button (and panel)
## stay hidden until it is researched.
const LAUNCH_UNLOCK_RESEARCH: String = "early_rocketry"

## Show the Launches button only once the player has reached Early Rocketry; keep
## the panel hidden (and closed) before then.
func _refresh_launch_access() -> void:
	var unlocked: bool = ResearchTree.is_unlocked(LAUNCH_UNLOCK_RESEARCH)
	if launches_button:
		launches_button.visible = unlocked
	if not unlocked and launch_panel and launch_panel.visible:
		launch_panel.hide()

## Research that unlocks the Automation panel (standing build/launch orders).
const AUTOMATION_UNLOCK_RESEARCH: String = "autonomous_factories"

## Reveal the Automation button only once Industrial AI is researched; keep it hidden
## (and the panel closed) before then.
func _refresh_automation_access() -> void:
	if sidebar:
		sidebar.set_automation_locked(not ResearchTree.is_unlocked(AUTOMATION_UNLOCK_RESEARCH))

func _spawn_satellite(origin_planet: Planet, target_planet: Planet, arrival: String, launch_id: int, flight_days: float = 60.0) -> void:
	var sat := Satellite.new()
	sat.name         = "Satellite_%d" % launch_id
	sat.arrival_mode = arrival
	$WorldRoot.add_child(sat)
	sat.begin_transfer(
		$WorldRoot/Planets/sun as Node3D,
		origin_planet,
		target_planet,
		flight_days
	)
	_launch_satellites[launch_id] = sat

## A Solar Deployment craft: flies straight to its reserved swarm slot and removes
## itself on arrival (the swarm collector takes its place — see init_planets).
func _spawn_swarm_satellite(origin_planet: Planet, slot_pos: Vector3, launch_id: int, flight_days: float) -> void:
	var sat := Satellite.new()
	sat.name            = "Satellite_%d" % launch_id
	sat.arrival_mode    = "swarm"
	sat.swarm_target_pos = slot_pos
	$WorldRoot.add_child(sat)
	sat.begin_transfer(
		$WorldRoot/Planets/sun as Node3D,
		origin_planet,
		origin_planet,   # target planet unused in swarm mode; pass origin to stay valid
		flight_days
	)
	_launch_satellites[launch_id] = sat

func _process(delta: float) -> void:
	_update_realtime_clock()   # wall clock ticks regardless of game pause/timescale

	# ── Drain one pending event notification per frame ────────────────────────
	if not _pending_event_notifications.is_empty():
		# Bound the backlog: a deep-time flood (e.g. relativistic-missile alerts) could queue
		# faster than one-per-frame forever.  Keep only the most recent few popup cards — the
		# events still land on the (also-bounded) timeline; we just don't stack thousands of cards.
		if _pending_event_notifications.size() > 5:
			_pending_event_notifications = _pending_event_notifications.slice(-5)
		_show_event_card(_pending_event_notifications.pop_front())

	# ── Autosave timer (runs even while paused) ───────────────────────────────
	if settings_menu and not game_over:
		var autosave_interval: int = settings_menu.get_autosave_seconds()
		if autosave_interval > 0:
			_autosave_accum += delta
			if _autosave_accum >= float(autosave_interval):
				_autosave_accum = 0.0
				save_game()

	if SolarSystem.paused or SolarSystem.ui_paused or game_over:
		return

	time_accum += delta
	var spd: float = SolarSystem.seconds_per_day

	if spd >= FAST_THRESHOLD:
		# ── Normal mode: advance day-by-day ───────────────────────────────────
		while time_accum >= spd and not game_over:
			time_accum -= spd
			advance_day()
	else:
		# ── Fast mode: skip months/days, advance whole years per frame ────────
		var secs_per_year: float = spd * 365.25
		if secs_per_year > 0.0 and time_accum >= secs_per_year:
			var years_to_add: int = int(time_accum / secs_per_year)
			if years_to_add > 0:
				time_accum -= float(years_to_add) * secs_per_year
				year += years_to_add
				month = 0
				day   = 0
				_update_timescale()
				_on_years_advanced_fast(years_to_add)

	if not game_over and spd > 0.0:
		# Game-days elapsed this frame.  ALL accumulation is driven by this rather
		# than real frame time, so production/consumption scale correctly with the
		# timescale: the same number of game-days yields the same resources whether
		# the player is at 1× or fast-forwarding through millions of years.
		var delta_days: float = delta / spd

		# Burn fuel FIRST: it sets how much of the fuel-burning fleet is running, which
		# _get_total_production then folds into this slice's energy.
		_consume_fuel(delta_days)
		var production := _get_total_production()
		for resource in production:
			ResearchTree.resources[resource] = ResearchTree.resources.get(resource, 0.0) + production[resource] * delta_days
		_accumulate_compounds(delta_days)
		_accumulate_emissions(delta_days)
		_process_production(delta_days)
		_process_construction(delta_days)
		_process_automation()
		_accumulate_entropy(delta_days)   # heat shed to the cooling universe, dS = Q/T
		_check_thermal_labor_alerts()     # one-shot overheating / labour-shortage notices
		# Clamp minerals and energy to their storage caps; science is never capped.
		for resource: String in _cached_storage_caps:
			if ResearchTree.resources.has(resource):
				ResearchTree.resources[resource] = minf(
					ResearchTree.resources[resource], _cached_storage_caps[resource]
				)
		# Evolve population on the same game-day clock.
		var pop_before: float = float(stats.get("current_population", 0))
		_update_population(delta_days)
		var pop_after: float = float(stats.get("current_population", 0))
		# Births = replacement (deaths ≈ population ÷ life expectancy) + net growth.
		var life_exp: float = _life_expectancy()
		stats["life_expectancy"] = life_exp
		_people_ever_lived += pop_after * (delta_days / 365.25) / life_exp \
			+ maxf(0.0, pop_after - pop_before)
		_refresh_stats()
		statistics_page.set_stats(stats)
		_update_hud()
		# Keep the star map's mission/attack progress + energy readout live while it's open.
		if sidebar and sidebar.star_map and sidebar.star_map.visible:
			refresh_star_map()

	# ── Throttled panel refresh (once per frame, capped at ~4 Hz) ────────────────
	# get_planet_data duplicates composition/inventory dictionaries and a BuildPanel rebuild
	# recreates its whole node tree — doing either every frame, or once per queued/completed
	# build, was the construction-time lag.  Coalesce roster changes into one rebuild per tick.
	_ui_refresh_accum += delta
	if _ui_refresh_accum >= UI_REFRESH_SEC:
		_ui_refresh_accum = 0.0
		# Only refresh the merged panel's ACTIVE tab, and only while it's open.
		if _planet_tabs and _planet_tabs.visible and current_planet != "":
			if planet_info_page.visible:
				planet_info_page.set_planet_info(get_planet_data(current_planet))
			elif build_panel.visible:
				if _build_ui_dirty:
					build_panel.apply_counts(_get_catalog_for_display())   # roster changed — patch in place
				else:
					build_panel.refresh_affordability(_build_cost_stockpiles())          # recolour only
			elif _population_page and _population_page.visible:
				_population_page.set_stats(_population_stats(current_planet))
			elif _inventory_page and _inventory_page.visible:
				_inventory_page.set_inventory(current_planet, get_planet_data(current_planet))
			elif _extraction_page and _extraction_page.visible:
				_extraction_page.set_extraction(current_planet, extraction_data(current_planet))
			elif production_panel and production_panel.visible:
				production_panel.set_planet(current_planet)   # no-op if the body didn't change
		if _build_ui_dirty and launch_panel.visible:
			launch_panel.set_launch_mods(_build_launch_mods_map())
		_build_ui_dirty = false

func advance_day() -> void:
	day += 1

	var dim: int = days_per_month[month]
	if month == 1 and is_leap(year):
		dim = 29

	if day >= dim:
		day = 0
		month += 1
		if month >= 12:
			month = 0
			year += 1
			_update_timescale()
			_refresh_stats()
			statistics_page.push_snapshot(year, stats)
			_last_snapshot_year = year
			_check_extinction_events()
			_check_population_splits()
			_check_interstellar_arrivals()
			_check_interstellar_attacks()
			_process_aliens()
			_process_vn_colonization()
			_update_regions()
			_check_incoming_attacks()
			_check_probe_arrivals()
			_check_message_arrivals()
			_check_asteroid_impact()
			_check_pandemic()
			_check_nuclear_war()
			_check_game_events("year")
			_check_game_events("population")
			_check_game_events("compute")
			if timeline_panel and timeline_panel.visible:
				timeline_panel.set_current_year(year)

	var today_abs := _to_abs_day(year, month, day)
	var any_completed := false
	for launch in active_launches:
		if launch["status"] == "active":
			var end_abs := _to_abs_day(
				int(launch["end_year"]), int(launch["end_month"]), int(launch["end_day"])
			)
			if today_abs >= end_abs:
				launch["status"] = "completed"
				any_completed = true
				# Fire mission-type events.
				var m_target: String = launch.get("target", "")
				var m_arrival: String = launch.get("arrival", "")
				if m_arrival == "orbit":
					_check_game_events("orbit_mission")
				if m_target == "mars":
					_check_game_events("mission_mars")
				if m_target in ["jupiter", "saturn", "uranus", "neptune"]:
					_check_game_events("mission_outer")
				if launch["mission"] == "Colony Ship":
					var target: String = m_target
					if target != "" and not colonized_planets.has(target):
						colonized_planets.append(target)
						_colonized_year[target]   = year
						_split_thresholds[target] = int(randf_range(500_000.0, 1_000_000.0))
						_colony_parent[target]    = str(launch.get("origin", "earth"))
						_establish_colony_base(target)
						print("[Game] Colony established on %s from %s (split in ~%d yrs)" % [
							target.capitalize(), _colony_parent[target], _split_thresholds[target]
						])
						_check_game_events("colony_count")
				# Solar Satellites arrive at the Sun and join the Dyson swarm.
				var payload: int = int(launch.get("payload", 0))
				if payload > 0:
					solar_satellites_deployed = clampi(
						solar_satellites_deployed + payload, 0, _swarm_max())
					_pending_swarm = maxi(0, _pending_swarm - payload)
					_mark_prod_dirty()   # swarm now beams back more power
	if any_completed:
		# Drop finished missions so active_launches stays bounded (it would otherwise
		# grow without limit across deep time) and the panel shows only in-flight craft.
		var still: Array = []
		for l in active_launches:
			if l["status"] == "active":
				still.append(l)
		active_launches = still
		_check_population_splits()
	if launch_panel.visible:
		launch_panel.set_game_date(year, month + 1, day + 1)
		launch_panel.set_orbital_state(_build_orbital_state())
		launch_panel.set_swarm_state(_build_satellite_stock(), solar_satellites_deployed, _swarm_max())
		launch_panel.set_launch_stock(_build_launch_stock())
		launch_panel.refresh_launches(_compute_launch_display_data())

## Populate _bdef_cache from the full levelled catalogue (called once in _ready).
func _init_building_cache() -> void:
	_bdef_cache.clear()
	for b: Dictionary in BuildingData.all():
		# Structural mass — the tonnage of the thing — cached once so the upkeep pass never has
		# to re-add a bill of materials.  Maintenance scales with how much building there is.
		var mass: float = 0.0
		for res: String in (b.get("cost", {}) as Dictionary):
			if res not in Units.NON_MASS_KEYS:
				mass += float(b["cost"][res])
		b["_mass"] = mass
		b["_upkeep"] = mass * UPKEEP_J_PER_GRAM 			* float(UPKEEP_CATEGORY_MULT.get(str(b.get("category", "")), 1.0))
		_bdef_cache[b["name"]] = b
	# Recipe lookups too, so _process_production doesn't linear-scan the recipe list twice
	# per job every frame (that scan was the frame-rate drag while production was running).
	_recipe_cache.clear()
	for r: Dictionary in RecipeData.RECIPES:
		_recipe_cache[r["name"]] = r

## O(1) building-def lookup via pre-built cache.
func _find_building_def(building_name: String) -> Dictionary:
	return _bdef_cache.get(building_name, {})

## Mark production cache stale.  Call whenever buildings, policies, or
## research change so the next _get_compute_rate / _get_total_production
## call recomputes from scratch.
func _mark_prod_dirty() -> void:
	_prod_dirty = true

# ── Storage capacity helpers ──────────────────────────────────────────────────

## Base storage granted to every planet that has been colonised (or Earth).
## Minerals is a mass, so it rides Units.MASS_SCALE; energy is in Joules and does not.
const _PLANET_BASE_STORAGE: Dictionary = {
	"minerals": 100_000.0 * Units.MASS_SCALE,
	"energy":   100_000.0 * Units.ENERGY_STORAGE_SCALE}

## Returns the storage capacity this specific planet contributes to the global
## pool: base allocation (if colonised / Earth) + capacity from storage buildings.
func _get_planet_storage_cap(planet_name: String) -> Dictionary:
	var cap: Dictionary = _PLANET_BASE_STORAGE.duplicate() \
		if _is_body_buildable(planet_name) \
		else {"minerals": 0.0, "energy": 0.0}
	for b_name: String in planet_buildings.get(planet_name, []):
		var stor: Dictionary = (_bdef_cache.get(b_name, {}) as Dictionary).get("storage", {})
		for resource: String in stor:
			cap[resource] = cap.get(resource, 0.0) + float(stor[resource])
	return cap

## Global cap = sum of every planet's individual capacity.
func _compute_storage_caps() -> Dictionary:
	var caps: Dictionary = {"minerals": 0.0, "energy": 0.0}
	# Earth always has base storage.
	for resource: String in caps:
		caps[resource] += _PLANET_BASE_STORAGE[resource]
	# Each colonised planet also gets a base allocation.
	for _pname: String in colonized_planets:
		for resource: String in caps:
			caps[resource] += _PLANET_BASE_STORAGE[resource]
	# Storage buildings on every planet with construction activity.
	for planet_name: String in planet_buildings:
		for b_name: String in planet_buildings[planet_name]:
			var stor: Dictionary = (_bdef_cache.get(b_name, {}) as Dictionary).get("storage", {})
			for resource: String in stor:
				if caps.has(resource):
					caps[resource] += float(stor[resource])
	return caps

## Re-sum the building-derived contributions (compute/minerals/energy/MC/radiator/storage).
## Runs ONLY when the roster changes (_prod_dirty) — NOT every frame.  Population and boosts
## are applied cheaply afterwards by _combine_production, so this O(buildings) sweep happens
## only on build/demolish/colony/swarm changes.
func _recompute_production_cache() -> void:
	var compute:  float = 0.0
	var minerals: float = 0.0
	var energy:   float = 0.0
	var radiator: float = 0.0
	var built_mc: Dictionary = {}
	var fuel_demand: Dictionary = {}   # planet → { fuel → g/game-day }
	var plants: Dictionary = {}        # planet → { building → {"energy", "fuel"} }
	var pstats: Dictionary = {}        # planet → per-world sums the per-frame passes need
	var detection: float = 0.0         # civilisation-wide signature-detection power
	var nuclear: float = 0.0           # civilisation-wide reactor capacity, in level-1 equivalents
	var upkeep: float = 0.0            # running cost of everything switched on
	var counts: Dictionary = {}        # planet → { building → standing }, reused by the UI
	for planet_name: String in planet_buildings:
		var pmc: float = 0.0
		# Tally the roster ONCE, then work per building TYPE.  A world holds thousands of
		# structures but only tens of kinds, so every per-building dictionary lookup below
		# happens once per kind instead of once per instance.
		var tally: Dictionary = {}
		for bn in planet_buildings[planet_name]:
			tally[bn] = int(tally.get(bn, 0)) + 1
		counts[planet_name] = tally
		var act_map: Dictionary = active_buildings.get(planet_name, {})
		# Everything below is roster-derived, so it is summed HERE (once per roster change)
		# rather than by re-walking thousands of buildings on every single frame.
		var st: Dictionary = {
			"mine": 0.0, "atmo": 0.0,        # extraction rates
			"co2_base": 0.0, "co2_fuel": {}, # emissions: always-on vs fuel-gated
			"e_total": 0.0, "e_dirty": 0.0,  # non-fuel energy, and how much of it emits
			"e_fuel_dirty": {},              # fuel-gated energy that emits, by building
		}
		for b_name: String in tally:
			var standing: int = int(tally[b_name])
			# Only SWITCHED-ON buildings produce, draw, burn, or vent.  Absent from the map means
			# all of them; a stored figure is clamped in case some were demolished since.
			var n: float = float(clampi(int(act_map.get(b_name, standing)), 0, standing))
			if n <= 0.0:
				continue
			var bdef: Dictionary = _bdef_cache.get(b_name, {})
			var prod: Dictionary = bdef.get("production", {})
			compute  += (prod.get("compute",  0.0) as float) * n
			minerals += (prod.get("minerals", 0.0) as float) * n
			pmc      += float(bdef.get("mc_capacity", 0.0)) * n
			radiator += float(bdef.get("radiator_capacity", 0.0)) * n
			upkeep   += float(bdef.get("_upkeep", 0.0)) * n
			st["mine"] = float(st["mine"]) + (prod.get("minerals", 0.0) as float) * n
			st["atmo"] = float(st["atmo"]) + float(bdef.get("atmo_rate", 0.0)) * n
			detection += float(bdef.get("detection", 0.0)) * n
			# Fissile capability tracks REACTOR CAPACITY, so a higher tier counts for as much
			# more as it generates — and every tier counts, which plain name-matching missed.
			if str(bdef.get("base_name", "")) == "Nuclear Plant":
				nuclear += pow(BuildingData.LEVEL_OUTPUT_MULT, float(int(bdef.get("level", 1)) - 1)) * n
			var co2f: float = float(bdef.get("co2_per_energy", 0.0))
			# A plant with a fuel line is only as productive as its supply, so hold its energy
			# aside (and tally its draw) instead of counting it as always-on.
			var burn: Dictionary = bdef.get("consumption", {})
			var e: float = (prod.get("energy", 0.0) as float) * n
			if burn.is_empty():
				energy += e
				st["e_total"] = float(st["e_total"]) + e
				if co2f > 0.0:
					st["co2_base"] = float(st["co2_base"]) + e * co2f
					st["e_dirty"] = float(st["e_dirty"]) + e
				continue
			var pf: Dictionary = fuel_demand.get(planet_name, {})
			for fuel: String in burn:
				pf[fuel] = float(pf.get(fuel, 0.0)) + float(burn[fuel]) * n
			fuel_demand[planet_name] = pf
			var pp: Dictionary = plants.get(planet_name, {})
			pp[b_name] = {"energy": e, "fuel": burn}
			plants[planet_name] = pp
			if co2f > 0.0:
				var cf: Dictionary = st["co2_fuel"]
				cf[b_name] = float(cf.get(b_name, 0.0)) + e * co2f
				var ed: Dictionary = st["e_fuel_dirty"]
				ed[b_name] = float(ed.get(b_name, 0.0)) + e
		built_mc[planet_name] = pmc
		pstats[planet_name] = st
	_cached_planet_stats = pstats
	_cached_planet_counts = counts
	_bld_upkeep = upkeep
	_cached_detection = detection
	_cached_nuclear = nuclear
	_cached_planet_built_mc = built_mc
	_cached_planet_fuel = fuel_demand
	_cached_planet_plants = plants
	# Re-derive the live fuel-burning output from the last known supply ratios (a plant with no
	# recorded ratio yet is assumed fed, so a roster change never blanks the grid for a frame).
	var live: float = 0.0
	for p: String in plants:
		var pfac: Dictionary = _fuel_factor.get(p, {})
		for b_name: String in plants[p]:
			live += float((plants[p][b_name] as Dictionary)["energy"]) \
				* clampf(float(pfac.get(b_name, 1.0)), 0.0, 1.0)
	_live_fossil_energy = live
	# Dyson swarm: collectors beam power to the grid, less per lane the farther out it sits.
	_bld_compute  = compute
	_bld_minerals = minerals
	_bld_energy   = energy + _swarm_power()
	_bld_radiator = radiator
	# Storage caps are also roster-derived — refresh them in the same dirty pass.
	_cached_storage_caps = _compute_storage_caps()
	_prod_dirty = false

## Cheap, O(1) per-frame combine of the cached building sums with the current population and
## the research/policy multipliers, producing the live compute rate and production dict.
func _combine_production() -> void:
	var flops_per_person: float = evolution_ui.get_unlocked_compute_per_individual() \
		if evolution_ui else 1.0e17
	var pop: float = float(stats.get("current_population", 0))
	var compute: float = (pop * flops_per_person + _bld_compute) \
		* (1.0 + ResearchTree.get_boost("research_speed")) * _policy_compute_mult()
	var minerals: float = _bld_minerals \
		* (1.0 + ResearchTree.get_boost("matter_production")) * _policy_minerals_mult()
	# Always-on generation plus however much of the fuel-burning fleet is actually fed.
	var energy: float = (_bld_energy + _live_fossil_energy) \
		* (1.0 + ResearchTree.get_boost("energy_production")) * _policy_energy_mult()

	# ── Waste-heat throttle ────────────────────────────────────────────────────
	_cached_radiator_cap = (BASE_RADIATOR_W + _bld_radiator) \
		* (1.0 + ResearchTree.get_boost("heat_management")) * _thermal_coldness()
	_thermal_ratio = energy / maxf(_cached_radiator_cap, 1.0)
	energy *= _thermal_efficiency(energy, _cached_radiator_cap)
	# Everything switched on draws maintenance power off the top.  This can go negative: a grid
	# that can't carry its own infrastructure drains the reserve until the player idles something.
	energy -= _bld_upkeep

	_cached_compute = compute
	_cached_prod = {
		"science":  compute * science_multiplier * _policy_science_mult()
					* (1.0 + ResearchTree.get_boost("science_production")),
		"minerals": minerals,
		"energy":   energy,
	}

# ── Policy multipliers ────────────────────────────────────────────────────────
# The formulas live in PoliticsData so the politics screen can display the exact
# same values it shows the player.  These thin wrappers apply them to live state.

func _policy_science_mult() -> float:
	return PoliticsData.science_mult(policies)

func _policy_compute_mult() -> float:
	return PoliticsData.compute_mult(policies)

func _policy_minerals_mult() -> float:
	return PoliticsData.minerals_mult(policies)

func _policy_energy_mult() -> float:
	return PoliticsData.energy_mult(policies)

## Returns a duration multiplier to apply to all new missions.
func _policy_mission_dur_mult() -> float:
	return PoliticsData.mission_dur_mult(policies)

func _on_policy_changed(policy_id: String, value: Variant) -> void:
	policies[policy_id] = value
	_mark_prod_dirty()

# ── Evolution / population divergence ─────────────────────────────────────────

## Check every populated world (Earth plus each colony) and, once its population has
## been sustained past its random divergence threshold, branch a new lineage off the
## population it descends from.  Idempotent — safe to call every year / fast tick.
func _check_population_splits() -> void:
	if not evolution_ui:
		return
	for world: String in _colonized_year:
		if _variant_parent.has(world):
			continue   # already diverged
		var threshold: int     = _split_thresholds.get(world, 500_000)
		var years_elapsed: int = year - int(_colonized_year[world])
		if years_elapsed < threshold:
			continue

		# Descend from the world this population came from — but only if that world
		# has itself diverged; otherwise the colonists were still baseline stock.
		var origin: String = str(_colony_parent.get(world, ""))
		var parent_world: String = origin if (origin != "" and _variant_parent.has(origin)) else ""

		_variant_parent[world] = parent_world
		if not evolution_ui.add_planet_variant(world, parent_world):
			continue   # node already existed (e.g. replay) — no notification

		var epithet: String = EvolutionTreeData.epithet_for(world)
		print("[Game] Lineage divergence: H. sapiens %s after %d years on %s" % [
			epithet, years_elapsed, world.capitalize()
		])
		var notif: Dictionary = {
			"id":       "split_" + world,
			"year":     year,
			"title":    "Lineage Divergence",
			"desc":     "The population of %s has been reproductively isolated for %s. It is now classified as a distinct lineage: H. sapiens %s." % [
				world.capitalize(),
				Units.format_si_verbose(float(years_elapsed), "yr"),
				epithet
			],
			"category": "civilization",
		}
		_pending_event_notifications.append(notif)
		if timeline_panel:
			timeline_panel.add_live_event(notif)

# ── Timescale ─────────────────────────────────────────────────────────────────

## Recompute SolarSystem.seconds_per_day from elapsed game-years.
## Formula: INIT * exp(-DECAY * elapsed), clamped to [MIN, INIT].
## The _user_speed_mult divides the result so higher mult = faster real time.
func _update_timescale() -> void:
	var elapsed: float = maxf(float(year - 2026), 0.0)
	var raw: float = TIMESCALE_INIT * exp(-TIMESCALE_DECAY * elapsed)
	SolarSystem.seconds_per_day = maxf(TIMESCALE_MIN, raw) / _user_speed_mult
	SolarSystem.current_year = year
	SolarSystem.snap_year = float(year)   # default; _prepare_snap_year() overrides on pause

# ── Extinction events ─────────────────────────────────────────────────────────

## Returns the Sun's current radius in AU by interpolating through Planet.SUN_STAGES.
## Uses the same stage data that drives the visual so the engulfment threshold is
## always in sync with what the player can see.
## Returns the Sun's radius in AU, interpolated from Planet.SUN_STAGES.
## Returns a very large value once the planetary nebula fires so every remaining
## inhabited world is treated as engulfed in a single check.
func _get_sun_radius_au(y: int) -> float:
	if y >= PLANETARY_NEBULA_YEAR:
		return 99999.0   # nebula sterilises everything
	var stages: Array = Planet.SUN_STAGES
	var lo: Array = stages[0]
	var hi: Array = stages[stages.size() - 1]
	for i in range(stages.size() - 1):
		if y >= int(stages[i][0]) and y < int(stages[i + 1][0]):
			lo = stages[i]
			hi = stages[i + 1]
			break
	var span: float = float(int(hi[0]) - int(lo[0]))
	var t: float = 0.0 if span <= 0.0 else clampf((float(y) - float(int(lo[0]))) / span, 0.0, 1.0)
	# Index [4] = solar_radii (physics); index [2] = visual_mult (display only).
	var solar_radii: float = lerpf(float(lo[4]), float(hi[4]), t)
	return SUN_RADIUS_BASE_AU * solar_radii

## Called every in-game year (and from fast mode). Safe to call repeatedly.
func _check_extinction_events() -> void:
	if game_over:
		return

	# ── Orbital freeze ────────────────────────────────────────────────────────
	if year >= SolarSystem.ORBIT_FREEZE_YEAR:
		SolarSystem.set_solar_system_active(false)

	# The Sun's photosphere physically swallows any planet inside its radius — destroy them
	# (and their moons/infrastructure) whether or not humanity is still there.
	var sun_au: float = _get_sun_radius_au(year)
	_destroy_engulfed_planets(sun_au)

	# ── Sun Red Giant ─────────────────────────────────────────────────────────
	# Extinction fires when every inhabited planet (Earth + colonies) is inside
	# the Sun's expanding radius.  Colonising outer worlds buys real time:
	#   Mars survives until ~7.6 B yr, Jupiter until ~7.8 B yr, etc.
	if not has_left_solar_system:
		var inhabited: Array = (["earth"] as Array) + colonized_planets
		var engulfed: Array = []
		for pname: String in inhabited:
			if sun_au >= PLANET_ORBIT_AU.get(pname.to_lower(), 9999.0):
				engulfed.append(pname.capitalize())
		if engulfed.size() == inhabited.size() and not engulfed.is_empty():
			var planet_str: String
			if engulfed.size() == 1:
				planet_str = engulfed[0]
			elif engulfed.size() == 2:
				planet_str = "%s and %s" % [engulfed[0], engulfed[1]]
			else:
				planet_str = ", ".join(engulfed.slice(0, engulfed.size() - 1)) \
					+ ", and " + engulfed[engulfed.size() - 1]
			var cause: String
			var desc: String
			if year >= PLANETARY_NEBULA_YEAR:
				cause = "Planetary nebula"
				desc  = "Sol has ejected its outer envelope. System-wide ultraviolet flux exceeds habitable tolerance. Inhabited worlds: 0. Remnant: white dwarf, cooling."
			else:
				cause = "Solar envelope expansion"
				desc  = "Sol's photosphere now encloses the orbit of %s. Inhabited worlds outside the photosphere: 0." % planet_str
			trigger_game_over(cause, desc)

## Planets (and their moons/infrastructure) whose orbit the Sun's photosphere has swallowed.
const _PLANET_NAMES: Array = ["mercury", "venus", "earth", "mars",
	"jupiter", "saturn", "uranus", "neptune"]
var _engulfed_planets: Dictionary = {}   # planet name → true once destroyed by the Sun

## Destroy any planet now inside the Sun's radius: remove its 3-D body (moons, rings, orbital
## infrastructure, orbit line) and wipe its colony/population.  Idempotent per planet.
func _destroy_engulfed_planets(sun_au: float) -> void:
	var planets := get_node_or_null("WorldRoot/Planets")
	for pname: String in _PLANET_NAMES:
		if sun_au < float(PLANET_ORBIT_AU.get(pname, 9999.0)):
			continue
		if planets:
			var pnode := planets.get_node_or_null(pname)
			if pnode and pnode.has_method("engulf"):
				pnode.engulf()   # visual destruction (idempotent via the planet's own guard)
		if not _engulfed_planets.has(pname):
			_engulfed_planets[pname] = true
			world_pop.erase(pname)          # all life on it is gone
			colonized_planets.erase(pname)  # no longer a colony
			_mark_prod_dirty()
			_announce("World destroyed",
				"%s falls within Sol's photosphere and is consumed." % pname.capitalize(),
				"engulf_%s_%d" % [pname, year])

## Pause the game and display the extinction screen.
func trigger_game_over(cause: String, description: String) -> void:
	if game_over:
		return
	# Interstellar refuge: as long as at least one other star system is still colonised,
	# humanity survives the catastrophe instead of going extinct.  Marking the species as
	# no longer Sol-bound also stops the recurring solar-death check from re-firing.
	if not colonized_stars.is_empty():
		has_left_solar_system = true
		_announce("Catastrophe Survived",
			"%s would have ended humanity — but the colony at %s endures. The species survives among the stars." % [
				cause, str(colonized_stars[0]).capitalize()],
			"survived_%s_%d" % [cause, year])
		return
	game_over          = true
	SolarSystem.paused = true
	_refresh_stats()
	# Record the final moment, then mirror the run's history onto the extinction screen.
	statistics_page.push_snapshot(year, stats)
	game_over_screen.set_graph_history(statistics_page.get_graph())
	game_over_screen.show_game_over(cause, description, year, stats, _people_ever_lived)

## Called when the player presses "Start New Civilization" on the game-over screen.
func _on_restart_requested() -> void:
	SolarSystem.paused = false
	start_new_game()
	politics_page.load_policies(policies)
	_check_population_splits()
	_refresh_launch_access()   # fresh run: hide Launches again until Early Rocketry
	_refresh_automation_access()   # fresh run: hide Automation again until Industrial AI
	_refresh_stats()
	_update_hud()

## Called in fast mode: bulk-advance the game by years_advanced years per frame.
func _on_years_advanced_fast(years_advanced: int) -> void:
	_refresh_stats()
	# Snapshot interval scales with the timescale so that roughly the same
	# real-world time separates every graph point no matter how fast the sim runs.
	# Formula: interval = FAST_THRESHOLD / seconds_per_day, meaning one snapshot
	# per ~1 real second of gameplay.  At the slowest timescale (1e-9 s/day) this
	# works out to ~500 000 game-years between points; at the fast-mode boundary
	# (5e-4 s/day) it collapses back to 1 year, matching normal-mode behaviour.
	var snapshot_interval: int = maxi(1, int(FAST_THRESHOLD / SolarSystem.seconds_per_day))
	if year - _last_snapshot_year >= snapshot_interval:
		statistics_page.push_snapshot(year, stats)
		_last_snapshot_year = year
	_check_extinction_events()
	if not game_over:
		_check_population_splits()
		_check_interstellar_arrivals()
		_check_interstellar_attacks()
		_process_aliens()
		_process_vn_colonization()
		_update_regions()
		_check_incoming_attacks()
		_check_probe_arrivals()
		_check_message_arrivals()
		_check_asteroid_impact()
		_check_pandemic()
		_check_nuclear_war()
		_check_game_events("year")
		_check_game_events("population")
		_check_game_events("compute")
		if timeline_panel and timeline_panel.visible:
			timeline_panel.set_current_year(year)

## Process all active manufacturing jobs: consume inputs from compound_inventory
## and the main resource pools, then deposit outputs.  `delta_days` is elapsed
## game-days, so recipe throughput scales with the timescale like everything else.
func _process_production(delta_days: float) -> void:
	if _production_jobs.is_empty():
		_last_mc_state = {}
		return
	var panel_open: bool = production_panel.is_visible_in_tree()   # gate per-frame UI churn on visibility (it's a tab now)

	# ── Per-planet Manufacturing Capacity (MC) ────────────────────────────────
	# Each job demands "work" per day (≈ its material throughput).  A world's capacity
	# is its manual base plus its factories, scaled by automation and by how well the
	# civilisation's single finite labour force can staff all built capacity.  When a
	# planet's demand exceeds its capacity, every job there is throttled in proportion,
	# so MC acts as a per-day rate cap — identical behaviour at any timescale.
	var demand: Dictionary = {}              # planet → Σ rate × work
	for job in _production_jobs:
		var r := _find_recipe_by_name(job.get("recipe", ""))
		if r.is_empty():
			continue
		var jp: String = str(job.get("planet", "earth"))
		# Rates are in normalised units (1× = 1 g of product/day), so the work a job demands
		# scales with the same factor its throughput does.
		demand[jp] = float(demand.get(jp, 0.0)) \
			+ float(job.get("rate", 1.0)) * RecipeData.scale(r) * _recipe_work(r)

	var automation: float = _automation_factor()
	# One finite labour force staffs all built capacity; automation lowers the workers
	# each unit needs, so a heavily-automated economy decouples manufacturing from
	# population — a shrinking species can still grow its industry past the pop peak.
	var staffing: float = _mc_staffing()
	var capacity_planets: Dictionary = {}
	for p: String in _cached_planet_built_mc:
		capacity_planets[p] = true
	for p: String in demand:
		capacity_planets[p] = true

	# Per-planet throttle factor (computed once, reused for every job on that world).
	var throttle: Dictionary = {}
	_last_mc_state = {}
	for p: String in capacity_planets:
		var mc: float = (BASE_MC + float(_cached_planet_built_mc.get(p, 0.0))) * automation * staffing
		var d: float = float(demand.get(p, 0.0))
		throttle[p] = 1.0 if (d <= mc or d <= 0.0) else mc / d
		_last_mc_state[p] = {"capacity": mc, "demand": d}

	# ── Run each job at its MC-throttled effective rate ────────────────────────
	for job in _production_jobs:
		var recipe := _find_recipe_by_name(job.get("recipe", ""))
		if recipe.is_empty():
			continue
		# A job runs on a specific planet, drawing from and feeding that planet's
		# inventory (global resources like energy are shared).
		var planet: String = str(job.get("planet", "earth"))
		var mc_throttle: float = float(throttle.get(planet, 1.0))
		# Normalised rate: the slider's 1× is one gram of product per day, whatever the
		# recipe's raw stoichiometry says.
		var rate: float = float(job.get("rate", 1.0)) * RecipeData.scale(recipe) * mc_throttle
		var inputs: Dictionary = recipe.get("inputs", {})

		# Run the job for as much of this game-time slice as the inputs allow, instead
		# of all-or-nothing.  Over long timescales delta_days is enormous and inputs
		# arrive concurrently (mine → smelter → factory), so a full-slice buffer never
		# exists up front — producing the affordable fraction keeps the chain flowing
		# and lets resources accumulate correctly at any timescale.
		var run_days: float = delta_days
		var bottleneck: String = ""
		for key: String in inputs:
			var per_day: float = float(inputs[key]) * rate
			if per_day <= 0.0:
				continue
			var affordable_days: float = _get_stockpile(key, planet) / per_day
			if affordable_days < run_days:
				run_days = affordable_days
				bottleneck = key
		run_days = maxf(0.0, run_days)

		# Status priority: an input shortage is shown first; otherwise, if the world's
		# manufacturing capacity is the limit, flag that; else the job runs clean.  Only
		# pushed while the panel is open — updating (and re-shaping) hidden labels every
		# frame per job was the main cost that made building/producing stutter.
		if panel_open:
			var job_id := int(job.get("id", 0))
			if bottleneck != "":
				production_panel.set_job_status(job_id, false, bottleneck)
			elif mc_throttle < 0.999:
				production_panel.set_job_status(job_id, false, "capacity")
			else:
				production_panel.set_job_status(job_id, true, "")

		if run_days <= 0.0 or rate <= 0.0:
			continue

		for key: String in inputs:
			_deduct_stockpile(key, float(inputs[key]) * rate * run_days, planet)
		var outputs: Dictionary = recipe.get("outputs", {})
		for key: String in outputs:
			_add_stockpile(key, float(outputs[key]) * rate * run_days, planet)

	if panel_open:
		production_panel.set_mc_state(_last_mc_state)

## O(1) recipe-def lookup via the pre-built cache (see _init_building_cache).
func _find_recipe_by_name(name: String) -> Dictionary:
	return _recipe_cache.get(name, {})

## Manufacturing "work" one batch of a recipe demands per unit rate — its material
## throughput (sum of inputs except the energy/science it also draws from global pools),
## or an explicit "work" override.  Floored at 1 so every recipe consumes some capacity.
func _recipe_work(recipe: Dictionary) -> float:
	if recipe.has("work"):
		return maxf(1.0, float(recipe["work"]))
	var w: float = 0.0
	var inputs: Dictionary = recipe.get("inputs", {})
	for key: String in inputs:
		if key == "energy" or key == "science":
			continue
		w += float(inputs[key])
	return maxf(1.0, w)

## Industrial automation multiplier (≥ 1): raises manufacturing capacity and lowers the
## labour each unit of capacity needs.  Sourced from the industry research lane, so
## self-replicating industry is what finally decouples output from population.
func _automation_factor() -> float:
	return 1.0 + ResearchTree.get_boost("automation")

## Civilisation-wide staffing fraction (0..1): how much of all built capacity the single
## finite labour force can run, with automation lowering the workers each unit needs.
## Shared by _process_production and the planet panel so both show the same numbers.
func _mc_staffing() -> float:
	var total_raw: float = 0.0
	for p: String in _cached_planet_built_mc:
		total_raw += BASE_MC + float(_cached_planet_built_mc[p])
	var labor_need: float = total_raw * LABOR_PER_CAP / maxf(_automation_factor(), 0.001)
	if labor_need <= 0.0:
		return 1.0
	return clampf(float(stats.get("current_population", 0)) / labor_need, 0.0, 1.0)

## Effective Manufacturing Capacity (work-units/day) of a world: base + factories,
## times automation, scaled by staffing.
func _planet_mc_capacity(planet: String) -> float:
	return (BASE_MC + float(_cached_planet_built_mc.get(planet, 0.0))) \
		* _automation_factor() * _mc_staffing()

# ── Automation execution ──────────────────────────────────────────────────────
# Standing orders from the AutomationPanel, evaluated once per frame in both normal
# and fast time.  Rules are maintenance targets — build up to a count, keep a number
# of missions in flight — and each only acts when it can afford to, so it self-paces
# against the economy at any timescale.

func _on_automation_changed(rules: Array) -> void:
	_automation_rules = rules

## Toggle autonomous von Neumann colonisation.  Turning it ON kicks off seeding on the next tick;
## turning it OFF stops new seeds but can't recall a swarm already replicating in the void.
func _on_vn_colonization_changed(enabled: bool) -> void:
	_vn_enabled = enabled
	if enabled and not _vn_unlocked():
		_announce("Von Neumann colonisation locked",
			"Requires Relativistic Navigation and Self-Replicating Industry before probes can be built.",
			"vn_locked_%d" % year)

func _process_automation() -> void:
	if _automation_rules.is_empty():
		return
	var angles: Dictionary = {}
	var angles_built := false
	for rule_v in _automation_rules:
		var rule: Dictionary = rule_v
		if not bool(rule.get("enabled", true)):
			continue
		match str(rule.get("type", "")):
			"build":
				_run_build_rule(rule)
			"launch":
				if not angles_built:
					angles = _build_orbital_state()
					angles_built = true
				_run_launch_rule(rule, angles)

## Maintain at least rule.target of a building on its world, building one at a time
## while affordable.  Stops the instant a build fails so it never busy-loops when broke.
func _run_build_rule(rule: Dictionary) -> void:
	var planet: String = str(rule.get("planet", "earth"))
	var building: String = str(rule.get("building", ""))
	var target: int = int(rule.get("target", 0))
	var guard: int = 0
	# Count what's already standing AND what's queued, so the rule fills the queue up to
	# the target once and then waits for construction — instead of re-queueing every frame.
	while _count_building(planet, building) + _queued_count(planet, building) < target \
			and guard < target:
		if not try_build(planet, building):
			break
		guard += 1

## Keep rule.keep missions of this kind in flight, launching at most ONE per tick — so a
## rule ramps its fleet up over successive frames (and is naturally paced by how fast the
## origin can supply rockets/fuel) rather than spawning the whole batch in a single frame.
func _run_launch_rule(rule: Dictionary, angles: Dictionary) -> void:
	var mission: String = str(rule.get("mission", ""))
	var origin: String = str(rule.get("origin", "earth"))
	var target: String = str(rule.get("target", ""))
	var keep: int = maxi(1, int(rule.get("keep", 1)))
	if _count_active_launches(mission, origin, target) >= keep:
		return   # fleet already at strength
	_auto_launch(rule, angles)   # one launch per tick; retries next tick if it can afford more

## Build a launch params dict from a rule (mirroring the LaunchPanel via LaunchPlanner)
## and submit it through the same _on_launch_requested path the manual UI uses.
func _auto_launch(rule: Dictionary, angles: Dictionary) -> void:
	var mission: String = str(rule.get("mission", ""))
	var m_idx: int = _mission_index(mission)
	if m_idx < 0:
		return
	var origin: String = str(rule.get("origin", "earth"))
	var target: String = str(rule.get("target", ""))
	var fuel_id: String = str(rule.get("fuel", ""))
	var arrival: String = str(rule.get("arrival", "orbit"))
	var origin_cap: String = origin.capitalize()
	var target_cap: String = target.capitalize()
	var accel: float = _fuel_accel(fuel_id)
	var mods: Dictionary = _planet_launch_mods(origin)
	var cost_mult: float = float(mods.get("cost", 1.0))
	var dur_mult: float = float(mods.get("duration", 1.0)) * _policy_mission_dur_mult()
	var duration: int = LaunchPlanner.duration_days(
		origin_cap, target_cap, arrival, accel, angles, 0.0, dur_mult)
	if duration <= 0:
		return   # invalid combination (e.g. land on the Sun)
	_on_launch_requested({
		"mission":      mission,
		"origin":       origin,
		"target":       target,
		"start_offset": 0,
		"duration":     duration,
		"rockets":      LaunchPlanner.rockets(m_idx, origin_cap, target_cap, cost_mult),
		"fuel_id":      fuel_id,
		"fuel_amount":  LaunchPlanner.propellant_mass(
			m_idx, origin_cap, target_cap, angles, 0.0, cost_mult, fuel_id),
		"arrival":      arrival,
	})

## In-flight launches matching a rule's mission/origin/target.
func _count_active_launches(mission: String, origin: String, target: String) -> int:
	var c: int = 0
	for l in active_launches:
		if l.get("status", "") == "active" and l.get("mission", "") == mission \
				and l.get("origin", "") == origin and l.get("target", "") == target:
			c += 1
	return c

## Index of a mission in MissionData.MISSION_TYPES by name (-1 if not found).
func _mission_index(mission: String) -> int:
	for i in range(MissionData.MISSION_TYPES.size()):
		if str(MissionData.MISSION_TYPES[i]["name"]) == mission:
			return i
	return -1

## Acceleration (m/s²) of a fuel id, for transit-time planning.
func _fuel_accel(fuel_id: String) -> float:
	for f in MissionData.FUELS:
		if str((f as Dictionary)["id"]) == fuel_id:
			return float((f as Dictionary).get("accel", 1.0e-2))
	return 1.0e-2

## The per-planet compound inventory dict for `planet` (created on first access).
## A moon shares its parent planet's material stockpile (one colony's logistics span the
## planet and its moons), so building on a moon draws on — and its mines feed — the parent.
func _planet_inv(planet: String) -> Dictionary:
	var key: String = planet
	if _is_moon(planet):
		var parent: String = _moon_parent(planet)
		if parent != "":
			key = parent
	if not compound_inventory.has(key):
		compound_inventory[key] = {}
	return compound_inventory[key]

# ── Body helpers (planets + moons) ────────────────────────────────────────────

## True when `id` is a cosmetic moon ("<planet>_moon_<n>").
func _is_moon(id: String) -> bool:
	return id.find("_moon_") > 0

## Parent planet of a moon id, or "" when `id` is not a moon.
func _moon_parent(id: String) -> String:
	var idx: int = id.find("_moon_")
	return id.substr(0, idx) if idx > 0 else ""

## Any real body's info/build panel can be opened — no probe required to inspect a world.
## (Whether you can BUILD there is a separate check; see _is_body_buildable.)
func _is_body_selectable(id: String) -> bool:
	return id != ""

## A body that can be built on: home, a colonised planet, or a moon of one — moons inherit
## their parent colony's foothold, so you build them out once the planet itself is settled.
func _is_body_buildable(id: String) -> bool:
	if id == "earth" or colonized_planets.has(id):
		return true
	var parent: String = _moon_parent(id)
	return parent != "" and (parent == "earth" or colonized_planets.has(parent))

## Human-readable name for a planet or moon (capitalised id, or the moon's proper name).
func _body_display_name(id: String) -> String:
	return str(MOON_NAMES.get(id, id.capitalize()))

## Composition (with crust) for ore-mining + the panel; moons use a generic regolith.
func _body_composition(id: String) -> Dictionary:
	if PlanetData.PLANETS.has(id):
		return (PlanetData.PLANETS[id] as Dictionary).get("composition_g", {})
	if _is_moon(id):
		return MOON_COMPOSITION
	return {}

## The three abstract civilisation-wide pools.  Everything else is a physical compound held in
## a specific world's inventory — and its mass is aggregated into "minerals" (the Matter readout).
const GLOBAL_POOLS: Array = ["science", "minerals", "energy"]

## Current held amount of a resource.  science/minerals/energy are global pools;
## every other compound is stored per-planet (mined and crafted locally).
func _get_stockpile(key: String, planet: String) -> float:
	if key in GLOBAL_POOLS:
		return float(ResearchTree.resources.get(key, 0.0))
	return float(_planet_inv(planet).get(key, 0.0))

## Total count of a crafted item (e.g. "Missile", "Berserker") across every planet inventory.
func _player_item_count(item: String) -> float:
	var n: float = 0.0
	for p: String in compound_inventory:
		n += float((compound_inventory[p] as Dictionary).get(item, 0.0))
	return n

## Remove `amount` of a crafted item from planet inventories (Earth first).  Returns false and
## deducts nothing if the total on hand is short.
func _consume_player_item(item: String, amount: float) -> bool:
	if _player_item_count(item) < amount:
		return false
	var need: float = amount
	var order: Array = ["earth"]
	for p: String in compound_inventory:
		if p != "earth":
			order.append(p)
	for p: String in order:
		if not compound_inventory.has(p):
			continue
		var inv: Dictionary = compound_inventory[p]
		var take: float = minf(float(inv.get(item, 0.0)), need)
		if take > 0.0:
			inv[item] = float(inv.get(item, 0.0)) - take
			_mirror_matter(-take)   # a fired missile is mass that has left the civilisation
			need -= take
		if need <= 0.0:
			break
	return true

## Deducts from the global pool (science/minerals/energy) or the planet's inventory.
func _deduct_stockpile(key: String, amount: float, planet: String) -> void:
	if key in GLOBAL_POOLS:
		ResearchTree.resources[key] = maxf(0.0, float(ResearchTree.resources.get(key, 0.0)) - amount)
		return
	var inv: Dictionary = _planet_inv(planet)
	var had: float = float(inv.get(key, 0.0))
	var removed: float = minf(amount, had)   # mirror what ACTUALLY left, not what was asked for
	inv[key] = had - removed
	_mirror_matter(-removed)

## Player confirmed a dump in the Inventory tab: discard `amount` grams of a compound from the
## currently-viewed body (clamped to what's actually held, since stock can tick down between the
## dialog opening and the confirm).  Mining refills over time.
func _on_inventory_dump(compound: String, amount: float) -> void:
	if current_planet == "" or amount <= 0.0:
		return
	var held: float = _get_stockpile(compound, current_planet)
	if held <= 0.0:
		return
	# _deduct_stockpile mirrors the loss into the Matter pool for us, so the top-bar readout
	# drops by exactly what was jettisoned.
	_deduct_stockpile(compound, minf(amount, held), current_planet)
	if _inventory_page and _inventory_page.visible:
		_inventory_page.set_inventory(current_planet, get_planet_data(current_planet))
	_update_hud()   # reflect the loss in the Matter box immediately, even while paused

## Player redistributed a world's mining allocation in the Extraction tab.
func _on_extraction_focus_changed(planet: String, weights: Dictionary) -> void:
	set_extraction_focus(planet, weights)
	if _extraction_page and _extraction_page.visible:
		_extraction_page.set_extraction(planet, extraction_data(planet))

## Adds to the global pool (science/minerals/energy) or the planet's inventory.
func _add_stockpile(key: String, amount: float, planet: String) -> void:
	if key in GLOBAL_POOLS:
		ResearchTree.resources[key] = float(ResearchTree.resources.get(key, 0.0)) + amount
		return
	var inv: Dictionary = _planet_inv(planet)
	inv[key] = float(inv.get(key, 0.0)) + amount
	_mirror_matter(amount)

## Keep the Matter pool in step with the compound inventories it aggregates.  Every gram that
## enters or leaves a world's stockpile moves it, so building, crafting, burning fuel, and
## dumping all register — where before only mining ever touched it and it just climbed.
## Recipes are not mass-conserving (13 g of ore and coke yield 6 g of iron), so the difference
## correctly leaves the total as slag and flue gas.
func _mirror_matter(delta: float) -> void:
	if delta == 0.0:
		return
	ResearchTree.resources["minerals"] = maxf(
		0.0, float(ResearchTree.resources.get("minerals", 0.0)) + delta)

## A colony ship delivers a foothold so the new world can bootstrap its own
## (per-planet) economy: a few mines to extract local materials, plus a small cache
## of construction supplies to raise the first structures.  Without this the colony
## would start with an empty inventory and be unable to afford anything.
func _establish_colony_base(planet_name: String) -> void:
	if not planet_buildings.has(planet_name):
		planet_buildings[planet_name] = []
	for _i in range(3):
		planet_buildings[planet_name].append("Mine")
	for _i in range(2):
		planet_buildings[planet_name].append("Biomass Burner")   # local power for life support
	# Through _add_stockpile so the delivered supplies register in the Matter aggregate.
	_add_stockpile("Concrete", 50_000.0 * Units.MASS_SCALE, planet_name)
	_add_stockpile("Steel",    20_000.0 * Units.MASS_SCALE, planet_name)
	world_pop[planet_name] = maxf(float(world_pop.get(planet_name, 0.0)), COLONY_SEED_POP)  # founders
	_mark_prod_dirty()

func _on_production_changed(jobs: Array) -> void:
	_production_jobs = jobs.duplicate(true)

## Returns { node_id: true } for every completed research node — used to gate recipes.
func _completed_research_map() -> Dictionary:
	var result: Dictionary = {}
	for node in ResearchTree.get_unlocked_nodes():
		result[node.id] = true
	return result

## Distribute mine output (boosted) into compound_inventory by crust mass
## fractions.  `delta_days` is elapsed game-days so extraction scales with the
## timescale, matching the bulk minerals accumulation.
func _accumulate_compounds(delta_days: float) -> void:
	if _prod_dirty:
		_recompute_production_cache()
	var minerals_mult: float = (1.0 + ResearchTree.get_boost("matter_production")) * _policy_minerals_mult()
	for planet_name: String in _cached_planet_stats:
		var st: Dictionary = _cached_planet_stats[planet_name]
		var mine_rate: float = float(st["mine"])
		var atmo_rate: float = float(st["atmo"])
		if mine_rate <= 0.0 and atmo_rate <= 0.0:
			continue
		var comp: Dictionary = _body_composition(planet_name) as Dictionary
		# Mines split their yield across the CRUST.  That mass is already counted in the Matter
		# pool via production.minerals, so it is written straight to the inventory — mirroring
		# it as well would count every gram mined twice.
		if mine_rate > 0.0:
			_extract_layer(planet_name, comp.get("crust", {}),
				mine_rate * minerals_mult * delta_days, false)
		# Condensers split theirs across the ATMOSPHERE.  They have no production.minerals line,
		# so nothing else accounts for their yield — it is mirrored into the Matter total here.
		if atmo_rate > 0.0:
			_extract_layer(planet_name, comp.get("atmosphere", {}),
				atmo_rate * minerals_mult * delta_days, true)

## Split `mass` grams across one composition layer by mass fraction and deposit the result in the
## world's inventory.  `mirror` also adds that mass to the Matter aggregate — set it only for
## sources the production pipeline doesn't already account for.
func _extract_layer(planet_name: String, layer: Dictionary, mass: float, mirror: bool) -> void:
	if layer.is_empty() or mass <= 0.0:
		return
	var inv: Dictionary = _planet_inv(planet_name)
	var focus: Dictionary = extraction_focus.get(planet_name, {})
	# With a focus set, the operation is working named deposits rather than scooping average
	# ground: the split follows the player's allocation instead of crustal abundance.  That is
	# what makes a rare-but-concentrated resource like coal extractable at industrial rates.
	var weights: Dictionary = {}
	var total: float = 0.0
	for compound: String in layer:
		var w: float = float(focus.get(compound, 0.0)) if not focus.is_empty() \
			else float(layer[compound])
		if w > 0.0:
			weights[compound] = w
			total += w
	# An allocation that targets nothing present here falls back to abundance, so a misconfigured
	# world still mines something rather than silently producing nothing.
	if total <= 0.0:
		for compound: String in layer:
			weights[compound] = float(layer[compound])
			total += float(layer[compound])
	if total <= 0.0:
		return
	for compound: String in weights:
		inv[compound] = float(inv.get(compound, 0.0)) + float(weights[compound]) / total * mass
	if mirror:
		_mirror_matter(mass)

## Per-world extraction allocation: planet → { compound → weight }.  Empty (the default) means
## the operation takes whatever the ground gives, split by crustal abundance.
var extraction_focus: Dictionary = {}

## The extraction picture for one world, for the Extraction panel: every crust compound with its
## natural abundance, the player's current allocation, and the resulting yield.
func extraction_data(planet_name: String) -> Dictionary:
	var crust: Dictionary = (_body_composition(planet_name) as Dictionary).get("crust", {})
	var total_crust: float = 0.0
	for c in crust:
		total_crust += float(crust[c])
	var mine_rate: float = 0.0
	for b_name: String in planet_buildings.get(planet_name, []):
		mine_rate += float((_bdef_cache.get(b_name, {}) as Dictionary).get("production", {}).get("minerals", 0.0))
	mine_rate *= (1.0 + ResearchTree.get_boost("matter_production")) * _policy_minerals_mult()
	var focus: Dictionary = extraction_focus.get(planet_name, {})
	var rows: Array = []
	for compound: String in crust:
		var abundance: float = float(crust[compound]) / total_crust if total_crust > 0.0 else 0.0
		rows.append({
			"compound": compound,
			"abundance": abundance,
			# With an allocation set, anything absent from it is getting NOTHING — falling back
			# to abundance there would show a share the operation isn't actually mining.
			"weight": float(focus.get(compound, 0.0)) if not focus.is_empty() else abundance,
		})
	return {"rows": rows, "mine_rate": mine_rate, "focused": not focus.is_empty()}

## Store a world's extraction allocation (weights are normalised by the panel).
func set_extraction_focus(planet_name: String, weights: Dictionary) -> void:
	if weights.is_empty():
		extraction_focus.erase(planet_name)
	else:
		extraction_focus[planet_name] = weights.duplicate()

## Vent CO₂ from combustion power plants into each planet's atmosphere, in
## proportion to the energy they generate (production.energy × co2_per_energy),
## scaled by elapsed game-days so it tracks the timescale like all other flows.
## Burn this slice's fuel for every plant with a "consumption" block, drawing from the world it
## stands on.  A world that can only cover part of its demand runs its whole fuel fleet at that
## fraction (and burns only that fraction), so power fades as the seams run dry rather than
## cutting out.  Sets _fuel_factor per planet and the live fuel-burning output for _combine_production.
func _consume_fuel(delta_days: float) -> void:
	if _prod_dirty:
		_recompute_production_cache()
	if _cached_planet_fuel.is_empty():
		_fuel_factor = {}
		_live_fossil_energy = 0.0
		return
	var live: float = 0.0
	var factors: Dictionary = {}
	for planet_name: String in _cached_planet_fuel:
		var demand: Dictionary = _cached_planet_fuel[planet_name]
		# One ratio PER FUEL: every plant burning it draws on the same pool and is cut back
		# together, while a plant burning a different fuel is untouched.
		var ratio: Dictionary = {}
		for fuel: String in demand:
			var need: float = float(demand[fuel]) * delta_days
			ratio[fuel] = 1.0 if need <= 0.0 \
				else clampf(_get_stockpile(fuel, planet_name) / need, 0.0, 1.0)
			var burned: float = need * float(ratio[fuel])
			if burned > 0.0:
				_deduct_stockpile(fuel, burned, planet_name)
		# A plant runs at the share of its scarcest input — one fuel short throttles only it.
		var pfac: Dictionary = {}
		for b_name: String in _cached_planet_plants.get(planet_name, {}):
			var rec: Dictionary = _cached_planet_plants[planet_name][b_name]
			var f: float = 1.0
			for fuel: String in (rec["fuel"] as Dictionary):
				f = minf(f, float(ratio.get(fuel, 1.0)))
			pfac[b_name] = f
			live += float(rec["energy"]) * f
		factors[planet_name] = pfac
	_fuel_factor = factors
	_live_fossil_energy = live

func _accumulate_emissions(delta_days: float) -> void:
	# Per-planet emission rate (grams/game-day) from combustion plants.
	if _prod_dirty:
		_recompute_production_cache()
	var emit_rate: Dictionary = {}
	for planet_name: String in _cached_planet_stats:
		var st: Dictionary = _cached_planet_stats[planet_name]
		# Always-on emitters are a cached constant; fuel-gated ones are scaled by how well each
		# was fed this tick — a handful of building TYPES, not thousands of buildings.
		var pfac: Dictionary = _fuel_factor.get(planet_name, {})
		var co2_rate: float = float(st["co2_base"])
		for b_name: String in (st["co2_fuel"] as Dictionary):
			co2_rate += float(st["co2_fuel"][b_name]) 				* clampf(float(pfac.get(b_name, 1.0)), 0.0, 1.0)
		if co2_rate > 0.0:
			emit_rate[planet_name] = co2_rate * PoliticsData.co2_mult(policies)

	# Integrate emission AND natural sequestration in closed form: the exact solution
	# of dCO₂/dt = rate − CO₂/τ.  Correct for any delta_days (so a single deep-time
	# frame is right), and CO₂ relaxes toward rate·τ — zero once emissions stop, which
	# is what lets the climate recover when the grid goes clean.
	var decay: float = exp(-delta_days / CO2_SEQUESTRATION_DAYS)
	var gain: float = CO2_SEQUESTRATION_DAYS * (1.0 - decay)
	var planets: Dictionary = {}
	for p: String in atmospheric_co2:
		planets[p] = true
	for p: String in emit_rate:
		planets[p] = true
	for p: String in planets:
		var co2: float = float(atmospheric_co2.get(p, 0.0)) * decay + float(emit_rate.get(p, 0.0)) * gain
		if co2 < 1.0:
			atmospheric_co2.erase(p)
		else:
			atmospheric_co2[p] = co2

## Current life expectancy in years: the 1945 baseline raised by each unlocked medical
## research node and reduced by pollution from a CO2-emitting power grid.
func _life_expectancy() -> float:
	var le: float = BASE_LIFE_EXPECTANCY
	for node_id: String in MEDICAL_RESEARCH:
		if ResearchTree.is_unlocked(node_id):
			le += float(MEDICAL_RESEARCH[node_id])
	le -= _dirty_power_fraction() * POLLUTION_LE_PENALTY
	le += PoliticsData.life_expectancy_bonus(policies)   # healthcare/welfare vs pollution
	return maxf(MIN_LIFE_EXPECTANCY, le)

## Fraction of total power generation (buildings + Dyson swarm) that comes from
## CO2-emitting plants — drives the pollution penalty on life expectancy.
func _dirty_power_fraction() -> float:
	var dirty: float = 0.0
	var total: float = 0.0
	if _prod_dirty:
		_recompute_production_cache()
	for p_name: String in _cached_planet_stats:
		var st: Dictionary = _cached_planet_stats[p_name]
		var pfac: Dictionary = _fuel_factor.get(p_name, {})
		total += float(st["e_total"])
		dirty += float(st["e_dirty"])
		# Idle (unfuelled) plants neither generate nor pollute — they scale out of both sides.
		for b_name: String in (_cached_planet_plants.get(p_name, {}) as Dictionary):
			var f: float = clampf(float(pfac.get(b_name, 1.0)), 0.0, 1.0)
			total += float((_cached_planet_plants[p_name][b_name] as Dictionary)["energy"]) * f
			dirty += float((st["e_fuel_dirty"] as Dictionary).get(b_name, 0.0)) * f
	total += _swarm_power()   # the swarm is clean
	return dirty / total if total > 0.0 else 0.0

# Returns compute rate (population + buildings, boosted by tech and policy).
func _get_compute_rate() -> float:
	if _prod_dirty:
		_recompute_production_cache()
	_combine_production()
	return _cached_compute

# Returns per-second production of every storable resource.
func _get_total_production() -> Dictionary:
	if _prod_dirty:
		_recompute_production_cache()
	_combine_production()
	return _cached_prod

func get_planet_data(planet_name: String) -> Dictionary:
	var d := {
		"name":       _body_display_name(planet_name),
		# Population is global and attributed to Earth (humanity's home); colonies
		# show 0 here.  Always a whole number of people.
		"population": int(world_pop.get(planet_name, 0)),   # this world's own population
		"energy":     0.0,
		"compute":    0.0,
	}

	var built: Array = planet_buildings.get(planet_name, [])
	var counts: Dictionary = {}
	var mine_output_rate: float = 0.0
	for b_name in built:
		var bdef := _find_building_def(b_name)
		d["energy"]  = d["energy"]  + bdef.get("production", {}).get("energy", 0.0)
		d["compute"] = d["compute"] + bdef.get("production", {}).get("compute", 0.0)
		mine_output_rate += float((bdef.get("production", {}) as Dictionary).get("minerals", 0.0))
		counts[b_name] = counts.get(b_name, 0) + 1

	# A planet's compute is dominated by its people: every individual contributes
	# the best unlocked evolution node's FLOP/s (buildings add on top).  Without
	# this the panel only showed the tiny building compute, missing the population.
	var flops_per_person: float = evolution_ui.get_unlocked_compute_per_individual() \
		if evolution_ui else 1.0e17
	d["compute"] = d["compute"] + float(d["population"]) * flops_per_person

	var buildings_list: Array = []
	for b_name in counts:
		buildings_list.append({"name": b_name, "count": counts[b_name]})
	d["buildings"] = buildings_list
	# Build composition with crust depleted by mining and the atmosphere's CO₂
	# raised by combustion emissions.  Uses this planet's own inventory.
	var inv: Dictionary = _planet_inv(planet_name)
	var raw_comp: Dictionary = _body_composition(planet_name)
	var added_co2: float = float(atmospheric_co2.get(planet_name, 0.0))
	if raw_comp.is_empty():
		d["composition_g"] = raw_comp
	else:
		var comp: Dictionary = {}
		for layer: String in raw_comp:
			if layer == "crust" and not inv.is_empty():
				var depleted: Dictionary = {}
				for compound: String in raw_comp["crust"]:
					depleted[compound] = maxf(
						0.0,
						float(raw_comp["crust"][compound]) - float(inv.get(compound, 0.0))
					)
				comp["crust"] = depleted
			elif layer == "atmosphere" and added_co2 > 0.0:
				# Duplicate so we never mutate the PlanetData constant.
				var atmo: Dictionary = (raw_comp["atmosphere"] as Dictionary).duplicate()
				atmo["CO2"] = float(atmo.get("CO2", 0.0)) + added_co2
				comp["atmosphere"] = atmo
			else:
				comp[layer] = raw_comp[layer]
		d["composition_g"] = comp
	d["compound_inventory"] = inv.duplicate()

	# Per-compound mine output: distribute mine_output_rate by crust mass fractions.
	var crust_comp: Dictionary = (_body_composition(planet_name) as Dictionary).get("crust", {})
	var mined: Dictionary = {}
	if mine_output_rate > 0.0 and not crust_comp.is_empty():
		var total_crust := 0.0
		for compound in crust_comp:
			total_crust += float(crust_comp[compound])
		if total_crust > 0.0:
			for compound in crust_comp:
				mined[compound] = float(crust_comp[compound]) / total_crust * mine_output_rate

	# Also surface any compounds currently in this planet's inventory that were
	# produced by manufacturing recipes (not mined), so the panel shows them.
	# Use a rate of 0 so they appear in the list without a misleading +x/s figure.
	for compound: String in inv:
		if float(inv[compound]) > 0.0 and not mined.has(compound):
			mined[compound] = 0.0

	d["mined_resources"] = mined

	# Manufacturing Capacity — effective work/day and the load the active recipes place
	# on it, so the panel shows how much industry this world can run (and whether it's
	# saturated).  Factories raise the capacity.
	d["mc_capacity"] = _planet_mc_capacity(planet_name)
	d["mc_used"]     = float((_last_mc_state.get(planet_name, {}) as Dictionary).get("demand", 0.0))
	# Civilisation-wide labour staffing fraction (0..1): the finite workforce can only run so
	# much built capacity, so a shrinking population throttles every world's MC until
	# automation research offsets it.
	d["labor_staffing"] = _mc_staffing()

	# Active construction on this world — its building speed is this planet's MC, so the
	# panel can show what's being raised and how close it is.
	var queue: Array = build_queue.get(planet_name, [])
	var mc_rate: float = _planet_free_mc(planet_name)   # spare capacity after recipes
	var con_list: Array = []
	for job: Dictionary in queue:
		var work: float = maxf(1.0, float(job.get("work", 1.0)))
		var prog: float = float(job.get("progress", 0.0))
		var eta: float = (work - prog) / mc_rate if mc_rate > 0.0 else -1.0
		con_list.append({
			"name": str(job.get("building", "")),
			"frac": clampf(prog / work, 0.0, 1.0),
			"eta_days": eta,   # of the front job; later jobs wait their turn
		})
	d["construction"] = con_list

	# Storage — per-planet capacity and global usage for the info panel.
	d["storage_cap"]        = _get_planet_storage_cap(planet_name)
	d["global_storage_cap"] = _cached_storage_caps.duplicate()
	d["global_resources"]   = {
		"minerals": ResearchTree.resources.get("minerals", 0.0),
		"energy":   ResearchTree.resources.get("energy",   0.0),
	}

	return d

## Current stockpile of every resource/compound that appears in any building cost,
## for the build panel's live affordability colouring (uses the viewed planet's
## inventory, since you build with what's stored on that planet).
func _build_cost_stockpiles() -> Dictionary:
	var have: Dictionary = {}
	for b: Dictionary in BuildingData.all():
		for res: String in (b.get("cost", {}) as Dictionary):
			if not have.has(res):
				have[res] = _get_stockpile(res, current_planet)
	return have

func _get_catalog_for_display() -> Array:
	var has_colony: bool   = _is_body_buildable(current_planet)
	var planet_type: String = PLANET_TYPES.get(current_planet, "rocky")   # moons → rocky
	var built: Array = planet_buildings.get(current_planet, [])
	# Tally once instead of rescanning the roster per catalogue entry.  With single-building
	# scale a world holds thousands of structures, and the old nested scan was O(built × catalogue)
	# — tens of millions of comparisons per refresh.
	var tally: Dictionary = {}
	for bn in built:
		tally[bn] = int(tally.get(bn, 0)) + 1
	var result: Array = []
	for b: Dictionary in BuildingData.all():
		var cnt: int = int(tally.get(b["name"], 0))
		# Non-buildable 1945 power plants always remain listed on Earth (their home),
		# even after the player demolishes the last one — so the entry never vanishes.
		# On other worlds they show only while owned.
		var buildable: bool = b.get("buildable", true)
		if not buildable and cnt == 0 and current_planet != "earth":
			continue
		# Buildings incompatible with this planet type are hidden entirely —
		# not grayed out.  There is no point advertising a Mine on a gas giant.
		var allowed: Array = b.get("allowed_types", [])
		if not allowed.is_empty() and planet_type not in allowed:
			continue
		var entry: Dictionary = b.duplicate()
		# A generated tier carries its own gate; the base tier uses the authored table.
		var req: String = str(b.get("level_research", ""))
		if req == "":
			req = BuildingUnlocks.BUILDING_UNLOCK_REQUIREMENTS.get(str(b.get("base_name", b["name"])), "")
		var tech_ok: bool = req == "" or ResearchTree.is_unlocked(req)
		entry["available"] = has_colony and tech_ok
		if not has_colony:
			entry["requires"] = "colony_mission"
		elif not tech_ok:
			entry["requires"] = req
		else:
			entry["requires"] = ""
		entry["count"] = cnt
		entry["active"] = clampi(int((active_buildings.get(current_planet, {}) as Dictionary)
			.get(b["name"], cnt)), 0, cnt)
		entry["upkeep"] = float(b.get("_upkeep", 0.0))
		entry["in_progress"] = _queued_count(current_planet, b["name"])
		# Current stockpile (on this planet) of each cost resource so the panel can
		# dim the ones the player can't yet afford here.
		var have: Dictionary = {}
		for res: String in (b.get("cost", {}) as Dictionary):
			have[res] = _get_stockpile(res, current_planet)
		entry["have"] = have
		# Upgrade path: what this tier becomes, what the retrofit costs, and whether it can be
		# done right now (one standing, the next tier researched, and the difference affordable).
		var nxt: String = _next_level_name(str(b["name"]))
		entry["next_level"] = nxt
		if nxt != "":
			var up_cost: Dictionary = _upgrade_cost(str(b["name"]), nxt)
			entry["upgrade_cost"] = up_cost
			entry["upgrade_label"] = str(_find_building_def(nxt).get("name", nxt))
			var nreq: String = str(_find_building_def(nxt).get("level_research", ""))
			var afford: bool = true
			for res: String in up_cost:
				have[res] = _get_stockpile(res, current_planet)   # so it dims like a build cost
				if float(have[res]) < float(up_cost[res]):
					afford = false
			entry["can_upgrade"] = cnt > 0 and afford \
				and (nreq == "" or ResearchTree.is_unlocked(nreq))
		result.append(entry)
	return result

## Produces a human-readable label for the planet-type requirement,
## e.g. ["rocky"] → "rocky planet"  |  ["rocky","gas_giant"] → "rocky or gas giant planet"
func _building_type_label(allowed_types: Array) -> String:
	var names: Array = allowed_types.map(func(t: String) -> String:
		return t.replace("_", " "))
	return " or ".join(names) + " planet"

func select_planet(planet_name: String) -> void:
	# Any body can be inspected without a probe; only an empty id is rejected.
	if not _is_body_selectable(planet_name):
		return
	current_planet = planet_name
	sidebar.hide_all()
	# Populate every tab up front, then reveal the merged panel (tabs switch between them).
	planet_info_page.set_planet_info(get_planet_data(planet_name))
	build_panel.set_planet(planet_name, _get_catalog_for_display())
	if _population_page:
		_population_page.set_stats(_population_stats(current_planet))
	if _inventory_page:
		_inventory_page.set_inventory(planet_name, get_planet_data(planet_name))
	if _extraction_page:
		_extraction_page.set_extraction(planet_name, extraction_data(planet_name))
	if production_panel:
		production_panel.set_planet(planet_name)
		production_panel.set_mc_state(_last_mc_state)
	_build_ui_dirty = false
	if _planet_tabs:
		_planet_tabs.show()

## Attempt to build one `building_name` on `planet_name`.  Returns true on success,
## false if it's invalid, research-locked, or unaffordable (the automation executor
## relies on the return value to know when to stop topping up a maintained count).
func try_build(planet_name: String, building_name: String) -> bool:
	var building := _find_building_def(building_name)
	if building.is_empty():
		return false

	if not _is_body_buildable(planet_name):
		return false

	# A generated tier carries its own gate; the base tier uses the authored table.
	var req: String = str(building.get("level_research", ""))
	if req == "":
		req = BuildingUnlocks.BUILDING_UNLOCK_REQUIREMENTS.get(
			str(building.get("base_name", building_name)), "")
	if req != "" and not ResearchTree.is_unlocked(req):
		return false

	# Pay with global resources (energy) and this planet's local compound inventory.
	var cost: Dictionary = building.get("cost", {})
	for resource: String in cost:
		if _get_stockpile(resource, planet_name) < float(cost[resource]):
			return false

	for resource: String in cost:
		_deduct_stockpile(resource, float(cost[resource]), planet_name)

	# Queue the structure for construction rather than raising it instantly: it now takes
	# work that the planet's Manufacturing Capacity grinds through over game-time.
	if not build_queue.has(planet_name):
		build_queue[planet_name] = []
	build_queue[planet_name].append({
		"building": building_name,
		"work": _building_work(building),
		"progress": 0.0,
	})

	# Panels refresh on the throttled tick in _process (coalesced), not per queued build —
	# rebuilding the BuildPanel node tree on every try_build was a construction-lag source.
	_build_ui_dirty = true
	return true

# ── Building levels ───────────────────────────────────────────────────────────

## The next tier up from `building_name` ("Mine" → "Mine II"), or "" at the top of the line.
func _next_level_name(building_name: String) -> String:
	var def: Dictionary = _find_building_def(building_name)
	if def.is_empty():
		return ""
	var base: String = str(def.get("base_name", building_name))
	var want: int = int(def.get("level", 1)) + 1
	for b: Dictionary in BuildingData.all():
		if str(b.get("base_name", "")) == base and int(b.get("level", 1)) == want:
			return str(b["name"])
	return ""

## What a retrofit costs: the DIFFERENCE between the two tiers, so the materials already
## standing in the old structure count toward the new one.  Resources the higher tier needs
## less of simply drop out (no refunds).
func _upgrade_cost(from_name: String, to_name: String) -> Dictionary:
	var from_cost: Dictionary = _find_building_def(from_name).get("cost", {})
	var to_cost:   Dictionary = _find_building_def(to_name).get("cost", {})
	var out: Dictionary = {}
	for res: String in to_cost:
		var delta: float = float(to_cost[res]) - float(from_cost.get(res, 0.0))
		if delta > 0.0:
			out[res] = delta
	return out

## How many upgrades OUT of `building_name` are already queued on this world — so the player
## can't queue more retrofits than they have standing structures to retrofit.
func _queued_upgrades(planet_name: String, building_name: String) -> int:
	var n: int = 0
	for job: Dictionary in build_queue.get(planet_name, []):
		if str(job.get("upgrade_from", "")) == building_name:
			n += 1
	return n

## Retrofit one standing `building_name` into the next tier up.  Charges only the difference in
## materials and queues the work like any other construction — the old structure keeps running
## until the retrofit completes, then is consumed by it (see _complete_build).
func try_upgrade(planet_name: String, building_name: String) -> bool:
	var to_name: String = _next_level_name(building_name)
	if to_name == "" or not _is_body_buildable(planet_name):
		return false
	# Need a structure that isn't already spoken for by a queued retrofit.
	if _count_building(planet_name, building_name) - _queued_upgrades(planet_name, building_name) <= 0:
		return false
	var to_def: Dictionary = _find_building_def(to_name)
	var req: String = str(to_def.get("level_research", ""))
	if req != "" and not ResearchTree.is_unlocked(req):
		return false
	var cost: Dictionary = _upgrade_cost(building_name, to_name)
	for res: String in cost:
		if _get_stockpile(res, planet_name) < float(cost[res]):
			return false
	for res: String in cost:
		_deduct_stockpile(res, float(cost[res]), planet_name)
	if not build_queue.has(planet_name):
		build_queue[planet_name] = []
	# Half the work of building the tier outright — you are enlarging a structure, not
	# raising one from nothing.
	build_queue[planet_name].append({
		"building": to_name,
		"upgrade_from": building_name,
		"work": _building_work(to_def) * 0.5,
		"progress": 0.0,
	})
	_build_ui_dirty = true
	return true

## Work (MC·days) needed to assemble a building: the bulk of its material bill, so larger
## structures take proportionally longer.  A planet builds at its MC (work/day), so the
## build time is _building_work / mc_capacity — higher industry ⇒ faster construction.
func _building_work(building: Dictionary) -> float:
	var w: float = 0.0
	for key: String in (building.get("cost", {}) as Dictionary):
		if key == "energy" or key == "science":
			continue          # global pools, not assembled mass
		w += float(building["cost"][key])
	return maxf(BASE_MC * 0.25, w)   # floor so even cheap builds take a beat

## Advance every planet's construction queue.  Each world pours its Manufacturing Capacity
## (work-units/day) into its queued builds in order; a structure is raised the instant its
## work is met, and a fast world can finish several in one time-slice.
func _process_construction(delta_days: float) -> void:
	if build_queue.is_empty() or delta_days <= 0.0:
		return
	for planet: String in build_queue.keys():
		var jobs: Array = build_queue[planet]
		if jobs.is_empty():
			continue
		# Construction uses the manufacturing capacity left AFTER recipes — a world running
		# its factories flat-out has nothing spare to build with until it adds capacity.
		var budget: float = _planet_free_mc(planet) * delta_days   # spare work available
		while budget > 0.0 and not jobs.is_empty():
			var job: Dictionary = jobs[0]
			var need: float = float(job["work"]) - float(job["progress"])
			if budget >= need:
				budget -= need
				jobs.pop_front()
				_complete_build(planet, job)
			else:
				job["progress"] = float(job["progress"]) + budget
				budget = 0.0
		if jobs.is_empty():
			build_queue.erase(planet)

## Finish a construction job: the building now exists, so register it and refresh anything
## that depends on the planet's roster (production cache, panels, star-map weapons).
func _complete_build(planet_name: String, job: Dictionary) -> void:
	var building_name: String = str(job.get("building", ""))
	if building_name == "":
		return
	if not planet_buildings.has(planet_name):
		planet_buildings[planet_name] = []
	# A retrofit consumes the structure it grew out of.  Done here rather than at queue time so
	# the old building keeps producing for the whole span of the upgrade.  If it vanished in the
	# meantime (demolished, or wiped with the colony) the new tier still stands — the materials
	# were already paid, so swallowing them would be the worse outcome.
	var from_name: String = str(job.get("upgrade_from", ""))
	if from_name != "":
		var built: Array = planet_buildings[planet_name]
		var idx: int = built.rfind(from_name)
		if idx != -1:
			built.remove_at(idx)
	planet_buildings[planet_name].append(building_name)
	_mark_prod_dirty()

	# Panels refresh on the throttled tick in _process — many completions in one frame
	# (fast-forward) collapse into a single rebuild instead of one per building.
	_build_ui_dirty = true
	if building_name == "Orbital Laser" and sidebar and sidebar.star_map and sidebar.star_map.visible:
		refresh_star_map()   # the laser is now available as a star-map weapon

## How many of `building_name` are queued (under construction) on `planet_name`.
func _queued_count(planet_name: String, building_name: String) -> int:
	var c: int = 0
	for job: Dictionary in build_queue.get(planet_name, []):
		if str(job.get("building", "")) == building_name:
			c += 1
	return c

## Number of `building_name` currently standing on `planet_name`.
func _count_building(planet_name: String, building_name: String) -> int:
	# Read the tally the roster pass already built rather than rescanning thousands of entries —
	# batch actions call this repeatedly, and at 10 000 buildings the scan dominated them.
	if _prod_dirty:
		_recompute_production_cache()
	return int((_cached_planet_counts.get(planet_name, {}) as Dictionary).get(building_name, 0))

func _on_build_requested(planet_name: String, building_name: String, count: int = 1) -> void:
	# A manual click gets instant feedback (works while paused, when the throttled tick is
	# not running).  Automation calls try_build directly and stays coalesced/throttled.
	# A batch stops at the first failure, so "+100" with materials for 40 queues 40.
	var placed: int = 0
	for _i in range(maxi(1, count)):
		if not try_build(planet_name, building_name):
			break
		placed += 1
	if placed > 0:
		planet_info_page.set_planet_info(get_planet_data(planet_name))
		if build_panel.visible:
			build_panel.apply_counts(_get_catalog_for_display())   # patch counts in place, no rebuild
		_build_ui_dirty = false

## Player moved a building's active-count slider: switch that many on and refresh the readouts
## (the roster cache is already marked dirty by set_active_count).
func _on_active_changed(planet_name: String, building_name: String, count: int) -> void:
	set_active_count(planet_name, building_name, count)
	planet_info_page.set_planet_info(get_planet_data(planet_name))
	_update_hud()

## Player pressed Upgrade on a building's dropdown: queue the retrofit and refresh the panel
## the same coalesced way a manual build does.
func _on_upgrade_requested(planet_name: String, building_name: String, count: int = 1) -> void:
	var done: int = 0
	for _i in range(maxi(1, count)):
		if not try_upgrade(planet_name, building_name):
			break
		done += 1
	if done > 0:
		planet_info_page.set_planet_info(get_planet_data(planet_name))
		if build_panel.visible:
			build_panel.apply_counts(_get_catalog_for_display())
		_build_ui_dirty = false

func _on_demolish_requested(planet_name: String, building_name: String, count: int = 1) -> void:
	var built: Array = planet_buildings.get(planet_name, [])
	# Enforce per-building minimums (e.g. always keep ≥1 Biomass Burner so energy
	# production can't collapse and soft-lock the economy).
	var standing: int = 0
	for bn in built:
		if bn == building_name:
			standing += 1
	var min_count: int = int((_bdef_cache.get(building_name, {}) as Dictionary).get("min_count", 0))
	# Take down as many as asked, stopping at the floor — a batch never over-demolishes.
	var removable: int = mini(maxi(1, count), standing - min_count)
	if removable <= 0:
		return
	for _i in range(removable):
		var idx: int = built.rfind(building_name)   # remove the last-placed copy
		if idx == -1:
			break
		built.remove_at(idx)
	_mark_prod_dirty()
	planet_info_page.set_planet_info(get_planet_data(planet_name))
	if build_panel.visible:
		build_panel.apply_counts(_get_catalog_for_display())   # in place; self-heals if a row vanished
	if launch_panel.visible:
		launch_panel.set_launch_mods(_build_launch_mods_map())

func _on_research_completed(node: ResearchNode) -> void:
	_mark_prod_dirty()
	print("[Game] Unlocked: %s" % node.display_name)
	if current_planet != "" and build_panel.visible:
		build_panel.set_planet(current_planet, _get_catalog_for_display())
	production_panel.refresh_recipes(_completed_research_map())
	if node.id == LAUNCH_UNLOCK_RESEARCH:
		_refresh_launch_access()   # reveal Launches the moment Early Rocketry lands
	if node.id == AUTOMATION_UNLOCK_RESEARCH:
		_refresh_automation_access()   # reveal Automation the moment Industrial AI lands
	_check_population_splits()

# ── Date helpers ─────────────────────────────────────────────────────────────

func _days_in_month(m: int, y: int) -> int:
	var base: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if m == 1 and is_leap(y):
		return 29
	return base[m]

## Absolute day index relative to 2026-01-01.  Computed in closed form so it
## stays O(1) even at the billions-of-years timescales the late game reaches —
## a per-year loop here would hang the game once `year` grows large.
func _to_abs_day(y: int, m: int, d: int) -> int:
	var total := d
	for i in range(m):
		total += _days_in_month(i, y)
	return total + _year_start_abs_day(y)

## Days from 2026-01-01 to the first day of year `y` (negative before 2026).
func _year_start_abs_day(y: int) -> int:
	return _days_since_year_one(y) - _days_since_year_one(2026)

## Days elapsed from 0001-01-01 to the first day of year `y`, using the
## proleptic Gregorian leap rule (matches is_leap()).  Closed-form, no loops.
func _days_since_year_one(y: int) -> int:
	var n := y - 1                                   # completed years before y
	return n * 365 + _leap_years_through(n)

## Count of leap years in the inclusive range [year 1 .. year `y`].
func _leap_years_through(y: int) -> int:
	if y <= 0:
		return 0
	@warning_ignore("integer_division")
	var count := y / 4 - y / 100 + y / 400
	return count

func _date_add_days(sy: int, sm: int, sd: int, n: int) -> Array:
	var ry := sy
	var rm := sm
	var rd := sd + n
	while rd >= _days_in_month(rm, ry):
		rd -= _days_in_month(rm, ry)
		rm += 1
		if rm >= 12:
			rm = 0
			ry += 1
	return [ry, rm, rd]

# ── Launch logic ──────────────────────────────────────────────────────────────

func _compute_launch_display_data() -> Array:
	var result: Array = []
	var today_abs := _to_abs_day(year, month, day)
	for launch in active_launches:
		var entry: Dictionary = (launch as Dictionary).duplicate()
		if launch["status"] == "active":
			var end_abs := _to_abs_day(
				int(launch["end_year"]), int(launch["end_month"]), int(launch["end_day"])
			)
			entry["days_remaining"] = max(0, end_abs - today_abs)
		result.append(entry)
	return result

func _on_launch_requested(params: Dictionary) -> void:
	var m_name: String = params.get("mission", "")
	var mission_def: Dictionary = {}
	for m in MissionData.MISSION_TYPES:
		if m["name"] == m_name:
			mission_def = m
			break
	if mission_def.is_empty():
		return

	var origin_name: String = params.get("origin", "earth")
	var target_name: String = params.get("target", "")
	var arrival: String = params.get("arrival", "orbit")

	# Solar Deployment ferries a batch of manufactured Solar Satellites to the Sun.
	# Validate (and size) the payload before spending anything on the launch vehicle.
	var sat_payload: int = 0
	if mission_def.get("sun_only", false):
		if target_name != "sun":
			return                                    # this carrier only flies to the Sun
		var room: int = _swarm_max() - solar_satellites_deployed
		if room <= 0:
			return                                    # swarm already full
		var avail: int = int(_get_stockpile(mission_def.get("payload", ""), origin_name))
		sat_payload = mini(int(mission_def.get("payload_per_launch", 0)), mini(avail, room))
		if sat_payload <= 0:
			return                                    # no satellites stockpiled to loft

	# Propellant is the ENTIRE cost of a launch, drawn from the origin world's inventory.  The
	# quantity was derived from the trajectory's energy requirement (LaunchPlanner.propellant_mass),
	# so a harder transfer or a worse window is paid for in fuel and nothing else.
	var fuel_id: String = str(params.get("fuel_id", ""))
	var fuel_amount: float = float(params.get("fuel_amount", 0.0))
	if fuel_id == "" or _get_stockpile(fuel_id, origin_name) < fuel_amount:
		return
	if fuel_amount > 0.0:
		_deduct_stockpile(fuel_id, fuel_amount, origin_name)
	if sat_payload > 0:
		_deduct_stockpile(mission_def.get("payload", ""), float(sat_payload), origin_name)

	var start_offset: int = params.get("start_offset", 0)
	# The panel already folded the policy duration multiplier into params.duration,
	# so use it directly — re-applying here would shorten the trip twice and make
	# the actual arrival disagree with the time shown at launch.
	var duration: int    = int(params.get("duration", 30))
	var start_date := _date_add_days(year, month, day, start_offset)
	var end_date   := _date_add_days(start_date[0], start_date[1], start_date[2], duration)

	var launch := {
		"id":          _next_launch_id,
		"mission":     m_name,
		"origin":      origin_name,
		"target":      target_name,
		"arrival":     arrival,
		"payload":     sat_payload,
		"start_year":  start_date[0],
		"start_month": start_date[1],
		"start_day":   start_date[2],
		"end_year":    end_date[0],
		"end_month":   end_date[1],
		"end_day":     end_date[2],
		"status":      "active",
	}
	_next_launch_id += 1
	active_launches.append(launch)
	launch_panel.refresh_launches(_compute_launch_display_data())

	# Sending a Survey probe unlocks that body's planet-bar button.
	if m_name == "Survey":
		_mark_surveyed(target_name)

	# Spawn a craft for every launch, including local orbit insertions where the
	# target is the origin planet itself (it just settles straight into orbit).
	if target_name != "":
		var origin_planet := get_node_or_null("WorldRoot/Planets/" + origin_name) as Planet
		var target_planet := get_node_or_null("WorldRoot/Planets/" + target_name) as Planet
		if origin_planet and target_planet:
			if sat_payload > 0:
				# Solar Deployment: the rocket flies to its reserved swarm slot and, on
				# arrival, becomes the deployed collector there.
				var reserved: int = solar_satellites_deployed + _pending_swarm
				_pending_swarm += 1
				var planets := get_node_or_null("WorldRoot/Planets")
				var slot_pos: Vector3 = origin_planet.global_position
				if planets and planets.has_method("swarm_slot_world_pos"):
					slot_pos = planets.swarm_slot_world_pos(reserved)
				_spawn_swarm_satellite(origin_planet, slot_pos, launch["id"], float(duration))
			else:
				_spawn_satellite(origin_planet, target_planet, arrival, launch["id"], float(duration))

## Best (lowest) launch cost & duration multipliers a planet's infrastructure
## grants (e.g. a Space Elevator).  Returns {"cost": float, "duration": float};
## {1.0, 1.0} when the planet has no launch-modifying building.
func _planet_launch_mods(planet_name: String) -> Dictionary:
	var cost_mult: float = 1.0
	var dur_mult:  float = 1.0
	for b_name: String in planet_buildings.get(planet_name, []):
		var bdef: Dictionary = _bdef_cache.get(b_name, {})
		if bdef.has("launch_cost_mult"):
			cost_mult = minf(cost_mult, float(bdef["launch_cost_mult"]))
		if bdef.has("launch_duration_mult"):
			dur_mult = minf(dur_mult, float(bdef["launch_duration_mult"]))
	return {"cost": cost_mult, "duration": dur_mult}

## Per-planet Solar Satellite stock, so the LaunchPanel can size/gate a Solar
## Deployment's payload by the chosen origin.
func _build_satellite_stock() -> Dictionary:
	var out: Dictionary = {}
	for p: String in compound_inventory:
		out[p] = int(float((compound_inventory[p] as Dictionary).get("SolarSatellite", 0.0)))
	return out

## Per-planet stock of the rockets + fuels a launch can draw on, so the LaunchPanel
## can show "have N" and refuse to fly when the origin can't cover the cost.
func _build_launch_stock() -> Dictionary:
	var keys: Array = ["Rocket"]
	for f: Dictionary in MissionData.FUELS:
		keys.append(str(f["id"]))
	var out: Dictionary = {}
	for p: String in compound_inventory:
		var inv: Dictionary = compound_inventory[p]
		var stock: Dictionary = {}
		for k: String in keys:
			stock[k] = int(float(inv.get(k, 0.0)))
		out[p] = stock
	return out

## Map of { planet_name → {cost, duration} } for every planet whose buildings
## discount launches, so the LaunchPanel can adjust cost/time by chosen origin.
func _build_launch_mods_map() -> Dictionary:
	var out: Dictionary = {}
	for planet_name: String in planet_buildings:
		var mods: Dictionary = _planet_launch_mods(planet_name)
		if mods["cost"] < 1.0 or mods["duration"] < 1.0:
			out[planet_name] = mods
	return out

## Called by the sidebar when the Launches view is opened, so the panel reflects
## the current date, defaults its origin to the planet being viewed, and shows any
## launch-infrastructure discounts (e.g. a Space Elevator).
func refresh_launch_panel() -> void:
	launch_panel.set_game_date(year, month + 1, day + 1)
	launch_panel.set_current_planet(current_planet)
	launch_panel.set_launch_mods(_build_launch_mods_map())
	launch_panel.set_mission_duration_mult(_policy_mission_dur_mult())
	launch_panel.refresh_fuels()
	launch_panel.set_orbital_state(_build_orbital_state())
	launch_panel.set_swarm_state(_build_satellite_stock(), solar_satellites_deployed, _swarm_max())
	launch_panel.set_launch_stock(_build_launch_stock())
	launch_panel.refresh_launches(_compute_launch_display_data())

# ── Interstellar colonisation ─────────────────────────────────────────────────

## Distance (ly) to a named star, from the star-map catalogue.
## name → star record.  _star_pos / _star_distance_ly used to LINEAR-SCAN the whole catalogue on
## every call, and they are called from inside loops over alien systems and candidate targets —
## at ten thousand stars that made the yearly alien pass quadratic and cost whole frames.  The
## catalogue only ever grows (the observation range is monotonic), so a size change is a
## sufficient staleness check.
var _star_index: Dictionary = {}
var _star_index_size: int = -1

func _star_lookup(star_name: String) -> Dictionary:
	var all: Array = StarMapPanel.all_stars()
	if all.size() != _star_index_size:
		_star_index.clear()
		for s: Dictionary in all:
			_star_index[str(s["name"])] = s
		# Clusters are colonisation targets too, and the mission machinery addresses everything
		# by name — so they live in the same index and _star_pos/_star_distance_ly just work.
		for c: Dictionary in StarMapPanel.star_clusters():
			_star_index[str(c["name"])] = c
		_star_index_size = all.size()
	return _star_index.get(star_name, {})

func _star_distance_ly(star_name: String) -> float:
	return float(_star_lookup(star_name).get("dist", 0.0))

## Launch an interstellar colony ship from Sol to a star with a chosen max speed β and
## max acceleration.  The real relativistic energy (accel + coast + decel for the ship's
## mass over the distance) is computed by StarMapPanel.plan_flight and gated on reserves.
func _on_colonize_requested(star_name: String, gamma_max: float, accel: float) -> void:
	if star_name == "" or colonized_stars.has(star_name):
		return
	if not ResearchTree.is_unlocked("relativistic_navigation"):
		return   # interstellar flight is gated on Relativistic Navigation research
	for m in interstellar_missions:
		if str(m.get("target", "")) == star_name:
			return   # already en route
	var dist: float = _star_distance_ly(star_name)
	if dist <= 0.0:
		return
	var plan: Dictionary = StarMapPanel.plan_flight(dist, gamma_max, accel)
	var cost: float = float(plan["energy"])
	if ResearchTree.resources.get("energy", 0.0) < cost:
		return
	ResearchTree.resources["energy"] = maxf(0.0,
		float(ResearchTree.resources.get("energy", 0.0)) - cost)
	var years: float = float(plan["years"])
	var peak_beta: float = float(plan["peak_beta"])
	var peak_gamma: float = float(plan["peak_gamma"])
	interstellar_missions.append({
		"target":     star_name,
		"start_year": float(year),
		"end_year":   float(year) + years,
		"speed_c":    peak_beta,
		"gamma":      peak_gamma,
		"accel_time_frac": float(plan.get("accel_time_frac", 0.5)),
		"accel_dist_frac": float(plan.get("accel_dist_frac", 0.5)),
	})
	# Describe the cruise speed as %c while meaningful, otherwise as a Lorentz factor.
	var speed_desc: String = ("%d%% c" % int(round(peak_beta * 100.0))) if peak_gamma < 100.0 \
		else ("γ %s" % Units.format_si(peak_gamma, ""))
	_announce("Interstellar Launch",
		"A colony ship departs Sol for %s, cruising at %s. Estimated arrival: year %d (%s transit)." % [
			star_name, speed_desc, int(round(float(year) + years)), Units.format_si(years, "yr")],
		"interstellar_launch_%s_%d" % [star_name, year])
	refresh_star_map()

## Complete any colony ships whose arrival year has passed → the star is colonised.
func _check_interstellar_arrivals() -> void:
	if interstellar_missions.is_empty():
		return
	var still: Array = []
	var newly_vn: Array = []   # von Neumann probes that just colonised — they replicate onward
	for m in interstellar_missions:
		if float(year) >= float(m.get("end_year", INF)):
			var target: String = str(m.get("target", ""))
			if target != "" and not colonized_stars.has(target):
				_reveal_alignment(target)   # first contact: the system's alignment is now known
				var tpos: Vector3 = _star_pos(target)
				var vn: bool = bool(m.get("vn", false))
				if tpos.length() > DETAILED_RADIUS_LY:
					# Far colony — folded into the statistical region; no individual world, and no
					# individual replication (the region spreads statistically from here on).
					# Silent — the autonomous swarm's per-region events would flood the timeline;
					# progress is summarised by _vn_check_milestone instead.
					_region_colonize(tpos)
				else:
					colonized_stars.append(target)
					_colony_year[target] = year   # start its infrastructure clock
					world_pop[target] = maxf(float(world_pop.get(target, 0.0)), COLONY_SEED_POP)
					if not vn:
						_announce("Interstellar Colony",
							"A self-sustaining human colony is established around %s. Inhabited star systems: %d." % [
								target, colonized_stars.size() + 1],
							"interstellar_arrival_%s_%d" % [target, year])
					else:
						newly_vn.append(target)
		else:
			still.append(m)
	interstellar_missions = still
	for t in newly_vn:
		_vn_replicate(str(t))   # spawn the next generation of probes from each new colony
	_vn_check_milestone()
	refresh_star_map()

## Announce only when the grand total of settled systems + colonised regions crosses a milestone —
## keeps the autonomous swarm's progress on the timeline without an entry per colony.
func _vn_check_milestone() -> void:
	var settled: int = colonized_stars.size() + _regions.size()
	while _vn_milestone_idx < VN_MILESTONES.size() and settled >= int(VN_MILESTONES[_vn_milestone_idx]):
		var m: int = int(VN_MILESTONES[_vn_milestone_idx])
		_vn_milestone_idx += 1
		_announce("Colonisation milestone",
			"Human colonisation now spans %d star systems and galactic regions." % settled,
			"vn_milestone_%d" % m)

## Number of von Neumann probes currently in flight.
func _vn_inflight() -> int:
	var n: int = 0
	for m in interstellar_missions:
		if bool((m as Dictionary).get("vn", false)):
			n += 1
	return n

## Whether autonomous colonisation is possible at all (both techs researched).
func _vn_unlocked() -> bool:
	return ResearchTree.is_unlocked("relativistic_navigation") \
		and ResearchTree.is_unlocked("self_replicating_industry")

## Launch a von Neumann probe from `from_pos` (ly, Sol-relative) to `target_star`, if it isn't
## already colonised/en-route, the in-flight cap allows it, and the energy is affordable.
## Returns true on launch.  The energy cost is a light fraction of a colony ship's — expansion is
## still throttled by the shared energy pool, so a broke civilisation stops spreading.
func _vn_launch(target_star: String, from_pos: Vector3) -> bool:
	if not _vn_unlocked() or target_star == "" or colonized_stars.has(target_star):
		return false
	if _vn_inflight() >= VN_MAX_INFLIGHT:
		return false
	for m in interstellar_missions:
		if str(m.get("target", "")) == target_star:
			return false   # already en route
	var dist: float = maxf(from_pos.distance_to(_star_pos(target_star)), 0.01)
	var plan: Dictionary = StarMapPanel.plan_flight(dist, VN_GAMMA, VN_ACCEL)
	var cost: float = float(plan["energy"]) * VN_MASS_FRAC
	if float(ResearchTree.resources.get("energy", 0.0)) < cost:
		return false
	ResearchTree.resources["energy"] = maxf(0.0,
		float(ResearchTree.resources.get("energy", 0.0)) - cost)
	interstellar_missions.append({
		"target": target_star, "vn": true,
		"start_year": float(year), "end_year": float(year) + float(plan["years"]),
		"speed_c": float(plan["peak_beta"]), "gamma": float(plan["peak_gamma"]),
		"accel_time_frac": float(plan.get("accel_time_frac", 0.5)),
		"accel_dist_frac": float(plan.get("accel_dist_frac", 0.5)),
	})
	return true

## A colony founded by a probe sends the next generation to the nearest uncolonised stars it can
## resolve (no tight distance cap — the galaxy is sparse, so a probe hops as far as it must).
func _vn_replicate(from_star: String) -> void:
	if colonized_stars.size() >= VN_MAX_COLONIES:
		return
	var origin: Vector3 = _star_pos(from_star)
	for tgt in _nearest_uncolonised(origin, VN_REPLICATE_COUNT, INF):
		_vn_launch(str(tgt), origin)

## The nearest uncolonised, not-en-route stars within `max_ly` of `origin` (up to `max_n`).
func _nearest_uncolonised(origin: Vector3, max_n: int, max_ly: float) -> Array:
	var cand: Array = []   # [dist, name]
	var enroute: Dictionary = {}
	for m in interstellar_missions:
		enroute[str(m.get("target", ""))] = true
	for s: Dictionary in StarMapPanel.all_stars():
		var nm: String = str(s["name"])
		if colonized_stars.has(nm) or enroute.has(nm):
			continue
		var spos: Vector3 = s["pos"]
		# A far star whose region is already colonised is left to statistical diffusion — a probe
		# only needs to seed each far region ONCE, which keeps individual probes bounded.
		if spos.length() > DETAILED_RADIUS_LY and _region_taken(spos):
			continue
		var d: float = origin.distance_to(spos)
		if d <= max_ly and d > 0.01:
			cand.append([d, nm])
	cand.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var out: Array = []
	for i in range(mini(max_n, cand.size())):
		out.append(str(cand[i][1]))
	return out

## Hands-free seeding: while the directive is on and nothing is spreading, launch a fresh probe
## toward the nearest uncolonised star from Sol (or the frontier).  Replication then self-sustains.
func _process_vn_colonization() -> void:
	if game_over or not _vn_enabled or not _vn_unlocked():
		return
	if colonized_stars.size() >= VN_MAX_COLONIES:
		return
	if _vn_inflight() > 0:
		return   # a swarm is already spreading — let it run
	# Seed from Sol.  (Replication carries it onward from each colony's own neighbourhood.)
	for tgt in _nearest_uncolonised(Vector3.ZERO, 1, INF):
		if _vn_launch(str(tgt), Vector3.ZERO):
			# Fixed id → announced only the first time a swarm is seeded, not on every re-seed.
			_announce("Von Neumann probe launched",
				"A self-replicating colony probe departs Sol. It will spread from star to star on arrival.",
				"vn_first_launch")
		break

# ── Statistical galaxy regions (frontier aggregation) ────────────────────────────
## Tile id ("q,r") of the hexagonal prism containing a Sol-relative position: a flat-top hex
## axial coordinate in the galactic plane.  The prism is a single tall column (no vertical
## stacking), so height plays no part in the id.
## Origin of the region lattice, in Sol-relative coordinates: the GALACTIC CENTRE.  Anchoring
## there rather than on Sol puts the centre of the galaxy exactly at the centre of tile "0,0",
## and lets the grid cover the whole disk from one radius instead of reaching 86 000 ly to catch
## the far rim from an off-centre origin.
func _region_origin() -> Vector3:
	return (_gal_axes()[0] as Vector3) * StarMapPanel.SOL_GC_LY

func _region_id(pos: Vector3) -> String:
	var ax: Array = _gal_axes()
	var rel: Vector3 = pos - _region_origin()    # measured from the galactic centre
	var gpx: float = rel.dot(ax[0] as Vector3)   # galactic in-plane x (toward centre)
	var gpy: float = rel.dot(ax[1] as Vector3)   # galactic in-plane y (toward l=90)
	var qf: float = (2.0 / 3.0 * gpx) / HEX_SIZE
	var rf: float = (-1.0 / 3.0 * gpx + HEX_SQRT3 / 3.0 * gpy) / HEX_SIZE
	var hex: Vector2i = _hex_round(qf, rf)
	return "%d,%d" % [hex.x, hex.y]

## Round fractional axial hex coords to the nearest hex (via cube rounding).
func _hex_round(q: float, r: float) -> Vector2i:
	var x: float = q
	var z: float = r
	var y: float = -x - z
	var rx: float = round(x)
	var ry: float = round(y)
	var rz: float = round(z)
	var dx: float = absf(rx - x)
	var dy: float = absf(ry - y)
	var dz: float = absf(rz - z)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector2i(int(rx), int(rz))

## Sol-relative centre of a hex-prism tile from its id.
func _region_center(id: String) -> Vector3:
	var p: PackedStringArray = id.split(",")
	var q: float = float(p[0])
	var r: float = float(p[1])
	var lx: float = HEX_SIZE * (1.5 * q)                              # galactic in-plane x
	var ly: float = HEX_SIZE * (HEX_SQRT3 / 2.0 * q + HEX_SQRT3 * r)  # galactic in-plane y
	var ax: Array = _gal_axes()
	# Lattice origin is the galactic centre; the result is still Sol-relative.
	return _region_origin() + (ax[0] as Vector3) * lx + (ax[1] as Vector3) * ly

## How many stars a tile actually contains: the galactic stellar density at its centre times the
## prism's volume.  Deterministic from position, so it needn't be stored (survives save/load free).
func _region_star_count(center: Vector3) -> float:
	return StarMapPanel.galactic_density(center) * GALAXY_STAR_DENSITY * HEX_AREA_LY2 * HEX_HEIGHT_LY

## Region record for a cell, created on first use with a colonisable capacity weighted by the
## galactic density at the cell centre (so voids stay empty and the disk/arms fill densely).
func _get_region(id: String) -> Dictionary:
	if not _regions.has(id):
		var dens: float = StarMapPanel.galactic_density(_region_center(id))
		var colonizable: float = REGION_STARS_PER_CELL * dens
		_regions[id] = {"colonized": 0.0, "pop": 0.0, "colonizable": colonizable}
	return _regions[id]

## Fold a far colonisation into its region (aggregate — no individual world is tracked).
func _region_colonize(pos: Vector3) -> void:
	var r: Dictionary = _get_region(_region_id(pos))
	r["colonized"] = minf(float(r["colonized"]) + 1.0, maxf(float(r["colonizable"]), 1.0))
	r["pop"] = maxf(float(r["pop"]), COLONY_SEED_POP)

## Colonised regions for the galaxy map: [{center: Vector3 (ly, Sol-relative), frac: 0..1}].
func galaxy_regions_data() -> Array:
	var out: Array = []
	for id: String in _regions:
		var reg: Dictionary = _regions[id]
		var colonizable: float = maxf(float(reg["colonizable"]), 1.0)
		var frac: float = clampf(float(reg["colonized"]) / colonizable, 0.0, 1.0)
		if frac > 0.0:
			var center: Vector3 = _region_center(id)
			out.append({"center": center, "frac": frac, "stars": _region_star_count(center)})
	return out

## Hex circumradius (ly), so the map can draw each region as a hexagon at its true footprint.
func galaxy_region_cell_ly() -> float:
	return HEX_SIZE

## The galactic in-plane axes [gx, gy], so the map can lay each hexagon flat in the disk plane.
func galaxy_region_plane_axes() -> Array:
	var ax: Array = _gal_axes()
	return [ax[0], ax[1], ax[2]]

## Prism height of a region tile (ly) — the galaxy's full vertical thickness.
func galaxy_region_height_ly() -> float:
	return HEX_HEIGHT_LY

## The region grid surrounding the player (Sol): every non-void cell within REGION_GRID_RADIUS,
## with its stellar density and current colonised fraction.  The cell list + densities are cached
## once (Sol-fixed and deterministic); only the colonised fraction is refreshed per call.
func galaxy_region_grid() -> Array:
	if _region_grid_cache.is_empty():
		var n: int = REGION_GRID_RADIUS
		for q in range(-n, n + 1):
			for r in range(maxi(-n, -q - n), mini(n, -q + n) + 1):   # hex disc centred on the galaxy
				var id: String = "%d,%d" % [q, r]
				var center: Vector3 = _region_center(id)
				var dens: float = StarMapPanel.galactic_density(center)
				if dens < 1.0e-3:
					continue   # void tile — never drawn
				# Star count is deterministic from position, so it belongs in the one-time build
				# rather than being recomputed on every call.
				_region_grid_cache.append({
					"id": id, "center": center, "density": dens,
					"stars": _region_star_count(center), "frac": 0.0,
				})
	# Only the colonised fraction changes, so it is patched IN PLACE and the cache itself is
	# returned.  This is called from the galaxy maps' _draw AND from their hover picking, i.e.
	# every frame and every mouse move — rebuilding ~900 dictionaries each time was pure garbage,
	# and the collector pauses it caused were the periodic stutter.
	# Callers treat the result as read-only.
	for c: Dictionary in _region_grid_cache:
		var reg: Dictionary = _regions.get(str(c["id"]), {})
		c["frac"] = 0.0 if reg.is_empty() else clampf(
			float(reg["colonized"]) / maxf(float(reg["colonizable"]), 1.0), 0.0, 1.0)
	return _region_grid_cache

## Full detail for one region tile (by id), for the galaxy map's selection sidebar.
func galaxy_region_info(id: String) -> Dictionary:
	var center: Vector3 = _region_center(id)
	var dens: float = StarMapPanel.galactic_density(center)
	var colonizable: float = REGION_STARS_PER_CELL * dens
	var colonized: float = 0.0
	var pop: float = 0.0
	if _regions.has(id):
		var reg: Dictionary = _regions[id]
		colonized = float(reg["colonized"])
		pop = float(reg["pop"])
	var gc: Vector3 = (_gal_axes()[0] as Vector3) * StarMapPanel.SOL_GC_LY   # galactic centre, Sol-relative
	return {
		"id": id,
		"center": center,
		"dist_sol_ly": center.length(),
		"dist_gc_ly": (center - gc).length(),
		"density": dens,
		"stars": _region_star_count(center),
		"colonizable": colonizable,
		"colonized": colonized,
		"frac": clampf(colonized / maxf(colonizable, 1.0), 0.0, 1.0),
		"population": pop,
		"capacity": colonizable * COLONY_HABITAT_K,
	}

## Total population living in the statistical regions (the far galaxy).
func _region_population() -> float:
	var t: float = 0.0
	for id: String in _regions:
		t += float((_regions[id] as Dictionary)["pop"])
	return t

## Whether `pos` is a far target whose region is already colonised (so individual probes don't
## keep re-seeding it — statistical diffusion handles the interior).
func _region_taken(pos: Vector3) -> bool:
	var id: String = _region_id(pos)
	return _regions.has(id) and float((_regions[id] as Dictionary)["colonized"]) > 0.0

## Cheap closed-form evolution of the statistical galaxy: each colonised region colonises more of
## its own stars, grows its population logistically toward the colonised capacity, and diffuses to
## a neighbour.  O(regions) per tick — independent of how many stars the galaxy actually holds.
func _update_regions() -> void:
	if _regions.is_empty():
		return
	var dyears: float = float(year) - _region_last_year
	if dyears <= 0.0:
		return
	_region_last_year = float(year)
	var r_growth: float = POP_GROWTH_PER_YEAR * PoliticsData.pop_growth_mult(policies)
	var decay: float = exp(-r_growth * dyears)
	var to_seed: Array = []   # defer neighbour seeding so we don't mutate _regions mid-iteration
	for id: String in _regions:
		var reg: Dictionary = _regions[id]
		var colonized: float = float(reg["colonized"])
		var colonizable: float = float(reg["colonizable"])
		if colonized <= 0.0 or colonizable < 1.0:
			continue   # empty or a void cell (no stars to colonise) — no growth, no spread
		# Colonise more of the region's own stars over time (saturating growth).
		if colonized < colonizable:
			reg["colonized"] = minf(colonizable, colonized + colonizable * REGION_SATURATE_RATE * dyears)
		# Population grows logistically toward the capacity the colonised stars support.
		var frac: float = clampf(float(reg["colonized"]) / colonizable, 0.0, 1.0)
		var k: float = colonizable * COLONY_HABITAT_K * frac
		var pop: float = float(reg["pop"])
		if k > 1.0 and pop > 0.0:
			reg["pop"] = k / (1.0 + (k / pop - 1.0) * decay)
		# Diffuse to a neighbour with probability rising as the region fills.
		if randf() < clampf(REGION_SPREAD_RATE * frac * dyears, 0.0, 0.5):
			to_seed.append(id)
	for id: String in to_seed:
		var nbid: String = _region_neighbour_id(id)
		# Don't spread into the void — only seed a neighbour that actually holds stars.
		if StarMapPanel.galactic_density(_region_center(nbid)) < 1.0e-3:
			continue
		var nb: Dictionary = _get_region(nbid)
		if float(nb["colonized"]) < 1.0:
			nb["colonized"] = 1.0
			nb["pop"] = maxf(float(nb["pop"]), COLONY_SEED_POP)

## A random adjacent cell id (one step in a random axis direction).
func _region_neighbour_id(id: String) -> String:
	var p: PackedStringArray = id.split(",")
	var d: Vector2i = HEX_DIRS[randi() % HEX_DIRS.size()]
	return "%d,%d" % [int(p[0]) + d.x, int(p[1]) + d.y]

## Cosmic scale factor relative to the present (≥1): how much space has stretched since
## the game epoch.  Dark-energy-dominated expansion is exponential — a(t) ∝ e^(t/τ) with
## an e-folding time of one Hubble time (~14.4 Gyr) — so over deep time unbound galaxies
## recede without bound and eventually leave the observable universe.  The exponent is
## clamped so the late game can't overflow the float.
const EXPANSION_EPOCH_YEAR: int = 2026
const HUBBLE_TIME_YR: float = 1.44e10
func _cosmic_scale() -> float:
	return exp(minf(float(year - EXPANSION_EPOCH_YEAR) / HUBBLE_TIME_YR, 80.0))

## Push interstellar state (colonised stars, in-flight missions, energy) to the star map.
func refresh_star_map() -> void:
	if sidebar == null or sidebar.star_map == null:
		return
	# Skip the full rebuild while the map is closed — attack/arrival resolutions call this
	# every tick, and in the late game (many in-flight strikes) that was the frame-rate drag.
	# It's repopulated the moment the panel is opened (sidebar._on_starmap_pressed).
	if not sidebar.star_map.visible:
		return
	sidebar.star_map.set_cosmic_scale(_cosmic_scale())
	var colo: Dictionary = {}
	for s in colonized_stars:
		colo[str(s)] = true
	var disp: Array = []
	for m in interstellar_missions:
		var sy: float = float(m.get("start_year", year))
		var ey: float = float(m.get("end_year", year))
		var tf: float = 0.0 if ey <= sy else clampf((float(year) - sy) / (ey - sy), 0.0, 1.0)
		# Position along the path follows the accel→coast→decel profile, so the ship
		# visibly slows as it nears the target rather than crawling at a constant rate.
		var p: float = StarMapPanel.flight_progress(
			tf, float(m.get("accel_time_frac", 0.5)), float(m.get("accel_dist_frac", 0.5)))
		disp.append({"target": str(m.get("target", "")), "progress": p})
	# Recon probes ride the same accel→coast→decel dashed line as colony ships.
	for m in probe_missions:
		var psy: float = float(m.get("start_year", year))
		var pey: float = float(m.get("end_year", year))
		var ptf: float = 0.0 if pey <= psy else clampf((float(year) - psy) / (pey - psy), 0.0, 1.0)
		var pp: float = StarMapPanel.flight_progress(
			ptf, float(m.get("accel_time_frac", 0.5)), float(m.get("accel_dist_frac", 0.5)))
		disp.append({"target": str(m.get("target", "")), "progress": pp})
	sidebar.star_map.set_interstellar_state(colo, disp, ResearchTree.resources.get("energy", 0.0))
	sidebar.star_map.set_star_factions(_displayed_factions())
	# In-flight weapon strikes (laser pulses + berserker swarms) with their progress.
	var atk: Array = []
	for a in interstellar_attacks:
		var sy: float = float(a.get("start_year", year))
		var ey: float = float(a.get("end_year", year))
		var p: float = 0.0 if ey <= sy else clampf((float(year) - sy) / (ey - sy), 0.0, 1.0)
		atk.append({"target": str(a.get("target", "")), "progress": p,
			"kind": str(a.get("kind", "laser")), "power": float(a.get("power", 1.0))})
	sidebar.star_map.set_attacks(atk)
	# Incoming relativistic missiles: a red streak from the hostile source toward the target.
	var inc: Array = []
	for a in incoming_attacks:
		var sy: float = float(a.get("start_year", year))
		var ey: float = float(a.get("end_year", year))
		var p: float = 0.0 if ey <= sy else clampf((float(year) - sy) / (ey - sy), 0.0, 1.0)
		# In-system worlds (Earth, colonies) all render toward Sol at the map centre; only
		# interstellar-colony targets point at their own star.
		var atgt: String = str(a.get("target", "earth"))
		var render_tgt: String = "sol" if PLANET_TYPES.has(atgt) else atgt
		inc.append({"source": str(a.get("source", "")), "target": render_tgt,
			"progress": p, "kind": str(a.get("kind", "missile"))})
	sidebar.star_map.set_incoming(inc)
	sidebar.star_map.set_alien_intel(_alien_intel())
	sidebar.star_map.set_weapon_caps(_has_orbital_laser(), _has_berserkers(), _has_player_missiles())
	sidebar.star_map.set_arsenal(int(_player_item_count("Missile")), int(_player_item_count("Berserker")))
	sidebar.star_map.set_year(float(year))
	# Reveal procedural stars only within the player's observation reach: a naked-eye baseline,
	# extended by telescope power (once Radio Astronomy is researched) and by the colony frontier
	# (you can resolve stars around your colonies).  The range is monotonic — never un-sees a star.
	var obs_range: float = 4000.0
	obs_range = maxf(obs_range, _telescope_power() * 2000.0)
	for cs in colonized_stars:
		# Each colony resolves stars around it — its own orbital telescopes push the frontier out.
		var cd: float = _star_distance_ly(str(cs))
		var scopes: int = int(_colony_infra_at(str(cs))["telescopes"])
		obs_range = maxf(obs_range, maxf(cd * 2.0, cd + float(scopes) * COLONY_TELESCOPE_REACH_LY))
	StarMapPanel.set_observation_range(obs_range)
	sidebar.star_map.set_colony_intel(_player_colony_intel())
	sidebar.star_map.set_interstellar_unlocked(ResearchTree.is_unlocked("relativistic_navigation"))

## What the star map should show: only DETECTED alien systems.  A detected system whose
## alignment the player hasn't confirmed by contact shows "unknown" (yellow); confirmed ones
## show their true alignment.  Undetected civilisations are omitted entirely (hidden).
func _displayed_factions() -> Dictionary:
	var out: Dictionary = {}
	for name: String in star_factions:
		if not _detected_aliens.has(name):
			continue
		out[name] = str(star_factions[name]) if _known_alignments.has(name) else "unknown"
	return out

## Reveal a system's true alignment (called on first contact — a colony ship arriving).
## Contact also counts as a detection, so a system you reach is always shown.
func _reveal_alignment(star_name: String) -> void:
	if star_factions.has(star_name):
		_known_alignments[star_name] = true
		_detected_aliens[star_name] = true

## Seed alien presence at a handful of stars.  Alignment is hidden until contact and the
## systems themselves are hidden until detected — _detected_aliens starts empty.  Signature
## epochs are set in the past so their light is already en route (detection depends on optics).
func _seed_star_factions() -> void:
	star_factions = {}
	_known_alignments = {}
	_alien_since = {}
	_detected_aliens = {}
	_alien_fired = {}
	_alien_last_year = float(year)
	var names: Array = []
	for s in StarMapPanel.all_stars():
		names.append(str(s["name"]))
	names.shuffle()
	for i in range(names.size()):
		if i >= 6:
			break
		var nm: String = names[i]
		star_factions[nm] = "aggressive" if i < 3 else "peaceful"
		# Founded in the past, so its signal is already crossing to us — some may be
		# detectable early with good optics, others still en route.
		_alien_since[nm] = float(year) - _star_distance_ly(nm) - randf_range(0.0, 800.0)

## 3-D map position of a star (game units), or ZERO if unknown.
func _star_pos(star_name: String) -> Vector3:
	var s: Dictionary = _star_lookup(star_name)
	return s["pos"] if s.has("pos") else Vector3.ZERO

## Combined signature-detection power: base astronomy + every telescope building's
## "detection" contribution, scaled by detection research.  ZERO until Radio Astronomy is
## researched — SETI is a gated capability, so no alien signature can be resolved before it.
func _telescope_power() -> float:
	if not ResearchTree.is_unlocked("radio_astronomy"):
		return 0.0
	if _prod_dirty:
		_recompute_production_cache()
	return (TELESCOPE_BASE_POWER + _cached_detection) * (1.0 + ResearchTree.get_boost("detection"))

## Deterministic alien infrastructure at a given OBSERVATION year: pass (year − distance) to
## get the light-delayed state the player can actually see.  {dyson: 0..1, telescopes, lasers}.
func _alien_infra_at(star: String, obs_year: float) -> Dictionary:
	var age: float = obs_year - float(_alien_since.get(star, obs_year))
	if age <= 0.0:
		return {"dyson": 0.0, "telescopes": 0, "lasers": 0, "missiles": 0, "berserkers": 0}
	var lasers: int = 0
	var missiles: int = 0
	var berserkers: int = 0
	if str(star_factions.get(star, "peaceful")) == "aggressive":
		# Only hostiles ring their world with weapons and manufacture an offensive arsenal;
		# both grow steadily with the civilisation's age (their "crafting" over deep time).
		lasers = int(age / ALIEN_LASER_YEARS)
		missiles = int(age / ALIEN_MISSILE_YEARS)
		berserkers = int(age / ALIEN_BERSERKER_YEARS)
		# Subtract the consumable munitions this system has already spent — lasers are reusable
		# emplacements, but missiles and berserker seeds are expended when fired.
		var fired: Dictionary = _alien_fired.get(star, {})
		missiles = maxi(0, missiles - int(fired.get("missiles", 0)))
		berserkers = maxi(0, berserkers - int(fired.get("berserkers", 0)))
	return {
		"dyson":      clampf(age / ALIEN_DYSON_YEARS, 0.0, 1.0),
		"telescopes": int(age / ALIEN_TELESCOPE_YEARS),
		"lasers":     lasers,
		"missiles":   missiles,
		"berserkers": berserkers,
	}

## Intel to show for every DETECTED alien system: the light-delayed infrastructure, resolved
## only as far as the player's telescopes reach (a returned probe overrides both the delay and
## the limit with full current intel).  star → {alignment, dyson, telescopes, lasers, detail,
## diplo, probed}.  Everything here is speed-of-light limited.
func _alien_intel() -> Dictionary:
	var out: Dictionary = {}
	var tel: float = _telescope_power()
	for star: String in star_factions:
		if not _detected_aliens.has(star):
			continue
		var dist: float = _star_distance_ly(star)
		var probed: bool = _infra_probed.has(star)
		var obs_year: float = float(year) if probed else float(year) - dist
		var infra: Dictionary = _alien_infra_at(star, obs_year)
		var detail: float = 1.0 if probed \
			else clampf(tel / maxf(dist * INFRA_DETAIL_REACH, 1.0), 0.0, 1.0)
		out[star] = {
			"alignment":  str(star_factions[star]) if _known_alignments.has(star) else "unknown",
			"dyson":      float(infra["dyson"]),
			"telescopes": int(infra["telescopes"]),
			"lasers":     int(infra["lasers"]),
			"missiles":   int(infra.get("missiles", 0)),
			"berserkers": int(infra.get("berserkers", 0)),
			"detail":     detail,
			"diplo":      str(_diplo_status.get(star, "")),
			"probed":     probed,
		}
	return out

## A player interstellar colony's infrastructure, grown deterministically from its founding year
## exactly like an alien colony's — a Dyson swarm (0..1), orbital telescopes, and defensive lasers.
func _colony_infra_at(star: String) -> Dictionary:
	var age: float = float(year - int(_colony_year.get(star, year)))
	if age <= 0.0:
		return {"dyson": 0.0, "telescopes": 0, "lasers": 0}
	return {
		"dyson":      clampf(age / COLONY_DYSON_YEARS, 0.0, 1.0),
		"telescopes": int(age / COLONY_TELESCOPE_YEARS),
		"lasers":     int(age / COLONY_LASER_YEARS),
	}

## Infrastructure of every player interstellar colony, for the star map's colony readout.
func _player_colony_intel() -> Dictionary:
	var out: Dictionary = {}
	for s in colonized_stars:
		out[str(s)] = _colony_infra_at(str(s))
	return out

## Systems that will fire on human worlds: the innately aggressive ones plus any the player
## has declared war on, minus any that are allied.
func _hostile_systems() -> Array:
	var out: Array = []
	for star: String in star_factions:
		if str(_diplo_status.get(star, "")) == "allied":
			continue
		if str(star_factions[star]) == "aggressive" or str(_diplo_status.get(star, "")) == "war":
			out.append(star)
	return out

## Advance the alien simulation: detect signatures that have reached us, and let alien
## civilisations expand to new systems.  Batches across however many years elapsed, so it
## behaves the same at 1× and when fast-forwarding millions of years per frame.
func _process_aliens() -> void:
	if game_over:
		return
	var dyears: float = float(year) - _alien_last_year
	if dyears <= 0.0:
		return
	_alien_last_year = float(year)
	_detect_alien_signatures(dyears)
	_spread_aliens(dyears)
	_launch_alien_attacks(dyears)

## Roll to pick up each undetected alien signature whose light has had time to arrive.
func _detect_alien_signatures(dyears: float) -> void:
	var tel: float = _telescope_power()
	var newly: int = 0
	for star: String in star_factions.keys():
		if _detected_aliens.has(star):
			continue
		var dist: float = _star_distance_ly(star)
		# The signal can't be seen until its light has crossed the gulf to Sol.
		if float(year) < float(_alien_since.get(star, 0.0)) + dist:
			continue
		var p_year: float = clampf(ALIEN_DETECT_BASE * tel / maxf(dist, 1.0), 0.0, 0.9)
		var p: float = 1.0 - pow(1.0 - p_year, minf(dyears, 1.0e6))
		if randf() < p:
			_detected_aliens[star] = true
			newly += 1
			if newly <= 3:   # avoid a flood of cards when a huge time-slice reveals many
				_announce("Signature detected",
					"A non-thermal electromagnetic signature resolves at %s (%.1f ly). Emission predates detection by ≥%d yr (light-travel time)." % [
						star, dist, int(dist)],
					"detect_%s_%d" % [star, year])

## Alien civilisations expand: each occupied system has a per-year chance to found a colony
## at the nearest unoccupied star (their "resources" scale with how many systems they hold,
## so growth compounds).  Batched over the elapsed years and capped by available stars.
func _spread_aliens(dyears: float) -> void:
	if star_factions.is_empty():
		return
	# Decide HOW MANY systems spread before looking for anywhere to put them.  At the base rate
	# a colonisation is rare, so building a candidate list of every uncolonised star first meant
	# allocating (and discarding) a several-thousand-entry array on almost every single year.
	var expected: float = float(star_factions.size()) * ALIEN_SPREAD_RATE * dyears
	var count: int = int(expected)
	if randf() < (expected - float(count)):   # fractional remainder → probabilistic +1
		count += 1
	if count <= 0:
		return
	var targets: Array = []
	for s: Dictionary in StarMapPanel.all_stars():
		var nm: String = str(s["name"])
		if not star_factions.has(nm) and not colonized_stars.has(nm):
			targets.append(nm)
	if targets.is_empty():
		return
	count = mini(count, targets.size())
	var sources: Array = star_factions.keys()
	for _i in range(count):
		if targets.is_empty():
			break
		var src: String = str(sources[randi() % sources.size()])
		var align: String = str(star_factions[src])
		var spos: Vector3 = _star_pos(src)
		var best: int = 0
		var best_d: float = INF
		for ti in range(targets.size()):
			var d: float = spos.distance_to(_star_pos(str(targets[ti])))
			if d < best_d:
				best_d = d
				best = ti
		var tgt: String = str(targets[best])
		targets.remove_at(best)
		star_factions[tgt] = align
		_alien_since[tgt] = float(year)   # a fresh signature begins here, en route to Sol

## Aggressive civilisations fling relativistic kinetic missiles at human worlds.  Each
## aggressive system has a small per-year chance to launch at Sol or one of our colonies;
## the missile crosses at RKKV_BETA and is resolved by _check_incoming_attacks on arrival.
func _launch_alien_attacks(dyears: float) -> void:
	if star_factions.is_empty():
		return
	var hostiles: Array = _hostile_systems()   # aggressive + war-declared, minus allied
	# Deterrence (MAD): once the player fields civilisation-ending berserker seeds, an aggressor
	# knows any strike invites its own annihilation — so it grows far more cautious, cutting its
	# launch rate.  The larger the player's arsenal, the harder the throttle (down to a floor); it
	# never stops entirely.  Edge-announced so the player understands the lull (and its return).
	var deter_strength: float = _player_deterrent_strength()
	var deterred: bool = deter_strength > 0.0 and not hostiles.is_empty()
	if deterred != _deterrent_active:
		_deterrent_active = deterred
		if deterred:
			_announce("Deterrence established",
				"Hostile civilisations have registered your self-replicating berserker arsenal. Wary of mutually assured annihilation, they sharply curtail their attacks.",
				"deterrent_on_%d" % year)
		else:
			_announce("Deterrence lapsed",
				"Your berserker stockpile is exhausted. Hostile civilisations resume attacking at full intensity.",
				"deterrent_off_%d" % year)
	# Hard-cap the number of missiles in flight — this bounds the array, the per-tick
	# resolution work, and the event/timeline spam even when aliens have overrun the map.
	if incoming_attacks.size() >= RKKV_MAX_INFLIGHT:
		return
	if hostiles.is_empty():
		return
	# Each missile targets a specific inhabited WORLD (a strike destroys only that world, not
	# the whole system): Earth, an in-system colony, or an interstellar colony.
	var targets: Array = ["earth"]
	for cp in colonized_planets:
		targets.append(str(cp))
	for cs in colonized_stars:
		targets.append(str(cs))
	# The launch rate is capped so late-game spread (dozens of hostile systems) doesn't
	# multiply into a barrage; and the batch can never overshoot the in-flight ceiling.
	var attackers: float = minf(float(hostiles.size()), RKKV_ATTACKER_CAP)
	var expected: float = attackers * ALIEN_AGGRESSION_RATE * dyears
	if deterred:
		expected *= _deterrence_mult(deter_strength)   # bigger arsenal → harder throttle (to a floor)
	var count: int = int(expected)
	if randf() < (expected - float(count)):
		count += 1
	count = mini(count, RKKV_MAX_INFLIGHT - incoming_attacks.size())
	if count <= 0:
		return
	for _i in range(count):
		var src: String = str(hostiles[randi() % hostiles.size()])
		var tgt: String = str(targets[randi() % targets.size()])
		# In-system worlds (Earth/colonies) sit at Sol's distance; a colony star's distance is
		# the separation between the two stars (STARS positions are already in light-years).
		var dist: float = _star_distance_ly(src) if PLANET_TYPES.has(tgt) \
			else _star_pos(src).distance_to(_star_pos(tgt))
		if dist <= 0.0:
			dist = _star_distance_ly(src)
		# Weapon choice, gated by what this system still has on hand: orbital lasers are reusable
		# emplacements; missiles and berserker seeds are consumed when fired (tracked in
		# _alien_fired and subtracted from the age-derived stockpile in _alien_infra_at).
		var arsenal: Dictionary = _alien_infra_at(src, float(year))
		var has_laser: bool = int(arsenal["lasers"]) > 0
		var has_missile: bool = int(arsenal["missiles"]) > 0
		var has_berserker: bool = int(arsenal["berserkers"]) > 0
		if not (has_laser or has_missile or has_berserker):
			continue   # out of ammunition and no laser — this hostile stays quiet this tick
		var kind: String = ""
		var roll: float = randf()
		if has_laser and roll < 0.40:
			kind = "laser"
		elif has_berserker and roll < 0.55:
			kind = "berserker"
		elif has_missile:
			kind = "missile"
		elif has_laser:
			kind = "laser"
		else:
			kind = "berserker"
		# Expend the munition — lasers fire for free, missiles and berserkers deplete the magazine.
		if kind == "missile" or kind == "berserker":
			var spent: Dictionary = _alien_fired.get(src, {})
			var mkey: String = "missiles" if kind == "missile" else "berserkers"
			spent[mkey] = int(spent.get(mkey, 0)) + 1
			_alien_fired[src] = spent
		var beta: float = 1.0 if kind == "laser" else (0.3 if kind == "berserker" else RKKV_BETA)
		incoming_attacks.append({
			"source": src, "target": tgt, "kind": kind,
			"start_year": float(year), "end_year": float(year) + dist / beta,
		})
	# One throttled "inbound" notice (not one per missile) — impacts are always reported.
	if float(year) - _rkkv_notice_year >= RKKV_LAUNCH_NOTICE_GAP:
		_rkkv_notice_year = float(year)
		var note: String = "%d relativistic projectiles are tracked inbound toward human worlds." % count \
			if count > 1 else "A relativistic projectile is tracked inbound toward a human world."
		_announce("Relativistic projectiles inbound", note, "rkkv_notice_%d" % year)

## Resolve relativistic missiles whose arrival year has passed.  A colony strike wipes that
## colony out; a Sol strike guts the home population.  Impacts are COALESCED into at most two
## announcements per tick so a fast-forward cluster can't flood the timeline.
func _check_incoming_attacks() -> void:
	if incoming_attacks.is_empty():
		return
	var still: Array = []
	var earth_hit: bool = false
	var worlds_lost: Array = []          # in-system + interstellar colonies destroyed this tick
	for a in incoming_attacks:
		if float(year) < float(a.get("end_year", INF)):
			still.append(a)
			continue
		var tgt: String = str(a.get("target", "earth"))
		if tgt == "earth":
			earth_hit = true                          # the home world specifically
		elif colonized_planets.has(tgt):
			colonized_planets.erase(tgt)              # an in-system colony world
			world_pop.erase(tgt)                      # all life on it killed
			worlds_lost.append(tgt)
		elif colonized_stars.has(tgt):
			colonized_stars.erase(tgt)                # an interstellar colony world
			world_pop.erase(tgt)
			worlds_lost.append(tgt)
		# else: that world was already gone before impact — the mass strikes empty space.
	var resolved: bool = still.size() != incoming_attacks.size()
	incoming_attacks = still
	if not worlds_lost.is_empty():
		_mark_prod_dirty()   # removed colonies no longer contribute habitat/output

	# An Earth strike destroys all life on Earth.  The species survives only if a colony (in-
	# system or interstellar) endures; otherwise it's extinction.
	if earth_hit:
		world_pop["earth"] = 0.0                       # everyone on Earth is killed
		_devastate_home()
		stats["current_population"] = _total_population()
		if colonized_planets.is_empty() and colonized_stars.is_empty():
			trigger_game_over("Relativistic bombardment",
				"Earth is struck by a relativistic kinetic impactor and sterilised. Inhabited worlds: 0.")
		else:
			_announce("Relativistic impact — Earth",
				"Earth is struck and sterilised; the species endures on its colonies.",
				"rkkv_hit_earth_%d" % year)
	if not worlds_lost.is_empty():
		var desc: String = "%s is annihilated by a relativistic impact." % str(worlds_lost[0]).capitalize() \
			if worlds_lost.size() == 1 \
			else "%d worlds are annihilated by relativistic impacts." % worlds_lost.size()
		_announce("Relativistic impact — colony lost", desc, "rkkv_hit_world_%d" % year)
	if resolved:
		refresh_star_map()

## A relativistic impact on the home system destroys a chunk of Earth's infrastructure,
## durably lowering its energy/mineral output — and therefore carrying capacity — until the
## player rebuilds.  At least one Biomass Burner is spared so energy can't collapse entirely.
func _devastate_home() -> void:
	var built: Array = planet_buildings.get("earth", [])
	if built.is_empty():
		return
	var survivors: Array = []
	var kept_burner: bool = false
	for b in built:
		if b == "Biomass Burner" and not kept_burner:
			survivors.append(b)   # keep one burner (soft-lock guard)
			kept_burner = true
		elif randf() < 0.65:      # ~35% of everything else is wiped out
			survivors.append(b)
	planet_buildings["earth"] = survivors
	_mark_prod_dirty()
	_build_ui_dirty = true

# ── Orbital laser ─────────────────────────────────────────────────────────────

## Does any world have an Orbital Laser built?  Gates the firing panel's availability.
func _has_orbital_laser() -> bool:
	for p: String in planet_buildings:
		if _count_building(p, "Orbital Laser") > 0:
			return true
	return false

## Von Neumann berserkers are available once self-replicating industry is researched.
func _has_berserkers() -> bool:
	return ResearchTree.is_unlocked("self_replicating_industry")

## Weighted size of the player's deterrent arsenal.  A civilisation-ending berserker seed is the
## credible existential threat that makes deterrence work, so it takes at least one to arm it; from
## there each berserker counts in full and each stockpiled relativistic missile a fraction, so a
## bigger arsenal deters harder.  Zero (no deterrence) until the first berserker is on hand.
func _player_deterrent_strength() -> float:
	if not _has_berserkers():
		return 0.0
	var berserkers: float = _player_item_count("Berserker")
	if berserkers < 1.0:
		return 0.0
	return berserkers + _player_item_count("Missile") * MISSILE_DETER_WEIGHT

## Hostile aggression multiplier for a given deterrent strength: one unit throttles attacks to
## DETERRENCE_MULT, and each further unit multiplies them down by DETERRENCE_STACK, bottoming out
## at DETERRENCE_FLOOR.  Returns 1.0 (no throttle) when the player has no deterrent.
func _deterrence_mult(strength: float) -> float:
	if strength <= 0.0:
		return 1.0
	return clampf(DETERRENCE_MULT * pow(DETERRENCE_STACK, strength - 1.0), DETERRENCE_FLOOR, 1.0)

## Fire the Orbital Laser at a star system: a light-speed white pulse that crosses the
## distance over the light-travel time, then obliterates whatever force is there.  Energy
## cost grows with distance² (the beam spreads).
func _on_laser_requested(star_name: String, power: float) -> void:
	if game_over or star_name == "" or not _has_orbital_laser():
		return
	if _attack_in_flight(star_name):
		return
	var dist: float = _star_distance_ly(star_name)
	if dist <= 0.0:
		return
	var pw: float = maxf(power, 1.0)
	var cost: float = StarMapPanel.laser_energy(dist) * pw
	if ResearchTree.resources.get("energy", 0.0) < cost:
		return
	ResearchTree.resources["energy"] = maxf(0.0,
		float(ResearchTree.resources.get("energy", 0.0)) - cost)
	interstellar_attacks.append({
		"target": star_name, "kind": "laser", "power": pw,
		"start_year": float(year), "end_year": float(year) + dist,   # light speed: 1 ly/yr
	})
	_announce("Laser Fired",
		"A directed-energy pulse streaks toward %s at the speed of light. Impact in ~%s." % [
			star_name, Units.format_si(dist, "yr")],
		"laser_%s_%d" % [star_name, year])
	refresh_star_map()

## Launch a von Neumann berserker swarm at a star system.  Uses the same speed/accel flight
## model as a colony ship (player dials in max γ and acceleration); cost is its relativistic
## launch energy scaled by the swarm seed's small rest mass.
func _on_berserker_requested(star_name: String, gamma_max: float, accel: float, count: int) -> void:
	if game_over or star_name == "" or not _has_berserkers():
		return
	var dist: float = _star_distance_ly(star_name)
	if dist <= 0.0:
		return
	var plan: Dictionary = StarMapPanel.plan_flight(dist, gamma_max, accel)
	var cost: float = float(plan["energy"]) * StarMapPanel.BERSERKER_MASS_FRAC
	var years: float = float(plan["years"])
	# Launch a salvo: each seed consumes one crafted Berserker + its launch energy.  Stop early
	# if the magazine or the power budget runs out.
	var launched: int = 0
	for _i in range(maxi(1, count)):
		if float(ResearchTree.resources.get("energy", 0.0)) < cost:
			break
		if not _consume_player_item("Berserker", 1.0):
			break   # no crafted berserker seed left
		ResearchTree.resources["energy"] = maxf(0.0,
			float(ResearchTree.resources.get("energy", 0.0)) - cost)
		interstellar_attacks.append({
			"target": star_name, "kind": "berserker",
			"start_year": float(year), "end_year": float(year) + years,
		})
		launched += 1
	if launched == 0:
		return
	_announce("Berserkers Launched",
		"%d von Neumann berserker seed%s accelerate toward %s at %s. Arrival in ~%s; they will replicate." % [
			launched, "" if launched == 1 else "s", star_name,
			StarMapPanel.fmt_beta(float(plan["peak_gamma"])), Units.format_si(years, "yr")],
		"berserker_%s_%d" % [star_name, year])
	refresh_star_map()

## Relativistic weaponry (player missiles + recon probes) unlock with interstellar flight.
func _has_player_missiles() -> bool:
	return ResearchTree.is_unlocked("relativistic_navigation")

## Fire a relativistic kinetic missile at a star system: crosses at RKKV_BETA and annihilates
## whatever force is there on arrival.  Cost scales with distance² (aiming a relativistic mass
## across light-years is exacting).
func _on_missile_requested(star_name: String, gamma_max: float, accel: float, count: int) -> void:
	if game_over or star_name == "" or not _has_player_missiles():
		return
	var dist: float = _star_distance_ly(star_name)
	if dist <= 0.0:
		return
	var plan: Dictionary = StarMapPanel.plan_flight(dist, gamma_max, accel)
	var cost: float = float(plan["energy"]) * StarMapPanel.MISSILE_MASS_FRAC
	var years: float = float(plan["years"])
	# Fire a salvo: each missile consumes one crafted Missile + its launch energy, stopping
	# early when the magazine or power budget is exhausted.
	var launched: int = 0
	for _i in range(maxi(1, count)):
		if float(ResearchTree.resources.get("energy", 0.0)) < cost:
			break
		if not _consume_player_item("Missile", 1.0):
			break   # no crafted missile left
		ResearchTree.resources["energy"] = maxf(0.0,
			float(ResearchTree.resources.get("energy", 0.0)) - cost)
		interstellar_attacks.append({
			"target": star_name, "kind": "missile",
			"start_year": float(year), "end_year": float(year) + years,
		})
		launched += 1
	if launched == 0:
		return
	_announce("Relativistic missiles launched",
		"%d relativistic kinetic missile%s accelerate toward %s at %s. Impact in ~%s." % [
			launched, "" if launched == 1 else "s", star_name,
			StarMapPanel.fmt_beta(float(plan["peak_gamma"])), Units.format_si(years, "yr")],
		"pmissile_%s_%d" % [star_name, year])
	refresh_star_map()

## Send a lightweight recon probe to a star.  It travels (relativistically) and, on arrival,
## resolves that system's full current infrastructure and alignment — the only way to see past
## the telescope/light-delay fog before you commit a colony ship.
func _on_probe_requested(star_name: String, gamma_max: float, accel: float) -> void:
	if game_over or star_name == "" or not _has_player_missiles():
		return
	if _infra_probed.has(star_name):
		return
	for m in probe_missions:
		if str(m.get("target", "")) == star_name:
			return   # one probe per target at a time
	var dist: float = _star_distance_ly(star_name)
	if dist <= 0.0:
		return
	var plan: Dictionary = StarMapPanel.plan_flight(dist, gamma_max, accel)
	var cost: float = float(plan["energy"]) * StarMapPanel.PROBE_MASS_FRAC
	if ResearchTree.resources.get("energy", 0.0) < cost:
		return
	ResearchTree.resources["energy"] = maxf(0.0,
		float(ResearchTree.resources.get("energy", 0.0)) - cost)
	var years: float = float(plan["years"])
	probe_missions.append({
		"target": star_name, "start_year": float(year), "end_year": float(year) + years,
		"accel_time_frac": float(plan.get("accel_time_frac", 0.5)),
		"accel_dist_frac": float(plan.get("accel_dist_frac", 0.5)),
	})
	_announce("Recon probe launched",
		"A lightweight probe departs Sol for %s. Arrival in ~%s; it will resolve the system's full state." % [
			star_name, Units.format_si(years, "yr")],
		"probe_%s_%d" % [star_name, year])
	refresh_star_map()

## Resolve probes that have arrived: full current intel on their target (overrides the
## telescope/light-delay limit for that system henceforth).
func _check_probe_arrivals() -> void:
	if probe_missions.is_empty():
		return
	var still: Array = []
	for m in probe_missions:
		if float(year) >= float(m.get("end_year", INF)):
			var t: String = str(m.get("target", ""))
			_infra_probed[t] = true
			if star_factions.has(t):
				_detected_aliens[t] = true
				_reveal_alignment(t)
				_announce("Probe report — %s" % t,
					"The probe resolves %s: a %s civilisation, full infrastructure recorded." % [
						t, str(star_factions[t])],
					"probe_report_%s_%d" % [t, year])
			else:
				_announce("Probe report — %s" % t,
					"The probe resolves %s: no civilisation present." % t,
					"probe_report_%s_%d" % [t, year])
		else:
			still.append(m)
	probe_missions = still
	refresh_star_map()

## Transmit a message to a detected alien system.  It (and any reply) travel at light speed,
## so the outcome resolves after a round trip of 2×distance years.
func _on_message_requested(star_name: String, kind: String) -> void:
	if game_over or star_name == "" or not _detected_aliens.has(star_name) or not star_factions.has(star_name):
		return
	for m in outgoing_messages:
		if str(m.get("target", "")) == star_name:
			return   # a message is already in transit to this system
	var dist: float = _star_distance_ly(star_name)
	if dist <= 0.0:
		return
	if kind != "war":
		if ResearchTree.resources.get("energy", 0.0) < MSG_ALLY_ENERGY:
			return
		ResearchTree.resources["energy"] = maxf(0.0,
			float(ResearchTree.resources.get("energy", 0.0)) - MSG_ALLY_ENERGY)
	outgoing_messages.append({
		"target": star_name, "kind": kind,
		"start_year": float(year), "end_year": float(year) + 2.0 * dist,   # there and back
	})
	_announce("Transmission sent",
		"%s message dispatched to %s (%.1f ly). A reply, if any, returns in ~%s." % [
			kind.capitalize(), star_name, dist, Units.format_si(2.0 * dist, "yr")],
		"msg_%s_%s_%d" % [kind, star_name, year])
	refresh_star_map()

## Resolve message round-trips whose reply has arrived.
func _check_message_arrivals() -> void:
	if outgoing_messages.is_empty():
		return
	var still: Array = []
	for m in outgoing_messages:
		if float(year) >= float(m.get("end_year", INF)):
			_resolve_message(str(m.get("target", "")), str(m.get("kind", "contact")))
		else:
			still.append(m)
	outgoing_messages = still
	refresh_star_map()

## Apply a diplomatic reply.  Peaceful systems accept alliance/trade; aggressive ones rebuff
## (and an overture to a hostile can turn it openly warlike).  Any contact reveals alignment.
func _resolve_message(star: String, kind: String) -> void:
	if not star_factions.has(star):
		return   # the system is gone
	_reveal_alignment(star)
	var align: String = str(star_factions[star])
	match kind:
		"contact":
			if _diplo_status.get(star, "") == "":
				_diplo_status[star] = "contact"
			_announce("Reply from %s" % star,
				"Contact established. Alignment resolved: %s." % align, "reply_%s_%d" % [star, year])
		"ally":
			if align == "peaceful":
				_diplo_status[star] = "allied"
				_announce("Reply from %s" % star, "%s accepts an alliance." % star, "reply_%s_%d" % [star, year])
			else:
				_diplo_status[star] = "war"
				_announce("Reply from %s" % star,
					"%s rebuffs the overture and turns openly hostile." % star, "reply_%s_%d" % [star, year])
		"trade":
			if align == "peaceful":
				if _diplo_status.get(star, "") != "allied":
					_diplo_status[star] = "trading"
				ResearchTree.resources["science"]  = float(ResearchTree.resources.get("science", 0.0)) + 5.0e12
				ResearchTree.resources["energy"]    = float(ResearchTree.resources.get("energy", 0.0)) + 2.0e9
				ResearchTree.resources["minerals"]  = float(ResearchTree.resources.get("minerals", 0.0)) + 5.0e8
				_announce("Reply from %s" % star,
					"%s agrees to trade. A cache of science, energy, and materials is received." % star,
					"reply_%s_%d" % [star, year])
			else:
				_announce("Reply from %s" % star, "%s refuses to trade." % star, "reply_%s_%d" % [star, year])
		"war":
			_diplo_status[star] = "war"
			_announce("Reply from %s" % star,
				"%s registers your declaration of war." % star, "reply_%s_%d" % [star, year])

## Is there already a weapon strike in flight to this star?  (Prevents double-firing.)
func _attack_in_flight(star_name: String) -> bool:
	for a in interstellar_attacks:
		if str(a.get("target", "")) == star_name:
			return true
	return false

## Resolve any weapon strikes whose arrival year has passed: the target's alien force is
## destroyed (berserkers also leave the system consumed).
func _check_interstellar_attacks() -> void:
	if interstellar_attacks.is_empty():
		return
	var still: Array = []
	for a in interstellar_attacks:
		if float(year) >= float(a.get("end_year", INF)):
			var target: String = str(a.get("target", ""))
			var kind: String = str(a.get("kind", "laser"))
			var had: bool = star_factions.has(target)
			star_factions.erase(target)   # the force there is wiped out
			_diplo_status.erase(target)
			_infra_probed.erase(target)
			var outcome: String = "The force there is obliterated." if had else "It strikes empty space."
			if kind == "berserker":
				_announce("Berserker Strike",
					"The berserker swarm reaches %s and devours the system. %s" % [target,
						"The hostile force is annihilated." if had else "Nothing organised remained."],
					"berserker_hit_%s_%d" % [target, year])
			elif kind == "missile":
				_announce("Relativistic Impact",
					"The relativistic missile shatters %s. %s" % [target, outcome],
					"pmissile_hit_%s_%d" % [target, year])
			else:
				_announce("Laser Strike",
					"The laser pulse lances %s. %s" % [target, outcome],
					"laser_hit_%s_%d" % [target, year])
		else:
			still.append(a)
	interstellar_attacks = still
	refresh_star_map()

## Queue a timeline notification (shared helper for interstellar events).
func _announce(title: String, desc: String, id: String) -> void:
	var notif: Dictionary = {
		"id": id, "year": year, "title": title, "desc": desc, "category": "civilization",
	}
	_pending_event_notifications.append(notif)
	if timeline_panel:
		timeline_panel.add_live_event(notif)

## Snapshot of every launchable planet's current orbital angle (radians), so the
## LaunchPanel can compute the actual-path (launch-window) energy cost.
func _build_orbital_state() -> Dictionary:
	const NAMES := ["mercury", "venus", "earth", "mars",
		"jupiter", "saturn", "uranus", "neptune"]
	var out: Dictionary = {}
	for pname: String in NAMES:
		var p := get_node_or_null("WorldRoot/Planets/" + pname) as Planet
		if p:
			out[pname] = p.orbit_angle
	return out

func save_game(path: String = "") -> void:
	if path == "":
		path = GameSession.current_save_path
	if path == "":
		path = "user://saves/default.json"

	var data: Dictionary = {
		"research":           ResearchTree.save_state(),
		"year":               year,
		"month":              month,
		"day":                day,
		"population":         stats.get("current_population", EARTH_NATURAL_K),
		"people_ever_lived":  _people_ever_lived,
		"production_jobs":    production_panel.get_jobs(),
		"automation_rules":   _automation_rules,
		"planet_buildings":   planet_buildings,
		"build_queue":        build_queue,
		"extraction_focus":   extraction_focus,
		"active_buildings":   active_buildings,
		"entropy_exported":   entropy_exported,
		"resources":          ResearchTree.resources,
		"active_launches":    active_launches,
		"next_launch_id":     _next_launch_id,
		"solar_satellites_deployed": solar_satellites_deployed,
		"colonized_planets":  colonized_planets,
		"colonized_stars":    colonized_stars,
		"world_pop":          world_pop,
		"engulfed_planets":   _engulfed_planets,
		"interstellar_missions": interstellar_missions,
		"colony_year":           _colony_year,
		"vn_enabled":            _vn_enabled,
		"vn_milestone_idx":      _vn_milestone_idx,
		"regions":               _regions,
		"region_last_year":      _region_last_year,
		"interstellar_attacks":  interstellar_attacks,
		"incoming_attacks":      incoming_attacks,
		"outgoing_messages":     outgoing_messages,
		"probe_missions":        probe_missions,
		"diplo_status":          _diplo_status,
		"infra_probed":          _infra_probed,
		"star_factions":      star_factions,
		"known_alignments":   _known_alignments,
		"alien_since":        _alien_since,
		"detected_aliens":    _detected_aliens,
		"alien_fired":        _alien_fired,
		"alien_last_year":    _alien_last_year,
		"deterrent_active":   _deterrent_active,
		"colonized_year":     _colonized_year,
		"split_thresholds":   _split_thresholds,
		"colony_parent":      _colony_parent,
		"variant_parent":     _variant_parent,
		"surveyed_planets":   surveyed_planets,
		"policies":           policies,
		"stats_history":      statistics_page.get_save_data(),
		"compound_inventory": compound_inventory,
		"atmospheric_co2":    atmospheric_co2,
		"fired_events":       _fired_events,
		"fired_event_years":  _fired_event_years,
		"next_impact_year":   _next_impact_year,
		"next_pandemic_year": _next_pandemic_year,
		"next_nuclear_year":  _next_nuclear_year,
		"arms_strain":        _arms_strain,
	}

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		print("Saved to %s" % path)

func load_game(path: String = "") -> void:
	if path == "":
		path = GameSession.current_save_path
	if path == "":
		return
	if not FileAccess.file_exists(path):
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return

	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary:
		return

	var data: Dictionary = parsed

	# Dyson-swarm size.  Set the base value first so the Orbital Array migration in
	# the planet_buildings block below can add to it (older saves have no key → 0).
	solar_satellites_deployed = int(data.get("solar_satellites_deployed", 0))

	ResearchTree.load_tree(ResearchTreeData.build())
	if data.has("research") and data["research"] is Dictionary:
		ResearchTree.load_state(data["research"])

	year  = int(data.get("year",  2026))
	month = int(data.get("month", 0))
	day   = int(data.get("day",   0))
	stats["current_population"] = float(data.get("population", stats.get("current_population", EARTH_NATURAL_K)))
	_people_ever_lived = float(data.get("people_ever_lived", PEOPLE_EVER_LIVED_1945))

	if data.has("planet_buildings") and data["planet_buildings"] is Dictionary:
		planet_buildings = data["planet_buildings"]
		# Migrate renamed buildings so older saves keep their structures.
		const _RENAMES := {
			"Compute Core":  "Data Center",
			"Biomass Grid":  "Biomass Burner",   # 1945 grids → real power plants
			"Biomass Plant": "Biomass Burner",
			"Coal Grid":     "Coal Plant",
			"Oil Grid":      "Oil Plant",
			"Storage Depot": "Matter Depot",     # storage split into matter + energy
			"Orbital Cache": "Orbital Vault",
		}
		# Retired "Orbital Array" infrastructure → deployed Solar Satellites.  Each old
		# array was 24 swarm collectors, so carry that forward, then drop the buildings.
		var _migrated_arrays: int = 0
		for _pname: String in planet_buildings:
			var _list: Array = planet_buildings[_pname]
			for _i in range(_list.size()):
				if _RENAMES.has(_list[_i]):
					_list[_i] = _RENAMES[_list[_i]]
			while _list.has("Orbital Array"):
				_list.erase("Orbital Array")
				_migrated_arrays += 1
		if _migrated_arrays > 0:
			solar_satellites_deployed = clampi(
				solar_satellites_deployed + _migrated_arrays * 24, 0, _swarm_max())
		# Guarantee Earth keeps at least one Biomass Burner (soft-lock guard).
		var _earth: Array = planet_buildings.get("earth", [])
		if not _earth.has("Biomass Burner"):
			_earth.append("Biomass Burner")
			planet_buildings["earth"] = _earth

	build_queue = data["build_queue"] if (data.has("build_queue") and data["build_queue"] is Dictionary) else {}
	extraction_focus = data["extraction_focus"] if (data.has("extraction_focus") and data["extraction_focus"] is Dictionary) else {}
	active_buildings = data["active_buildings"] if (data.has("active_buildings") and data["active_buildings"] is Dictionary) else {}
	entropy_exported = float(data.get("entropy_exported", 0.0))
	_heat_alerted = false
	_labor_alerted = false

	if data.has("resources") and data["resources"] is Dictionary:
		for key in data["resources"]:
			ResearchTree.resources[key] = float(data["resources"][key])

	if data.has("active_launches") and data["active_launches"] is Array:
		active_launches = data["active_launches"]
	else:
		active_launches = []
	# Reserved swarm slots = Solar Deployment crafts still in flight.
	_pending_swarm = 0
	for _l in active_launches:
		if _l.get("status", "") == "active" and int(_l.get("payload", 0)) > 0:
			_pending_swarm += int(_l.get("payload", 0))

	if data.has("next_launch_id"):
		_next_launch_id = int(data["next_launch_id"])
	else:
		_next_launch_id = active_launches.size() + 1

	if data.has("colonized_planets") and data["colonized_planets"] is Array:
		colonized_planets = data["colonized_planets"]
	else:
		colonized_planets = []

	colonized_stars = []
	if data.has("colonized_stars") and data["colonized_stars"] is Array:
		for sname in data["colonized_stars"]:
			colonized_stars.append(str(sname))
	# Per-world populations.  Older saves (no world_pop) fall back to attributing the whole
	# saved headcount to Earth plus a seed on each colony.
	world_pop = {}
	if data.has("world_pop") and data["world_pop"] is Dictionary:
		for k: String in data["world_pop"]:
			world_pop[k] = float(data["world_pop"][k])
	else:
		world_pop["earth"] = float(stats.get("current_population", 2_300_000_000.0))
		for cp in colonized_planets:
			world_pop[str(cp)] = COLONY_SEED_POP
		for cs in colonized_stars:
			world_pop[str(cs)] = COLONY_SEED_POP
	if not world_pop.has("earth"):
		world_pop["earth"] = MIN_POPULATION
	stats["current_population"] = _total_population()
	_engulfed_planets = {}
	if data.has("engulfed_planets") and data["engulfed_planets"] is Dictionary:
		for k: String in data["engulfed_planets"]:
			_engulfed_planets[k] = true
	interstellar_missions = []
	if data.has("interstellar_missions") and data["interstellar_missions"] is Array:
		for m in data["interstellar_missions"]:
			interstellar_missions.append((m as Dictionary).duplicate())
	_colony_year = {}
	if data.has("colony_year") and data["colony_year"] is Dictionary:
		for k: String in data["colony_year"]:
			_colony_year[k] = int(data["colony_year"][k])
	_regions = {}
	if data.has("regions") and data["regions"] is Dictionary:
		for k: String in data["regions"]:
			var rec: Dictionary = data["regions"][k]
			_regions[k] = {
				"colonized":   float(rec.get("colonized", 0.0)),
				"pop":         float(rec.get("pop", 0.0)),
				"colonizable": float(rec.get("colonizable", 0.0)),
			}
	_region_last_year = float(data.get("region_last_year", float(year)))
	_vn_enabled = bool(data.get("vn_enabled", false))
	_vn_milestone_idx = int(data.get("vn_milestone_idx", 0))
	if sidebar and sidebar.automation_panel:
		sidebar.automation_panel.set_vn_enabled(_vn_enabled)
	interstellar_attacks = []
	if data.has("interstellar_attacks") and data["interstellar_attacks"] is Array:
		for a in data["interstellar_attacks"]:
			interstellar_attacks.append((a as Dictionary).duplicate())
	incoming_attacks = []
	if data.has("incoming_attacks") and data["incoming_attacks"] is Array:
		for a in data["incoming_attacks"]:
			incoming_attacks.append((a as Dictionary).duplicate())
	outgoing_messages = []
	if data.has("outgoing_messages") and data["outgoing_messages"] is Array:
		for a in data["outgoing_messages"]:
			outgoing_messages.append((a as Dictionary).duplicate())
	probe_missions = []
	if data.has("probe_missions") and data["probe_missions"] is Array:
		for a in data["probe_missions"]:
			probe_missions.append((a as Dictionary).duplicate())
	_diplo_status = {}
	if data.has("diplo_status") and data["diplo_status"] is Dictionary:
		for k: String in data["diplo_status"]:
			_diplo_status[k] = str(data["diplo_status"][k])
	_infra_probed = {}
	if data.has("infra_probed") and data["infra_probed"] is Dictionary:
		for k: String in data["infra_probed"]:
			_infra_probed[k] = true
	star_factions = {}
	if data.has("star_factions") and data["star_factions"] is Dictionary:
		for k: String in data["star_factions"]:
			star_factions[k] = str(data["star_factions"][k])
	else:
		_seed_star_factions()   # older save: assign fresh alien presence
	_known_alignments = {}
	if data.has("known_alignments") and data["known_alignments"] is Dictionary:
		for k: String in data["known_alignments"]:
			_known_alignments[k] = true
	# Alien detection/expansion state.  Older saves (star_factions but no signature epochs)
	# fall back to fresh epochs so their signals are still en route.
	_alien_since = {}
	if data.has("alien_since") and data["alien_since"] is Dictionary:
		for k: String in data["alien_since"]:
			_alien_since[k] = float(data["alien_since"][k])
	else:
		for k: String in star_factions:
			_alien_since[k] = float(year) - _star_distance_ly(k) - randf_range(0.0, 800.0)
	_detected_aliens = {}
	if data.has("detected_aliens") and data["detected_aliens"] is Dictionary:
		for k: String in data["detected_aliens"]:
			_detected_aliens[k] = true
	_alien_fired = {}
	if data.has("alien_fired") and data["alien_fired"] is Dictionary:
		for k: String in data["alien_fired"]:
			var rec: Dictionary = data["alien_fired"][k]
			_alien_fired[k] = {
				"missiles":   int(rec.get("missiles", 0)),
				"berserkers": int(rec.get("berserkers", 0)),
			}
	_alien_last_year = float(data.get("alien_last_year", float(year)))
	_deterrent_active = bool(data.get("deterrent_active", false))

	_colonized_year   = {}
	_split_thresholds = {}
	_colony_parent    = {}
	if data.has("colonized_year") and data["colonized_year"] is Dictionary:
		for k: String in data["colonized_year"]:
			_colonized_year[k] = int(data["colonized_year"][k])
	if data.has("split_thresholds") and data["split_thresholds"] is Dictionary:
		for k: String in data["split_thresholds"]:
			_split_thresholds[k] = int(data["split_thresholds"][k])
	if data.has("colony_parent") and data["colony_parent"] is Dictionary:
		for k: String in data["colony_parent"]:
			_colony_parent[k] = str(data["colony_parent"][k])
	# Earth's lineage clock starts at the 1945 game epoch.
	if not _colonized_year.has("earth"):
		_colonized_year["earth"]   = 1945
		_split_thresholds["earth"] = int(randf_range(500_000.0, 1_000_000.0))
	# Back-fill colonies that pre-date this save format — treat them as
	# freshly colonised so the split will fire after a further 500k–1M years.
	for planet_name: String in colonized_planets:
		if not _colonized_year.has(planet_name):
			_colonized_year[planet_name]   = year
			_split_thresholds[planet_name] = int(randf_range(500_000.0, 1_000_000.0))

	# Restore which bodies have been surveyed (planet-bar unlocks).
	if data.has("surveyed_planets") and data["surveyed_planets"] is Array:
		surveyed_planets = []
		for entry in data["surveyed_planets"]:
			surveyed_planets.append(str(entry))
	else:
		# Older save: infer from any Survey missions already launched.
		surveyed_planets = ["earth"]
		for launch: Dictionary in active_launches:
			if launch.get("mission", "") == "Survey":
				var t: String = str(launch.get("target", ""))
				if t != "" and not surveyed_planets.has(t):
					surveyed_planets.append(t)
	if not surveyed_planets.has("earth"):
		surveyed_planets.append("earth")

	policies = PoliticsData.default_state()
	if data.has("policies") and data["policies"] is Dictionary:
		for key: String in data["policies"]:
			policies[key] = data["policies"][key]
	politics_page.load_policies(policies)

	# Rebuild the evolution tree from the saved lineage map.  variant_parent is an
	# ordered { world → parent world } dict; replaying it in insertion order
	# guarantees each parent lineage exists before its descendant is added.
	_variant_parent = {}
	evolution_ui.reset_to_baseline()
	if data.has("variant_parent") and data["variant_parent"] is Dictionary:
		for world: String in data["variant_parent"]:
			var parent_world: String = str(data["variant_parent"][world])
			_variant_parent[world] = parent_world
			evolution_ui.add_planet_variant(world, parent_world)
	_check_population_splits()

	if data.has("stats_history") and data["stats_history"] is Dictionary:
		statistics_page.load_save_data(data["stats_history"])

	# compound_inventory is per-planet { planet → { compound → grams } }.  Older
	# saves stored a flat { compound → grams } global pool — attribute that to Earth.
	compound_inventory = {}
	if data.has("compound_inventory") and data["compound_inventory"] is Dictionary:
		var saved_inv: Dictionary = data["compound_inventory"]
		var is_per_planet: bool = false
		for v in saved_inv.values():
			if v is Dictionary:
				is_per_planet = true
			break
		if is_per_planet:
			for pname: String in saved_inv:
				var pinv: Dictionary = {}
				for compound in (saved_inv[pname] as Dictionary):
					pinv[compound] = float(saved_inv[pname][compound])
				compound_inventory[pname] = pinv
		else:
			var earth_inv: Dictionary = {}
			for compound in saved_inv:
				earth_inv[compound] = float(saved_inv[compound])
			compound_inventory["earth"] = earth_inv

	atmospheric_co2 = {}
	if data.has("atmospheric_co2") and data["atmospheric_co2"] is Dictionary:
		for key: String in data["atmospheric_co2"]:
			atmospheric_co2[key] = float(data["atmospheric_co2"][key])

	if data.has("production_jobs") and data["production_jobs"] is Array:
		_production_jobs = data["production_jobs"].duplicate(true)
		production_panel.load_jobs(_production_jobs)
	else:
		_production_jobs = []
		production_panel.load_jobs([])

	if data.has("automation_rules") and data["automation_rules"] is Array:
		_automation_rules = (data["automation_rules"] as Array).duplicate(true)
	else:
		_automation_rules = []
	if sidebar and sidebar.automation_panel:
		sidebar.automation_panel.load_rules(_automation_rules)

	_fired_events = []
	_fired_event_years = {}
	if data.has("fired_events") and data["fired_events"] is Array:
		for entry in data["fired_events"]:
			_fired_events.append(str(entry))
	if data.has("fired_event_years") and data["fired_event_years"] is Dictionary:
		for k: String in data["fired_event_years"]:
			_fired_event_years[k] = int(data["fired_event_years"][k])
	# Asteroid-impact schedule (old saves: schedule a fresh one from the current year).
	_next_impact_year = int(data.get("next_impact_year",
		year + randi_range(IMPACT_GAP_MIN, IMPACT_GAP_MAX)))
	_impact_cooldown_ms = 0
	_next_pandemic_year = int(data.get("next_pandemic_year",
		year + randi_range(PANDEMIC_GAP_MIN, PANDEMIC_GAP_MAX)))
	_pandemic_cooldown_ms = 0
	_next_nuclear_year = int(data.get("next_nuclear_year",
		year + randi_range(NUCLEAR_GAP_MIN, NUCLEAR_GAP_MAX)))
	_nuclear_cooldown_ms = 0
	_arms_strain = float(data.get("arms_strain", 0.0))
	_pending_event_notifications = []

	# Replay fired events onto the timeline so cards appear after a load.
	# Use the saved fire-year so each card appears at the correct position.
	if timeline_panel:
		for ev_def: Dictionary in GameEvents.EVENTS:
			var ev_id: String = ev_def["id"]
			if _fired_events.has(ev_id):
				var stamped: Dictionary = ev_def.duplicate()
				stamped["year"] = _fired_event_years.get(ev_id, year)
				timeline_panel.add_live_event(stamped)

	_mark_prod_dirty()
	# Pre-compute storage caps from loaded buildings so the first _process tick
	# doesn't clamp resources below what the player's infrastructure supports.
	_cached_storage_caps = _compute_storage_caps()
	# Recompute the timescale for the loaded year so a far-future save resumes at
	# the correct (fast) speed instead of day-by-day stepping through eons.
	_update_timescale()
	# Start paused so the player can orient before time begins running.
	SolarSystem.paused = true
	print("Loaded from %s" % path)

## Refresh the stats dict with the latest live values so set_stats() and
## push_snapshot() always see current resource totals.
# ── Population model ────────────────────────────────────────────────────────────

## Carrying capacity from currently available resources.  Earth's biosphere is a
## fixed floor; off-world population needs both habitat (colonies) and life
## support (energy + minerals output), limited by whichever resource is scarcer.
## Total carrying capacity = sum of every inhabited world's own capacity.
func _population_capacity() -> float:
	var total: float = 0.0
	for w: String in _inhabited_worlds():
		total += _world_capacity(w)
	return total

## Earth's carrying-capacity multiplier from atmospheric CO₂: 1.0 when pristine,
## falling smoothly toward 0 as CO₂ builds (no random roll — a deterministic ceiling).
func _climate_capacity_factor() -> float:
	var co2: float = float(atmospheric_co2.get("earth", 0.0))
	return maxf(0.05, 1.0 / (1.0 + co2 / CO2_K_HALF))

## Advance population one logistic step over `delta_days` game-days toward the
## resource-driven capacity.  Uses the closed-form logistic solution, which is
## exact for a constant K and numerically stable for any step size — essential
## when a single frame can span millions of years at the fastest timescale.
func _update_population(delta_days: float) -> void:
	if delta_days <= 0.0:
		return
	var r: float = POP_GROWTH_PER_YEAR / 365.25 * PoliticsData.pop_growth_mult(policies)
	var decay: float = exp(-r * delta_days)
	var species_alive: float = _total_population() > 1.0   # true if humanity exists anywhere
	# Drop stale entries for worlds that are no longer inhabited (colony destroyed / lost).
	for w: String in world_pop.keys():
		if not _is_inhabited(w):
			world_pop.erase(w)
	# Grow each world's population logistically toward its OWN capacity (closed-form, exact at
	# any timescale).  An empty-but-habitable world is re-settled by migrants — but only while
	# the species survives somewhere; if nowhere is left, populations stay at zero (extinction).
	for world: String in _inhabited_worlds():
		var k: float = _world_capacity(world)
		var pop: float = float(world_pop.get(world, 0.0))
		if pop <= 0.0:
			if k > 1.0 and species_alive:
				pop = minf(k, COLONY_SEED_POP)   # migrants re-found the colony
			else:
				world_pop[world] = 0.0
				continue
		var new_pop: float = k / (1.0 + (k / pop - 1.0) * decay) if k > 0.0 else 0.0
		world_pop[world] = floorf(maxf(0.0, new_pop))
	# Mirror the total into stats for everywhere that reads a single global headcount.
	stats["current_population"] = _total_population()
	# No people left anywhere → extinction.  Humanity also survives in the statistical galaxy
	# regions, so a full collapse only ends the run once THOSE are empty too.
	if not game_over and stats["current_population"] + _region_population() < 1.0:
		trigger_game_over("Population collapse",
			"No humans remain on any world. Inhabited worlds: 0.")

func _refresh_stats() -> void:
	stats["year"]             = year
	stats["compute_rate"]     = _get_compute_rate()
	stats["science"]          = ResearchTree.resources.get("science",  0.0)
	stats["minerals"]         = ResearchTree.resources.get("minerals", 0.0)
	stats["energy"]           = ResearchTree.resources.get("energy",   0.0)
	stats["colony_count"]     = colonized_planets.size()
	# Galaxy-wide figures: the detailed worlds plus the statistical-region population/spread.
	stats["region_count"]     = _regions.size()
	stats["region_population"] = _region_population()
	stats["galaxy_population"] = _total_population() + _region_population()
	stats["life_expectancy"]  = _life_expectancy()
	stats["ai_autonomy"]      = PoliticsData.ai_autonomy(policies)
	stats["existential_risk"] = PoliticsData.existential_risk(policies)
	stats["radiator_capacity"] = _cached_radiator_cap
	stats["waste_heat"]        = _thermal_ratio * _cached_radiator_cap   # raw power draw (W)
	stats["thermal_ratio"]     = _thermal_ratio
	stats["entropy_exported"]  = entropy_exported
	stats["labor_staffing"]    = _mc_staffing()

func _fmt_year_hud() -> String:
	if SolarSystem.seconds_per_day < FAST_THRESHOLD:
		# Fast mode — months/days are meaningless, show compact year
		if year >= 1_000_000_000:
			return "%.3f B" % (float(year) / 1_000_000_000.0)
		if year >= 1_000_000:
			return "%.2f M" % (float(year) / 1_000_000.0)
		if year >= 10_000:
			return "%d K" % (year / 1000)
		return str(year)
	else:
		return "%d : %02d : %02d" % [year, month + 1, day + 1]

func _update_hud() -> void:
	if time_label:
		time_label.text = _fmt_year_hud()

	var prod         := _get_total_production()
	var compute_rate := _get_compute_rate()
	# Each stored unit:  1 science = 1 FLOP  |  1 mineral = 1 Gram  |  1 energy = 1 Joule
	# Each rate unit:    compute → FLOP/s  |  minerals → Grams/s  |  energy → Watts
	var min_cap: float = _cached_storage_caps.get("minerals", 0.0)
	var en_cap:  float = _cached_storage_caps.get("energy",   0.0)
	var raw_load: float = _thermal_ratio * _cached_radiator_cap   # power drawn before curtailment
	# One box per resource: current amount on top, accumulation underneath (blank when there is
	# no accumulation — Compute is itself a rate, Heat is instantaneous).
	_set_res_box("compute", Units.format_si(compute_rate, "FLOP/s"), "")
	_set_res_box("minerals",
		"%s / %s" % [Units.format_si(ResearchTree.resources.get("minerals", 0.0), "g"),
			Units.format_si(min_cap, "g")],
		"+%s" % Units.format_si(prod.get("minerals", 0.0), "g/s"))
	_set_res_box("energy",
		"%s / %s" % [Units.format_si(ResearchTree.resources.get("energy", 0.0), "J"),
			Units.format_si(en_cap, "J")],
		"+%s" % Units.format_si(prod.get("energy", 0.0), "W"))
	_set_res_box("heat",
		"%s / %s" % [Units.format_si(raw_load, "W"), Units.format_si(_cached_radiator_cap, "W")], "")
	# Amber the Heat box when the grid is radiating-limited (draw over capacity).
	if _res_boxes.has("heat"):
		(_res_boxes["heat"]["value"] as Label).modulate = Color(0.95, 0.65, 0.30) \
			if _thermal_ratio > 1.02 else Color(1.0, 1.0, 1.0)
	# Science lives on the research panel now, not the top bar.
	if research_ui and research_ui.has_method("set_science"):
		research_ui.set_science(
			ResearchTree.resources.get("science", 0.0), prod.get("science", 0.0))

func _on_save_pressed() -> void:
	save_game()

func _on_settings_pressed() -> void:
	settings_menu.visible = true

func _on_settings_closed() -> void:
	# Settings saved itself; nothing extra needed — game remains in its current pause state.
	pass

func _on_low_speed_pressed() -> void:
	_user_speed_mult = 0.25   # 4× slower than base
	_update_timescale()

func _on_medium_speed_pressed() -> void:
	_user_speed_mult = 1.0    # base speed
	_update_timescale()

func _on_high_speed_pressed() -> void:
	_user_speed_mult = 4.0    # 4× faster than base
	_update_timescale()

# ── Game event system ─────────────────────────────────────────────────────────

## Evaluate all unfired events of the given trigger_type against current state.
## Called from advance_day (yearly), fast mode, and mission/colony completion.
func _check_game_events(trigger_type: String) -> void:
	for ev: Dictionary in GameEvents.EVENTS:
		var ev_id: String = ev["id"]
		if _fired_events.has(ev_id):
			continue
		if ev["trigger_type"] != trigger_type:
			continue

		var fired := false
		match trigger_type:
			"year":
				fired = year >= int(ev["trigger_value"])
			"population":
				fired = float(stats.get("current_population", 0)) >= float(ev["trigger_value"])
			"colony_count":
				fired = colonized_planets.size() >= int(ev["trigger_value"])
			"compute":
				fired = _get_compute_rate() >= float(ev["trigger_value"])
			"orbit_mission", "mission_mars", "mission_outer":
				fired = true   # the trigger is the call itself

		if fired:
			_fired_events.append(ev_id)
			_fired_event_years[ev_id] = year
			# Stamp the event with the year it actually fired so the timeline
			# card is anchored to the correct position on the canvas.
			var stamped: Dictionary = ev.duplicate()
			stamped["year"] = year
			_pending_event_notifications.append(stamped)
			if timeline_panel:
				timeline_panel.add_live_event(stamped)

## Fire a major asteroid impact when the scheduled year arrives.  Rate-limited in
## real time so skipping through eons in fast mode can't trigger a flood of them.
func _check_asteroid_impact() -> void:
	if game_over or year < _next_impact_year:
		return
	if Time.get_ticks_msec() < _impact_cooldown_ms:
		return   # too soon since the last strike (deep fast-forward guard)
	# Planetary-defence policy widens the interval between impacts.
	_next_impact_year   = year + int(randi_range(IMPACT_GAP_MIN, IMPACT_GAP_MAX) \
		* PoliticsData.asteroid_gap_mult(policies))
	_impact_cooldown_ms = Time.get_ticks_msec() + IMPACT_REAL_COOLDOWN_MS
	_trigger_asteroid_impact()

# ── Shelters ──────────────────────────────────────────────────────────────────

## How many people a world's Bunkers can carry through a catastrophe.
func _shelter_capacity(planet_name: String) -> float:
	var cap: float = 0.0
	for b_name: String in planet_buildings.get(planet_name, []):
		cap += float((_bdef_cache.get(b_name, {}) as Dictionary).get("shelter", 0.0))
	return cap

## The shelter structures standing on a world.  They are built to outlast the surface, so a
## catastrophe that levels everything else leaves these — and the people inside them.
func _surviving_shelters(planet_name: String) -> Array:
	var out: Array = []
	for b_name: String in planet_buildings.get(planet_name, []):
		if float((_bdef_cache.get(b_name, {}) as Dictionary).get("shelter", 0.0)) > 0.0:
			out.append(b_name)
	return out

## Survivors of a catastrophe on `planet_name`: whatever the death toll leaves, or everyone the
## world's shelters can hold — whichever is larger.  Shelters can't save people who were never
## there, so capacity is capped at the living population.
func _sheltered_survivors(planet_name: String, pop: float, kill_frac: float) -> float:
	var exposed: float = pop * (1.0 - kill_frac)
	var sheltered: float = minf(_shelter_capacity(planet_name), pop)
	return floorf(maxf(MIN_POPULATION, maxf(exposed, sheltered)))

## A mountain-sized asteroid strikes one inhabited world: it levels every structure
## there and kills much of the population (softened when humanity is spread across
## several worlds).  Survivable by design — one emergency Biomass Burner is left so
## the grid can recover, and the population floor prevents outright extinction.
func _trigger_asteroid_impact() -> void:
	var inhabited: Array = (["earth"] as Array) + colonized_planets
	var target: String = str(inhabited[randi() % inhabited.size()])

	# Kill a majority of the population, divided across inhabited worlds — colonies
	# mean each strike claims a smaller share of all humanity.  Anyone the struck world's
	# bunkers can hold comes back out regardless of the toll.
	var pop: float = float(stats.get("current_population", 0))
	var kill_frac: float = randf_range(0.50, 0.85) / float(inhabited.size())
	var shelter: float = minf(_shelter_capacity(target), pop)
	var survivors: float = _sheltered_survivors(target, pop, kill_frac)
	var lost: float = maxf(0.0, pop - survivors)

	# Raze the struck world's infrastructure, leaving one lone Biomass Burner running so energy
	# production (and thus the ability to rebuild anything) never hits zero — plus the bunkers,
	# which are built to outlast the surface.  Done after the toll so the shelters still count.
	planet_buildings[target] = (["Biomass Burner"] as Array) + _surviving_shelters(target)
	_mark_prod_dirty()
	stats["current_population"] = survivors
	_refresh_stats()

	var notif: Dictionary = {
		"id":       "impact_%d" % year,
		"year":     year,
		"title":    "Asteroid Impact",
		"desc":     "Impact event recorded on %s. Surface structures: 0 remaining. Population change: −%s (−%d%%).%s" % [
			target.capitalize(), Units.format_si_verbose(lost, ""), int(round(kill_frac * 100.0)),
			"" if shelter <= 0.0 else " Shelters held %s below ground." \
				% Units.format_si_verbose(shelter, "")
		],
		"category": "warning",
	}
	_pending_event_notifications.append(notif)
	if timeline_panel:
		timeline_panel.add_live_event(notif)
	print("[Game] Asteroid impact on %s: %s killed, all infrastructure destroyed." % [
		target.capitalize(), Units.format_si_verbose(lost, "")])

## Scheduled engineered-pandemic roll.  Probability compounds with the factors that
## make a deliberate plague more likely and more lethal; rate-limited like impacts so
## deep fast-forward can't spam it.
func _check_pandemic() -> void:
	if game_over or year < _next_pandemic_year:
		return
	if Time.get_ticks_msec() < _pandemic_cooldown_ms:
		return
	_next_pandemic_year   = year + randi_range(PANDEMIC_GAP_MIN, PANDEMIC_GAP_MAX)
	_pandemic_cooldown_ms = Time.get_ticks_msec() + IMPACT_REAL_COOLDOWN_MS

	# No engineered-pandemic risk before the bioengineering capability exists.
	var biotech: int = 0
	for node_id: String in PANDEMIC_BIOTECH:
		if ResearchTree.is_unlocked(node_id):
			biotech += 1
	if biotech == 0:
		return

	var inhabited: int = 1 + colonized_planets.size()
	var ai: float = PoliticsData.ai_autonomy(policies)
	var le: float = _life_expectancy()
	# More bioengineering and more AI raise the odds; spreading across worlds lowers
	# them; poor public health (low life expectancy) raises them.
	var prob: float = PANDEMIC_BASE \
		* (1.0 + 0.4 * float(biotech)) \
		* (1.0 + 2.0 * ai) \
		* (2.0 / (1.0 + float(inhabited))) \
		* clampf(BASE_LIFE_EXPECTANCY / le, 0.5, 3.0)
	if randf() < clampf(prob, 0.0, 0.95):
		_trigger_pandemic()

## A synthetic plague kills much of the population — divided across inhabited worlds,
## so colonies blunt it.  Survivable by design unless the species is already fragile.
func _trigger_pandemic() -> void:
	var inhabited: int = 1 + colonized_planets.size()
	var pop: float = float(stats.get("current_population", 0))
	var kill_frac: float = randf_range(0.70, 0.95) / float(inhabited)
	var survivors: float = floorf(maxf(MIN_POPULATION, pop * (1.0 - kill_frac)))
	var lost: float = maxf(0.0, pop - survivors)
	stats["current_population"] = survivors
	_refresh_stats()

	var notif: Dictionary = {
		"id":       "pandemic_%d" % year,
		"year":     year,
		"title":    "Engineered Pandemic",
		"desc":     "Engineered-pathogen outbreak recorded. Population change: −%s (−%d%%)." % [
			Units.format_si_verbose(lost, ""), int(round(kill_frac * 100.0))],
		"category": "warning",
	}
	_pending_event_notifications.append(notif)
	if timeline_panel:
		timeline_panel.add_live_event(notif)
	print("[Game] Engineered pandemic: %s killed." % Units.format_si_verbose(lost, ""))

## Geopolitical tension [0,1].  Highest when humanity is packed onto one world under
## resource scarcity and an arms buildup; falls toward zero as it spreads off-world and
## reaches abundance.  Drives nuclear-war risk — and is what the player defuses by
## escaping the cradle rather than merely disarming.
func _geopolitical_tension() -> float:
	# Each colonised planet AND each interstellar colony dilutes single-world rivalry;
	# spreading to the stars is the strongest defuser of geopolitical tension.
	var worlds: float = 1.0 + float(colonized_planets.size()) + 2.0 * float(colonized_stars.size())
	var concentration: float = 1.0 / worlds                       # one world = maximal rivalry
	var pop: float = float(stats.get("current_population", 0))
	var scarcity: float = clampf(pop / maxf(_population_capacity(), 1.0), 0.0, 1.0)
	var arms: float = clampf(float(policies.get("military_spending", 10.0)) / 50.0, 0.0, 1.0)
	return clampf(concentration * (0.4 + 0.6 * scarcity) * (0.6 + 0.8 * arms), 0.0, 1.0)

## Total Nuclear Plants standing across every world.
func _nuclear_plant_count() -> int:
	if _prod_dirty:
		_recompute_production_cache()
	return int(_cached_nuclear)

## Latent weapons capability from the civilian fission fleet (0..1): more reactors mean
## more fissile material and know-how a tense world can turn to arms.  Saturating, so
## the first reactors add the most risk and a vast fleet can't push it past 1.0.
func _nuclear_proliferation() -> float:
	var n: float = float(_nuclear_plant_count())
	return n / (n + NUCLEAR_PROLIF_HALF)

## Scheduled nuclear-war roll.  Probability compounds with a sustained military/tension
## standoff (_arms_strain) and is rate-limited like the other catastrophes.  The "means"
## term is military spending plus the civilian reactor fleet's latent arsenal, so a
## nuclear-heavy grid raises the risk even if spending is low.  No means at all, or
## near-zero tension, means no exchange — so spreading off-world (which collapses
## tension) is the real escape, not merely cutting spending or reactors.
func _check_nuclear_war() -> void:
	if game_over or year < _next_nuclear_year:
		return
	if Time.get_ticks_msec() < _nuclear_cooldown_ms:
		return
	_next_nuclear_year   = year + randi_range(NUCLEAR_GAP_MIN, NUCLEAR_GAP_MAX)
	_nuclear_cooldown_ms = Time.get_ticks_msec() + IMPACT_REAL_COOLDOWN_MS

	var tension: float = _geopolitical_tension()
	# The "means" to wage nuclear war: declared military spending PLUS the latent arsenal
	# the civilian reactor fleet represents.  So building out nuclear power raises the
	# risk even at low military spending — a real downside to that clean, dense energy.
	var military: float = clampf(float(policies.get("military_spending", 10.0)) / 50.0, 0.0, 1.0)
	var means: float = clampf(military + _nuclear_proliferation(), 0.0, 1.0)
	var pressure: float = tension * means
	# Compounding: a sustained standoff ratchets the danger; calm/de-escalation relaxes it.
	_arms_strain = clampf(_arms_strain * NUCLEAR_STRAIN_DECAY + pressure, 0.0, 5.0)
	if means <= 0.0 or tension < 0.05:
		return   # no arsenal at all, or nothing left to fight over

	var prob: float = NUCLEAR_BASE * pressure * (1.0 + _arms_strain)
	if randf() < clampf(prob, 0.0, 0.9):
		_trigger_nuclear_war()

## A strategic exchange devastates Earth's population and industry.  Off-world colonies
## are spared (the conflict is between Earth powers), so spreading out blunts it.
func _trigger_nuclear_war() -> void:
	var inhabited: int = 1 + colonized_planets.size()
	var pop: float = float(stats.get("current_population", 0))
	var kill_frac: float = randf_range(0.55, 0.90) / float(inhabited)
	# Whoever Earth's bunkers can hold survives the exchange no matter how bad it gets.
	var shelter: float = minf(_shelter_capacity("earth"), pop)
	var survivors: float = _sheltered_survivors("earth", pop, kill_frac)
	var lost: float = maxf(0.0, pop - survivors)
	stats["current_population"] = survivors

	# Roughly half of Earth's surface industry is destroyed; one Biomass Burner is left
	# so power production (and recovery) can't collapse to zero.  Bunkers are hardened
	# against exactly this, so they always come through.
	if planet_buildings.has("earth"):
		var kept: Array = []
		for b: String in planet_buildings["earth"]:
			if randf() > 0.5 or float((_bdef_cache.get(b, {}) as Dictionary).get("shelter", 0.0)) > 0.0:
				kept.append(b)
		if not kept.has("Biomass Burner"):
			kept.append("Biomass Burner")
		planet_buildings["earth"] = kept
	_arms_strain = 0.0      # the standoff broke
	_mark_prod_dirty()
	_refresh_stats()

	var notif: Dictionary = {
		"id":       "nuclear_%d" % year,
		"year":     year,
		"title":    "Nuclear War",
		"desc":     "Strategic nuclear exchange recorded on Earth. Population change: −%s (−%d%%). Surface industry: heavily degraded.%s" % [
			Units.format_si_verbose(lost, ""), int(round(kill_frac * 100.0)),
			"" if shelter <= 0.0 else " Shelters held %s below ground." \
				% Units.format_si_verbose(shelter, "")],
		"category": "warning",
	}
	_pending_event_notifications.append(notif)
	if timeline_panel:
		timeline_panel.add_live_event(notif)
	print("[Game] Nuclear war: %s killed." % Units.format_si_verbose(lost, ""))

## Build the CanvasLayer and VBoxContainer used for event notification cards.
func _setup_event_notifications() -> void:
	_event_notif_layer = CanvasLayer.new()
	_event_notif_layer.layer = 50
	_event_notif_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_event_notif_layer)

	var anchor := Control.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_event_notif_layer.add_child(anchor)

	_event_notif_vbox = VBoxContainer.new()
	_event_notif_vbox.set_anchor(SIDE_TOP,    0.0)
	_event_notif_vbox.set_anchor(SIDE_RIGHT,  1.0)
	_event_notif_vbox.set_anchor(SIDE_BOTTOM, 0.0)
	_event_notif_vbox.set_anchor(SIDE_LEFT,   1.0)
	_event_notif_vbox.offset_top    = 12
	_event_notif_vbox.offset_right  = -12
	_event_notif_vbox.offset_left   = -12 - 320
	_event_notif_vbox.size_flags_horizontal = Control.SIZE_SHRINK_END
	_event_notif_vbox.add_theme_constant_override("separation", 6)
	anchor.add_child(_event_notif_vbox)

## Spawn a single notification card for the given event dict.
## Cards auto-dismiss after 10 seconds or when the × button is pressed.
func _show_event_card(ev: Dictionary) -> void:
	if not _event_notif_vbox:
		return
	var cat: String      = ev.get("category", "civilization")
	var cat_col: Color   = GameEvents.CATEGORY_COLORS.get(cat, Color.WHITE)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(320, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.10, 0.14, 0.95)
	style.border_color = cat_col
	style.set_border_width_all(2)
	style.border_width_left = 4
	style.corner_radius_top_left     = 4
	style.corner_radius_top_right    = 4
	style.corner_radius_bottom_left  = 4
	style.corner_radius_bottom_right = 4
	card.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	card.add_child(hbox)

	# Left accent bar color block
	var bar := ColorRect.new()
	bar.color = cat_col
	bar.custom_minimum_size = Vector2(4, 0)
	bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(bar)

	# Text area
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   8)
	margin.add_theme_constant_override("margin_right",  4)
	margin.add_theme_constant_override("margin_top",    6)
	margin.add_theme_constant_override("margin_bottom", 6)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(margin)

	var txt_vbox := VBoxContainer.new()
	txt_vbox.add_theme_constant_override("separation", 2)
	margin.add_child(txt_vbox)

	var year_lbl := Label.new()
	year_lbl.text = str(year)
	year_lbl.add_theme_font_size_override("font_size", 10)
	year_lbl.add_theme_color_override("font_color", cat_col)
	txt_vbox.add_child(year_lbl)

	var title_lbl := Label.new()
	title_lbl.text = ev.get("title", "")
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt_vbox.add_child(title_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = ev.get("desc", "")
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", Color(0.68, 0.68, 0.76))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt_vbox.add_child(desc_lbl)

	# Dismiss button
	var dismiss := Button.new()
	dismiss.text = "×"
	dismiss.flat = true
	dismiss.add_theme_font_size_override("font_size", 16)
	dismiss.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	dismiss.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	dismiss.pressed.connect(card.queue_free)
	hbox.add_child(dismiss)

	_event_notif_vbox.add_child(card)

	# Slide in from right
	card.modulate.a = 0.0
	var tween := card.create_tween()
	tween.tween_property(card, "modulate:a", 1.0, 0.35)
	# Auto-dismiss after 10 seconds
	tween.tween_interval(10.0)
	tween.tween_property(card, "modulate:a", 0.0, 0.5)
	tween.tween_callback(card.queue_free)
