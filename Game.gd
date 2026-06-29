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
const MINERALS_PER_CAPITA: float = 0.5       # Grams/s of output per sustained off-world person
const MIN_POPULATION:      float = 1.0e5     # floor short of outright extinction
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
var current_planet: String = ""
var science_multiplier: float = 1.0   # science produced per compute per second
var policies: Dictionary = {}         # policy_id -> bool or float
var active_launches: Array = []
var _next_launch_id: int = 1
var _launch_satellites: Dictionary = {}
## Solar Satellites that have arrived at the Sun and joined the Dyson swarm.  The
## swarm renderer (init_planets.gd) reads this to light up one collector each.
var solar_satellites_deployed: int = 0
## Hard cap = total collector slots in the swarm (keep in sync with init_planets.gd
## SWARM_LANES × SWARM_PER_LANE).  Each deployed satellite also feeds the grid.
const SWARM_SAT_MAX:   int   = 6 * 24          # 144 slots
# Each deployed collector beams back ~100 GW (on the scale of a fossil station), so a
# full 144-satellite swarm delivers ~14.4 TW — the largest power source in the game,
# the payoff for the long manufacture-and-launch campaign that builds it out.
const SWARM_SAT_POWER: float = 1.0e11          # watts beamed back per deployed satellite
var colonized_planets: Array = []     # planets that have received a completed Colony Ship

## Interstellar colonies and in-flight colony ships (from the star map).
## colonized_stars: [star_name…];  interstellar_missions: [{target, start_year, end_year, speed_c}]
var colonized_stars: Array = []
var interstellar_missions: Array = []
## In-flight weapon strikes on star systems: [{target, kind:"laser"|"berserker",
## start_year, end_year}].  Laser pulses cross at light speed; berserkers crawl sub-light.
var interstellar_attacks: Array = []
## Alien presence at stars: star_name → "aggressive" | "peaceful".  Highlighted red /
## blue on the star map.  Seeded per game.
var star_factions: Dictionary = {}

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

## Bodies whose planet-bar button is unlocked: Earth (home) plus any body a Survey
## probe has been sent to.  Keyed by lower-case body name.
var surveyed_planets: Array = ["earth"]
## name → Button, populated in _ready from the PlanetBar.
var _planet_buttons: Dictionary = {}

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

# ── Manufacturing Capacity (MC) ───────────────────────────────────────────────
## Industrial throughput is per-planet: each world can only run so much manufacturing
## at once.  Its capacity = a manual base (cottage industry) + the factories built on
## it, multiplied by automation, then scaled by how well the civilisation's one finite
## labour force can staff all that capacity.  See _process_production.
const BASE_MC: float       = 5000.0    # manual industry every inhabited world has, work/day
const LABOR_PER_CAP: float = 2000.0    # people needed per raw work-unit (before automation)
## planet → Σ factory mc_capacity, refreshed in _recompute_production_cache.
var _cached_planet_built_mc: Dictionary = {}
## planet → { "capacity": work/day, "demand": work/day } from the last production tick,
## pushed to the ProductionPanel for its capacity readout.
var _last_mc_state: Dictionary = {}

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

@onready var science_label: Label = $main_ui/VBoxContainer3/HBoxContainer/ScienceLabel
@onready var research_ui: Control = $main_ui/VBoxContainer3/HBoxContainer2/research_tree
@onready var time_label: Label = $main_ui/VBoxContainer3/HBoxContainer/TimeBox/time
@onready var statistics_page: Control = $main_ui/VBoxContainer3/HBoxContainer2/StatisticsPage
@onready var planet_info_page: PanelContainer = $main_ui/PlanetInfoPage
@onready var build_panel: PanelContainer = $main_ui/BuildPanel
@onready var launch_panel: PanelContainer = $main_ui/LaunchPanel
@onready var sidebar: SidebarControl     = $main_ui/VBoxContainer3/HBoxContainer2
@onready var planet_bar: Control         = $main_ui/PlanetBar
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
		"minerals": 50.0,
		"energy": 20.0
	}

	year = 1945
	month = 0
	day = 0
	stats["current_population"] = 2_300_000_000.0   # world population in 1945
	time_accum = 0.0
	active_launches = []
	_next_launch_id = 1
	solar_satellites_deployed = 0
	colonized_planets = []
	colonized_stars = []
	interstellar_missions = []
	interstellar_attacks = []
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
	var earth_buildings: Array = []
	for _i in range(6):  earth_buildings.append("Mine")
	for _i in range(10): earth_buildings.append("Matter Depot")   # +10M matter cap to bank mine output
	for _i in range(10): earth_buildings.append("Biomass Burner")
	for _i in range(10): earth_buildings.append("Coal Plant")
	for _i in range(5):  earth_buildings.append("Oil Plant")
	earth_buildings.append("Research Lab")
	planet_buildings = {"earth": earth_buildings}
	# Starter production: a working industrial base in the production menu —
	# quicklime → concrete, the foundation for expanding the operation.
	_production_jobs = [
		{"id": 1, "recipe": "Lime Production",     "planet": "earth", "rate": 2.0},
		{"id": 2, "recipe": "Concrete Production", "planet": "earth", "rate": 1.0},
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
	_refresh_planet_buttons()
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
	launch_panel.launch_requested.connect(_on_launch_requested)
	production_panel.production_changed.connect(_on_production_changed)
	if sidebar and sidebar.automation_panel:
		sidebar.automation_panel.automation_changed.connect(_on_automation_changed)
	if sidebar and sidebar.star_map:
		sidebar.star_map.colonize_requested.connect(_on_colonize_requested)
		sidebar.star_map.laser_requested.connect(_on_laser_requested)
		sidebar.star_map.berserker_requested.connect(_on_berserker_requested)
	politics_page.policy_changed.connect(_on_policy_changed)
	game_over_screen.restart_requested.connect(_on_restart_requested)
	settings_menu.closed.connect(_on_settings_closed)

	_setup_event_notifications()
	_init_planet_buttons()
	_setup_bar_backgrounds()

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

func _setup_bar_backgrounds() -> void:
	var canvas := $main_ui
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.10, 0.86)
	style.set_corner_radius_all(4)
	style.set_border_width_all(1)
	style.border_color = Color(0.35, 0.45, 0.65, 0.35)

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

