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
var colonized_planets: Array = []     # planets that have received a completed Colony Ship

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
## Running integral of population × time (person-years), used to derive
## total humans ever lived shown on the game-over screen.
var _person_years: float = 0.0
## Accumulated real seconds since the last autosave.
var _autosave_accum: float = 0.0

# ── Production cache ──────────────────────────────────────────────────────────
## True whenever buildings, research, or policies have changed and the cached
## production totals must be recomputed before next use.
var _prod_dirty: bool = true
var _cached_compute: float = 0.0
var _cached_prod: Dictionary = {"science": 0.0, "minerals": 0.0, "energy": 0.0}

## Accumulated mass of each crust compound extracted by all mines, in grams.
var compound_inventory: Dictionary = {}

## Active manufacturing jobs from the Production panel.
## Each entry: { "id": int, "recipe": String, "planet": String, "rate": float }
var _production_jobs: Array = []

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
@onready var sidebar: HBoxContainer      = $main_ui/VBoxContainer3/HBoxContainer2
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
		SolarSystem.toggle_ui_pause()
		get_tree().paused = SolarSystem.ui_paused

	if event.is_action_pressed("pause"):
		SolarSystem.toggle_pause()
		get_viewport().set_input_as_handled()

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
	colonized_planets = []
	compound_inventory = {}
	_production_jobs   = []
	planet_buildings = {
		"earth": [
			"Mine", "Mine", "Mine", "Mine",
			"Coal Plant", "Coal Plant", "Coal Plant", "Coal Plant",
			"Oil Plant", "Oil Plant", "Oil Plant", "Oil Plant",
			"Solar Farm", "Research Lab",
		]
	}
	policies = PoliticsData.default_state()
	game_over              = false
	has_left_solar_system  = false
	_user_speed_mult       = settings_menu.get_default_speed_mult() if settings_menu else 1.0
	_autosave_accum        = 0.0
	_last_snapshot_year    = 1945
	_person_years          = 0.0
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

	# Endgame music player — keeps playing while the game-over screen is up, so it
	# must ignore the tree pause that trigger_game_over() sets.
	if not ResearchTree.research_completed.is_connected(_on_research_completed):
		ResearchTree.research_completed.connect(_on_research_completed)

	build_panel.build_requested.connect(_on_build_requested)
	build_panel.demolish_requested.connect(_on_demolish_requested)
	launch_panel.launch_requested.connect(_on_launch_requested)
	production_panel.production_changed.connect(_on_production_changed)
	politics_page.policy_changed.connect(_on_policy_changed)
	game_over_screen.restart_requested.connect(_on_restart_requested)
	settings_menu.closed.connect(_on_settings_closed)

	if GameSession.should_load_on_start and GameSession.current_save_path != "":
		load_game(GameSession.current_save_path)
	else:
		start_new_game()

	politics_page.load_policies(policies)
	_check_extinction_events()   # hides planets immediately if year ≥ ORBIT_FREEZE_YEAR
	_check_evolution_triggers()
	production_panel.refresh_recipes(_completed_research_map())
	_refresh_stats()
	_update_hud()
	_setup_satellite()

func _setup_satellite() -> void:
	sattelite.visible = false

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

	if not game_over:
		var production := _get_total_production()
		for resource in production:
			ResearchTree.resources[resource] = ResearchTree.resources.get(resource, 0.0) + production[resource] * delta
		_accumulate_compounds(delta)
		_process_production(delta)
		# Clamp minerals and energy to their storage caps; science is never capped.
		for resource: String in _cached_storage_caps:
			if ResearchTree.resources.has(resource):
				ResearchTree.resources[resource] = minf(
					ResearchTree.resources[resource], _cached_storage_caps[resource]
				)
		# Evolve population on the game-day clock so it tracks resources at any speed.
		if spd > 0.0:
			var delta_days: float = delta / spd
			_update_population(delta_days)
			# Accumulate person-days → convert to person-years for the final stat.
			_person_years += float(stats.get("current_population", 0)) * delta_days / 365.25
		_refresh_stats()
		statistics_page.set_stats(stats)
		_update_hud()

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
			_check_evolution_triggers()
			if timeline_panel and timeline_panel.visible:
				timeline_panel.set_current_year(year)

	if current_planet != "" and planet_info_page.visible:
		planet_info_page.set_planet_info(get_planet_data(current_planet))

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
				if launch["mission"] == "Colony Ship":
					var target: String = launch.get("target", "")
					if target != "" and not colonized_planets.has(target):
						colonized_planets.append(target)
						print("[Game] Colony established on %s" % target.capitalize())
	if any_completed:
		_check_evolution_triggers()
	if launch_panel.visible:
		launch_panel.set_game_date(year, month + 1, day + 1)
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
	for planet_name: String in planet_buildings:
		for b_name: String in planet_buildings[planet_name]:
			var prod: Dictionary = (_bdef_cache.get(b_name, {}) as Dictionary).get("production", {})
			compute  += (prod.get("compute",  0.0) as float)
			minerals += (prod.get("minerals", 0.0) as float)
			energy   += (prod.get("energy",   0.0) as float)
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

