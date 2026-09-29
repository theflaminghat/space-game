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

### Time and speed

`SolarSystem.seconds_per_day` is the one dial. `TIMESCALE_BASE` (0.25 s per game-day) never
changes; the player picks a multiplier from `Game.SPEED_TIERS`, ten rungs from 1× to 10⁹×, each
unlocked by reaching a year. Below `FAST_THRESHOLD` the game stops simulating days at all.

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

**The Sun is a build site**, not a world: `_is_body_buildable("sun")` is true once
`space_power_infrastructure` is researched. Its orbital lanes hold the swarm's support structures
and everything in §5.

**Textures** are SVG, rasterised at import to 2048×1024. `planet_polar_blur.gdshader` computes
each pixel's map coordinates from its direction rather than the mesh's UVs — which is what stops
the pole of a sphere mesh smearing — and softens texel crowding near the poles.
`body_texture_hires.gd` re-rasterises the *selected* body at 4096×2048 on a worker thread.

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
