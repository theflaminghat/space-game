# Don't Go Extinct — architecture

A civilisation simulation in Godot 4.7, played from 1945 to the heat death of the universe. This
document is for someone changing the code: what the parts are, where the rules live, which
invariants must not be broken, and how to test a change.

Everything here was read off the code, and the numbers are the constants the game actually runs
on. Where a number is quoted, the file that owns it is named — trust that file, not this page, if
they ever disagree.

---

## 1. Shape of the project

Three scenes, no scene inheritance: `start_menu.tscn` → `game_setup.tscn` → `node_3d.tscn`. The
last one is the game; everything else is a menu.

**Autoloads** (`project.godot`):

| Autoload | Holds |
|---|---|
| `ResearchTree` | The tech tree's live state, and the global resource pools (`resources`) |
| `SolarSystem` | The world clock, pause flags, and the star's own state |
| `GameSession` | Choices made on the setup screen, and the save path to load |

**`Game.gd` is the simulation.** 7,700 lines hanging off the root of `node_3d.tscn`, holding the
economy, population, launches, aliens, catastrophes, save/load and most of the UI plumbing. It is
the biggest thing in the repo by a factor of two and the first place to look for anything.

Everything else falls into four groups:

- **Data modules** — static `class_name` tables with no state: `buildings.gd`, `recipes.gd`,
  `planet_data.gd`, `compound_data.gd`, `missions.gd`, `ResearchTreeData.gd`, `politics_data.gd`,
  `doctrine.gd`, `unlocks.gd`, `trade_data.gd`, `star_model.gd`, `polities.gd`, `star_chunks.gd`,
  `wiki_data.gd`.
- **Scene scripts** — `planet.gd`, `asteroid_belt.gd`, `satellite.gd`, `camera_pivot.gd`,
  `init_planets.gd`, `body_picker.gd`.
- **Panels** — one script per screen: `BuildPanel`, `LaunchPanel`, `StarMapPanel`,
  `ProductionPanel`, `AutomationPanel`, `PlanetInfoPage`, `InventoryPage`, `ExtractionPage`,
  and the rest.
- **Support** — `units.gd` (SI formatting), `panel_background.gd`, `sidebar_control.gd`.

---

## 2. The simulation loop

`Game._process(delta)` is the whole clock. Read it before changing anything time-related.

```
_process(delta)
├── real-time work (autosave, event cards, realtime clock)
├── if SolarSystem.paused or ui_paused or game_over:  return   ← everything below stops
├── time_accum += delta
├── if seconds_per_day >= FAST_THRESHOLD (5e-4):
│     while time_accum >= spd:  advance_day()        ← DAY MODE
│   else:
│     year += whole years;  _on_years_advanced_fast() ← FAST MODE
├── per-frame simulation on delta_days = delta / spd
│     fuel, star lifters, husbandry, thrust, production, construction,
│     automation, entropy, population, food, _update_hud()
└── throttled UI pass (UI_REFRESH_SEC = 0.25 s)
```

**The rule that matters: `advance_day()` only runs in day mode.** Anything put there is invisible
in fast mode, which is most of a long run. Two bugs of exactly that shape have already been found
and fixed (§7). UI belongs in `_update_hud()` or the throttled pass; simulation belongs in the
`delta_days` block, which runs in both modes.

Anything that must happen in both modes needs a counterpart in `_on_years_advanced_fast()` — the
timeline year, the statistics snapshots and `_process_launch_arrivals()` each have one. Fast mode
begins at the 1000× rung, which unlocks in 2100, so this is not an edge case.

### Repeatable rolls

Anything the player could reload a save to re-roll is decided by `Game._roll()` and its siblings
(`_roll_range`, `_roll_int`, `_roll_pick`), not by the global RNG.

