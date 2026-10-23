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

**The player divides the compute, one budget at a time.** `ComputePanel` (sidebar, "compute")
writes `compute_alloc`: `track -> {human, ai}`. There is one track per catastrophe the forecast
models (`FORECAST_TRACKS` — asteroid, pandemic, nuclear) plus `science`, because looking for
rocks and looking for plagues are not the same calculation and a civilisation can be excellent
at one and blind to the other.

The two pools (`COMPUTE_POOLS`) are the population's own thinking and everything built for it —
`_cached_compute_human` and `_cached_compute_ai`, split in `_combine_production()`. They are
budgeted separately because they are not substitutable: one grows with how many people there
are, the other with what has been built, so the machines can be pointed at the future while the
people stay on the tree.

The sliders are **weights, not shares**: raising one does not require hunting down another to
pay for it, and `compute_shares()` divides each pool in proportion to what is pointed at it. Two
rules sit on top — the forecast tracks get nothing before `predictive_modeling` is known (so a
budget can never tax science in exchange for nothing), and science keeps at least
`1 - FORECAST_MAX_SHARE` (10%) of every pool, so a civilisation cannot think itself into being
unable to build what the forecast warned it about. Both the allocation and the frontiers below
are saved, and an older save carrying only the single `compute_forecast_share` is spread across
the tracks by `_migrate_compute_alloc()`.

**Foresight is a stock, not a readout of the current budget.** `foresight_frontier[track]` is an
absolute YEAR, pushed outward by `_advance_foresight()` on the per-frame game-day clock (so it
runs in both time modes) and never retreating. What shrinks is the lead time, because the present
keeps walking towards it: `forecast_horizon_years(track)` is `frontier - year`, so a horizon held
steady costs a year's worth of compute every year and closes at a year per year once it stops
being paid for. Nothing has to take it away.

The rate is `d(frontier)/dt = FORESIGHT_K * c / h²`, with `FORESIGHT_K = REF_YEARS² / REF_FLOPS`
chosen so that holding a budget steady settles exactly where the old instantaneous formula put
it — `forecast_equilibrium_years()` is that resting point, and the panel shows it as what a
budget is working towards. Two guards: `FORESIGHT_MAX_RATE` (16 modelled years per year) stops
the h² denominator making the opening of a run free, which otherwise put any serious budget at
its resting horizon inside a fortnight; and a single step may approach the resting horizon but
never pass it, because a fast-mode slice millions of years wide would otherwise put every
frontier on the Lyapunov wall in one frame.

Each track's events are walked only as far as its own frontier, so an unfunded simulation
reports nothing at all.

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

### The cluster shell is streamed

Clusters used to be one hexagonal tile's worth, generated once, with nothing at all beyond the
tile wall. They are now generated **per tile**, deterministically from the galaxy seed and the
tile's own axial coordinates, and the loaded **patch** is Sol's tile plus the six bordering it.
The patch follows Sol: `Game` calls `StarMapPanel.set_cluster_origin(SolarSystem.sol_position())`
from `_run_star_thrust()`, and when the Shkadov thruster carries the star over a tile border the
three tiles that stop bordering are evicted and three new ones are generated. A tile regenerates
identically if it is ever entered again, so leaving and returning is free of consequence.

`tile_of()` / `tile_center()` / `tile_neighbours()` live in `StarMapPanel` and `Game` delegates
to them, so the cluster shell and the statistical region grid cannot drift out of alignment —
the test checks them against `Game._region_id()` across the grid.

**Two tiers of detail.** Only Sol's own cell and the cells bordering it are carved into exact
polyhedra; the rest of the patch is drawn as batched points. That is not cosmetic — carving the
whole patch measured **9.8 s per border crossing**, against 129 ms for the focus. The bordering
set is free to compute: `_carve_cell` already reports which rivals actually bound a cell, and
those *are* the Voronoi neighbours.

**The hot path is one distance test.** `set_cluster_origin()` runs on every tick the thruster
moves. Inside `_focus_safe_r` — half the distance from Sol's seed to its nearest rival — nothing
can have changed, so it returns immediately. The full check is 16 800 distances plus a re-carve
and measured 121 ms; it would otherwise have been paid every frame.

**Cluster names are tile-addressed** (`"Cluster -8:4-042"`). A bare running index means nothing
once more than one tile exists, and the name is what saves bind to. The old `"Cluster C-042"`
series cannot be generated any more and is dropped on load by `Game._drop_unknown_clusters()` —
matched on that exact prefix, not on "whatever is not currently loaded", because a cluster in an
unloaded tile is still real and the save round-trip audits put their own keys in those
dictionaries.

**Three things that cost real time and are easy to reintroduce:**

- `in_sol_cell()` is called once per star by the generator. It must test only the half-spaces
  that *bound* the home cell (about 15), not every seed in the patch. Testing 6 000 stars
  against 16 800 seeds is 100 M operations and was most of a 22-second scene load.
- Nothing may generate before `set_galaxy_seed()`. Panels are built before `start_new_game()`
  picks the seed, and whatever asked first built the entire patch against seed 0, which was then
  discarded and rebuilt — 14 tiles' work for a 7-tile patch.
- `Game`'s `_star_lookup` name index is keyed on `StarMapPanel.patch_version()` as well as the
  star count, because the patch changes without `all_stars()` changing at all.

**Tiles are generated in parallel.** `_generate_tile()` is a pure function of the tile and the
galaxy seed — its own `RandomNumberGenerator`, constants, and the galactic basis — so the tiles a
patch is missing go to `WorkerThreadPool` together. The basis is a lazy cache and is warmed on
the main thread first, which is the one piece of shared state a worker reads.
`verify_tile_threads` pins the whole claim: five cold parallel builds, one of them with the basis
cache deliberately emptied, each compared cluster-for-cluster **in order** against a serial build.
Order matters as much as content — the index into the patch is identity for the focus set and the
selection, and names are what saves bind to.

**The sampler was jamming.** Seeds are placed by random sequential adsorption with a minimum
separation of `CLUSTER_SEP_FRAC` × the mean spacing, and at 0.86 that sat near the jamming limit:
the last tenth of the seeds cost 58 % of all the darts. Stepping back to 0.80 is four times
cheaper for a nearest-neighbour spread of 0.070 against 0.055 — both far below the 0.52 of seeds
thrown with no separation at all, so the cells stay as even as `mean_vol` needs. The table in the
constant's own comment has the measured curve.