func _policy_science_mult() -> float:
	var m := 1.0
	if bool(policies.get("open_source",    false)): m += 0.20
	if bool(policies.get("carbon_tax",     false)): m += 0.08
	if bool(policies.get("free_press",     true)):  m += 0.05
	# research_budget: 50% is neutral; range adds ±20 %
	m += (float(policies.get("research_budget", 50.0)) - 50.0) / 50.0 * 0.20
	# space_budget: +1 % per 10 % spent
	m += float(policies.get("space_budget", 10.0)) / 10.0 * 0.01
	return maxf(0.1, m)

func _policy_compute_mult() -> float:
	var m := 1.0
	if bool(policies.get("ai_research", false)): m += 0.20
	if bool(policies.get("ubi",         false)): m += 0.10
	return m

func _policy_minerals_mult() -> float:
	var m := 1.0
	if bool(policies.get("automation",      false)): m += 0.15
	if bool(policies.get("asteroid_mining", false)): m += 0.25
	if bool(policies.get("ubi",             false)): m -= 0.05
	# tax_rate: 35 % is neutral; each 5 % above/below shifts minerals ±2 %
	m += (float(policies.get("tax_rate", 35.0)) - 35.0) / 5.0 * 0.02
	# military_spending drains minerals (−10 % at max 50 %)
	m -= float(policies.get("military_spending", 10.0)) / 50.0 * 0.10
	return maxf(0.05, m)

func _policy_energy_mult() -> float:
	var m := 1.0
	if bool(policies.get("automation",  false)): m -= 0.10
	if bool(policies.get("carbon_tax",  false)): m -= 0.15
	return maxf(0.05, m)

## Returns a duration multiplier to apply to all new missions.
func _policy_mission_dur_mult() -> float:
	if bool(policies.get("nuclear_propulsion", false)):
		return 0.80   # 20 % shorter transit
	return 1.0

func _on_policy_changed(policy_id: String, value: Variant) -> void:
	policies[policy_id] = value
	_mark_prod_dirty()

# ── Evolution triggers ────────────────────────────────────────────────────────