func _init_planet_buttons() -> void:
	_planet_buttons.clear()
	if planet_bar == null:
		return
	for pname: String in ["sun", "mercury", "venus", "earth", "mars",
			"jupiter", "saturn", "uranus", "neptune"]:
		var btn := planet_bar.get_node_or_null(pname + "_button") as Button
		if btn:
			_planet_buttons[pname] = btn

## Enable a body's button only once a Survey probe has been sent there (Earth is
## always available).  Locked buttons get an explanatory tooltip.
func _refresh_planet_buttons() -> void:
	for pname: String in _planet_buttons:
		var unlocked: bool = pname == "earth" or surveyed_planets.has(pname)
		var btn: Button = _planet_buttons[pname]
		btn.disabled = not unlocked
		btn.tooltip_text = "" if unlocked else "Send a Survey probe here to unlock"

## Mark a body as surveyed (called when a Survey mission is launched to it) and
## refresh the planet bar.  No-op if already surveyed.
func _mark_surveyed(body: String) -> void:
	if body == "" or surveyed_planets.has(body):
		return
	surveyed_planets.append(body)
	_refresh_planet_buttons()

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
const AUTOMATION_UNLOCK_RESEARCH: String = "autonomous_industrial_control"

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

func _process(delta: float) -> void:
	# ── Drain one pending event notification per frame ────────────────────────
	if not _pending_event_notifications.is_empty():
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

		var production := _get_total_production()
		for resource in production:
			ResearchTree.resources[resource] = ResearchTree.resources.get(resource, 0.0) + production[resource] * delta_days
		_accumulate_compounds(delta_days)
		_accumulate_emissions(delta_days)
		_process_production(delta_days)
		_process_automation()
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
			_check_asteroid_impact()
			_check_pandemic()
			_check_nuclear_war()
			_check_game_events("year")
			_check_game_events("population")
			_check_game_events("compute")
			if timeline_panel and timeline_panel.visible:
				timeline_panel.set_current_year(year)

	if current_planet != "" and planet_info_page.visible:
		planet_info_page.set_planet_info(get_planet_data(current_planet))

	# Live-update which build-cost items the player can currently afford (recolour
	# only — no rebuild, so the menu's scroll position is preserved).
	if build_panel.visible:
		build_panel.refresh_affordability(_build_cost_stockpiles())

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
						solar_satellites_deployed + payload, 0, SWARM_SAT_MAX)
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
		launch_panel.set_swarm_state(_build_satellite_stock(), solar_satellites_deployed, SWARM_SAT_MAX)
		launch_panel.set_launch_stock(_build_launch_stock())
		launch_panel.refresh_launches(_compute_launch_display_data())

## Populate _bdef_cache from BuildingData.BUILDINGS (called once in _ready).
func _init_building_cache() -> void:
	_bdef_cache.clear()
	for b: Dictionary in BuildingData.BUILDINGS:
		_bdef_cache[b["name"]] = b

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
const _PLANET_BASE_STORAGE: Dictionary = {"minerals": 100_000.0, "energy": 100_000.0}

## Returns the storage capacity this specific planet contributes to the global
## pool: base allocation (if colonised / Earth) + capacity from storage buildings.
func _get_planet_storage_cap(planet_name: String) -> Dictionary:
	var cap: Dictionary = _PLANET_BASE_STORAGE.duplicate() \
		if (planet_name == "earth" or colonized_planets.has(planet_name)) \
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