Together, a cold seven-tile patch went from **875 ms to 186 ms** (144 ms of generation plus the
42 ms carve) and scene load from 2 659 ms to 1 989 ms. Deferring the six bordering tiles to a
later frame was the original plan and is no longer worth its ordering risk: clusters are now a
tenth of the load, and the home cell that `in_sol_cell()` filters the catalogue against would
have had to be re-derived as tiles arrived.

`CLUSTER_COUNT` (seeds per tile) is the knob for cluster size, and its cost is scene load, since
the patch is seven tiles rather than one — now a far cheaper knob to turn than the 1200 → 3.5 s,
1600 → 4.3 s, 2400 → 5.6 s it measured before the two changes above.

### What the star map draws, and when

`StarMapPanel._draw()` is the most expensive frame in the game: about 8 400 clusters and 6 000
stars, and it redraws **continuously while the simulation runs**, because `Game` pushes mission
progress and the energy readout every simulated day with the map open and each push queues a
redraw. Three things keep it affordable, and all three are easy to undo by accident.

**Visibility is decided before any transform.** `_rel()` rotates into the galactic basis and
remaps onto the log radial scale; `_detail_alpha()` only ever wanted the *length* of that
result, which is `_display_radius()` of the plain distance. Testing first and transforming after
is worth a third of a rebuild at a deep zoom, where nothing in the shell is visible at all.

**Budgets are distance CUTS, not orderings.** `_refresh_lod_cuts()` keeps the K-th nearest
distance for the star-body budget and the cluster-glyph budget; `rank >= BUDGET` is a question
about a threshold, and the K-th nearest distance answers it without a sort. It is guarded by a
tolerance of 1 % of the cut, not by equality on the reference point — the reference is locked to
Sol, and under a Shkadov thruster Sol moves every frame.

**The cluster sort is cached per VIEW.** Which clusters are glyphs and where the rest land in the
batched point cloud is a function of the frame origin, the zoom, the two view angles and the
panel size — nothing the simulation touches. `_cl_pts` / `_cl_pt_col` / `_cl_glyph_idx` are held
across frames and rebuilt only when one of those moves, behind a `_cluster_pt_tol()` tolerance
derived from half a pixel of positional error (so it tightens as the player zooms in). Measured
at 1600×900 with the patch at 8 401 clusters, over frames that each force a redraw:

| Zoom | Sorted every frame | Cached |
|---|---|---|
| 1 | 52.2 ms | 26.9 ms |
| 3 | 56.8 ms | 29.3 ms |
| 8 | 46.7 ms | 25.0 ms |
| 40 | 16.3 ms | 9.6 ms |

Two things the cache depends on and would silently break without:

- `_focus_version` is bumped by `_build_cluster_cells()`, **not** derived from
  `_patch_version` — crossing a cluster border inside one tile recarves the focus set without
  changing the patch, and the focus set is exactly what decides who gets a glyph.
- Colonisation reaches the cache as `_colonized.size()`. The colour of a settled cluster is baked
  into the point cloud, and a count is the only O(1) way to notice it changed. The glyph tier
  re-derives its colours every frame, so the neighbourhood the player is actually reading is
  never stale; a colony lost and another gained between two frames would leave one 1-pixel point
  the wrong colour until the view next moves.

### The production cache

`_recompute_production_cache()` turns the building rosters into the raw sums the per-frame
`_combine_production()` reads. It is the most-called expensive function in the game: a build, a
demolish, a switch, a research unlock or any panel read forces it, several times a second under
automation. Two things keep it off the critical path, and one of them was 81 % of it.

**Everything is worked per building KIND, never per standing structure.** A world holds thousands
of structures and nine kinds of them, so the roster is tallied once and every definition lookup
happens once per kind. The main sweep already did this; `_compute_storage_caps()` did not, and it
walks the same rosters — two dictionary lookups, a default-dictionary allocation and a loop setup
per building, to answer a question about its type. Fixing that alone took the rebuild from
**11.6 ms to 2.8 ms** at 13 327 buildings, and 46.7 ms to 10.3 ms at 53 308. It now takes the
sweep's own tally as an argument rather than reading `_cached_planet_counts`, because the rebuild
calls it while still marked dirty.

**Each world's contribution is cached** (`_prod_planet`, built by `_planet_contribution()`). A
build moves one world and leaves the sum over all the others untouched, so `_mark_prod_dirty()`
takes the world that changed. At a fixed 53 308 buildings, one world dirty:

| Worlds | One world dirty | Every world |
|---|---|---|
| 1 | 10.7 ms | 9.9 ms |
| 4 | 3.4 ms | 10.4 ms |
| 12 | 1.1 ms | 10.5 ms |
| 20 | 0.8 ms | 11.1 ms |

One world is no gain, by construction — the world that moved *is* the whole roster. The saving
is the world count, which is what "re-sum only the one that moved" means.

**An unnamed planet means every world, and that is always correct.** Passing a name is an
optimisation; the rosters are mutated in sixteen places and a scheme where forgetting one gave a
wrong number rather than a slower rebuild would not be worth having. Two backstops enforce that:

- **Roster length.** A tally's counts must add up to the length of the list they came from — an
  O(kinds) check. A mutation that never announced itself is caught on the next rebuild.
- **The solar factor** (luminosity × insolation) is stored with each record and compared against
  the live one to `PROD_SOLAR_TOL`. Collectors are rated against the light that reaches them, and
  that moves for reasons that are not any world's roster: the Sun brightens on its own, and star
  shades dim every world at once while being a roster change on `"sun"` alone. A century of
  brightening is inside the tolerance and costs nothing; 200 Myr, or a shade, re-rates everything.

`_cached_planet_stats` and `_cached_planet_counts` publish the cache's **own** dictionaries, not
copies. Every reader is read-only today and `verify_prod_cache` says so, so a future writer finds
out there rather than through a slowly drifting figure.

### Microchip grades

Three fabrication processes, each gated deeper in the tree, each a step closer to what
thermodynamics allows a computer to be:

| Grade | Research | Physics |
|---|---|---|
| 1 | `microprocessors` | photolithographic CMOS — a logic transition dumps its charge to ground, ~10⁵ kT wasted per operation |
| 2 | `adiabatic_logic` | charge recovered rather than dumped, approaching the Landauer bound of *kT* ln 2 — the floor for **erasing** one bit |
| 3 | `reversible_computing` | nothing is erased, so that bound does not apply; dissipation is set by how hard the machine is driven and what error correction costs |