## Inspects game state and adds/unlocks evolution nodes as conditions are met.
## Safe to call repeatedly — all operations are idempotent.
func _check_evolution_triggers() -> void:
	if not evolution_ui:
		return

	var compute := _get_compute_rate()

	# Pre-compute sets used by multiple checks
	var planets_with_completed_mission: Dictionary = {}
	var has_orbit_complete := false
	for launch: Dictionary in active_launches:
		if launch["status"] == "completed":
			planets_with_completed_mission[launch.get("target", "")] = true
			if launch.get("arrival", "") == "orbit":
				has_orbit_complete = true

	var outer_planets := ["jupiter", "saturn", "uranus", "neptune"]
	var outer_visited  := false
	var outer_colonized := false
	for p: String in outer_planets:
		if planets_with_completed_mission.has(p): outer_visited  = true
		if colonized_planets.has(p):              outer_colonized = true

	# ── H. sapiens orbitalis ──────────────────────────────────────────────────
	# Appears when any orbit mission completes; unlocks immediately on that same event.
	if has_orbit_complete:
		if evolution_ui.add_evolution_node("homo_sapiens_orbitalis"):
			pass   # just added — fall through to unlock check
		if not evolution_ui.is_node_unlocked("homo_sapiens_orbitalis"):
			evolution_ui.unlock_evolution_node("homo_sapiens_orbitalis")

	# ── H. sapiens martis ─────────────────────────────────────────────────────
	# Appears when any mission reaches Mars; unlocks on Mars colony.
	if planets_with_completed_mission.has("mars"):
		evolution_ui.add_evolution_node("homo_sapiens_martis")
	if evolution_ui.is_node_visible("homo_sapiens_martis") \
			and not evolution_ui.is_node_unlocked("homo_sapiens_martis") \
			and colonized_planets.has("mars"):
		evolution_ui.unlock_evolution_node("homo_sapiens_martis")

	# ── H. sapiens gravitus ───────────────────────────────────────────────────
	# Appears when any mission reaches an outer planet; unlocks on outer-planet colony.
	if outer_visited:
		evolution_ui.add_evolution_node("homo_sapiens_gravitus")
	if evolution_ui.is_node_visible("homo_sapiens_gravitus") \
			and not evolution_ui.is_node_unlocked("homo_sapiens_gravitus") \
			and outer_colonized:
		evolution_ui.unlock_evolution_node("homo_sapiens_gravitus")

	# ── H. astralis ───────────────────────────────────────────────────────────
	# Appears once orbitalis is unlocked; unlocks at compute ≥ 50.
	if evolution_ui.is_node_unlocked("homo_sapiens_orbitalis"):
		evolution_ui.add_evolution_node("homo_astralis")
	if evolution_ui.is_node_visible("homo_astralis") \
			and not evolution_ui.is_node_unlocked("homo_astralis") \
			and compute >= 50.0:
		evolution_ui.unlock_evolution_node("homo_astralis")

	# ── H. pelagicus ─────────────────────────────────────────────────────────
	# Appears once martis is unlocked; unlocks on any outer-planet colony.
	if evolution_ui.is_node_unlocked("homo_sapiens_martis"):
		evolution_ui.add_evolution_node("homo_pelagicus")
	if evolution_ui.is_node_visible("homo_pelagicus") \
			and not evolution_ui.is_node_unlocked("homo_pelagicus") \
			and outer_colonized:
		evolution_ui.unlock_evolution_node("homo_pelagicus")

	# ── H. cyberneticus ───────────────────────────────────────────────────────
	# Appears when both orbitalis is unlocked and gravitus is visible;
	# unlocks at compute ≥ 100.
	if evolution_ui.is_node_unlocked("homo_sapiens_orbitalis") \
			and evolution_ui.is_node_visible("homo_sapiens_gravitus"):
		evolution_ui.add_evolution_node("homo_cyberneticus")
	if evolution_ui.is_node_visible("homo_cyberneticus") \
			and not evolution_ui.is_node_unlocked("homo_cyberneticus") \
			and compute >= 100.0:
		evolution_ui.unlock_evolution_node("homo_cyberneticus")

	# ── H. digitalis ─────────────────────────────────────────────────────────
	# Appears when cyberneticus is unlocked; unlocks at compute ≥ 1 000.
	if evolution_ui.is_node_unlocked("homo_cyberneticus"):
		evolution_ui.add_evolution_node("homo_digitalis")
	if evolution_ui.is_node_visible("homo_digitalis") \
			and not evolution_ui.is_node_unlocked("homo_digitalis") \
			and compute >= 1000.0:
		evolution_ui.unlock_evolution_node("homo_digitalis")

	# ── H. mechanicus galacticus ──────────────────────────────────────────────
	# Appears when digitalis is unlocked; unlocks with 3+ established colonies.
	if evolution_ui.is_node_unlocked("homo_digitalis"):
		evolution_ui.add_evolution_node("homo_mechanicus_galacticus")
	if evolution_ui.is_node_visible("homo_mechanicus_galacticus") \
			and not evolution_ui.is_node_unlocked("homo_mechanicus_galacticus") \
			and colonized_planets.size() >= 3:
		evolution_ui.unlock_evolution_node("homo_mechanicus_galacticus")