## Rebuild _cached_compute and _cached_prod in a single pass over all buildings.
## Called lazily by _get_compute_rate / _get_total_production when _prod_dirty.
func _recompute_production_cache() -> void:
	# Population compute: each individual contributes the best unlocked evolution
	# node's FLOP/s value (10^17 for all current nodes).
	var flops_per_person: float = evolution_ui.get_unlocked_compute_per_individual()
	var pop: float = float(stats.get("current_population", 0))
	var compute: float = pop * flops_per_person
	var minerals: float = 0.0
	var energy:   float = 0.0
	var built_mc: Dictionary = {}
	for planet_name: String in planet_buildings:
		var pmc: float = 0.0
		for b_name: String in planet_buildings[planet_name]:
			var bdef: Dictionary = _bdef_cache.get(b_name, {})
			var prod: Dictionary = bdef.get("production", {})
			compute  += (prod.get("compute",  0.0) as float)
			minerals += (prod.get("minerals", 0.0) as float)
			energy   += (prod.get("energy",   0.0) as float)
			pmc      += float(bdef.get("mc_capacity", 0.0))
		built_mc[planet_name] = pmc
	_cached_planet_built_mc = built_mc
	# Dyson swarm: every Solar Satellite deployed to the Sun beams power to the grid.
	energy += float(solar_satellites_deployed) * SWARM_SAT_POWER
	compute  *= (1.0 + ResearchTree.get_boost("research_speed")) * _policy_compute_mult()
	minerals *= (1.0 + ResearchTree.get_boost("matter_production")) * _policy_minerals_mult()
	energy   *= (1.0 + ResearchTree.get_boost("energy_production"))  * _policy_energy_mult()
	_cached_compute       = compute
	_cached_prod          = {
		# science_production boost scales how quickly science resources accumulate
		# (distinct from research_speed, which scales how fast an active job progresses)
		"science":  compute * science_multiplier * _policy_science_mult()
					* (1.0 + ResearchTree.get_boost("science_production")),
		"minerals": minerals,
		"energy":   energy,
	}
	# Recompute storage caps in the same dirty pass so they're always current.
	_cached_storage_caps = _compute_storage_caps()
	_prod_dirty = false

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

	# ── Sun Red Giant ─────────────────────────────────────────────────────────
	# Extinction fires when every inhabited planet (Earth + colonies) is inside
	# the Sun's expanding radius.  Colonising outer worlds buys real time:
	#   Mars survives until ~7.6 B yr, Jupiter until ~7.8 B yr, etc.
	if not has_left_solar_system:
		var sun_au: float = _get_sun_radius_au(year)
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
		demand[jp] = float(demand.get(jp, 0.0)) + float(job.get("rate", 1.0)) * _recipe_work(r)

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
		var rate: float = float(job.get("rate", 1.0)) * mc_throttle
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

		var job_id := int(job.get("id", 0))
		# Status priority: an input shortage is shown first; otherwise, if the world's
		# manufacturing capacity is the limit, flag that; else the job runs clean.
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

	production_panel.set_mc_state(_last_mc_state)

## Look up a recipe by exact name (searches the full master list).
func _find_recipe_by_name(name: String) -> Dictionary:
	for r in RecipeData.RECIPES:
		if r["name"] == name:
			return r
	return {}

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
	while _count_building(planet, building) < target and guard < target:
		if not try_build(planet, building):
			break
		guard += 1

## Keep rule.keep missions of this kind in flight, launching while affordable/valid.
func _run_launch_rule(rule: Dictionary, angles: Dictionary) -> void:
	var mission: String = str(rule.get("mission", ""))
	var origin: String = str(rule.get("origin", "earth"))
	var target: String = str(rule.get("target", ""))
	var keep: int = int(rule.get("keep", 0))
	var active: int = _count_active_launches(mission, origin, target)
	var guard: int = 0
	while active < keep and guard < keep:
		var before: int = active_launches.size()
		_auto_launch(rule, angles)
		if active_launches.size() == before:
			break   # couldn't launch (unaffordable / invalid) — retry next frame
		active += 1
		guard += 1

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
		"fuel_amount":  LaunchPlanner.fuel(m_idx, origin_cap, target_cap, angles, 0.0, cost_mult),
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
func _planet_inv(planet: String) -> Dictionary:
	if not compound_inventory.has(planet):
		compound_inventory[planet] = {}
	return compound_inventory[planet]

## Current held amount of a resource.  science/minerals/energy are global pools;
## every other compound is stored per-planet (mined and crafted locally).
func _get_stockpile(key: String, planet: String) -> float:
	if key in ["science", "minerals", "energy"]:
		return float(ResearchTree.resources.get(key, 0.0))
	return float(_planet_inv(planet).get(key, 0.0))