**Grade 3 is deliberately not a physical limit**, because a fabricated chip cannot reach one.
Margolus–Levitin bounds operations per joule-second and Bremermann bounds a mass of matter, both
many orders beyond any lithographic device, and reversible logic buys its low dissipation by
running slowly. Grade 3 is the last rung physics leaves for something still recognisably a chip.

`Game.chip_grade()` is the deepest process known — order of research does not matter, only
depth.

**Each grade is its own item**, fabricated by its own recipe: `Microchip`, `AdiabaticChip`,
`ReversibleChip` (`CompoundData`). The research alone buys nothing; reaching a rung costs a
production line.

`BuildingData.LEVEL_CHIP` is what makes them matter. `_scaled()` **substitutes** the chip in a
generated tier's cost, so a structure whose level-1 bill lists `Microchip` needs
`AdiabaticChip` at tier II and `ReversibleChip` at tier III — the bill keeps its shape, and the
tier simply cannot be built out of the previous generation's electronics. Buildings that never
needed chips (a concrete mine) are untouched at every tier.

So the efficiency a better process buys arrives as **the output multiplier of the tier it lets
you build**: an AI Research Hub III produces 3.5² the compute of a level-1 hub and cannot exist
without reversible chips, which makes reversible logic worth ~12× on that line.

There is deliberately **no global multiplier** from the grade on top of that. There was one
briefly, and once the chips became items gating the tiers it counted the same progression twice
— and worse, it paid out from the research alone, before a single better chip had been
fabricated, which is the opposite of the point.

No grade becomes dead data: the base chip is still what rockets, robots, satellites, missiles
and von Neumann probes are assembled from after reversible logic is in hand, so the first
fabrication line never stops being worth running.

### Repeatable research

Most nodes are one discovery. Some are a line of work that keeps paying, and carry a
`max_level` above 1 — set from `ResearchTreeData.LEVELS`, which is the whole cost of making
another line repeatable. Each pass costs `level_cost_growth` (default 2.0) times the one before
it and adds its boosts again, linearly, so the fifth pass of a five-level node costs sixteen
times the first for the same increment. That curve, not a cap, is what decides when pushing a
line further stops being worth the science. Only boost-granting nodes are listed, because a
boost is the one thing a second pass can meaningfully add.

**"Known" is the level, not the state.** `ResearchNode.is_known()` is `level >= 1`, and
`ResearchTree.is_unlocked()` reads it. This is load-bearing rather than tidy: starting a second
pass puts the node into `RESEARCHING`, so if the gates read the state instead, beginning an
upgrade would close everything the node had opened — boosts to zero, dependents re-locked,
buildings gone from the build panel until it finished. `cancel_research()` returns a part-done
upgrade to `UNLOCKED` rather than `AVAILABLE` for the same reason, and
`_refresh_single_availability()` never reconsiders a node that is known.

`tier` on a node is unrelated: that is DEPTH along the prerequisite chain, and it is what the
cost surcharge is keyed on. The two axes share no vocabulary in the code deliberately.

Levels are saved. A save written before they existed carries no `level`, and every node it
records as unlocked was taken exactly once — so `load_state()` reads the state as the level, and
an old save loads with every repeatable line sitting at its first pass.

`cost_shown()` rather than `cost_for_next_level()` is what the UI prints: on a maxed line the
latter names a pass that cannot be bought, and on an ordinary unlocked node it is double what
the node actually cost.

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

### Automation runs on both clocks, and carries a hold

Two faults that looked like one.

**`_process_automation()` was called only from the day-mode block.** Every standing order
therefore stopped the moment the game switched to fast mode — which is also the moment the
planets stop being drawn as bodies and become blurs, so the two looked connected and neither was
intended. Flights already out went on landing (`_process_launch_arrivals` *was* in the fast
path), so it read as the rules having run out of things to do rather than having stopped being
asked. It is now driven from both. One launch per tick either way: the executor retries, so a
fast tick crossing a million years still only starts what the fleet is short of.

**A standing Supply Run flew empty for ever.** The rule had no manifest and `_auto_launch` had
nothing to pass — the same launch, the same cost, nothing delivered, which is the quietest kind
of broken rule. A launch rule now carries `cargo`, the automation panel has a manifest editor
for it (shown only for a mission with a hold, offering what the chosen *origin* actually
holds — a rule naming something that world never dug would never fire), and it goes through the
same `_on_launch_requested` path the manual panel uses. That path charges the cargo's own mass
in extra rockets and refuses the launch if the origin cannot fill the manifest, so an
over-ambitious hold simply waits, exactly as a rule that cannot afford its rockets already does.

### Standing defence, and three lists instead of one

The panel kept every active rule in one column underneath the forms that make them. By the time
a civilisation has standing orders worth having it holds a couple of dozen, build and launch
rules interleaved, and the only way to find the one you wanted to switch off was to read all of
them. Forms are now on the left and active rules on the right, partitioned by `rule.type` into
**Building**, **Launches** and **Defence** — each with its own empty note, so a category with
nothing in it says which category is empty rather than leaving one blank line in a shared list.

**A defence rule answers the interception warning instead of raising it.** Both
`_raise_strike_threat` and `_raise_asteroid_threat` now open by asking `_auto_defend(body,
kind)`: if a rule covers that body against that kind of thing and the shot can be paid for, the
projectile is erased, the event is announced to the timeline, and the clock never stops.
`_defence_covers` matches the body and the two flags separately, so a world can be set to burn
down rocks and still be asked about a missile. The world is one of the eight in Sol or
`AutomationPanel.DEFEND_ANY` — projectiles are aimed at interstellar colonies as well, and by
the time that is happening there are more of them than a dropdown can name one at a time. An interception is a decision with one sensible
answer whenever the shot is affordable, and being stopped to make it every time across a million
years is the opposite of automation.

It is an answer, not a promise. `_auto_defend` re-checks `_has_orbital_laser()` and the energy
the shot costs, and declines if either is missing — which puts the warning back up, because then
there is a real decision again, and a standing order that silently did not fire is worse than
being asked. For strikes that check is belt-and-braces: `_can_intercept` already gated on the
array, the charge and the projectile being a missile or a berserker swarm before the threat was
ever raised, so a laser strike — which arrives with the light announcing it — is not something a
rule can promise to stop. For asteroids, which are warned about whether or not a shot exists, the
check is the whole of it.

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