# ── Timescale ─────────────────────────────────────────────────────────────────

## Recompute SolarSystem.seconds_per_day from elapsed game-years.
## Formula: INIT * exp(-DECAY * elapsed), clamped to [MIN, INIT].
## The _user_speed_mult divides the result so higher mult = faster real time.
func _update_timescale() -> void:
	var elapsed: float = maxf(float(year - 2026), 0.0)
	var raw: float = TIMESCALE_INIT * exp(-TIMESCALE_DECAY * elapsed)
	SolarSystem.seconds_per_day = maxf(TIMESCALE_MIN, raw) / _user_speed_mult
	SolarSystem.current_year = year

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
				cause = "Planetary Nebula"
				desc  = "The dying Sun has shed its outer envelope in a brilliant planetary nebula, flooding the solar system with searing ultraviolet radiation. The remaining colonies on %s have been sterilised. The Sun will spend the next 10 billion years cooling as a white dwarf." % planet_str
			else:
				cause = "Solar Expansion"
				desc  = "The expanding Sun has engulfed %s. Every world humanity called home has been consumed by stellar fire." % planet_str
			trigger_game_over(cause, desc)

## Pause the game and display the extinction screen.
func trigger_game_over(cause: String, description: String) -> void:
	if game_over:
		return
	game_over          = true
	SolarSystem.paused = true
	_refresh_stats()
	game_over_screen.show_game_over(cause, description, year, stats, _person_years)

## Called when the player presses "Start New Civilization" on the game-over screen.
func _on_restart_requested() -> void:
	SolarSystem.paused = false
	start_new_game()
	politics_page.load_policies(policies)
	_check_evolution_triggers()
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
		_check_evolution_triggers()
		if timeline_panel and timeline_panel.visible:
			timeline_panel.set_current_year(year)

## Distribute mine output (boosted) into compound_inventory by crust mass fractions.
## Process all active manufacturing jobs: consume inputs from compound_inventory
## and the main resource pools, then deposit outputs.  Called every frame.
var _prod_debug_timer: float = 0.0
func _process_production(delta: float) -> void:
	if _production_jobs.is_empty():
		return
	_prod_debug_timer += delta
	var do_print := _prod_debug_timer >= 2.0
	if do_print:
		_prod_debug_timer = 0.0
		print("[Production] processing %d jobs, delta=%.4f" % [_production_jobs.size(), delta])
	for job in _production_jobs:
		var recipe := _find_recipe_by_name(job.get("recipe", ""))
		if recipe.is_empty():
			continue
		var rate: float = float(job.get("rate", 1.0))

		# Check we can afford all inputs for this frame's slice.
		var inputs: Dictionary = recipe.get("inputs", {})
		var can_run := true
		var missing_input := ""
		for key: String in inputs:
			var need: float = float(inputs[key]) * rate * delta
			var have: float = _get_stockpile(key)
			if have < need:
				can_run = false
				missing_input = key
				break

		var job_id := int(job.get("id", 0))
		production_panel.set_job_status(job_id, can_run, missing_input)

		if do_print:
			if not can_run:
				print("[Production] job '%s' STALLED — missing '%s' (have %.4f, need %.4f/frame)" % [
					job.get("recipe","?"), missing_input,
					_get_stockpile(missing_input),
					float(recipe.get("inputs",{}).get(missing_input,0.0)) * float(job.get("rate",1.0)) * delta
				])
			else:
				print("[Production] job '%s' running — outputs: %s" % [job.get("recipe","?"), recipe.get("outputs",{})])

		if not can_run:
			continue

		# Deduct inputs.
		for key: String in inputs:
			var amount: float = float(inputs[key]) * rate * delta
			_deduct_stockpile(key, amount)

		# Credit outputs.
		var outputs: Dictionary = recipe.get("outputs", {})
		for key: String in outputs:
			var amount: float = float(outputs[key]) * rate * delta
			_add_stockpile(key, amount)

## Look up a recipe by exact name (searches the full master list).
func _find_recipe_by_name(name: String) -> Dictionary:
	for r in RecipeData.RECIPES:
		if r["name"] == name:
			return r
	return {}