A roll is a pure function of **(galaxy_seed, a tag naming the decision, a salt naming the
occasion)**. It is deliberately *not* a position in a random stream: a stream diverges the moment
the player does anything that draws a different number of values from it, so saving a stream
position would still hand them a different plague on the second attempt. Derived this way, the
year 2180 pandemic roll is the same number however the player reached 2180 and however many times
they load that save — and nothing has to be saved to make that true.

- Salt with the **year** for something that happens at a time (a plague, a raid, a detection).
- Salt with a **name** for something that is a property of a thing (a world's split date, a
  civilisation's founding epoch), which then never changes whenever it is first asked for.
- Two decisions on the same occasion need different **tags**, or they are perfectly correlated —
  whether the plague arrives and how hard it bites are separate rolls, not one number read twice.
- Inside a loop, salt with the iteration index, and keep salt spaces apart (`_i * 1000` for one
  pick, `_i * 1000 + _s + 1` for a sample loop) so iteration 1 does not reuse iteration 0's value.

The **odds** still move with everything the player does — bioengineering and AI raise pandemic
risk, colonies blunt it, military spending and reactor fleets raise the nuclear risk. Only the
coin is fixed, so mitigation works and scumming does not.

Left random on purpose: `galaxy_seed` itself, which has to be unpredictable, and cosmetic
randomness (ring colours, moon phases, rubble placement), where re-rolling costs nothing.
Everything under §6 already had its own seeded generator keyed on `galaxy_seed`.

### Forecasting

Compute buys **foresight**: `Game.forecast_horizon_years()` is how many years ahead the
civilisation can say what is coming, and `forecast_events()` is what it sees. Gated on
`predictive_modeling`; shown as dimmed red cards ahead of the present marker on the timeline.

**The player divides the compute.** `ComputePanel` (sidebar, "compute") sets
`compute_forecast_share`; the horizon reads that share, and science reads
`research_compute_share()` — the same FLOP cannot do both, so seeing further means researching
slower. The share is inert until `predictive_modeling` is known, so it can never tax science in
exchange for nothing, and it is capped at `FORECAST_MAX_SHARE` (90%) so research never stops
entirely. It is saved. Without this the forecast was free and automatic: a readout of total
compute with no decision attached.

It is honest only because the catastrophe schedule is deterministic (see "Repeatable rolls").
Every scheduled year, target and severity is a pure function of (galaxy_seed, tag, year), so a
forecast is the same arithmetic the year itself will do, run early. Before the rolls were made
repeatable this could not have been built honestly at all — the answer did not exist yet.

**Cost goes as the square of the horizon**, so horizon goes as the square root of compute.
Chaos is the justification: prediction error grows exponentially, and past the system's
Lyapunov time (`FORECAST_LYAPUNOV_YEARS`, 5 Myr) no amount of computing helps — which is where
the hard cap comes from rather than from a balance decision.

The exponent is **2** and not something steeper because of the range it must span. Compute runs
from ~10²⁶ FLOP/s at the opening to perhaps 10³¹ once the galaxy is settled. Cost *exponential*
in the horizon would make horizon linear in log(compute), which across five orders of magnitude
arrives either almost complete at the start or not until the very end; squared cost keeps it
growing the whole way.

Asteroids are reported as **certain** — schedule and consequences are settled arithmetic.
Plagues and wars are not: their years are settled but whether they fire is a roll against odds
that move with what the player does, so they are reported at today's odds and flagged. A forecast
that showed them as fate would be telling the player their choices do not matter.

`pandemic_probability()` and `nuclear_probability()` exist so the check and the forecast read one
formula; a forecast with its own copy would start lying the first time the real one was tuned.
`nuclear_probability()` deliberately does not ratchet `_arms_strain` — asking what the odds are
must not make them worse.

### Compute

`compute = population × COMPUTE_PER_INDIVIDUAL (1e17 FLOP/s) + buildings`, so even a modest world
thinks at ~10²⁶ FLOP/s. The compute buildings were authored at the scale of one server room — a
Data Center at 20 FLOP/s — which put them twenty-four orders of magnitude under the people using
them: ten thousand AI Research Hubs moved civilisation compute by 0.0000000007%. They are now
authored at the scale everything else is, one entry being the planetary network rather than the
building, anchored so a determined build-out roughly *matches* the population's own thinking
(~47% of the total at the sandbox's build) rather than dwarfing it.

### Time and speed

`SolarSystem.seconds_per_day` is the one dial. `SolarSystem.TIMESCALE_BASE` (0.25 s per game-day)
never changes; the player picks a multiplier from `Game.SPEED_TIERS`, ten rungs from 1× to 10⁹×,
each unlocked by reaching a year. Below `FAST_THRESHOLD` the game stops simulating days at all.

**Above `ORBIT_BLUR_ABOVE_MULT` (100×) the solar system stops being drawn body by body.** A planet
crosses its whole year between two frames at that speed, so the dot the player sees sits at an
essentially random point on its orbit. Past the threshold the bodies hide and each draws a
translucent ring (`Planet._blur_torus`) — the honest picture of something moving too fast to
resolve. Pausing, or slowing down, brings them straight back.

Three things make this reliable, and all three were bugs first:

- `seconds_per_day` has a setter that re-derives `solar_system_active`, so the state cannot drift
  from the speed however the speed was set — including code that assigns it directly rather than
  going through the speed ladder.
- `paused` and `ui_paused` have setters that emit `paused_changed`. Thirteen places wrote them
  directly and only five emitted, which left bodies holding whatever visibility they had when the
  last signal happened to fire.
- The cutoff was a **year** (`ORBIT_FREEZE_YEAR`, 1 000 000), from when the timescale was a fixed
  super-linear function of the date so "late" and "fast" were the same thing. It was also one-way:
  once a run passed the year, the bodies never came back however far it slowed down.

---

## 3. Economy

**Buildings** (`buildings.gd`) are authored as fleet-scale entries, then divided by `units` and
lifted by `Units.MASS_SCALE` into single structures, then tiered (I/II/III) by `LEVEL_*`. The
expanded catalogue comes from `BuildingData.all()`; `Game._bdef_cache` indexes it by name.

Keys a building may carry: `production`, `consumption` (fuel drawn from the world's inventory),
`storage`, `mc_capacity`, `radiator_capacity`, `beam_send`/`beam_recv`, `habitat`, `detection`,
plus the stellar-engineering keys (`star_lift_power`, `shade_fraction`, `husbandry_power`,
`mirror_coverage`). A new scalar output must be added to `LEVEL_SCALAR_KEYS` or its tiers will
cost more and do the same.

**Research gates building availability** through `unlocks.gd`
(`BUILDING_UNLOCK_REQUIREMENTS`), not through the building entry.

**Three pools and one inventory.** `ResearchTree.resources` holds the global `energy`,
`minerals`, `science`; `Game.compound_inventory[world]` holds per-world compounds. `_get_stockpile`
reads either, which is why a building cost can mix `energy` with `Steel`.

**Production** is recomputed only when dirty (`_mark_prod_dirty()` →
`_recompute_production_cache()`), then combined per frame in `_combine_production()`. Note the
ordering trap inside the recompute: it clears `_prod_dirty` at the END, and anything called
before that which asks for a building count will recurse.

Construction is work over time: `_building_work()` against the world's Manufacturing Capacity,
which is `BASE_MC` plus factories (and, off-world, an Orbital Construction Station).

### Saves

`save_schema.gd` holds one row per key in the save file, and both directions are generated from
it: `SaveSchema.encode()` on the way out, `decode()` on the way back. A field that is only a value
is one line in `FIELDS` and needs no code at either end.

Fields that need more than a value copied — a rename migration, a fallback for older saves, a UI
rebuild — are still written by hand in `Game.gd`, but they are **listed in the table anyway** with
`custom = true`, so the table stays a complete inventory of the file. `tests/audit_schema.gd`
holds `Game.gd` to it in both directions, and round-trips every plain field through a real save.

Forward compatibility is per-field defaults: a file written before a field existed simply has no
entry and gets the default. `tests/fixtures/` holds four genuine saves from earlier in development
(29 to 64 keys against today's 72, none with a version stamp) and `audit_oldsaves.gd` loads and
runs each one. `save_version` is stamped on every new save and nothing reads it yet — it exists so
that the day a field has to *change* meaning rather than merely appear, there is something to
branch on, which defaults alone can never express.

---

## 4. The solar system

`planet.gd` draws and moves each body: Kepler orbits, cosmetic moons, rings, orbit lines, and
`INFRA_LANES` — one ring per orbital structure type, with the instance count polled from the
roster. `asteroid_belt.gd` extends it. `init_planets.gd` draws the Dyson swarm.

**Everything in solar orbit sits inside Mercury's.** The lanes span 3.01 to 7.99 world units
against a solar surface at 2.35 and Mercury's **perihelion** at 8.58 — perihelion, not the 10.47
mean, because Mercury is eccentric enough (0.21) that a band sized to the mean would be swallowed
once a year. The Dyson swarm shares the band at 3.05–5.30.

Tightened that far, consecutive lanes are closer in radius than the structures are wide, so what
keeps them clear of one another is the angle between their orbital **planes**, stepped by the
golden angle (`INFRA_PLANE_ANGLE`) so no two consecutive lanes are alike. They were previously a
narrow random ±0.3 rad, which only worked because the lanes were a quarter of a unit apart. This
is the same trick the swarm uses to be a shell rather than a disk.

**The Sun is a build site**, not a world: `_is_body_buildable("sun")` is true once
`space_power_infrastructure` is researched. Its orbital lanes hold the swarm's support structures
and everything in §5.

**Textures** are SVG, rasterised at import to 4096×2048 and VRAM-compressed to BPTC (BC7).
`planet_polar_blur.gdshader` computes each pixel's map coordinates from its direction rather than
the mesh's UVs — which is what stops the pole of a sphere mesh smearing — and softens texel
crowding near the poles.

All thirteen maps together cost **139 MB** of texture memory. They were previously 2048×1024 and
*uncompressed* (12 of 13 at `compress/mode=0`, i.e. RGBA8 at 4 bytes a pixel), which cost 129 MB —
so quadrupling the pixels cost 9 MB, because the compression more than paid for it. BC7 error on
this content is under 1/255 mean even on the gas giants, where block artefacts would show worst.

There used to be a runtime LOD swap (`body_texture_hires.gd`) that re-rasterised the *selected*
body at twice its imported size on a worker thread, to avoid paying for every body at 2× at once.
With the imports at 4096 that swap was producing 8192×4096 **uncompressed** textures — 171 MB per
click, more than every map in the game costs together — so it was removed. If a per-body LOD is
ever wanted again, it has to compress what it produces.

---

## 5. Stellar engineering

`star_model.gd` is pure physics; `SolarSystem` holds the state; `Game` runs it per day.

The central idea: **the Sun is a function of its own state, not of the calendar.** A pristine
1 M☉ star reproduces the original fixed curve exactly (verified to 5 × 10⁻¹¹), so existing runs
are unaffected.

| Lever | Structure | Cost | Effect |
|---|---|---|---|
| Lifting | Star Lifter | 1.908 × 10¹¹ J/kg (binding energy), 60% efficient | Mass off the star; dims it, lengthens its life, banks hydrogen |
| Shading | Sunshade Constellation | Build cost only | Intercepts light; offsets warming, cuts solar output |
| Husbandry | Core Mixing Array | 1.145 × 10³¹ J per year of life | Winds the star's clock back; no mass or light lost |
| Propulsion | Shkadov Mirror | Build cost only | Thrust = 0.16% of L/c; moves Sol, and every distance with it |

**Two clocks.** `StarModel.stellar_age(year, mass, offset)` converts calendar year to the star's
own age; `year_of_age()` inverts it. Lifting slows the star's clock (lifetime ∝ M⁻²·⁵); husbandry
subtracts from it directly.

**Fate follows mass.** Above 0.5 M☉ the authored track runs to its end. Below it there is no
helium ignition: no giant branch, no engulfment, no nebula — `sun_red_giant_year()` and
`sun_nebula_year()` return `INF` and the readouts say "never". Below 0.08 M☉ fusion stops.

**Dimming has a price.** `_climate_capacity_factor()` penalises the *net* of CO₂ warming and the
light Earth is not receiving, so lifting a quarter of the Sun is a climate catastrophe in the cold
direction — and the player's own emissions become a counterweight.

---

## 6. Interstellar

### The sky

Three sources, assembled by `StarMapPanel.all_stars()`:

1. `STARS` — 60 real catalogued stars. Never range-filtered: bright ones are visible from far
   further than the telescopes reach.
2. The home-cell field — 6,000 procedural stars inside Sol's Voronoi cell (radius ≈ 460 ly),
   generated once. **Untouched by the chunk generator**: a run in progress has colonies and
   contacts there.
3. `star_chunks.gd` — everything outside that cell, generated on demand.

**Chunked generation** cuts space into fixed 100 ly cubes in *absolute* coordinates; a cube's
contents are a pure function of (galaxy seed, cube index). A cube therefore generates identically
whenever it is reached, from any direction, however many times. Nothing is stored and nothing is
saved.

The canon it obeys, all measured against the original field:

| Invariant | Value | Owner |
|---|---|---|
| True star density | `galactic_density(p) × 0.065` per ly³ | `StarMapPanel` |
| Rendered sampling | 1 in 250 (0.4%) | `StarChunks.SAMPLE` |
| Standing : future stars | 6000 : 4000, births log-distributed 10⁶–10¹⁴ | `StarMapPanel` |
| Civilisations | 1 per 6.8 × 10⁷ ly³ | `StarChunks.CIV_PER_LY3` |

The map draws at most `MAX_RESOLVED` (12,000) stars, and the *generation* radius solves that
budget for a distance — a crowded region is generated less far, an empty one out to full reach.
Region statistics never read this list; they use the true density.

### Who lives there

`polities.gd` separates two things the game previously conflated:

- A **race** is a species: one name, one 4,000 ly territory (`RACE_CELL_LY`).
- A **faction** is a polity: a government over an 800 ly volume (`FACTION_CELL_LY`), belonging to
  a race, with a temperament. One species commonly has many, and they disagree.

Both derive from position and seed. Names are built from syllables and must match temperament —
`name_matches_alignment()` exists so that invariant can be asserted.

In `Game`: `star_factions[star]` keeps the alignment string every older system reads;
`star_polity[star]` records the holding government; `_factions` / `_races` are the registries, and
they are saved.

**Alien behaviour** (`_process_aliens`, on the year clock): signatures are detected when their
light has had time to arrive; `_spread_aliens` colonises empty stars (a colony joins its parent's
polity, and a government past `POLITY_SPLIT_SYSTEMS` = 40 spawns a breakaway state instead);
`_alien_wars` lets aggressive polities take systems from each other within
`ALIEN_WAR_REACH_LY`; `_launch_alien_attacks` fires relativistic weapons at human worlds.

Expansion and war both sample candidates (`ALIEN_SPREAD_SAMPLE` = 32) rather than scanning
everything, and cap work per call. Without that, a filled galaxy costs seconds per tick.

### Salvos

Firing N missiles appends N records to `interstellar_attacks` — they are N real rounds, each
resolving on arrival. For *drawing*, `refresh_star_map` groups them by what defines a salvo
(target, kind, launch year, arrival year) into one display entry with a `count`, and the map draws
one track labelled `xN`. Ungrouped, every round drew at exactly the same place, so ten missiles
were ten identical strokes on identical pixels — visible only as overdraw, and ten times the work
for one line. `incoming_attacks` is grouped the same way.

Labels step clear of one another (`_salvo_label_pos`, reset each `_draw`): salvos sent a year
apart on a century-long flight sit almost on top of each other, and their counts ran together into
one unreadable number.

`_check_interstellar_attacks` groups arrivals the same way — by target and weapon — applies the
effect once and announces once with the count. Resolving round by round told the wrong story: the
first arrival erased the system, so every round after it reported striking *empty space*. Ten
missiles read as one hit and nine misses, and since the popup queue keeps the most recent few
(`_process` trims to 5), the cards the player actually saw were the misses. Whether anything was
there is now answered for a target **before** anything is erased, so every weapon group arriving
that year tells the same truth. `incoming_attacks` already accumulated into one event and was left
alone.

### Events that are places

`Game._announce()` takes an optional `extra` dictionary merged into the notification. A `"star"`
key makes the timeline card clickable: `TimelineCanvas` wires the card's `gui_input`, the click
travels up through `TimelinePanel.star_focus_requested` to `Game._on_timeline_star_focus`, which
opens the star map via `SidebarControl.show_star_map()` (an outright open, not the sidebar
button's toggle) and calls `StarMapPanel.focus_star()`.

`focus_star()` selects the object and brings it into view. The map is a Sol-centred log-radial
orrery with no pan, so that means setting `_zoom` to put the object's log radius at
`FOCUS_VIEW_FRAC` of the view radius, and turning `_yaw` so it sits out along screen-right rather
than behind Sol's glyph at the centre. Pitch is left alone — it is how the player has chosen to
look at the galactic plane.

Timeline cards are not saved, so this only applies to events raised in the current session.

### The autonomous swarm

Once `relativistic_navigation` and `self_replicating_industry` are researched, probes replicate on
their own: each arrival founds a colony, is added to `_vn_seeds`, and launches `VN_REPLICATE_COUNT`
more from where it landed. `_vn_resume()` revisits existing lineages round-robin so a branch that
hit the in-flight cap is not finished for good.

**Target choice is greedy, and deliberately left that way.** Each colony takes its own nearest
unclaimed star and marks it en route, first-come-first-served by queue position — so a colony
processed earlier can claim a star that a nearer one, not yet reached, would have been better
placed to take. Measured over a 2 800-colony swarm: median probe flies 58 ly to a star another
colony sits 26 ly from.

Handing the claim to the nearer colony was tried and reverted. Deferral only pays if the colony
deferred to actually goes, and here it usually does not — most "nearer" colonies are interior
lineages that will not come up for thousands of years, so the star waits while the deferring
lineage burns a slot in the time budget for nothing, and the flights that do happen get *longer*.
Colonies 2808 → 1307, p99 flight 183 → 321 ly; restricting deferral to colonies queued to act the
same tick recovered 118 of the 1501 lost. Fixing it properly needs global assignment — matching
stars to colonies rather than letting colonies grab — which is a different algorithm with a real
per-tick cost. `VN_HOP_LIMIT_LY` (250 ly) caps a single hop to an individual star as a guard rail;
it measured as neutral on colonies and frontier, and **clusters are exempt**, since a cluster is
the destination a swarm reaches precisely because nothing nearer is left.

**A colony surveys from where it is.** `_nearest_uncolonised()` searches the neighbourhood
generated around the colony (`VN_SURVEY_LY`, via `StarChunks.stars_near`) *as well as* the
Sol-resolved list. Searching only the latter — which is bounded by the player's telescopes and
trimmed to the nearest `MAX_RESOLVED` to **Sol** — meant a colony could only target stars visible
from Earth, so the swarm saturated the observation range and stopped: 434 ly against a 467 ly
range, held for fourteen thousand years. The two sources must not double-count the home cell,
which the procedural field owns, so generated stars inside it are skipped.

Beyond `DETAILED_RADIUS_LY` (2500 ly) arrivals stop becoming individual worlds and fold into
statistical regions instead, which then spread on their own.

**There is no cap on how many probes may be in flight.** There was — `VN_MAX_INFLIGHT`, twelve —
and it was the whole throughput of the swarm however large it grew, so expansion ran flat (in
fact decaying, as flights lengthened) at a few hundred stars per thousand years instead of
compounding; and a colony that happened to arrive while those twelve were out launched nothing at
all and was never revisited. After fifteen thousand years, 369 colonies had never seeded anything.

What is bounded now is *work*, not population: `_vn_pending` is a queue of lineages waiting to
replicate, worked through under a **time** budget (`VN_LAUNCH_MS`). A lineage that does not get
its turn keeps it. The budget is time rather than a count because a replication costs anywhere
from under a millisecond (frontier colony, empty sky) to fifteen (deep inside the bubble, where
the search must look everywhere to conclude there is nowhere to go).

Four things make it affordable at tens of thousands of colonies, each of which was a bug first:

- The queue is worked **before** the arrival loop's early return. Working it only on the way out
  meant a swarm with nothing currently aloft never launched again — no arrival to trigger a
  launch, no launch to produce an arrival. A permanent dead stop.
- A lineage that finds nowhere to go is **retired** from `_vn_seeds`. Colonisation never
  reverses, so it will never have anywhere to go again; without this, the settled interior was
  re-searched forever.
- `_nearest_uncolonised` walks a spatial grid (`_star_grid`) rather than the whole resolved list,
  takes the caller's en-route set rather than rebuilding it per call, and uses the maintained
  `_col_star_set` rather than rebuilding `taken` from `colonized_stars` — that last one alone was
  a quarter of a million dictionary inserts per tick at sixteen thousand colonies.
- The local chunk survey is skipped when the colony is inside the home cell, where the procedural
  field already owns the volume and every generated star would be rejected anyway.

### Clusters are not stars

A cluster is a Voronoi territory of the home tile holding thousands of stars, too far to resolve
one by one. It is settled a share at a time (`cluster_colonized`) and **inhabited** a share at a
time (`cluster_aliens`) — the share seeded from the canon civilisation density over the cluster's
own volume, scaled by how crowded the setup screen asked the galaxy to be (`alien_density_scale()`
— "Alone" puts nobody in any cluster). `Game.is_cluster()` tells one from a star.

**No diplomacy with a volume of space.** Trade and alliance are refused outright: there is no
counterparty, only many. (They were already unavailable because a cluster never enters `_intel`;
what would have enabled them is populating clusters with aliens, so the refusal is now explicit
and carries a tooltip saying why.)

Weapons work, because they hit a *share* rather than a system — `_resolve_cluster_strike()`:

- **Relativistic missiles** each pick systems at random out of thousands. Most of a cluster is
  empty rock, so most salvos find nobody, and the card says so. This is the honest answer at
  cluster scale rather than a softened one: missiles are a system weapon.
- **Berserkers** spread rather than strike, so what they take scales with how much there is to
  eat (`cluster_alien_share` + `cluster_colonized`), a roll, and the number sent — with
  diminishing returns, so more always takes more but never all: 1 seed ≈ 2%, 20 ≈ 35%, 100 ≈ 83%.
  They are indiscriminate: the player's own share of that cluster burns with the rest.
- **Lasers** are one beam at one point, and say so.

### Reaching it

`missions.gd` defines mission types and, crucially, **what may fly where**: each carries a
`targets` rule (`any` / `world` / `surface` / `star`), and `MissionData.allows_target()` /
`allows_arrival()` are the single source of truth. Both panels grey out what those functions
refuse, and `Game._on_launch_requested` enforces them again because automation and the console
call straight in.

Flights are drawn by `satellite.gd`. A craft carrying a structure to the Sun flies to the berth
its cargo will occupy in the orbital lane (`Planet.infra_slot_world_pos`) and vanishes there —
aiming at the body's centre would send it through the star.

---

## 7. Invariants worth protecting

These are not style preferences; each was a bug.

1. **Nothing that must happen over time belongs *only* in `advance_day()`.** It never runs in
   fast mode, which starts at 1000x — year 2100, well inside a normal run. UI refreshes go in
   `_update_hud()` or the throttled pass; anything on the year clock needs a call in
   `_on_years_advanced_fast()` as well. Three bugs have had exactly this shape: two hidden panels
   and, until now, every in-system flight, which stayed aloft forever above 100x.
2. **Roster-derived state must be rebuilt after a load**, before the first unpaused frame — a load
   leaves the game paused and `_process` returns early while paused. Related: anything reading the
   roster during a load must run *after* the roster is restored. `_sync_star_shades()` sat two
   hundred lines too early and synced against whatever was in memory from before the load.
3. **A polity has one temperament.** Register it once; further stars join it. Regenerating per
   star produced a "Compact" that was hostile at one of its own systems.
   And a star that has an alignment has a government: the loader used to seed all four faction
   maps for a legacy save and blank three of them on the next lines, leaving neighbours armed or
   peaceful with no polity and no species behind them.
4. **The setup screen's counts are civilisations, not systems.** One government may hold many
   stars.
5. **A pristine Sun must reproduce the original curve.** `regression.gd` asserts this against
   values captured before stellar engineering existed.
6. **The chunk cache may not be keyed on the year.** The year changes what is *visible*, not what
   exists; keying on it threw the whole cache away every tick.
7. **Generated names must not mislead.** A peaceful-sounding polity that shoots is a lie the
   player cannot see through.
8. **A decision the player could reload to re-roll goes through `_roll()`.** The global RNG is
   unseeded and its state is not saved, so before this, reloading a save before a plague re-rolled
   it — worth 300 million lives on a single asteroid strike in testing. See "Repeatable rolls"
   in §2.

---

## 8. Testing

The suite lives in `tests/`, with its own README. There is no framework: each test is a
`SceneTree` script and the harness is Godot itself.

```bash
tests/run.sh              # everything
tests/run.sh polities     # by name
```

A test loads `node_3d.tscn`, awaits some frames, pokes `Game` directly and prints `FAILS: n`.
Six traps, all of which have cost time:

- **`class_name` types are unreachable** from a `--script` runner when the class depends on an
  autoload. Use `load("res://x.gd")` or reach the node and call through it.
- **A script error aborts `_run()` before `quit()`**, so the run hangs until the timeout instead
  of failing. A test that "times out" is usually a typo'd method name.
- **The harness runs at thousands of frames a second**, so "await 150 frames" may be 0.025 s of
  simulated delta — nowhere near a 0.25 s UI throttle. Drive throttles directly.
- **Announcements are drained** into the timeline within a frame or two; check
  `_pending_event_notifications` immediately, not after awaiting.
- **Pin the RNG before the scene loads.** `Game._ready` does `galaxy_seed = randi()`, so anything
  touching generated stars or polities is a coin toss without `seed(...)` first.
- **An event card pauses the game and the tree.** A loop driving the simulation must clear
  `SolarSystem.paused`, `ui_paused` and `get_tree().paused` every iteration. And a craft is moved
  by the satellite node's own `_process`, so the tree has to really process frames — calling
  `Game._process()` by hand advances the simulation but never the craft.

Godot's string formatting has no `%e` or `%g`. Use `%f`, `str()` or `Units.format_si`.

New `class_name` scripts are not visible until the project is rescanned:
`godot --headless --path . --import`.