**Clusters fill the slots the stars leave over**, rather than competing with them by distance.
Mixed into one distance order, a cluster 300 ly out displaced a star 400 ly out — and with the
shell streamed there are eight thousand clusters where there were six hundred, so every lineage
anywhere always had one in reach. `_nearest_uncolonised` therefore collects stars first and only
then tops the result up from its own cluster buffer, which both matches what the exemption above
always described and makes "no star in reach" answerable from the result.

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
- A lineage with no uncolonised **star** in reach is **retired** from `_vn_seeds`, so the settled
  interior is not re-searched forever. *Stars*, not targets: a cluster is reachable at any
  distance and the streamed patch always holds an uncolonised one somewhere, so counting cluster
  probes meant no lineage could ever be enclosed and this path was dead. A lineage whose only
  remaining target is a cluster still sends to it and then sleeps — the probe that lands founds a
  lineage of its own, out where the frontier now is. `_vn_replicate` returns the number of probes
  sent **to stars** for exactly this reason. A retired lineage can be woken again, because
  occupation reverses even though colonisation does not — see `_vn_wake_near_freed`.
- `_nearest_uncolonised` walks a spatial grid (`_star_grid`) rather than the whole resolved list,
  takes the caller's en-route set rather than rebuilding it per call, and uses the maintained
  `_col_star_set` rather than rebuilding `taken` from `colonized_stars` — that last one alone was
  a quarter of a million dictionary inserts per tick at sixteen thousand colonies.
- The local chunk survey is skipped when the colony is inside the home cell, where the procedural
  field already owns the volume and every generated star would be rejected anyway.

### Flight tracks are clipped and budgeted

Two separate costs, both measured before either was touched. The baseline matters: the panel
queues its own redraw every frame **only while something is in flight**, so a probe that also
calls `queue_redraw()` gets two draws a frame with flights and one without, and doubles every
figure. The first pass at this measurement did exactly that.

**The dash walker was stepping off-screen.** The map is log-radial, so a track between two stars
projects tens of thousands of pixels across a panel sixteen hundred wide — one measured at
40 367 px. `_draw_travel_dashes()` stepped the whole of it in 14-pixel periods regardless:
672 000 dash segments a frame for 800 flights at zoom 40, of which about 98 % were outside the
panel. `_clip_segment()` (Liang–Barsky) now trims the walk to the visible stretch, and
`_draw_probe_track()` returns early when none of a track is on screen.

`_dash_start()` is a separate function because of the one thing that fix could get wrong: the
walk has to resume on **whole periods from the pattern's origin**, never from the clip boundary,
or the dashes crawl along the line every time the view moves. That property is asserted rather
than commented.

**And a track that IS on screen is still a handful of draw calls** — about 45 µs each, which is
near the floor for what it draws. Three thousand flights is a seventh of a second a frame, and
the late-game swarm runs to tens of thousands, so there is no drawing them all.
`FLIGHT_TRACK_BUDGET` (250) keeps the nearest tracks by distance from the view's own frame, as
the BUDGET-th nearest distance rather than a sort — the same answer the star field and the
cluster shell already give. The cut is cached behind a movement tolerance *and* the mission
count, because Game pushes the mission list every simulated day.

Frame cost at 1600×900, measured with the panel driving its own redraws:

| flights | zoom 2 | zoom 8 | zoom 40 |
|---|---|---|---|
| 3 000, before | 141 ms | 163 ms | 155 ms |
| 3 000, after | 55 ms | 54 ms | 32 ms |

The remainder is the star field and the cluster shell: 200 flights and 3 000 flights now differ
by about 7 ms.

### Star labels

A star is named if it is in the frame's chosen set — `NAME_RANGE_LY`, `NAME_BAND_INNER` and
`STAR_NAME_BUDGET` (16) — and inside the detail band, or if it is selected. **What is living
there does not enter into it**, which is why `_star_label_shown()` takes neither a colonised flag
nor a faction. The signature is the claim: a label cannot depend on who settled a star or who
lives there, because the rule is given no way to ask.

Both exemptions were real and both outgrew their reasoning. A colony was named everywhere
because one cannot act on a system one cannot identify — true until the swarm settled tens of
thousands of them. A known civilisation was named everywhere because there were a handful and
they are what the player is deciding about — true early, and not true of a galaxy the simulation
has been filling in for a million years. Either alone buries the map under its own labels, the
few worth reading among them.

**The highlight is not the name.** A colony keeps its green ring and a civilisation its red,
blue or yellow one, unconditionally: that costs one ring and says somebody is there. Only the
text is budgeted, and the colour carries the distinction without it.

**The selection is named whatever the band says**, which it was not before. That is the escape
hatch the whole rule needs: a star outside the name range has no label now, so clicking it has
to produce one or there is no telling which dot the info box is describing.

`verify_star_labels` specifies the rule exactly rather than sampling it — for an unselected star
the answer *is* "in the chosen set and inside the band", for every combination — so there is no
room left for an exemption to hide in.

### The star map's layer filter

Checkboxes in the map's top-right corner decide what is drawn: **Stars** (with a class each for
Human, Aggressive, Friendly, Unknown and Uninhabited), **Clusters** and **Galaxies**. All on by
default, so a filter nobody touches changes nothing.

**Uninhabited is a class like the others**, and it is the one that makes the feature work: the
four inhabited classes are a few dozen stars against six thousand empty ones, so without it the
filter cannot answer "show me only my holdings".

**The checkbox list is the legend.** The map has always been colour-coded by what is in a system
and nothing on screen said which colour meant what. `STAR_CLASSES` carries the id, the label and
the colour, `star_class()` decides which one a star is, and `_status_color_of()` is now a lookup
through the same table — so the swatch beside a checkbox is necessarily the colour the map paints
that star, rather than two lists that happen to agree today.

**A hidden object is also unclickable.** Filtering the draw alone leaves a star that can be
selected out of apparently empty space, with the launch panel then open on a target that is not on
screen. `_try_select()` and `_cluster_pickable()` apply the same filter, and turning off a layer
or a class drops a selection that falls in it.

Three things the filter has to be careful about:

- **The cluster sort is cached** (`_cl_key`), so the layer state is part of that key — otherwise
  hiding clusters would redraw the last cloud it built.