## Returns the current held amount of a named resource or compound.
func _get_stockpile(key: String) -> float:
	if key in ["science", "minerals", "energy"]:
		return float(ResearchTree.resources.get(key, 0.0))
	return float(compound_inventory.get(key, 0.0))

## Deducts from the appropriate pool (main resources or compound inventory).
func _deduct_stockpile(key: String, amount: float) -> void:
	if key in ["science", "minerals", "energy"]:
		ResearchTree.resources[key] = maxf(0.0, float(ResearchTree.resources.get(key, 0.0)) - amount)
	else:
		compound_inventory[key] = maxf(0.0, float(compound_inventory.get(key, 0.0)) - amount)

## Adds to the appropriate pool.  Unknown keys go to compound_inventory.
func _add_stockpile(key: String, amount: float) -> void:
	if key in ["science", "minerals", "energy"]:
		ResearchTree.resources[key] = float(ResearchTree.resources.get(key, 0.0)) + amount
	else:
		compound_inventory[key] = float(compound_inventory.get(key, 0.0)) + amount

func _on_production_changed(jobs: Array) -> void:
	_production_jobs = jobs.duplicate(true)
	print("[Production] jobs received: ", _production_jobs.size())

## Returns { node_id: true } for every completed research node — used to gate recipes.
func _completed_research_map() -> Dictionary:
	var result: Dictionary = {}
	for node in ResearchTree.get_unlocked_nodes():
		result[node.id] = true
	return result

func _accumulate_compounds(delta: float) -> void:
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
		var boosted: float = mine_rate * minerals_mult * delta
		for compound: String in crust_comp:
			var added: float = float(crust_comp[compound]) / total_crust * boosted
			compound_inventory[compound] = compound_inventory.get(compound, 0.0) + added

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
		"population": stats.get("current_population", 0) if planet_name == "earth" else 0,
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

	var buildings_list: Array = []
	for b_name in counts:
		buildings_list.append({"name": b_name, "count": counts[b_name]})
	d["buildings"] = buildings_list
	# Build composition with crust depleted by what mines have extracted so far.
	var raw_comp: Dictionary = (PlanetData.PLANETS.get(planet_name, {}) as Dictionary) \
		.get("composition_g", {})
	if raw_comp.is_empty() or compound_inventory.is_empty():
		d["composition_g"] = raw_comp
	else:
		var comp: Dictionary = {}
		for layer: String in raw_comp:
			if layer != "crust":
				comp[layer] = raw_comp[layer]
			else:
				var depleted: Dictionary = {}
				for compound: String in raw_comp["crust"]:
					depleted[compound] = maxf(
						0.0,
						float(raw_comp["crust"][compound]) - compound_inventory.get(compound, 0.0)
					)
				comp["crust"] = depleted
		d["composition_g"] = comp
	d["compound_inventory"] = compound_inventory.duplicate()

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

	# Also surface any compounds currently in the inventory that were produced by
	# manufacturing recipes (not mined), so the planet info panel shows them.
	# Use a rate of 0 so they appear in the list without a misleading +x/s figure.
	for compound: String in compound_inventory:
		if float(compound_inventory[compound]) > 0.0 and not mined.has(compound):
			mined[compound] = 0.0

	d["mined_resources"] = mined

	# Storage — per-planet capacity and global usage for the info panel.
	d["storage_cap"]        = _get_planet_storage_cap(planet_name)
	d["global_storage_cap"] = _cached_storage_caps.duplicate()
	d["global_resources"]   = {
		"minerals": ResearchTree.resources.get("minerals", 0.0),
		"energy":   ResearchTree.resources.get("energy",   0.0),
	}

	return d

func _get_catalog_for_display() -> Array:
	var has_colony: bool   = current_planet == "earth" or colonized_planets.has(current_planet)
	var planet_type: String = PLANET_TYPES.get(current_planet, "rocky")
	var result: Array = []
	for b: Dictionary in BuildingData.BUILDINGS:
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
		# Count how many of this building are on the current planet.
		var built: Array = planet_buildings.get(current_planet, [])
		var cnt: int = 0
		for bn in built:
			if bn == b["name"]:
				cnt += 1
		entry["count"] = cnt
		result.append(entry)
	return result