## Deducts from the global pool (science/minerals/energy) or the planet's inventory.
func _deduct_stockpile(key: String, amount: float, planet: String) -> void:
	if key in ["science", "minerals", "energy"]:
		ResearchTree.resources[key] = maxf(0.0, float(ResearchTree.resources.get(key, 0.0)) - amount)
	else:
		var inv: Dictionary = _planet_inv(planet)
		inv[key] = maxf(0.0, float(inv.get(key, 0.0)) - amount)

## Adds to the global pool (science/minerals/energy) or the planet's inventory.
func _add_stockpile(key: String, amount: float, planet: String) -> void:
	if key in ["science", "minerals", "energy"]:
		ResearchTree.resources[key] = float(ResearchTree.resources.get(key, 0.0)) + amount
	else:
		var inv: Dictionary = _planet_inv(planet)
		inv[key] = float(inv.get(key, 0.0)) + amount

## A colony ship delivers a foothold so the new world can bootstrap its own
## (per-planet) economy: a few mines to extract local materials, plus a small cache
## of construction supplies to raise the first structures.  Without this the colony
## would start with an empty inventory and be unable to afford anything.
func _establish_colony_base(planet_name: String) -> void:
	if not planet_buildings.has(planet_name):
		planet_buildings[planet_name] = []
	for _i in range(3):
		planet_buildings[planet_name].append("Mine")
	var inv: Dictionary = _planet_inv(planet_name)
	inv["Concrete"] = float(inv.get("Concrete", 0.0)) + 50_000.0
	inv["Steel"]    = float(inv.get("Steel", 0.0)) + 20_000.0
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
	var minerals_mult: float = (1.0 + ResearchTree.get_boost("matter_production")) * _policy_minerals_mult()
	for planet_name: String in planet_buildings:
		var crust_comp: Dictionary = (PlanetData.PLANETS.get(planet_name, {}) as Dictionary) \
			.get("composition_g", {}).get("crust", {})
		if crust_comp.is_empty():
			continue
		var mine_rate: float = 0.0
		for b_name: String in planet_buildings[planet_name]:
			mine_rate += float((_bdef_cache.get(b_name, {}) as Dictionary) \
				.get("production", {}).get("minerals", 0.0))
		if mine_rate <= 0.0:
			continue
		var total_crust: float = 0.0
		for compound in crust_comp:
			total_crust += float(crust_comp[compound])
		if total_crust <= 0.0:
			continue
		var boosted: float = mine_rate * minerals_mult * delta_days
		var inv: Dictionary = _planet_inv(planet_name)
		for compound: String in crust_comp:
			var added: float = float(crust_comp[compound]) / total_crust * boosted
			inv[compound] = float(inv.get(compound, 0.0)) + added

## Vent CO₂ from combustion power plants into each planet's atmosphere, in
## proportion to the energy they generate (production.energy × co2_per_energy),
## scaled by elapsed game-days so it tracks the timescale like all other flows.
func _accumulate_emissions(delta_days: float) -> void:
	# Per-planet emission rate (grams/game-day) from combustion plants.
	var emit_rate: Dictionary = {}
	for planet_name: String in planet_buildings:
		var co2_rate: float = 0.0
		for b_name: String in planet_buildings[planet_name]:
			var bdef: Dictionary = _bdef_cache.get(b_name, {})
			var factor: float = float(bdef.get("co2_per_energy", 0.0))
			if factor <= 0.0:
				continue
			var e: float = float((bdef.get("production", {}) as Dictionary).get("energy", 0.0))
			co2_rate += e * factor
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
	for p_name: String in planet_buildings:
		for b_name: String in planet_buildings[p_name]:
			var bdef: Dictionary = _bdef_cache.get(b_name, {})
			var e: float = float((bdef.get("production", {}) as Dictionary).get("energy", 0.0))
			if e <= 0.0:
				continue
			total += e
			if float(bdef.get("co2_per_energy", 0.0)) > 0.0:
				dirty += e
	total += float(solar_satellites_deployed) * SWARM_SAT_POWER   # the swarm is clean
	return dirty / total if total > 0.0 else 0.0

# Returns compute rate (population + buildings, boosted by tech and policy).
func _get_compute_rate() -> float:
	if _prod_dirty:
		_recompute_production_cache()
	return _cached_compute

# Returns per-second production of every storable resource.
func _get_total_production() -> Dictionary:
	if _prod_dirty:
		_recompute_production_cache()
	return _cached_prod