- **`_marked_stars` short-circuits the per-star lookups** while nothing anywhere is colonised or
  claimed. That optimisation is preserved: with nothing marked every star is Uninhabited, so one
  checkbox answers for the whole catalogue and the loop is skipped outright rather than testing
  six thousand stars for an answer that cannot vary.
- **The filter is not saved.** It is a way of looking at the map rather than a property of the
  run, and a save that came back with half the galaxy missing would read as a bug.

### Orbital structures are right-handed

`Planet.infra_orientation()` builds each orbital structure's basis: up-axis outward, +Y radial,
which is the contract the models are built to (the depot hull is taller than it is deep for that
reason). `Basis(x, y, z)` is right-handed only when **x × y = z**, and it was built the other way
round — `radial.cross(t1)` instead of `t1.cross(radial)` — giving every instance a determinant of
−1. That is a mirror, and a mirrored instance transform reverses the effective winding of
everything it draws, so the renderer culls the near faces, keeps the far ones, and the structure
is shaded from the inside.

It was wrong for **every** lane and visible on exactly one, because a mirrored box is a box:
`rod`, `cyl`, `flat`, `box`, `dish` and `ring` are all symmetric enough to hide it, and the
Orbital Vault is the only lane that draws a modelled hull. The Dyson swarm's collectors
(`init_planets.gd`) had the same sign error, invisible for the same reason — a flat panel
mirrored about its own plane is the same quad in the same place.

**The sideways axis comes from the orbit, not from a world axis.** `infra_orientation()` takes
the lane's orbit normal and uses the along-track direction — which is what a satellite bus
actually does, and more to the point is defined everywhere on the orbit. Built from a fixed
world reference it is not: the previous version used UP, switching to RIGHT once a structure came
within 0.95 of straight overhead, and at that threshold the whole frame snapped about the radial
axis. Five of the twenty-one lanes are inclined steeply enough to cross it, four times an orbit,
turning as much as **171°** in a single frame — a structure visibly spinning part way round its
orbit and back.

No fixed reference avoids this; there is no continuous non-vanishing tangent field on a sphere.
The fix is a reference that moves with the orbit. The orbit normal is constant per lane and never
parallel to the radial, so their cross product never vanishes. (The Dyson swarm never had this:
its lane basis is computed once per lane and the per-panel axes are continuous in the orbit
angle.)

**The bug is not reachable through the MultiMesh it feeds.** A headless run has no renderer:
`MultiMesh.set_instance_transform()` keeps nothing and `get_instance_transform()` hands back the
identity, so an assertion that stands structures up and reads their transforms back passes
whatever the maths does. That is why the orientation is a named static function instead of four
lines inside the draw loop — `verify_infra_band` checks `infra_orientation()` directly: over 72
directions for determinant, radial +Y and orthonormality, and around every lane's full orbit at
0.5° resolution for continuity. Both checks were confirmed to fail with their respective bugs put
back — the first version of the handedness check read the transforms back off the lanes and
passed either way.

### Founding stock

Every lineage used to be identical. `EvolutionTreeData.planet_variant()` handed each diverged
world the same `COMPUTE_PER_INDIVIDUAL`, so "H. sapiens martian" and "H. sapiens terran" differed
by an epithet and a tree node and nothing else — the genealogy was recorded carefully in
`_colony_parent` and then carried no consequence. A civilisation of ten thousand colonies was one
population in ten thousand places, which means **one survival number**: whatever kills a colony
kills all of them.

A **stock** (`stock_data.gd`) is two choices made when a colony ship departs, plus the variation
it ends up carrying.

**How many go** is a shipping cost against genetic variation. A founder group is a sample of the
population it leaves, and a small sample loses the long tail of rare alleles — not inbreeding
depression (a hundred thousand people are far past that threshold) but a smaller pool for
selection to work from, and a smaller effective population, which drifts faster. So a light seed
is cheap, becomes its own lineage sooner (`_stock_split_threshold` scales the 500k–1M year timer
by variation), and realises less of whatever it was selected for. A broad seed costs four times
the launch and is the opposite.

**What has been written into them** is a SET of engineered traits (`TRAITS`), as multipliers on
four figures that already existed: `growth`, `life`, `compute` and `capacity`. High Intelligence
thinks at 1.7× and breeds at 0.8×; Rapid Maturation is the opposite; Vacuum Tolerance fits 1.7×
as many people on the same rock and is good at nothing else. Every row pays for itself somewhere
— `verify_stocks` asserts each has a gain, a cost, and is not beaten on every axis by another,
because a dominant choice would produce exactly the monoculture the feature exists to break.

**`MAX_TRAITS` (3) is what makes it a choice.** The multipliers all trade, but a genome that
could hold every trait would still come out ahead holding every trait: the costs do not stack
faster than the gains. With a cap the player is choosing between minds, bodies and numbers
instead of accumulating, and the cap reads as something real — how much of a genome can be
rewritten before it stops holding together.

**Settlers are drawn from the origin world, so the origin decides what they are made of.** The
standing order (`colony_stock`) says how many go and which sequences are spliced into them;
`StockData.found()` takes the sample out of `stock_of(origin)`. Splicing the founders before
they leave costs nothing beyond *holding the sequence* — this is editing, not filtering — but
the group is still a SAMPLE, so its variation can never exceed the parent's and a cheap seed
expresses an edit less fully whatever is written into it.

**A von Neumann probe carries the stock of the lineage that launched it.** That is what makes the
swarm's genetic geography follow the shape of the expansion rather than a menu, and it is the only
way the mechanic reaches the tens of thousands of colonies the player never sees. The standing
order is civilisation-wide for the same reason: nobody curates 34 000 colonies.

**Nothing can be ordered that the civilisation does not hold.** A ship is spliced for a sequence
or it is not, and you cannot splice what nobody has written — so the trait menu is live only for
what is in `lineage_archive` or writable with Synthetic Biology. In 1945 that is nothing, which
is correct: the trait system opens when the civilisation can either write a sequence or has been
sent one.

Two implementation notes:

- **Stocks are tracked for interstellar colonies, the evolution tree is not.** `_colonized_year`
  is only written for solar-system worlds, so the tree's node-per-world display stays the ten
  bodies `PLANET_EPITHET` can name while the mechanical layer follows the swarm to every star.
  Thirty thousand nodes would not be a tree.