## Produces a human-readable label for the planet-type requirement,
## e.g. ["rocky"] → "rocky planet"  |  ["rocky","gas_giant"] → "rocky or gas giant planet"
func _building_type_label(allowed_types: Array) -> String:
	var names: Array = allowed_types.map(func(t: String) -> String:
		return t.replace("_", " "))
	return " or ".join(names) + " planet"

func select_planet(planet_name: String) -> void:
	current_planet = planet_name
	sidebar.hide_all()
	planet_info_page.set_planet_info(get_planet_data(planet_name))
	build_panel.set_planet(planet_name, _get_catalog_for_display())

func try_build(planet_name: String, building_name: String) -> void:
	var building := _find_building_def(building_name)
	if building.is_empty():
		return

	if planet_name != "earth" and not colonized_planets.has(planet_name):
		return

	var req: String = BuildingUnlocks.BUILDING_UNLOCK_REQUIREMENTS.get(building_name, "")
	if req != "" and not ResearchTree.is_unlocked(req):
		return

	var cost: Dictionary = building.get("cost", {})
	for resource in cost:
		if ResearchTree.resources.get(resource, 0.0) < cost[resource]:
			return

	for resource in cost:
		ResearchTree.resources[resource] -= cost[resource]

	if not planet_buildings.has(planet_name):
		planet_buildings[planet_name] = []
	planet_buildings[planet_name].append(building_name)
	_mark_prod_dirty()

	planet_info_page.set_planet_info(get_planet_data(planet_name))
	if build_panel.visible:
		build_panel.set_planet(planet_name, _get_catalog_for_display())

func _on_build_requested(planet_name: String, building_name: String) -> void:
	try_build(planet_name, building_name)

func _on_demolish_requested(planet_name: String, building_name: String) -> void:
	var built: Array = planet_buildings.get(planet_name, [])
	var idx: int = built.rfind(building_name)   # remove the last-placed copy
	if idx == -1:
		return
	built.remove_at(idx)
	_mark_prod_dirty()
	planet_info_page.set_planet_info(get_planet_data(planet_name))
	if build_panel.visible:
		build_panel.set_planet(planet_name, _get_catalog_for_display())