func get_planet_data(planet_name: String) -> Dictionary:
	var planet_names := {
		"sun":     "Sun",
		"mercury": "Mercury", "venus": "Venus",   "earth": "Earth",
		"mars":    "Mars",    "jupiter": "Jupiter","saturn": "Saturn",
		"uranus":  "Uranus",  "neptune": "Neptune",
	}
	var d := {
		"name":       planet_names.get(planet_name, planet_name.capitalize()),
		# Population is global and attributed to Earth (humanity's home); colonies
		# show 0 here.  Always a whole number of people.
		"population": int(stats.get("current_population", 0)) if planet_name == "earth" else 0,
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
	var raw_comp: Dictionary = (PlanetData.PLANETS.get(planet_name, {}) as Dictionary) \
		.get("composition_g", {})
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
	var crust_comp: Dictionary = (PlanetData.PLANETS.get(planet_name, {}) as Dictionary) \
		.get("composition_g", {}).get("crust", {})
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
	for b: Dictionary in BuildingData.BUILDINGS:
		for res: String in (b.get("cost", {}) as Dictionary):
			if not have.has(res):
				have[res] = _get_stockpile(res, current_planet)
	return have

func _get_catalog_for_display() -> Array:
	var has_colony: bool   = current_planet == "earth" or colonized_planets.has(current_planet)
	var planet_type: String = PLANET_TYPES.get(current_planet, "rocky")
	var built: Array = planet_buildings.get(current_planet, [])
	var result: Array = []
	for b: Dictionary in BuildingData.BUILDINGS:
		# Count how many of this building are on the current planet.
		var cnt: int = 0
		for bn in built:
			if bn == b["name"]:
				cnt += 1
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
		var req: String = BuildingUnlocks.BUILDING_UNLOCK_REQUIREMENTS.get(b["name"], "")
		var tech_ok: bool = req == "" or ResearchTree.is_unlocked(req)
		entry["available"] = has_colony and tech_ok
		if not has_colony:
			entry["requires"] = "colony_mission"
		elif not tech_ok:
			entry["requires"] = req
		else:
			entry["requires"] = ""
		entry["count"] = cnt
		# Current stockpile (on this planet) of each cost resource so the panel can
		# dim the ones the player can't yet afford here.
		var have: Dictionary = {}
		for res: String in (b.get("cost", {}) as Dictionary):
			have[res] = _get_stockpile(res, current_planet)
		entry["have"] = have
		result.append(entry)
	return result

## Produces a human-readable label for the planet-type requirement,
## e.g. ["rocky"] → "rocky planet"  |  ["rocky","gas_giant"] → "rocky or gas giant planet"
func _building_type_label(allowed_types: Array) -> String:
	var names: Array = allowed_types.map(func(t: String) -> String:
		return t.replace("_", " "))
	return " or ".join(names) + " planet"

func select_planet(planet_name: String) -> void:
	# Bodies stay inaccessible until a Survey probe has been sent there (Earth is
	# home).  The planet-bar buttons enforce this too; this guards other callers.
	if planet_name != "earth" and not surveyed_planets.has(planet_name):
		return
	current_planet = planet_name
	sidebar.hide_all()
	planet_info_page.set_planet_info(get_planet_data(planet_name))
	build_panel.set_planet(planet_name, _get_catalog_for_display())

## Attempt to build one `building_name` on `planet_name`.  Returns true on success,
## false if it's invalid, research-locked, or unaffordable (the automation executor
## relies on the return value to know when to stop topping up a maintained count).
func try_build(planet_name: String, building_name: String) -> bool:
	var building := _find_building_def(building_name)
	if building.is_empty():
		return false

	if planet_name != "earth" and not colonized_planets.has(planet_name):
		return false

	var req: String = BuildingUnlocks.BUILDING_UNLOCK_REQUIREMENTS.get(building_name, "")
	if req != "" and not ResearchTree.is_unlocked(req):
		return false

	# Pay with global resources (energy) and this planet's local compound inventory.
	var cost: Dictionary = building.get("cost", {})
	for resource: String in cost:
		if _get_stockpile(resource, planet_name) < float(cost[resource]):
			return false

	for resource: String in cost:
		_deduct_stockpile(resource, float(cost[resource]), planet_name)

	if not planet_buildings.has(planet_name):
		planet_buildings[planet_name] = []
	planet_buildings[planet_name].append(building_name)
	_mark_prod_dirty()

	planet_info_page.set_planet_info(get_planet_data(planet_name))
	if build_panel.visible:
		build_panel.set_planet(planet_name, _get_catalog_for_display())
	if launch_panel.visible:
		launch_panel.set_launch_mods(_build_launch_mods_map())
	if building_name == "Orbital Laser" and sidebar and sidebar.star_map and sidebar.star_map.visible:
		refresh_star_map()   # the laser is now available as a star-map weapon
	return true

## Number of `building_name` currently standing on `planet_name`.
func _count_building(planet_name: String, building_name: String) -> int:
	var c: int = 0
	for b in planet_buildings.get(planet_name, []):
		if b == building_name:
			c += 1
	return c

func _on_build_requested(planet_name: String, building_name: String) -> void:
	try_build(planet_name, building_name)

func _on_demolish_requested(planet_name: String, building_name: String) -> void:
	var built: Array = planet_buildings.get(planet_name, [])
	var idx: int = built.rfind(building_name)   # remove the last-placed copy
	if idx == -1:
		return
	# Enforce per-building minimums (e.g. always keep ≥1 Biomass Burner so energy
	# production can't collapse and soft-lock the economy).
	var min_count: int = int((_bdef_cache.get(building_name, {}) as Dictionary).get("min_count", 0))
	if min_count > 0:
		var current: int = 0
		for bn in built:
			if bn == building_name:
				current += 1
		if current <= min_count:
			return
	built.remove_at(idx)
	_mark_prod_dirty()
	planet_info_page.set_planet_info(get_planet_data(planet_name))
	if build_panel.visible:
		build_panel.set_planet(planet_name, _get_catalog_for_display())
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
		var room: int = SWARM_SAT_MAX - solar_satellites_deployed
		if room <= 0:
			return                                    # swarm already full
		var avail: int = int(_get_stockpile(mission_def.get("payload", ""), origin_name))
		sat_payload = mini(int(mission_def.get("payload_per_launch", 0)), mini(avail, room))
		if sat_payload <= 0:
			return                                    # no satellites stockpiled to loft

	# Cost is the launch vehicle (Rockets) plus the chosen propellant, both drawn from
	# the origin planet's inventory.
	var rockets: float = float(params.get("rockets", 0))
	var fuel_id: String = str(params.get("fuel_id", ""))
	var fuel_amount: float = float(params.get("fuel_amount", 0.0))
	if _get_stockpile("Rocket", origin_name) < rockets:
		return
	if fuel_id != "" and _get_stockpile(fuel_id, origin_name) < fuel_amount:
		return
	_deduct_stockpile("Rocket", rockets, origin_name)
	if fuel_id != "" and fuel_amount > 0.0:
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
	launch_panel.set_swarm_state(_build_satellite_stock(), solar_satellites_deployed, SWARM_SAT_MAX)
	launch_panel.set_launch_stock(_build_launch_stock())
	launch_panel.refresh_launches(_compute_launch_display_data())

# ── Interstellar colonisation ─────────────────────────────────────────────────

## Distance (ly) to a named star, from the star-map catalogue.
func _star_distance_ly(star_name: String) -> float:
	for s: Dictionary in StarMapPanel.STARS:
		if str(s["name"]) == star_name:
			return float(s["dist"])
	return 0.0

## Launch an interstellar colony ship from Sol to a star with a chosen max speed β and
## max acceleration.  The real relativistic energy (accel + coast + decel for the ship's
## mass over the distance) is computed by StarMapPanel.plan_flight and gated on reserves.
func _on_colonize_requested(star_name: String, gamma_max: float, accel: float) -> void:
	if star_name == "" or colonized_stars.has(star_name):
		return
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
	for m in interstellar_missions:
		if float(year) >= float(m.get("end_year", INF)):
			var target: String = str(m.get("target", ""))
			if target != "" and not colonized_stars.has(target):
				colonized_stars.append(target)
				_announce("Interstellar Colony",
					"A self-sustaining human colony is established around %s. Inhabited star systems: %d." % [
						target, colonized_stars.size() + 1],
					"interstellar_arrival_%s_%d" % [target, year])
		else:
			still.append(m)
	interstellar_missions = still
	refresh_star_map()

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
	sidebar.star_map.set_interstellar_state(colo, disp, ResearchTree.resources.get("energy", 0.0))
	sidebar.star_map.set_star_factions(star_factions)
	# In-flight weapon strikes (laser pulses + berserker swarms) with their progress.
	var atk: Array = []
	for a in interstellar_attacks:
		var sy: float = float(a.get("start_year", year))
		var ey: float = float(a.get("end_year", year))
		var p: float = 0.0 if ey <= sy else clampf((float(year) - sy) / (ey - sy), 0.0, 1.0)
		atk.append({"target": str(a.get("target", "")), "progress": p,
			"kind": str(a.get("kind", "laser")), "power": float(a.get("power", 1.0))})
	sidebar.star_map.set_attacks(atk)
	sidebar.star_map.set_weapon_caps(_has_orbital_laser(), _has_berserkers())

## Seed alien presence at a handful of stars (aggressive = red, peaceful = blue).
func _seed_star_factions() -> void:
	star_factions = {}
	var names: Array = []
	for s in StarMapPanel.STARS:
		names.append(str(s["name"]))
	names.shuffle()
	for i in range(names.size()):
		if i < 3:
			star_factions[names[i]] = "aggressive"
		elif i < 6:
			star_factions[names[i]] = "peaceful"

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

## Launch a von Neumann berserker swarm at a star system — a slow, self-replicating
## weapon that consumes the target on arrival.
func _on_berserker_requested(star_name: String) -> void:
	if game_over or star_name == "" or not _has_berserkers():
		return
	if _attack_in_flight(star_name):
		return
	var dist: float = _star_distance_ly(star_name)
	if dist <= 0.0:
		return
	if ResearchTree.resources.get("energy", 0.0) < BERSERKER_ENERGY:
		return
	ResearchTree.resources["energy"] = maxf(0.0,
		float(ResearchTree.resources.get("energy", 0.0)) - BERSERKER_ENERGY)
	var years: float = dist / BERSERKER_BETA
	interstellar_attacks.append({
		"target": star_name, "kind": "berserker",
		"start_year": float(year), "end_year": float(year) + years,
	})
	_announce("Berserkers Launched",
		"A von Neumann berserker seed accelerates toward %s. It will arrive in ~%s and replicate." % [
			star_name, Units.format_si(years, "yr")],
		"berserker_%s_%d" % [star_name, year])
	refresh_star_map()

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
			if kind == "berserker":
				_announce("Berserker Strike",
					"The berserker swarm reaches %s and devours the system. %s" % [
						target, "The hostile force is annihilated." if had else "Nothing organised remained."],
					"berserker_hit_%s_%d" % [target, year])
			else:
				_announce("Laser Strike",
					"The laser pulse lances %s. %s" % [
						target, "The force there is obliterated." if had else "It strikes empty space."],
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
		"resources":          ResearchTree.resources,
		"active_launches":    active_launches,
		"next_launch_id":     _next_launch_id,
		"solar_satellites_deployed": solar_satellites_deployed,
		"colonized_planets":  colonized_planets,
		"colonized_stars":    colonized_stars,
		"interstellar_missions": interstellar_missions,
		"interstellar_attacks":  interstellar_attacks,
		"star_factions":      star_factions,
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
				solar_satellites_deployed + _migrated_arrays * 24, 0, SWARM_SAT_MAX)
		# Guarantee Earth keeps at least one Biomass Burner (soft-lock guard).
		var _earth: Array = planet_buildings.get("earth", [])
		if not _earth.has("Biomass Burner"):
			_earth.append("Biomass Burner")
			planet_buildings["earth"] = _earth

	if data.has("resources") and data["resources"] is Dictionary:
		for key in data["resources"]:
			ResearchTree.resources[key] = float(data["resources"][key])

	if data.has("active_launches") and data["active_launches"] is Array:
		active_launches = data["active_launches"]
	else:
		active_launches = []

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
	interstellar_missions = []
	if data.has("interstellar_missions") and data["interstellar_missions"] is Array:
		for m in data["interstellar_missions"]:
			interstellar_missions.append((m as Dictionary).duplicate())
	interstellar_attacks = []
	if data.has("interstellar_attacks") and data["interstellar_attacks"] is Array:
		for a in data["interstellar_attacks"]:
			interstellar_attacks.append((a as Dictionary).duplicate())
	star_factions = {}
	if data.has("star_factions") and data["star_factions"] is Dictionary:
		for k: String in data["star_factions"]:
			star_factions[k] = str(data["star_factions"][k])
	else:
		_seed_star_factions()   # older save: assign fresh alien presence

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
	_refresh_planet_buttons()

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
func _population_capacity() -> float:
	var prod: Dictionary = _get_total_production()
	var energy_prod:   float = float(prod.get("energy",   0.0))
	var minerals_prod: float = float(prod.get("minerals", 0.0))

	var supportable_offworld: float = minf(
		energy_prod   / ENERGY_PER_CAPITA,
		minerals_prod / MINERALS_PER_CAPITA
	)
	var colony_habitat: float = COLONY_HABITAT_K * float(colonized_planets.size())
	var offworld_k: float = maxf(0.0, minf(colony_habitat, supportable_offworld))
	# Climate: CO₂ deterministically shrinks Earth's habitable capacity.
	return (EARTH_NATURAL_K * _climate_capacity_factor() + offworld_k) \
		* PoliticsData.pop_capacity_mult(policies)

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
	var pop: float = float(stats.get("current_population", 0))
	var k:   float = _population_capacity()
	var new_pop: float
	if k <= MIN_POPULATION or pop <= 0.0:
		new_pop = MIN_POPULATION
	else:
		# P(t+Δ) = K / (1 + (K/P − 1)·e^(−rΔ)); handles both growth (P<K) and
		# decline (P>K) and converges to K as Δ → ∞.
		var r: float = POP_GROWTH_PER_YEAR / 365.25 * PoliticsData.pop_growth_mult(policies)
		var decay: float = exp(-r * delta_days)
		new_pop = k / (1.0 + (k / pop - 1.0) * decay)
	# People are counted in whole numbers — floor to keep the population integral.
	# Per-step growth is always far more than one person, so this never stalls.
	new_pop = floorf(maxf(MIN_POPULATION, new_pop))
	if new_pop != pop:
		stats["current_population"] = new_pop
		_mark_prod_dirty()   # population feeds the compute rate

func _refresh_stats() -> void:
	stats["year"]             = year
	stats["compute_rate"]     = _get_compute_rate()
	stats["science"]          = ResearchTree.resources.get("science",  0.0)
	stats["minerals"]         = ResearchTree.resources.get("minerals", 0.0)
	stats["energy"]           = ResearchTree.resources.get("energy",   0.0)
	stats["colony_count"]     = colonized_planets.size()
	stats["life_expectancy"]  = _life_expectancy()
	stats["ai_autonomy"]      = PoliticsData.ai_autonomy(policies)
	stats["existential_risk"] = PoliticsData.existential_risk(policies)

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

	if science_label:
		var prod         := _get_total_production()
		var compute_rate := _get_compute_rate()
		# Each stored unit:  1 science = 1 FLOP  |  1 mineral = 1 Gram  |  1 energy = 1 Joule
		# Each rate unit:    compute → FLOP/s  |  minerals → Grams/s  |  energy → Watts
		var min_cap: float = _cached_storage_caps.get("minerals", 0.0)
		var en_cap:  float = _cached_storage_caps.get("energy",   0.0)
		science_label.text = (
			"Compute: %s  |  Matter: %s / %s (+%s)  |  Energy: %s / %s (+%s)" % [
				Units.format_si_verbose(compute_rate, "FLOP/s"),
				Units.format_si_verbose(ResearchTree.resources.get("minerals", 0.0), "Grams"),
				Units.format_si_verbose(min_cap, "Grams"),
				Units.format_si_verbose(prod.get("minerals", 0.0), "Grams/s"),
				Units.format_si_verbose(ResearchTree.resources.get("energy",   0.0), "Joules"),
				Units.format_si_verbose(en_cap, "Joules"),
				Units.format_si_verbose(prod.get("energy",   0.0), "Watts"),
			]
		)
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

func _on_sun_button_pressed() -> void:
	select_planet("sun")

func _on_mercury_button_pressed() -> void:
	select_planet("mercury")

func _on_venus_button_pressed() -> void:
	select_planet("venus")

func _on_earth_button_pressed() -> void:
	select_planet("earth")

func _on_mars_button_pressed() -> void:
	select_planet("mars")

func _on_jupiter_button_pressed() -> void:
	select_planet("jupiter")

func _on_saturn_button_pressed() -> void:
	select_planet("saturn")

func _on_uranus_button_pressed() -> void:
	select_planet("uranus")

func _on_neptune_button_pressed() -> void:
	select_planet("neptune")

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

## A mountain-sized asteroid strikes one inhabited world: it levels every structure
## there and kills much of the population (softened when humanity is spread across
## several worlds).  Survivable by design — one emergency Biomass Burner is left so
## the grid can recover, and the population floor prevents outright extinction.
func _trigger_asteroid_impact() -> void:
	var inhabited: Array = (["earth"] as Array) + colonized_planets
	var target: String = str(inhabited[randi() % inhabited.size()])

	# Raze the struck world's infrastructure, leaving one lone Biomass Burner running
	# so energy production (and thus the ability to rebuild anything) never hits zero.
	planet_buildings[target] = ["Biomass Burner"]
	_mark_prod_dirty()

	# Kill a majority of the population, divided across inhabited worlds — colonies
	# mean each strike claims a smaller share of all humanity.
	var pop: float = float(stats.get("current_population", 0))
	var kill_frac: float = randf_range(0.50, 0.85) / float(inhabited.size())
	var survivors: float = floorf(maxf(MIN_POPULATION, pop * (1.0 - kill_frac)))
	var lost: float = maxf(0.0, pop - survivors)
	stats["current_population"] = survivors
	_refresh_stats()

	var notif: Dictionary = {
		"id":       "impact_%d" % year,
		"year":     year,
		"title":    "Asteroid Impact",
		"desc":     "Impact event recorded on %s. Surface structures: 0 remaining. Population change: −%s (−%d%%)." % [
			target.capitalize(), Units.format_si_verbose(lost, ""), int(round(kill_frac * 100.0))
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
	var c: int = 0
	for p: String in planet_buildings:
		for b in planet_buildings[p]:
			if b == "Nuclear Plant":
				c += 1
	return c

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
	var survivors: float = floorf(maxf(MIN_POPULATION, pop * (1.0 - kill_frac)))
	var lost: float = maxf(0.0, pop - survivors)
	stats["current_population"] = survivors

	# Roughly half of Earth's surface industry is destroyed; one Biomass Burner is left
	# so power production (and recovery) can't collapse to zero.
	if planet_buildings.has("earth"):
		var kept: Array = []
		for b: String in planet_buildings["earth"]:
			if randf() > 0.5:
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
		"desc":     "Strategic nuclear exchange recorded on Earth. Population change: −%s (−%d%%). Surface industry: heavily degraded." % [
			Units.format_si_verbose(lost, ""), int(round(kill_frac * 100.0))],
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