- **Thinking and living became properties of a population**, so human compute is
  Σ(pop × that world's stock) rather than one headcount times one figure.
  `_combine_production()` is documented as O(1) and must stay that way, so the weighted sums are
  accumulated by `_update_population()`, which already walks every world once a tick — and the
  per-world growth factor is memoised on the stock's growth multiplier, because stocks are a
  small discrete set and `exp()` per world would be thousands of calls a tick.

**Diversity is a property of the founding event, so it is stored, not derived.** A record without
one reads as a native population at full variation, which is what every world of a save written
before stocks existed was. `StockData.normalise()` is the gate: loading validates rather than
copies, so a renamed id or a hand-edited file still comes out as something the accessors can read
(hence `custom: true` in the save schema for both keys). A save naming one of the three life
histories traits replaced — `fecund`, `balanced`, `enduring` — comes back **unedited**: those
were selected rather than written and have no trait equivalent, and `load_game` filters the
archive to match so a loaded run cannot offer to splice something that no longer exists.

**A set of traits costs one hash lookup, not one per trait.** The record carries `tkey`, the
joined ids in `TRAITS` order, and `StockData.mult_table()` holds the worked-out product for all
42 legal sets — warmed behind a flag rather than a size test, since `mults_for()` fills entries
in lazily and a half-filled table would have the hot loop silently reading baseline multipliers.
So `_update_population` costs exactly what it did when a stock was a single row. Canonical
**`TRAITS` order and not tick order**, or two populations holding the same three traits would
hash to different keys and be different stocks.

**Capacity is applied in two places on purpose.** `_world_capacity()` folds in
`_stock_cap_mult()` for every caller that asks it — the stats page, the forecast, the colony
panel — but `_update_population`'s common case never calls it: an interstellar colony with
nothing built on it reads the shared `colony_k` instead, and that is most of the roster. The
loop applies the same figure itself from the record it already has in hand. The two have to
agree or the number the player reads is not the number growing.

**Both of the Launch panel's code-injected editors have to be MOVED, not just added.**
`_build_cargo_ui` and `_build_stock_ui` run early in `_ready()` and `add_child` appends to the
end of the panel's VBox — which is after the launch button and the active-launch list. The
cargo manifest had been sitting down there, below "Active Launches", since it was written. Both
are now moved up to `fuel_section.get_index()`, the same idiom the date and fuel sections
already use, which puts each against the Cost line it explains.

Two layout properties matter in a fixed 400px column, and `verify_stock_selector` measures the
rects rather than trusting a screenshot — a panel sitting flush against the window edge looks
exactly like one whose last control is cut off. (It measures them with the panel **shown**: a
hidden Control is never laid out, and asking one where its children are reports an overflow
that is not there.)

- A `Label`'s minimum width is its whole line, so an unwrapped title longer than the column
  pushes the column open from the inside rather than merely overflowing.
- `OptionButton.fit_to_longest_item` is on by default and reserves the width of the longest
  *entry* whether it is showing or not; `clip_text` is what lets the showing one give way once
  it has. Both are needed. It matters most for the cargo dropdown, whose entries are whatever
  the origin world is holding — a width this panel cannot know in advance.

**The selector is in the Launch panel**, under the Cost block it explains — a colony ship's
vehicle count is mostly the people in it, and `_mission_rockets()` folds the founder group's
mass multiplier in for that mission only. It is shown for a Colony Ship and nothing else, since
no other mission carries anybody. Game owns the order and the panel only asks: the dropdowns are
moved by the push that comes *back* from `set_colony_stock()`, guarded by `_stock_quiet` so the
push is not mistaken for the player touching the control, which would otherwise loop. A refused
order therefore leaves the dropdowns where they were rather than showing a selection the
simulation never accepted. `stock [founders] [traits…]` in the dev console does the same job —
naming any trait replaces the whole set, and `none` clears it.

**A menu of checkboxes, not a dropdown**, because a stock holds a *set* now and a dropdown can
only say one thing. It keeps the one-row layout the 400px column has room for: the button shows
what is ticked, the sequences are behind it, and `hide_on_checkable_item_selection` is off so
picking three traits is three clicks rather than three trips. A sequence nobody holds is
**greyed** rather than silently snapping back, which would read as a bug.

### Colonies have an economy, and can be shipped to

Interstellar colonies could not be traded with at all: the star map's Trade button was greyed
for anything colonised, and there was nothing on the other side anyway. A colony held no
inventory and produced nothing, and `trade_holdings()` returns the **civilisation-wide** energy
and science pools for every world — so a trade would have moved a number to itself.

**A colony mines its own system, unasked.** `_advance_colony_economy()` gives a slice of the
colonies another span of output each tick, into `compound_inventory` keyed by the star's name —
the same per-world store Earth and the planets use, so this needed no new machinery. Output is
population × `COLONY_YIELD_PER_CAPITA` × maturity, where maturity is the Dyson swarm the colony
has already been growing from its founding year. Which three materials a system yields is rolled
from its own name, so every colony has a character and the galaxy is worth shopping around in;
the systems are not modelled in enough detail to derive a real composition, and inventing one
per star would be a worse lie than an honest roll.

They stockpile without being told to because that is the only thing that makes sense at eight
hundred years round trip: a colony cannot be managed, only traded with, and what it has when a
request arrives is whatever it has been doing since anyone last looked.

**The economy itself is not where the cost was.** `_advance_colony_economy()` is a round-robin
slice and measures flat at 0.5 ms whether there are two hundred colonies or twenty thousand.
What slowed down was `_update_population()`, which walks every inhabited world every **day**: the
stock lookup added to it called `StockData.normalise()` seven times per world — `stock_of` once
and each of the three multiplier accessors twice, via `realisation_of` — each allocating a
dictionary and scanning the id tables linearly. At twenty thousand colonies that was **677 ms a
tick**.

Four changes, each measured:

- `normalise()` hands back a record that is already well formed **as it is**, allocating nothing.
  That also matches what the callers want: the adaptation pass and `direct_lineage` both mutate
  what they are given and write it back, which is a no-op once they are the same object.
- `found()` and `baseline()` return **complete** records, so they hit that fast path. Built
  short, they were rebuilt on every read — which is why the first version of the fast path never
  fired.
- The id tables are **indexed, not scanned** (`_by_founders`, `_by_strategy`).
- `_update_population` works the three multipliers out **inline**: `stock_of` is a plain lookup
  rather than a re-validation, and the one float `realisation_of` would re-validate a whole
  record to read is read directly. Nothing in the loop allocates.

677 ms → **69 ms** at twenty thousand colonies, against a 37.6 ms floor measured with the stock
work stubbed out entirely — so the feature went from ~640 ms to ~31 ms of that tick.

**At 1x the clock advances four simulated days a second** (`TIMESCALE_BASE` = 0.25 s/day), so a
day that costs 50 ms is 200 ms of work a second — sustained judder, not an occasional hitch.
That is what a late game felt like, and the per-day loops are where it was.

**The colony economy made an old O(worlds) walk expensive.** `_player_item_count()` sums one
crafted item across every world's inventory; `compound_inventory` held ten worlds before colonies
had an economy and fifteen thousand after. It is called twice a simulated day through
`_mc_staffing()` alone — `_refresh_stats` and `_process_production` — and three more times
whenever the star map refreshes.

It is now driven from `_home_worlds()` (Earth plus the in-system colonies) rather than filtered
out of `compound_inventory`, because walking fifteen thousand entries to reject all but ten costs
the same as walking them to add them up. That is also the **correct** answer, and the trade
system is the proof: a consignment from a colony exists precisely because what it has mined is
not yours until it has been flown home. Counting those stores as on-hand would say a robot four
hundred light-years away is on the factory floor. `_consume_player_item`, `_build_launch_stock`
and `_build_satellite_stock` follow the same rule, so what can be spent is exactly what was
reported. `_mc_staffing` 7.9 → 0.002 ms; `_refresh_stats` 8.4 → 0.14; `_process_production`
8.4 → 0.22.

**The population pass is sliced.** A colony is grown once per cycle of `POP_SLICES` (8) ticks
with the whole cycle's span at once, which is **exact**: logistic growth in closed form composes,
so `k/(1 + (k/p − 1)e^−rt)` over 8t is what eight steps of t give. It holds only where *k* held
across the span, so solar-system worlds — whose capacity moves as things are built on them — are
still grown every tick; there are ten of them.

The weighted sums accumulate across the cycle, each world contributing **once**, and are
published when it closes, so there is no running total to drift and no resync. A colony's visit
is its contribution; a solar-system world is visited every tick and so contributes on the closing
tick — counting it on each visit inflated the headcount eightfold, which is what
`verify_population_slice` caught. The headcount itself is carried by the deltas of what actually
changed and so stays current every tick; the weighted figures lag by up to one cycle, which is a
fraction of a percent on quantities that move on geological timescales.

`_update_population` 43.7 → 16.6 ms, `_consume_food` 5.4 → 0.01 ms (driven from the fed worlds
for the same reason as the item counts). A simulated day at fifteen thousand colonies: **67 → 17.5
ms**.

**The day tick's own loops were the rest of it.** `_update_population()` and `_consume_food()`
walk every inhabited world every simulated day, and at twenty thousand colonies they were
rebuilding the same answers each time:

- `_inhabited_worlds()` builds a fresh Array *and* a fresh Dictionary of every world per call —
  ten milliseconds a tick to restate what `world_pop` already says. Both loops now walk
  `world_pop` itself; entries are only reassigned, never added, so iterating while writing is
  safe, and anything to drop is collected and erased afterwards.
- The stale-entry prune was a second full pass over `world_pop.keys()`. It is folded into the
  pass that was walking those worlds anyway.
- `_total_population()` was called **three** times a tick for one figure — once for a bool
  ("is anyone left anywhere", which a tick-old number answers just as well), once at the end of
  `_consume_food` (starvation only ever takes people, and only from the few worlds fed from a
  stockpile, so the difference is known without counting again), and once in `_refresh_stats`
  for `galaxy_population`.
- `_consume_food` turns interstellar colonies away **first**, before reading a population and
  clearing a famine record for tens of thousands of worlds it was about to skip.
- The strategy table and the diversity constants are hoisted out of the loop: a static call and
  a constant read on another class are not free in GDScript at twenty thousand iterations.

Per simulated day at twenty thousand colonies: `_update_population` 677 → **48 ms**,
`_consume_food` 11.3 → **3.9 ms**, `_refresh_stats` 4.1 → **0.07 ms**.

What remains is the per-world floor — about a dozen dictionary operations and fifteen float ops,
~2.4 µs each. Cutting it further means visiting a slice of worlds per tick rather than all of
them, which the closed-form logistic makes *exact* (it composes over Δt), but which needs a
parallel key array to slice a Dictionary and running totals with a periodic resync, since the
weighted compute and life sums need every world. That is a different kind of change and has not
been made.

**A consignment is not a negotiation.** `is_own_colony()` branches the whole trade path: there
is no alignment to reveal, no standing to earn and no accept ratio, because there is nobody over
there to haggle with. `_resolve_own_colony_trade()` moves both halves for real — what was
escrowed at home is unloaded into the colony's store, and what was asked for comes out of that
store. A request larger than the colony can fill is **filled as far as it goes** rather than
refused: nobody over there decided anything, and a short delivery is the honest outcome.

**Mass costs energy to move, and that is what stops this being teleportation.** A message is
cheap; a consignment is kinetic energy per gram at a fraction of *c*.
`CONSIGNMENT_ENERGY_PER_GRAM_LY` is charged on both directions up front — the far end cannot be
asked to find the energy, because by the time it hears the request this civilisation may not
have any. Energy and science weigh nothing and are not freighted at all; they are a
transmission, already paid for. The consequence is the point: bulk material trade between stars
is unaffordable on a planetary grid and becomes ordinary once a star has been enclosed, which is
exactly when a civilisation could really do it.

Diplomacy stays shut for your own colonies — Contact, Alliance and Declare war have nobody to
address — and the button reads "Ship…" rather than "Trade…".

### Writing a sequence: Synthetic Biology

Until the research, the only sequences a civilisation has are the ones its colonies worked out
over three hundred thousand years of isolation and sent home — `lineage_archive` is the only way
to hold one.

`can_engineer_lineages()` (gated on `synthetic_biology`) is the difference between being *given*
a sequence and *writing* one: any trait in the table can be written from first principles and
put into any world, without waiting on anybody's colony.

**What it does not buy is instant people.** The sequence is information; getting it into a
living population is still a couple of generations of germ-line work, so an engineered splice
takes exactly the `SPLICE_YEARS` a traded one does. Having the answer was never the slow part.

The control lives on the **Population tab** of the planet panel ("Applied genomics"), the
in-system counterpart to the star map info box's splice dropdown for a colony. It is **hidden**
rather than greyed before the research: a permanently disabled control teaches less about why
the trait system works the way it does than one that is not there yet.

`splice_block_reason()` is the single test behind the offered options and the action, so the tab
cannot offer a splice the simulation would refuse — and the refusal before the research names
both ways out, the research and a colony that worked the sequence out.

### Trading sequence data with your own colonies

A colony four hundred light-years out is yours on the map and autonomous in every way that
matters: the round trip is eight hundred years. What can usefully cross that gap is not ore — it
is **information**, which has no mass and is the whole of what a written sequence is. Genetic
data is the one cargo interstellar distance does not make absurd, which is why this is the shape
the trade takes.

**The clocks are the design.** `_advance_lineages()` gives a slice of the settled worlds another
span each tick, and three things happen on wildly different timescales:

- **Variation recovers** by mutation toward what a native population carries
  (`DIVERSITY_RECOVERY_YEARS`, 3 Myr). A thin founder group is not thin forever; it just spends a
  geological age being so.
- **A splice in progress finishes**, in `SPLICE_YEARS` — **40 years**, scaled a little by the
  population's variation. This is the point of traits being spliced rather than bred: the system
  this replaced moved a population by *selection* and took 2 Myr to do it, which a run measured
  in millions could manage perhaps twice. At decades it is something the player does and then
  sees.
- **A distinct colony writes a sequence of its own**, in `DISCOVER_YEARS` (300 kyr), picked by a
  deterministic roll on the world and the year so a reloaded save discovers the same thing. This
  is the slow clock that is left, and deliberately the only one: **having** a trait is the scarce
  thing now, not distributing one. A colony with its own laboratories and nobody to share with is
  the only way a sequence enters the game that nobody wrote — and it is what gives the player
  something to ask for. A colony founded already carrying `MAX_TRAITS` never writes anything,
  which is the quiet cost of shipping a fully specialised seed: it has no room left to be
  surprising.

**The discovery is announced once per sequence, not once per colony.** Fifteen thousand colonies
will write Extended Lifespan thousands of times over a few million years, and every one after
the first is a second copy of something the player already knows they can ask for. `_trait_news`
(transient, not saved) holds the ones already reported, and nothing is reported at all once the
archive holds it.

**Distance is the price.** `request_lineage()` costs `2 × dist_ly` years, request out and data
back at *c*. In-system worlds answer instantly, which is correct rather than a special case. One
request per **world**, not per trait: everything that colony has written comes back in the same
transmission, because splitting it would be eight hundred years apiece for no reason.

**What comes back is the sequence.** Holding it in `lineage_archive` lets a colony ship be
founded carrying it and lets any settled world be spliced for it (`splice_trait()`). One splice
at a time per world — a second request replaces the first and starts the rollout again, because
half of one edit is not half of another.

**The offer lives on the system itself**, in the star map's info box, under the colony
infrastructure block — next to the distance that prices it. The button carries the wait rather
than hiding it in a tooltip, because the wait *is* the price: "Request lineage data (8.7 yr round
trip)" on a near colony, most of a millennium on a frontier one. Below it a dropdown lists what
can be spliced into the selected world.