func _on_research_completed(node: ResearchNode) -> void:
	_mark_prod_dirty()
	print("[Game] Unlocked: %s" % node.display_name)
	if current_planet != "" and build_panel.visible:
		build_panel.set_planet(current_planet, _get_catalog_for_display())
	production_panel.refresh_recipes(_completed_research_map())
	_check_evolution_triggers()

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

	var cost: Dictionary = params.get("actual_cost", mission_def.get("cost", {}))
	for resource in cost:
		if ResearchTree.resources.get(resource, 0.0) < cost[resource]:
			return
	for resource in cost:
		ResearchTree.resources[resource] -= cost[resource]

	var start_offset: int = params.get("start_offset", 0)
	var duration: int    = int(params.get("duration", 30) * _policy_mission_dur_mult())
	var start_date := _date_add_days(year, month, day, start_offset)
	var end_date   := _date_add_days(start_date[0], start_date[1], start_date[2], duration)

	var origin_name: String = params.get("origin", "earth")
	var target_name: String = params.get("target", "")
	var arrival: String = params.get("arrival", "orbit")

	var launch := {
		"id":          _next_launch_id,
		"mission":     m_name,
		"origin":      origin_name,
		"target":      target_name,
		"arrival":     arrival,
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

	if target_name != "" and target_name != origin_name:
		var origin_planet := get_node_or_null("WorldRoot/Planets/" + origin_name) as Planet
		var target_planet := get_node_or_null("WorldRoot/Planets/" + target_name) as Planet
		if origin_planet and target_planet:
			_spawn_satellite(origin_planet, target_planet, arrival, launch["id"], float(duration))

func _on_launches_button_pressed() -> void:
	launch_panel.set_game_date(year, month + 1, day + 1)
	launch_panel.refresh_launches(_compute_launch_display_data())

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
		"production_jobs":    production_panel.get_jobs(),
		"planet_buildings":   planet_buildings,
		"resources":          ResearchTree.resources,
		"active_launches":    active_launches,
		"next_launch_id":     _next_launch_id,
		"colonized_planets":  colonized_planets,
		"policies":           policies,
		"evolution": {
			"visible":  evolution_ui.get_visible_node_ids(),
			"unlocked": evolution_ui.get_unlocked_map(),
		},
		"stats_history":      statistics_page.get_save_data(),
		"compound_inventory": compound_inventory,
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

	ResearchTree.load_tree(ResearchTreeData.build())
	if data.has("research") and data["research"] is Dictionary:
		ResearchTree.load_state(data["research"])

	year  = int(data.get("year",  2026))
	month = int(data.get("month", 0))
	day   = int(data.get("day",   0))
	stats["current_population"] = float(data.get("population", stats.get("current_population", EARTH_NATURAL_K)))

	if data.has("planet_buildings") and data["planet_buildings"] is Dictionary:
		planet_buildings = data["planet_buildings"]

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

	policies = PoliticsData.default_state()
	if data.has("policies") and data["policies"] is Dictionary:
		for key: String in data["policies"]:
			policies[key] = data["policies"][key]
	politics_page.load_policies(policies)

	if data.has("evolution") and data["evolution"] is Dictionary:
		var ev: Dictionary = data["evolution"]
		var visible: Array  = ev.get("visible",  ["homo_sapiens"])
		var unlocked_ev: Dictionary = ev.get("unlocked", {"homo_sapiens": true})
		evolution_ui.load_evolution_state(visible, unlocked_ev)
	else:
		evolution_ui.reset_to_baseline()
	_check_evolution_triggers()

	if data.has("stats_history") and data["stats_history"] is Dictionary:
		statistics_page.load_save_data(data["stats_history"])

	compound_inventory = {}
	if data.has("compound_inventory") and data["compound_inventory"] is Dictionary:
		for key in data["compound_inventory"]:
			compound_inventory[key] = float(data["compound_inventory"][key])

	if data.has("production_jobs") and data["production_jobs"] is Array:
		_production_jobs = data["production_jobs"].duplicate(true)
		production_panel.load_jobs(_production_jobs)
	else:
		_production_jobs = []
		production_panel.load_jobs([])

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
	return EARTH_NATURAL_K + offworld_k

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
		var r: float = POP_GROWTH_PER_YEAR / 365.25
		var decay: float = exp(-r * delta_days)
		new_pop = k / (1.0 + (k / pop - 1.0) * decay)
	new_pop = maxf(MIN_POPULATION, new_pop)
	if not is_equal_approx(new_pop, pop):
		stats["current_population"] = new_pop
		_mark_prod_dirty()   # population feeds the compute rate

func _refresh_stats() -> void:
	stats["year"]             = year
	stats["compute_rate"]     = _get_compute_rate()
	stats["science"]          = ResearchTree.resources.get("science",  0.0)
	stats["minerals"]         = ResearchTree.resources.get("minerals", 0.0)
	stats["energy"]           = ResearchTree.resources.get("energy",   0.0)
	stats["colony_count"]     = colonized_planets.size()

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
			"Compute: %s  |  Science: %s (+%s)  |  Matter: %s / %s (+%s)  |  Energy: %s / %s (+%s)" % [
				Units.format_si_verbose(compute_rate, "FLOP/s"),
				Units.format_si_verbose(ResearchTree.resources.get("science",  0.0), "FLOP"),
				Units.format_si_verbose(prod.get("science",  0.0), "FLOP/s"),
				Units.format_si_verbose(ResearchTree.resources.get("minerals", 0.0), "Grams"),
				Units.format_si_verbose(min_cap, "Grams"),
				Units.format_si_verbose(prod.get("minerals", 0.0), "Grams/s"),
				Units.format_si_verbose(ResearchTree.resources.get("energy",   0.0), "Joules"),
				Units.format_si_verbose(en_cap, "Joules"),
				Units.format_si_verbose(prod.get("energy",   0.0), "Watts"),
			]
		)

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