Game is the authority for both halves. The panel emits `lineage_requested` /
`lineage_direct_requested` and shows whatever comes back, so an offer the simulation would refuse
is never clickable — and `lineage_block_reason()` is the single test behind both the greyed
button's label and `request_lineage()`'s refusal, rather than two copies of the rules that drift
apart.

Two implementation notes:

- **The pass is a round-robin slice** (`ADAPT_PER_TICK`, 64 worlds) because the roster runs to
  tens of thousands. Each world is credited with the span between *its own* visits — `dt × n /
  visited`, against the number **visited** and not against the cap, or a two-world civilisation
  advances thirty-two times too slowly.
- **`StockData.normalise()` carries `splice` / `splice_done` / `discover` through**, because it
  is the gate every stock passes coming off disk. Dropped there, a world two thirds of the way
  through a rollout would start again on every load.

**Traits are keyed by string id, deliberately.** The intended next half of this is trading
sequence data with other civilisations — a trait written by a population that lives somewhere you
do not. A trade has to name what it delivers across a save file, a light-delayed message and a
version boundary; a string does that and a row index does not. The multipliers in `TRAITS` are
stated explicitly rather than derived so that there is something to put a number against.

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
9. **Nothing is spent above a `return`.** `_on_launch_requested` charged a structure mission's
   whole bill of materials three refusals before the point of no return, so a carrier that could
   afford its station but not its rockets destroyed the station and flew nothing — and because
   the launch never happened, the fleet was never at strength and a standing automation rule did
   it again every tick. Every deduction now sits below every check, in one block. A comment in
   that function claiming "nothing is spent" was true for the mission it was written about and
   false for the one added later.
10. **A world appears in `_home_worlds()` once.** The list is Earth followed by the in-system
    colonies, and callers *sum over it*: a duplicate makes `_player_item_count` report twice the
    stock on hand (so `_consume_player_item` "succeeds" having spent half of it) and
    `_consume_food` feed the home world twice. Earth got into `colonized_planets` because the
    launch panel offers Earth as a target and treats `origin == target` as a local orbit
    insertion — right for every mission except the one that settles a world. Refused at the
    request, refused again at the arrival, de-duplicated in the list, and stripped on load.
11. **Stockpiles and reserves are floats, never `int()`.** `int()` saturates to `INT64_MIN`
    above 2^63, and these are gram and joule figures: a developed civilisation passes 9.2e18 J
    long before anything else, at which point the launch panel was told it held a large
    *negative* reserve and refused missions the origin could pay for many times over.
    `_build_satellite_stock` already documented this; `_build_launch_stock` had to learn it.
12. **One warning at a time.** `_check_incoming_attacks()` and `_check_asteroid_impact()` run
    four lines apart in the same tick body, and a fast tick spans thousands of years. The second
    warning used to replace the first and record *its* pause as "what the clock was doing
    before", so answering could never start the clock again. Both raisers now stand down while
    `_pending_threat` is set, and the asteroid check stands down **before** advancing its
    schedule, so the rock is postponed rather than skipped.

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
