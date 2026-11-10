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

### One line per recipe per world

A recipe already in production on a world is **greyed in the picker** and cannot be started
there again until it is taken off the list. Two copies was never two production lines — it was
one recipe listed twice, each with its own rate slider, competing for the same inputs.

**Per world, not globally**: the same recipe running on Mars says nothing about whether Earth
may start it, and `_recipe_running_here()` tests the active body's jobs by recipe *name*,
because that is what a job carries.

`_refresh_recipe_availability()` is called from every point the job set or the active world can
change — `_populate_recipes` (a research unlock), `_rebuild_job_list` (which covers a load, a
planet switch and a removal), and `_on_add_pressed`. It also moves the selection off a recipe
that has just gone into production, because the common gesture is "add this, now add the next
thing" and leaving the picker parked behind a dead button is worse than moving it.

**`_on_add_pressed` enforces it too**, not just the menu. The greying is what the player sees,
but that function is the one path that creates a job, and a popup built before the last change
must not be able to get a second copy past it.

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

**The population worklist is dealt, not filtered.** `_update_population` walks
`_pop_system` (the solar-system worlds, every tick) plus one of `_pop_parts` (the interstellar
colonies, dealt into `POP_SLICES` hands). It used to iterate `world_pop` itself and `continue`
past seven entries in eight. `_ensure_pop_parts` re-deals once a cycle, and at once whenever the
roster changes size — so a colony arriving is picked up immediately, while a change that keeps
the size equal waits for the cycle boundary, which is the same tolerance the slice already had.
`verify_population_slice` asserts the partition is exactly the roster, with nothing dealt twice
and nothing left out: a colony missing from it is a colony that never grows again.

Measured at 15 000 colonies, per frame: **17.3 ms → 9.0 ms**. The two halves were not what they
looked like — the eager default above was 5.4 ms of it and the dealt worklist 2.9 ms. What is
left is genuine arithmetic over the 1 875 worlds a frame actually owes, plus ~1.1 ms amortised
for the re-deal. `POP_SLICES` is the remaining lever, and it trades frame cost against how often
a colony is visited.

**Production** is recomputed only when dirty (`_mark_prod_dirty()` →
`_recompute_production_cache()`), then combined per frame in `_combine_production()`. Note the
ordering trap inside the recompute: it clears `_prod_dirty` at the END, and anything called
before that which asks for a building count will recurse.

Construction is work over time: `_building_work()` against the world's Manufacturing Capacity,
which is `BASE_MC` plus factories (and, off-world, an Orbital Construction Station).

### Naming a save

Saving already worked and had nothing to say. The pause menu's Save button called `save_game()`
with no path, which fell through to `user://saves/default.json` — so every run that had not been
*loaded* from a named slot overwrote the same file, there was no way to keep two games, and no
way to tell which one you were in.

`save_dialog.gd` asks for a name. **Game is the authority**, as for every other panel here: the
dialog emits `save_requested`, Game decides the path, writes, and hands back a result through
`set_result`, so what the player is told and what is on disk cannot disagree. A failure leaves
the dialog **open**, because the player's next move is to try another name.

**The sanitiser is shared on purpose.** `SaveDialog.sanitise()` strips the same three characters
`StartMenu` strips, and `verify_named_saves` asserts the two produce the same path for the same
name — if they ever drift, a save made in game is one the menu cannot find.

**Saving names the run.** On success `GameSession.current_save_path` becomes that slot, so the
next save goes there rather than back to `default.json`, and the name field opens pre-filled
with it. An unnamed run is offered its year instead ("Humanity 2187"), which is the one fact
that tells two saves of the same game apart.

Two smaller things `save_game()` gained, because a player-facing button needs them and a test
that can look at the disk itself did not: it **creates the save directory** (on a fresh install
`user://saves` does not exist, and `FileAccess.open(WRITE)` into a missing directory fails
silently), and it **returns whether the file was written**.

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

**Everything in solar orbit sits inside Mercury's.** The lanes span 4.79 to 8.37 world units
against a solar surface at 2.35 and Mercury's **perihelion** at 8.58 — perihelion, not the 10.47
mean, because Mercury is eccentric enough (0.21) that a band sized to the mean would be swallowed
once a year. The Dyson swarm hugs the star inside it at 3.05–4.39. The band used to run
3.01–7.99, straight through the collector shell with most of the infrastructure embedded in it.

**One structure is not in a lane at all, and has no model either:** the Shkadov Mirror stands on
the photosphere, in the gap between the star and the swarm, and is built in `planet.gd` as a
plain spherical cap. See §5.

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
| Propulsion | Shkadov Mirror | Build cost only | Thrust = 0.16% of L/c × the share of sky it covers; moves Sol, and every distance with it |

**Two clocks.** `StarModel.stellar_age(year, mass, offset)` converts calendar year to the star's
own age; `year_of_age()` inverts it. Lifting slows the star's clock (lifetime ∝ M⁻²·⁵); husbandry
subtracts from it directly.

**Fate follows mass.** Above 0.5 M☉ the authored track runs to its end. Below it there is no
helium ignition: no giant branch, no engulfment, no nebula — `sun_red_giant_year()` and
`sun_nebula_year()` return `INF` and the readouts say "never". Below 0.08 M☉ fusion stops.

**Dimming has a price.** `_climate_capacity_factor()` penalises the *net* of CO₂ warming and the
light Earth is not receiving, so lifting a quarter of the Sun is a climate catastrophe in the cold
direction — and the player's own emissions become a counterweight.

### One mirror, and its size is the physics

The Shkadov thruster is **one structure** — `"max_count": 1` in `buildings.gd`, enforced by
`Game.build_room()` and counted across the **whole family**, because the tiers are separate
catalogue entries and a cap read per entry would let the player stand three mirrors by building
one of each size. It is the only capped structure in the game; everything else returns
`BUILD_ROOM_UNLIMITED`. A queued **retrofit** is deliberately not counted, because an upgrade
consumes the structure it replaces rather than adding one.

So levelling it up is the only way to make it push harder, and what levelling it up buys is
literally a bigger mirror. `mirror_coverage` — the share of the star's sky the sail subtends — is
the whole of its physics (`StarModel.shkadov_thrust_n` turns it straight into newtons) and the
whole of its picture: `Planet.mirror_cap_mesh()` builds the cap of that coverage, read off
`SolarSystem.star_mirror_coverage`, which is the same number the thrust comes from. **The
picture cannot drift from the physics**, and a mirror with no coverage — none built, or the one
built switched off — is a mirror furled, and not drawn. The three tiers come out at 0.5%, 1.75%
and 6.125% of the sky; the top of that is about what a determined build-out of the old
thousand-segment fleet reached, now reached in three steps instead of by grinding, and the
`accelerando` achievement reads the ceiling off the catalogue rather than naming a number, so
retuning the coverage cannot leave an achievement nobody can earn (it asked for 0.99 of the sky
before, which one mirror never reaches).

**A save from before the cap carries a fleet**, and `load_game` collapses it: the biggest tier
standing is kept, the rest are dropped unrefunded, and the mirror's active-count entries go with
them so the one kept comes back **switched on**. Without that a loaded fleet would stand over
its cap for ever with its coverage saturated at a full sky, and a fleet the player had idled
would restore as a single idle mirror — a thruster that silently stopped working, which is the
failure `save_schema.gd`'s own header is about.

**It is drawn with no lane and with no model.** A statite does not orbit — it hovers, held off
the star by the light it reflects — so it stands still over one spot while the band circles past
it, and it is not hidden with the lanes past 100×, because a thing that does not move cannot
smear. It is a **spherical cap** on a shell concentric with the star, built in
`Planet.mirror_cap_mesh()` from the half-angle its coverage implies. That is what makes the
picture *be* the physics rather than proportional to it: a cap of half-angle θ covers exactly
(1 − cos θ)/2 of the sphere it lies on, which is the coverage the thrust was computed from — so
the area of the mesh over the area of that shell **is** the number `shkadov_thrust_n` is given.
`verify_shkadov` measures it off the built triangles rather than off the formula that built
them.

It inherits the star's scale through the parent, which is the opposite of what every lane does
— a lane cancels its body's scale so its structures are a constant world size on any planet,
while a share of the sky has to grow with the star under it.

**It had a model and gave it up.** It was drawn with the lane mesh the old fleet used: a stepped
dish on a boom with a statite bus behind it, authored at 0.28 units across. One mirror is a
hundred times that, so what the player saw was a piece of satellite hardware the width of a
star, and the boom reaching 0.062 back towards the photosphere had to be solved around — the
standoff was the root of `d = (0.5 + gap) / (1 − (back/radius)·tan θ)`, holding the *bus* clear
of the star while the sail's plane rose as it widened. A sail is a surface. `MIRROR_GAP` is now
simply where it flies, 0.02 above the photosphere, and the cap is at that distance at *every*
point of itself.

That is also what fixed its clearances. A flat disc standing on the star has its rim further out
than its centre, so the biggest mirror reached 1.6 solar radii — into the Dyson swarm's inner
lane at 1.3 — and the overlap had to be documented rather than forbidden. A cap has no point
further out than any other, so the sail is inside the gap at any size, up to and including a
closed shell. `verify_infra_band` asserts that at 6%, 50% and 100% of the sky.

The half-angle needs no bound either. The disc's rim ran away to infinity as θ approached a
right angle and had to be clamped at 45°; a cap at θ = π is a complete shell around the star,
which is what covering the whole sky means.

**The sail does not glow.** Everything built is lit by the sun and nothing else, so the face
turned away from the star is black — and from outside that is the only face there is, because
the sun's six lights all sit *on* the photosphere, inside the sail's standoff. The mirror reads
as a silhouette against the star it stands on. It briefly carried a 1300 K emission for the heat
a sail in 3.4 × 10⁷ W/m² really would radiate; that is gone.

**The thrust is on the Sun's panel, because the journey cannot show it.** Drift reads 0.000 ly
and the speed a ten-thousandth of a metre per second for the whole of a normal run, at every
size of mirror — so the old "Thrust" row (now "Drift") could never say that a retrofit did
anything. A "Mirror" row carries the sail's own figures instead: the share of the sky it covers
and the newtons that is worth. The two move together because thrust *is* the share of the sky:
integrating the escaping radiation of a star with a concentric arc over it gives
F = (L/c)·(1 − cos ψ)/2, exactly linear in coverage, which is the form `shkadov_thrust_n` has —
under a `MIRROR_THRUST_EFFICIENCY` calibrated against published Class-A accelerations rather
than a bare reflectivity, so the constant carries the practicality and the coverage carries the
size.

**The bill of materials is the sail's own mass.** 0.5% of the sky at the photosphere is
3.0 × 10¹⁶ m², and a statite has to hover on the light it reflects, which puts it near
10⁻⁴ kg/m² — about 3 × 10⁹ tonnes. The authored costs come to 5 × 10⁹ tonnes once
`Units.MASS_SCALE` is applied: the same number to within a factor of two. They are a hundred
times the old per-segment cost because one mirror now does what a hundred segments did, so the
price of a given thrust is unchanged.

### Taking the planets apart

The other half of the same idea, and the cheap half. `disassembly.gd` prices a gram the way
`star_model.gd` prices one: gravitational binding energy, (3/5)GM/R averaged over a uniform
sphere. The numbers are the design:

| | per kg | whole body |
|---|---|---|
| Sol, at the photosphere | 1.91 × 10¹¹ J | — |
| Earth | 3.75 × 10⁷ J | 2.24 × 10³² J |
| Mercury | 5.42 × 10⁶ J | 1.79 × 10³⁰ J |

A planet is four to five orders of magnitude cheaper per kilogram than its star. That is the
honest reason a civilisation eats the planets first, and it falls out of the physics rather than
being a balance decision.

**Which is also why energy cannot be the limit.** Mercury's entire binding energy is about five
days of a finished Dyson swarm; gate on energy alone and taking a planet apart is a button. What
actually limits it is moving 3.3 × 10²⁶ grams, so the **rate comes from machinery** — the
Planetary Disassembler, in grams per day, tiered like every other rated structure — and the
energy is a floor that stops it being free in 1960. One base unit is Mercury in ~900 000 years.
Short of energy the tick takes proportionally less rather than refusing: a half-powered
operation runs slowly.

**Outside in.** `LAYER_ORDER` is atmosphere → crust → mantle → core, because you cannot reach a
core through a mantle. That gives a half-eaten planet a different character from a fresh one —
the crust is the thin interesting layer, the mantle is bulk silicate, and the iron-nickel core a
swarm actually wants is last. On a gas giant the envelope *is* the planet, so Jupiter is a
hydrogen reservoir with a small rocky prize at the bottom.

**The removal ledger is stored, not derived, and this was a bug fix as much as a feature.** The
composition readout used to compute what was left as `crust mass − what the world is currently
holding`. Neat for a display, and wrong the moment anything *leaves* the inventory: spend the ore
on a building or ship it away and the crust quietly grew back. Harmless while nothing could
exhaust a crust; fatal for disassembly, which would let a planet be eaten for ever. `_body_removed`
(body → layer → compound → grams) is now the one ledger, **mining writes to it too**, and the
panel answers the same question the simulation does.

**A world shrinks as it is eaten.** `_world_capacity()` multiplies by `_body_remaining_fraction()`,
and capacity is already a *ceiling* in `_update_population` — so the population sheds down to
whatever ground is left, and nothing special has to kill anybody. When the last layer goes,
`_finish_disassembly()` takes the body out by the same route `_destroy_engulfed_planets()` does,
because the consequences are identical. Whatever was still in its stores is in orbit rather than
on a planet that no longer exists, so it is carried home instead of evaporating.

**A world being taken apart stops looking like a world.** Two things change, and they are
driven from deliberately different numbers.

**Size follows the mass left, by the cube root** (`DisassemblyData.radius_frac`). Mass goes as
the cube of the radius at constant density, so a planet with half its mass gone is 0.79 of its
radius and the first tenth off it is barely visible. That is correct: a crust is a skin.

**Appearance follows the LAYERS reached, not the mass** (`_disassembly_depth`, 0 at an untouched
world and 1 at the last of the core). A core is most of a planet by mass, so a mass-driven look
would leave a world apparently untouched long after its crust was gone and then race through the
interesting part — measured on Mercury, a mass ramp sits at 0.00 with the atmosphere gone and
0.09 with the whole crust gone, against 0.25 and 0.50 for the layer ramp. The depth counts only
the layers a body *has*, so losing Jupiter's envelope is half of Jupiter rather than a quarter.

`DisassemblyData.look(depth)` turns that into `mix` / `color` / `glow` / `metallic`: the surface
map gives way to incandescent silicate, which cools into iron as the core comes up.

**No new art, because the surface map stays in play as the body's relief.**
`planet_polar_blur.gdshader` takes four `strip_*` uniforms and modulates the exposed material by
the map's own luminance, so a half-eaten Mars reads as Mars with its crust off rather than as a
billiard ball — and the low ground glows hottest, which is where an excavation would have
reached. All four are zero on an untouched world, which is every world in a run that never does
this. `Planet.set_disassembly()` works in both directions, or a reloaded save would show the
last world the node happened to be told about.

**The planet panel rebuilds its composition list on the fraction, not just on the selection.**
What a body is made of used to be static per body, which is exactly the assumption disassembly
breaks.

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

**And it could only carry four or five things, or in a standing order only energy.** Both
manifest pickers read one map, `Game._build_launch_stock()`, and that map was a *whitelist* of
the goods a launch is **priced** in: `Rocket`, the propellants, and the bills of materials of
the structures a carrier mission flies. Pricing was all it was ever built for; pointing the
cargo editors at it meant the hold could be filled with airframes and fuel and not one thing a
colony would actually ask for — no steel, no water, no food.

In a *standing* order it was narrower still, and this is the part that reads as a different bug.
On a world that has not stockpiled rockets or propellant every key in that map is zero, and a
picker skips a zero — leaving `energy` as the only offer, because it is the civilisation-wide
reserve and so the one entry that is never empty. Which is also the one thing that cannot
usefully be shipped: it is in `GLOBAL_POOLS`, so `_deduct_stockpile` takes it from the pool at
launch and `_add_stockpile` hands it back to **the same pool** on arrival. A round trip to
nowhere, paid for in rockets.

The executor was never the limit — it ships any compound by key and always could, which
`verify_automation_cargo` had been proving with steel the whole time. So the map now reports
what each world **holds**, with the cost keys still written explicitly at zero so a gate reads a
definite number rather than a missing key, and copied rather than aliased so a panel cannot
write the inventory through it. `_home_worlds()` is Earth plus the in-system colonies — a dozen
worlds, not the fifteen thousand in `compound_inventory` — so a full copy costs 0.38 ms with
every world holding all 95 compounds, and the UI pass now builds it once for both panels instead
of twice.

What stays out is in `MissionData.HOLD_EXCLUDED`, asked through `MissionData.can_hold()` by both
pickers *and* by the launch itself, so what the player is offered and what the game will fly are
one rule. The executor filters rather than trusts because a manifest can arrive from a standing
order saved before the rule existed: the pool entry is dropped and the rest of the hold flies,
where refusing outright would strand a rule whose manifest the player can no longer see. Not a
theoretical case — the mass is counted in **grams**, so a reserve-sized figure asks for more
lift than there are rockets and the rule silently never fires.

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

### The star pass is cached

Measured at six thousand stars, the per-star loop in `_draw` **was** the map's entire frame
cost: 31.5 ms, against 6.9 ms for a frame with the map hidden. It split three ways, almost
evenly — `_rel` + `_project` 11.3 ms, the name conversion and two dictionary probes 12.4 ms,
`_display_radius` + `_detail_alpha` 7.1 ms. Nothing else on the panel was material.

None of that depends on anything but the star, the camera, the frame origin, the selection, who
holds what, and the layer filter. So the whole pass — `_st_vis`, `_st_pts`, `_st_col` — is cached
behind a key of exactly those, the same treatment `_cl_pts` already gives the clusters, with the
frame origin on a movement **tolerance** rather than in the key (a Shkadov-driven Sol moves
`_ref_pos` every frame, and an exact compare would rebuild for a sub-pixel displacement).

Then `_st_held` / `_st_fac` resolve who holds each star **by catalogue index**, rebuilt only when
that changes, which takes the 12.4 ms of `str(s0["name"])` and two probes per star off every
frame on which anything anywhere is marked.

| at 2 000 colonies | before | after |
|---|---|---|
| static view | 38.2 ms | **6.9 ms** |
| while turning | 64.4 ms | **57.6 ms** |

The static case is the one that matters: a map is read far more than it is turned, and the map's
own share of a still frame went from ~31 ms to nothing measurable.

### Sending a flight used to cost a rebuild a frame

Reported as "the star map gets laggy again after the player sends a flight", and it was two
things, both doing work to animate something that animates itself.

**The cache was thrown away on every push.** `set_interstellar_state` bumped `_marked_version`
unconditionally, and that version is in the star cache's key — including the view-independent
half, which holds `_rel(pos)` for every star and is the expensive one to rebuild. The UI pass
calls `refresh_star_map()` while the map is open, so from the moment anything was in flight the
whole pass was rebuilt sixty times a second.

The version exists to catch *a colony lost and another gained between two frames*, which the
counts miss. It does not need to fire when nothing moved. The comment beside it warned off "a
value compare of six thousand entries every frame" — correct in isolation, but weighed against
the wrong alternative: at 4 000 colonies that compare is **0.33 ms** and the rebuild it prevents
is **37 ms**.

**The push itself is a full rebuild.** `refresh_star_map()` duplicates the whole colony roster,
walks every cluster in the patch and rebuilds the faction map. None of that is what makes a
flight move — each track carries its own window and the panel places it from `_flight_year`,
which its own `_process` advances every frame. So it is throttled to `UI_REFRESH_SEC` like the
panel refresh beside it, with a **separate** accumulator so a star-map rebuild and a BuildPanel
rebuild need not land on the same frame.

| at 4 000 colonies | ms/frame |
|---|---|
| before | **80.8** |
| conditional bump only | 50.8 |
| + throttled push | **15.0** |

`verify_flight_refresh` pins the part that matters: not "stop bumping", but bump *when it means
something*. A push that changes nothing leaves the version alone; settling a star, a faction
appearing, and a **same-size swap** all still move it. The swap is the case the version exists
for and the counts cannot see.

### Turning: the other half of that sentence

"A map is read far more than it is turned" was true and was also an excuse. Turning still cost
**60 ms a frame — 16 fps** — because the cache key holds `_zoom`, `_yaw` and `_pitch`, so every
frame of a drag threw the whole thing away and rebuilt it. Profiled per section at 6 060 stars
and 8 401 clusters:

| turning, per frame | | |
|---|---|---|
| star rebuild | 32.4 ms | |
| cluster rebuild | 23.7 ms | |
| everything else | 4.1 ms | unchanged from a still frame |

The drawing was never the problem and the point count was never the problem. The field already
goes out as **one** batched `draw_multiline_colors`, which measures 0.7 ms; a still frame costs
4.4 ms in total. The 56 ms was GDScript, and two measurements said what kind:

- Truncating the star loop after its first half — the part before anything is transformed — cost
  12.0 ms of the 32.4. **A third of the loop was recomputing values that cannot change when the
  camera turns.**
- A synthetic loop doing nothing but project, cull and append over the same stars cost 5.5 ms.
  So of the 32.4, only ~5 was the projection; the rest was overhead around it.

And one number explained the shape of it: **6 059 of 6 060 stars survived the cheap culls and
were projected, and 607 landed on screen.** The distance and detail-band tests were discarding
one star in six thousand, so essentially the whole catalogue paid full price every frame.

**So each pass is split in two.** An inner cache (`_sv_*` for stars, `_cv_*` for clusters) keyed
on the catalogue, the frame origin, the selection, who holds what and the filters — *not* on
zoom, yaw, pitch or panel size — holding `_rel(pos)`, the distance, `_display_radius`, the
resolved status colour and the tier flags in parallel `Packed*` arrays. The outer cache is
unchanged and still keyed on the camera; its rebuild now only runs the detail band, the
projection, the screen cull and the tier choice.

What that moved off a turning frame, per point: a `sqrt` for the distance, `_rel`'s three dot
products plus a `sqrt` and a `log`, `_display_radius`'s `log`, and — the one that does not look
expensive until you read it — `_status_color_of`, which is a **linear scan of `STAR_CLASSES`
comparing strings**, run twice per star because `_star_shown` scans it again. A useful
consequence of caching the tier: a star past `STATUS_COLOR_LY` is known to be a bare status
point from its distance alone, so it never reaches `_star_state()` or `_star_screen_radius()`.

**Then the frame constants.** `_project` and `_detail_alpha` were called once per point — fifteen
thousand times a frame — and both re-derived the same handful of frame-fixed numbers on every
call. `_persp` is the worst of them: it recomputes the view radius (itself a call), the camera
distance and the near plane per point, for three values that are constant for the whole frame.
Hoisting those out of the loops and writing the arithmetic **inline** was worth more than the
cache split:

| turning, per frame | original | split caches | + hoisted and inlined |
|---|---|---|---|
| star rebuild | 32.4 ms | 11.5 ms | **5.1 ms** |
| cluster rebuild | 23.7 ms | 13.1 ms | **4.7 ms** |
| **total** | **60.2 ms** | 28.8 ms | **13.8 ms** |
| | *16 fps* | *35 fps* | ***72 fps*** |

Inlining a formula in two places is a real hazard, and `verify_starmap_project` is the price of
admission: `_project` and `_detail_alpha` remain the definition of record, every other caller
still goes through them, and the test compares the inlined arithmetic against both across five
views and 635 points. A y-sign flip or a dropped near-plane clamp fails it by tens of thousands
of pixels.

Its tolerances are split on purpose. Held to 0.001 px everywhere, it **failed by 64 px** — on a
synthetic test point projecting to a coordinate of 773 187 520, where that is a relative error of
8e-8 and nothing but single-precision rounding. Real catalogue positions agree to ~1e-4 px. So
anything that could actually be drawn is held to a hundredth of a pixel, and the absurd-depth
cases — which exist to exercise the near-plane clamp, and do catch its removal — are held to a
relative tolerance instead.

**One trade accepted.** The cluster loop used to test the detail band *before* calling `_rel`,
which its comment says "buys a third of a rebuild at a deep zoom". The inner cache transforms all
8 401 regardless, so recentring is marginally dearer than it was — but that runs when Sol moves
and the outer loop runs sixty times a second. The band test still comes first in the outer loop,
so the *projection* is still skipped at a deep zoom.

What is left on a turning frame is 1.8 ms of rings, galaxies and landmarks and 1.4 ms of the
per-star overlay loop, both of which a still frame pays too.

**Two ways this can go silently wrong**, both covered by `verify_starmap_cache`:

- **Who-holds-what enters the key as counts.** A colony swapped for another at the same count
  would be missed, which secession makes an ordinary event rather than a theoretical one.
  `_marked_version` is bumped by both pushes that can cause it. Without it the test fails with
  the colony marker still sitting on the old star.
- **The holder arrays are indexed by catalogue position**, and `all_stars()` filters the
  procedural field by *live* distance from Sol — so a travelling star rebuilds the catalogue,
  dropping some stars and gaining others, and can come out the same length. Length is therefore
  not enough: they are also keyed on `catalogue_version()`, which the catalogue already bumped
  on every rebuild for `_refresh_lod_cuts`.

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

**The belt's lanes were a second copy of this, and kept both faults.** A planet's structures
circle the planet; the belt's circle the **Sun**, out among the rocks on their own heliocentric
lanes, so `asteroid_belt.gd` builds its own per-instance transforms — and when the two faults
above were fixed in `planet.gd` the belt went on drawing every structure mirrored and
world-referenced. The whole belt was shaded from the inside: sun-facing hulls came out black
(measured at 11/255 against 136/255 after the fix, same frame, same light).

The belt now goes through `Planet.infra_orientation()` like everything else, with the plane
normal from `AsteroidBelt.infra_plane_normal()`. Its lanes *look* like a vertical bob about the
ecliptic rather than a tilted orbit — `y = r·sin(th − node)·sin(incl)` — but that expands to
`sin(incl)·(x·cos(node) − z·sin(node))`, linear in x and z, so each lane is a planar curve with a
constant normal after all: its angular momentum, `(−sin(incl)·cos(node), 1, sin(incl)·sin(node))`.
That sign, and not its opposite, is the one that leaves a structure facing the way it travels.

**The bug is not reachable through the MultiMesh it feeds.** A headless run has no renderer:
`MultiMesh.set_instance_transform()` keeps nothing and `get_instance_transform()` hands back the
identity, so an assertion that stands structures up and reads their transforms back passes
whatever the maths does. That is why the orientation is a named static function instead of four
lines inside the draw loop — `verify_infra_band` checks `infra_orientation()` directly: over 72
directions for determinant, radial +Y and orthonormality, and around every lane's full orbit at
0.5° resolution for continuity. Both checks were confirmed to fail with their respective bugs put
back — the first version of the handedness check read the transforms back off the lanes and
passed either way.

The belt is checked through `AsteroidBelt.infra_transform()`, which is the whole of what its draw
loop calls, for the same reason: all 21 lanes swept at 1° resolution for determinant, radial +Y,
orthonormality, continuity, that the frame lies flat in its lane's plane, and that the sideways
axis runs *with* the motion rather than against it. Put the old four lines back and the first and
last of those fail (determinant −1, along-track −1); hand it a plausible normal that ignores the
lane's node and the along-track and flatness checks fail.

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

### Everything is lit by the sun, and only by the sun

The scene carried an ambient fill of 0.4 and a faint self-emission on almost every material —
orbital structures, moons, asteroids, Dyson collectors — each justified as keeping a small dark
body readable where no light reached it. Together they meant **nothing on screen was ever
actually dark**: there was no night side anywhere in the system.

Ambient is now 0 and the emissions are gone. The one `OmniLight3D` at the sun is the whole of
the lighting. The sun keeps its own emission, because it is the light source, and the
disassembly shader keeps its `heat` term, because a planet glowing from its own exposed mantle
is real incandescence rather than fill. The Shkadov sail briefly made a third — standing on the
photosphere it runs near 1300 K and really would glow — and does not any more: it is a
silhouette against the star, which is what the rule says and what it would be.

Measured by sweeping the camera around a planet and summing frame luminance: **0.0 at 135°, 180°
and 225°**, full brightness sunward.

**The sun emits from its surface, not from a point at its centre.** One light at the centre of a
body of radius 2.35 is lighting the system from inside the star, and a point source lights
exactly half of everything with a hard terminator at 90° — identical at Neptune and hanging just
off the photosphere, which is the one place it is most wrong.

Godot has no sphere area light for diffuse. `OmniLight3D.light_size` widens only *shadow*
penumbra, and shadows are off here (an omni shadow at `omni_range = 4096` is a system-sized
cubemap). So the extent is built out of lights: `SUN_LIGHT_COUNT` of them on the photosphere at
the octahedral axes, each carrying a sixth of the energy, sized from the sun's own mesh so the
two cannot disagree. The scene's central light is freed rather than left as a seventh source.

**Measured, because the honest size of this is small.** A probe sphere just outside the
photosphere has a lit share of 0.262 under a point source and 0.268 under the shell; at Earth
the brightness profiles are identical to within noise. Both are correct. The wrap region is lit
by one or two of the six at grazing incidence, so it is a dim penumbra rather than a bright
extension — which is what a sphere source does — and at Earth the sun's angular radius is 6°, so
there is nothing to see. This is a correctness fix, not a visual transformation.

Two things that looked like faults and were not:

- **The first render came back black everywhere.** The camera pivot had put the camera on
  Earth's night side, which is now genuinely dark. The light reaches Earth comfortably — 21.9
  units against a range of 4096 with no falloff.
- **The `OmniLight3D` looked misplaced.** The scene file has the sun at (-3.64, -0.12, 0.01)
  while the light sits at `WorldRoot` origin, which reads as lighting the system from a point
  beside the sun. At runtime both are at the origin — the scene transform is overridden — so a
  function written to "fix" it was deleted rather than shipped with a comment asserting
  something false.

`verify_lane_models` has now had its material contract change twice in one session, and both
prior versions are recorded in its header: the lane colour as flat emission (which made a laser
dish uniformly pink whatever its map said), then emission routed through the albedo map (which
fixed the colour and left the real problem untouched).

### What makes an engineered plague likely

The old model was `base x (1 + 0.4·biotech_nodes) x (1 + 2·ai) x (2 / (1 + worlds)) x (BASE_LE /
le)`, and four things were wrong with it:

- **The colony count divided the odds, and `_trigger_pandemic` was already dividing the toll by
  it.** At five worlds that is 0.33 × 0.2 — expected losses fell about fifteenfold for settling
  the system. The direction was wrong anyway: more settled worlds, trading and travelling, is
  more coupling between reservoirs, not less. Colonies blunt the **toll**; they do not make an
  outbreak less likely.
- **Population never appeared.** Two billion and twenty billion gave identical odds, in a game
  that tracks people one at a time and models what a world can hold.
- **Life expectancy stood in for public health**, but `le` here is driven by the longevity
  splice — so engineering people to live longer made them less likely to catch a plague.
- **A count of unlocked research nodes never falls.** A civilisation that learned bioengineering
  a thousand years ago and stopped was as exposed as one editing genomes this year.

Now, over the solar system — which is where a plague spreads, since `_trigger_pandemic` reaches
Earth and the in-system colonies and leaves the interstellar ones alone:

| term | from | at |
|---|---|---|
| `editing` | splices running **now** (`st["splice"]`) | 7.9% baseline |
| `uniformity` | population-weighted `diversity_of()` | **16.6%** on minimal founders |
| `crowding` | `pop / _world_capacity` | 15.6% at 4× population |
| `traffic` | `active_launches` | 19.0% with 40 flights up |
| `surveillance` | `track_compute("pandemic")` | −20%+ fully allocated |

`uniformity` is the largest term on purpose: it is the one the rest of the game has been
building toward. A population spliced into one optimised genome is a monoculture, and the
founding-stock choice — until now a trade of launch mass against capability — is also a bet
about disease.

`surveillance` is the lever the UI already implied. The compute slider labelled "Epidemiological
modelling" bought foresight and nothing else: the player could watch an outbreak coming and do
nothing about it. It saturates, so pointing everything at it never reaches zero.

**`PANDEMIC_BASE` moved 0.03 → 0.017.** The new terms multiply to about 1.8 for an ordinary
standard-diversity civilisation, so holding the old base would have doubled the rate as a side
effect of a rewrite that was not supposed to change how often this happens. 0.017 puts that
civilisation back where it was; everything above it is the player's own doing.

### Alignment, and the fourth way a run ends

`ai_investment` was the strongest compute lever in the game and a one-way ratchet. Autonomy was
a pure function of the sliders, so it had no memory — set one back and the risk vanished the
same year — and `existential_risk` was `autonomy x 0.6`, a number that could not be driven to
zero and fed nothing but a happiness penalty and the pandemic odds. The three catastrophes were
an asteroid, a plague and a war, so the quantity the game is named after could not end a run.
The player took the slider to 100 because compute is the win condition, watched the figure
climb, and there was never anything on the other end of the decision.

**Two stocks, both ratchets.** Capability and understanding are not settings:

| | moves | falls |
|---|---|---|
| `_ai_capability` | closes `AI_CLOSE_RATE` of the distance to `PoliticsData.ai_autonomy(policies)` each check | never |
| `_ai_understood` | gains `AI_ALIGN_GAIN x` the alignment slider each check | never |

Capability that exists does not stop existing when the budget is cut, and understanding once had
is kept. `AI_ALIGN_GAIN` is deliberately the slower of the two: at equal budgets capability
outruns understanding, so **racing ahead is the default and catching up is the work**. Four
checks (~200 years at the mean gap) take capability most of the way to whatever is being asked
for; a full alignment budget needs about thirteen to cover it.

**The exposure is the gap**, and the per-check probability is that gap squared above a floor —
convex, so the difference between a small gap and a slightly larger one is small and the
difference between a large one and a slightly larger one is not. Level, the probability is
**exactly zero and stays there**.

Both of those matter for the same reason: a run reaches 10¹⁰⁰ years and this is checked every
20–80, so **any** non-zero per-check probability is a certainty given enough checks. That is
why the floor sits above the autonomy the *default* policy asks for — at 0.20 a civilisation
that never touched the AI sliders had a 61% chance of ending this way inside 100 000 years and
none at all of surviving a million, which is not a risk the player chose. Leaving the page
alone is exactly safe; the exposure starts where the deliberate investment does, and closing
it again is what alignment buys.

**Alignment is paid for in compute** — `compute_mult` loses up to 30% — and it does **not**
reduce `ai_autonomy`. Safety work does not make a system less capable; it makes it better
understood. Subtracting it from capability would have made the slider a way to un-build what was
built, which is the thing the whole model exists to deny.

**The politics page shows both numbers**: `72% → 0%`, where it is now and where the settings
take it. The stocks walk towards a setting over centuries, so a page showing only the settled
figure would report a slider as having already worked — and the lag between moving it and the
stock answering is the whole of the decision. Game pushes `ai_exposure()` into the page from the
throttled UI pass; `PoliticsData.existential_risk` is the settled figure and says so.

**It is the one ending that holdings do not blunt.** A war is fought between Earth powers, an
impactor hits one world, a plague crosses on traffic — every other threat in this game is
survived by being somewhere else, and that is deliberately the shape of them. A system that
improves itself has no blast radius to be outside of, so a civilisation across a hundred stars
ends exactly as one on Earth does. `verify_ai_runaway` asserts it with three settled stars on
the roster, because the temptation to make this work like the other three is the temptation to
give every risk in the game the same answer.

There is **no forecast track** for it either, where the other three each have one. A projection
of a system built to be better at projecting than its makers is not a thing the civilisation
gets to have. The warning is the risk row on the politics page, which is driven by the player's
own settings and visible from the first year.

The ending empties the roster before `trigger_game_over`, because the extinction screen reads
live state for its final figures and a headcount of two trillion under that header is a
contradiction. `_last_catastrophe` is recorded on the way out so the run record names it
(`no_mouth`, after Harlan Ellison).

### A colony's probes are built with a colony's star

`_vn_launch` charged `ResearchTree.resources["energy"]` whoever launched — so a probe assembled
four hundred light-years out, by a colony that may already have declared for itself, came out of
Sol's reserve in the same instant it left. The line directly below the charge already knew
better: it records `from_star` precisely because *"a replicated probe leaves the colony that
built it, which is halfway across the map from Sol"*.

**The audit is the useful part, because the gap was much smaller than it had been described as.**
Of the twenty-odd places energy is spent, every other one is the player acting from the solar
system — a launch, a laser, a message, a trade's freight, orbital defence — and those correctly
bill the home grid. Production was already solar-only, because an interstellar colony has no
`planet_buildings` entry to contribute one. One branch, not a system rewrite.

**And it was never a brake.** A probe costs 16.2 MJ against a starting energy *storage cap* of
301 TJ: eighteen million probes, before the research that makes any of it reachable. What paces
replication is `_vn_work_queue`'s round-robin and time budget, which this does not touch. So this
is a correctness fix and not a rebalance — stated in `verify_energy_locality`, because removing a
cost invites the question of what it was holding back and the answer is nothing.

Nothing is charged to the colony in its place, deliberately: a colony's economy is already an
abstraction over its age, and an energy ledger per colony would be fifteen thousand new entries
modelling something no mechanic reads.

**A regression this uncovered.** `_on_vn_probe_requested` builds its mission itself and never
calls `_vn_launch`, so moving the `we_are_bob` hook into `_vn_launch` had quietly stopped the
probe the player sends *by hand* — the one the achievement is named for — from earning it. Both
paths grant it now; `grant_achievement` is idempotent.

### Interstellar flights fail

The interstellar medium is not empty: roughly one hydrogen atom per cubic centimetre and a dust
grain now and then. A hull crossing it sweeps that up, and every grain arrives carrying
(γ−1)mc² — at γ=4 a microgram grain lands with the energy of a hand grenade, and the ship has no
warning because it is arriving very nearly with its own light. So the hazard is linear in the
distance swept and in the energy per impact, which is where the (γ−1) comes from.

| | loss |
|---|---|
| 4.4 ly at γ=4 *(Alpha Centauri)* | 0.9% |
| 50 ly at γ=4 | 8.8% |
| 250 ly at γ=4 *(`VN_HOP_LIMIT_LY`)* | **37%** |
| 250 ly at γ=1.5 *(the slow boat)* | 7.4% |
| 10 ly at γ=70 *(top of the slider, next door)* | 34% |

**The speed slider is the point.** It was a trade of energy against travel time; it is now a
trade against arriving at all, and the cheap slow crossing is the safe one. The swarm absorbs its
losses by numbers — two probes a colony, so a third failing slows the frontier rather than
stopping it.

**`loss_chance` lives in `StarMapPanel` beside `plan_flight`, not in Game**, because the launch
dialog has to quote it. That was not the original plan: the first version put the model in Game,
and a test assertion that "nothing is a guaranteed loss" failed — correctly, a 2 000 ly crossing
at γ=60 is hopeless. The model was right and the assertion was wrong, but it exposed the real
hole: a hopeless flight gave no warning. A risk the player cannot see before committing is a
trap rather than a decision, so the dialog quotes the figure Game then rolls against.

**Rolled once, at launch, recorded on the mission.** Two reasons that are not interchangeable:
the outcome has to survive a save, and a per-tick roll would turn a long flight from a risk into
a certainty.

**The player is told nothing until the silence.** The craft is drawn on its projected course for
the whole crossing, because that is what is believed — the same rule the lagged colony reports
follow. There is no telemetry to receive. The expected arrival passes and the sky stays quiet,
and that is the entire observation. A craft the player sent by hand is reported overdue; a
replicated probe's loss is silent, for the reason the swarm's arrivals already are.

### The ending says what ended it

The three catastrophes have no ending of their own. An asteroid, a plague and a nuclear war each
kill a great many people, and the run ends later when there is nobody left — under one cause,
with one description. So all three produced the same six words: *"No humans remain on any
world."*

`_last_catastrophe` records what landed and when; `_collapse_ending()` names it. The **interval**
is reported rather than elided, because a collapse three centuries after a war is a different
fact from one in the same year and stating the number is the whole of the difference. An
unrecognised kind falls back to the plain cause rather than producing a blank header.

**One place owns the window.** `_recent_catastrophe()` is asked by both the extinction screen and
the achievement, so the two cannot drift into naming a war on one and not the other.

`_last_catastrophe` is **saved**, which reverses an earlier decision. It was left out as "a few
years of context, not run state" while only an achievement read it; the screen reads it now, and
a run reloaded from the wrong side of a war would have ended unable to say there had been one.

**The test gap this exposed is the general one.** The first version of `verify_ending_cause`
exercised `_collapse_ending()` directly and never checked that the collapse site *calls* it —
reverting the trigger to its old hard-coded cause passed every assertion. It now drives a real
collapse and reads what the screen was given. Two things about the population model make that
harder than it looks, and both are worth knowing:

- Zeroing `world_pop` does not empty the galaxy. A world left in the roster at zero people still
  has a carrying capacity and grows back out of it — the population bottoms out near a million
  and climbs. The roster has to be **emptied**.
- One tick is not enough. The headcount is delta-tracked and only published whole when a
  population cycle closes, so a single call leaves the previous total standing.

### The run record

`Game.run_summary()` returns `[[label, value], …]`; the ending screen and the records page both
render it, and `run_summary_text()` is the same thing for the clipboard — two runs get compared
by someone pasting them side by side, which is the whole reason the peaks are kept.

**Peaks, not final state, and that was already settled.** `game_over_screen._build_stats_text`
had worked it out and said so: the final population and colony count are *"deliberately
absent"*, because at the end they are both zero. A run that held six thousand stars for a
billion years and one that never left Earth finish identically, so the last moment cannot tell
them apart. The high-water marks are therefore kept **as they happen** — the stats graph is
downsampled and the year a record was set is not recoverable from it afterwards. Four compares
on the year tick, nothing walked.

`stars_at_front` is the figure the whole rival-front feature exists to produce: how much of the
galaxy was yours when somebody else's probes turned up. Captured the year the front's light
**arrives**, not the year it started — what the player had when they found out is what they can
be held to — and never moved again. It defaults to `-1`, not `0`, because "the front was never
seen" and "it arrived before we had anything" are different facts.

**Rows are omitted rather than zeroed.** A run that never met the front and a run that lost
everything to it are different runs, and a table of blanks reads as a form. The consequence is
that two summaries are not always the same shape, which is correct: they are records of
different runs.

**The voice is the constraint, not decoration.** VOICE.md: the game reports, it does not
narrate. There is no "you held" and no closing sentence, because a summary that told the player
what their run amounted to would be making the conclusion for them. `verify_run_record` asserts
the absence of second person and of the banned editorial vocabulary, which is the only part of a
voice guide a test can hold.

`_build_stats_text` and its two formatters were deleted: both of its lines are now rows.

### Achievements

`achievements.gd` holds the table; `Game.achievements_earned` maps id → **the year it was
earned**, not a flag, so a run summary can say when. One schema row saves it.

**Granted two ways, and which one a given achievement gets is not arbitrary.** Anything with a
MOMENT is hooked at that moment, because the moment is the only place the fact exists — by the
next tick a seceded colony is simply gone and there is nothing left to notice. Anything that is
a THRESHOLD on state the game already keeps is swept once a year instead, on **both** clocks:
fast mode is where a run actually crosses the deep-time thresholds, and an achievement only the
day clock could grant would be unreachable in the era it is about.

The sweep deliberately touches no per-colony state. The roster is fifteen thousand entries, so
anything about colonies is granted where a colony changes instead — and the trait achievements
are checked where a splice lands rather than by walking every stock record a year.

**Three hooks were placed wrong first, and each was wrong in an instructive way.**

- `harsh_mistress` went on `_announce("A state breaks away")`, which is inside `_spread_aliens`
  and fires when an **alien** polity fragments. A player achievement wired to an alien event.
- Moving it raised the real question. Granting it when the colony secedes would announce the
  news the instant it happened — which is the one thing the light-lag exists to withhold. It now
  fires when the post arrives, in `_tick_colony_news`, and `no_reply` with it when that news is
  `ACH_LATE_NEWS_YEARS` stale.
- `we_are_bob` went on the probe announcement, which only covers the probe the **player** sends;
  a replicating swarm launches thousands through `_vn_launch` without one. It is now at the point
  in `_vn_launch` past which no launch can be refused.

**The endings needed a memory.** Every ending goes through `trigger_game_over`, but the three
catastrophes have no ending of their own — they kill people and the run ends as "Population
collapse" — so the cause cannot be named unless something remembers it. `_last_catastrophe`
records what landed and when, and the ending is only blamed on it within
`ACH_CATASTROPHE_WINDOW_YEARS`. It is deliberately not saved: it is a few years of context for
an ending, not run state.

**The page lists what has NOT been earned, except the failures.** The milestone groups are the
only place the game says out loud what it expects you to do, and a player opening the page in
their first minute should come away knowing that settling the system, replicating, enclosing a
star and taking a planet apart are all things that happen here. The failures are hidden until
earned, their group is omitted entirely while empty, and they are left out of the `N of M` count
— otherwise the total quietly tells the player how many ways there are to lose.

**A GDScript trap worth recording:** `-1 << 40` as a "never happened" sentinel is a *parse
error* — negative operands to `<<` are rejected. And because a parse error aborts `_run` before
`quit()`, the suite reports it as a bare `TIMEOUT` with no diagnosis. Two tests timed out before
the cause was found by loading `Game.gd` directly. Relatedly: piping Godot's output through
`grep` loses everything when the process is killed, so a hang must be captured to a file.

**The top bar reports the solar system, not the galaxy.** Three of the four readouts always did,
by accident of where they come from: Matter, Energy and Heat are summed off `planet_buildings`,
and an interstellar colony has no entry there — its infrastructure is the abstracted
`_colony_infra_at`, and what it mines goes into its own stores to be traded for
(`_advance_colony_economy`). Compute did not, because it is driven by population and
`_pop_weighted_compute` walks every world. Measured: forty colonies multiplied the figure driving
research by **139**, and a late-game roster is thousands — the solar system's own contribution
rounds to nothing against them.

That contradicted the rest of the design rather than merely inflating a number. The light-lag
that makes a colony ungovernable — every order describes a four-hundred-year-old situation — also
means it cannot be thinking for you now. So `_pop_weighted_compute_sol` accumulates the same
stock-weighted sum restricted to the solar system, keyed off the `is_star` flag the population
loop already has in hand, and `_combine_production` reads that. The galaxy-wide sum is still
kept; it is a real number, just not this one.

**The consequence is real and intended: late-game research now runs on the solar system's minds.**
A civilisation that wants more thinking has to build it where it lives, or trade for what the
frontier makes.

`verify_solar_pool` asserts both directions, and the second one is the point — an in-system colony
must still count, or "exclude the colonies" would have been a blanket exclusion that passed every
other assertion. Getting that assertion to mean anything took two tries: Earth grows by about nine
million people over the test's sixty ticks and Mars only holds six, so a before/after comparison
of the solar sum is satisfied by Earth alone. It now measures the sum **minus Earth's own people**
against what Mars actually holds.

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

### One palette, and it is the statistics and politics pages'

There was no theme resource and no palette. Every page picked its colours at the point of use, so
the same thing was spelled a different way on every page. A dim explanatory line was written
eleven ways — `0.62,0.62,0.70` · `0.62,0.68,0.80` · `0.65,0.65,0.72` · `0.68,0.72,0.78` ·
`0.70,0.72,0.78` · `0.70,0.75,0.85` · `0.72,0.76,0.84` · `0.74,0.78,0.88` · `0.75,0.75,0.75` ·
`0.60,0.66,0.76` · `0.6,0.6,0.66` — a good reading six ways, a bad one seven, and several of
those differences are below what anyone could see anyway. None of them meant anything: no page
chose its grey to say something another page's grey did not.

`UIPalette` is the whole set, and the values are not new. They are the ones the **statistics and
politics pages** were already using, which is where the look everything else is being brought to
came from; the roles are named after what those two pages use them *for*, so a page that needs
"the colour of an explanatory line" asks for `DIM` instead of inventing a grey. Three surfaces
(`SURFACE`, `RAISED`, `BORDER`), six weights of text (`TITLE`, `VALUE`, `TEXT`, `HEADER`, `DIM`,
`DISABLED`), four readings (`GOOD`, `WARN`, `BAD`, `NEUTRAL`), and the statistics page's seven
series colours, so that a resource is the same colour wherever it is named — science was green on
the graph, one blue in the research tree, another in the build panel and a third on the timeline.

The amber is the one role the reference pages had no reading for, so it is taken from the
statistics page's compute series: `WARN` and `COMPUTE` are deliberately the same colour, and
`verify_menu_palette` allows that one pair and no other.

**Colour that carries meaning is not in it.** A star's spectral class, a world's crust and mantle,
a compound, a polity's banner, the category hues in `BuildingData`, `PoliticsData` and
`GameEvents` — those are data about the thing being drawn, not the colour of the window it is
drawn in. The test's `DATA` list names the scripts that hold them; everything else in the project
is swept for spelled-out colours, and a greyscale literal is allowed through as what it is, an
opacity rather than a hue.

Three things had to happen, and the third is the one that looked like success while doing nothing.

- **The pages.** `Game._restyle_menu_panels()` paints every menu panel `SURFACE` with a `BORDER`
  outline. Only the colours and the corners are written: `UIPalette.repaint()` reads the content
  margins off the theme's stylebox and writes them back, because those margins are what space a
  panel's children and a fresh `StyleBoxFlat` has none. The planet panel's six tab pages are
  given a **clear** fill instead — each covers the wrapper's content area exactly, so painted
  they hid the wrapper's outline behind themselves and bordered they would have drawn that
  outline six times, once per tab. The wrapper's frame is split across two styleboxes so it goes
  round the whole thing: the tab strip carries the top, left and right, the page below it carries
  the left, right and bottom, and the seam where they meet is the one edge neither draws, so the
  open tab joins to its page across it.
- **The controls.** Everything nobody had styled by hand — every button, dropdown, text field,
  list, slider, scrollbar, popup and dialog — was drawn in Godot's **default** theme: translucent
  neutral greys. On a navy UI those read as grey-brown boxes you could see the solar system
  through, and there are far more of them than there are hand-styled labels. `UIPalette.theme()`
  builds one `Theme` from the palette, and every box in it is a **recoloured duplicate** of the
  default theme's, so the margins, border widths and sizes that lay the controls out are exactly
  what they were. Two surfaces do nearly all of it: `RAISED` for a thing you press, `SURFACE` for
  a thing you type in or read a list out of, with a faint edge so it is visible on a page of the
  same colour.
- **Getting the theme to them.** A theme flows down the **Control** tree. The whole game UI hangs
  off `CanvasLayer`s, and a `CanvasLayer` is not a Control, so it cuts that chain: a theme set on
  the root `Window` reaches a Control parented straight to the window and nothing else — measured,
  not assumed. `GameSession` sets it on the root *and* hooks `node_added`, giving the theme to
  each Control whose parent is not a Control; everything inside such an island inherits as usual.
  Hooking the signal rather than sweeping once means a dialog built later — the save dialog, the
  encyclopedia, a trade offer — is dressed on the way in instead of having to remember to ask.
  Godot has no runtime setter for the project theme, which is the only thing that would have made
  this unnecessary.

Four views still paint their own background in `_draw` rather than carrying a panel: the star map,
the galaxy map, the galaxy debug grid and the evolution tree. Their fills come from `UIPalette`
too, except the star map's, which is deliberately **black** — it is a view of the sky. The test
pins that list, so a page that paints nothing at all shows up as a new name rather than as a hole.

Two colours in the game are not the palette's, both on the extinction screen: the header red and
the cause orange. `UIPalette.BAD` is the colour of a reading going the wrong way, which is not
what that is — it is the end of the run, and the one moment the UI is allowed to raise its voice.

**The statistics page's own legend was inverted**, which only showed up once everything else had
been brought onto it. The seven toggles start pressed, and `font_pressed_color` was white while
`font_color` was the series colour — so every button started white, the legend was blank, and a
line's colour appeared exactly when that line was switched *off* the graph and no longer drawn.
The two are the other way round now, with a series that is off reading `DISABLED`.

### The chrome: the frame, and the four readouts

**The light-blue border only ever showed two of its eight edges.** The top bar and the sidebar
button strip are plain containers that cannot take a background, so each is drawn over an opaque
backing `Panel` whose `StyleBoxFlat` supplies both the fill and the outline. A `StyleBoxFlat`
draws its border at the panel's **own** edges — so growing a bar's rect by the 6 × 4 backing
margin, which is what gives the content breathing room, moved those edges off the screen. Both
bars sit flush against the window: the top bar spans the full width at y = 0, the sidebar runs
down x = 0. What was left visible was the top bar's bottom border and the sidebar's right
border, which read as two lines across the middle of the screen rather than an outline around
anything.

Two things were needed and the first alone is a trap.

- **Clamp the backing to the viewport** (`_fit_bar_bg`). Pull the edge back on screen and the
  border comes with it, because the border is drawn at the edge.
- **Inset the bar stack by the same margin.** After clamping, the top bar's left border measured
  *0%* visible: `TimeBox` is a `PanelContainer` painting its own opaque stylebox flush at x = 0,
  directly over a 1px border at x = 0. The sidebar's left edge was 76% — the gaps are between
  buttons. So `VBoxContainer3` is inset by `BAR_BG_PAD` on the **left and top**, which is where
  the bars are flush and their children paint. Right and bottom are left alone deliberately: the
  top bar's children are left-aligned and the sidebar's buttons stop well short of the bottom,
  so the backing is all that paints there and those borders were already clear.

The seam needs nothing. The sidebar's backing still reaches up into the top bar's and draws its
top border there, but the top bar's backing is opaque and drawn after it — both were moved to
index 0, which left the top bar second and therefore on top — so the line is covered and the two
read as one L of chrome sharing a single edge.

Three things are measured off each other rather than set twice, because a pair of constants that
have to agree is a pair that will drift:

- **The corners are square** — the bars', and the menu panels' with them. A 4px radius on an
  edge flush with the window reads as a nick out of the frame, and a rounded page inside a square
  frame reads as two different UIs. The panels carry a backing three different ways: a plain
  `Control` with a `PanelBackground` behind it (square where it is built), a `PanelContainer`,
  and the planet panel's `TabContainer` — the last two take theirs from Godot's default theme,
  which rounds it by 3px. `Game._restyle_menu_panels()` overrides that per panel, on a
  *duplicate* of the stylebox (`UIPalette.repaint()`): the one the theme hands back is shared by
  every `PanelContainer` in the game, down to the row backings inside the pages, and squaring it
  in place would square all of them from whichever panel asked first. It sweeps the sidebar's
  own children rather than a list of names, so a page added later is square without anything
  being remembered. The same sweep is what paints them (see the palette, above).
- **A page MEETS the sidebar's border, on the same line.** The pages are siblings of the button
  strip in an HBox, so what separates them is the container's separation — 4px from the theme,
  while the strip's *backing*, which is the thing carrying the border, hangs `BAR_BG_PAD.x` = 6px
  further right. At 4 every page opened 2px inside the sidebar's outline and drew over the middle
  of it. At the overhang exactly it would start one pixel *past* that outline, which now that
  every page draws an outline of its own is two parallel lines a pixel apart. The separation is
  one less than the overhang, so a page's own left border lands on the sidebar's right border,
  and since the backings sit at index 0 the page is drawn over it: one line, in one colour. The
  menus touch the chrome rather than floating beside it.
- **Every page fills what is left of the window.** The compute and automation pages set a
  `custom_minimum_size` and no expand flag, so the HBox handed them their minimum — 620 and 820
  of a 1920 window — and they stopped two fifths of the way across. Invisible while the pages
  were translucent; once they were opaque navy it read as a panel that had failed to load. The
  minimum is a floor now and both expand, like every other page.
- **The sidebar's right border meets the clock's right edge.** They were 4px apart — close
  enough to read as a mistake rather than as two widths. The strip is sized from `TimeBox`'s
  measured rect so its *backing* lands on that edge, since the backing carries the border.
  Writing `custom_minimum_size` emits `resized`, which re-enters the layout pass, so it only
  writes a real change; otherwise the two bounce every frame.
- **The planet panel keeps one margin from the chrome on both sides** (`PLANET_PANEL_GAP`). Its
  top was a hard-coded 52, from when the bar ended there; the backing now reaches 58, so the
  panel had been starting four pixels *inside* the chrome. It is measured off the backing and
  re-measured each layout, and the panel's **height** is carried across the move — setting the
  top without the bottom silently shortens it once, permanently, which is the kind of loss a
  test comparing the height against itself can never see.
- **The launch panel rides the same line.** It carried the same stale 52 and is placed from the
  same measurement now (`_layout_menu_panels`). It opens against the same edge of the screen as
  the planet panel, and two panels sharing an edge six pixels out of step read as one of them
  having slipped. Only its top is written: its bottom is anchored to the window.

**The four resource readouts were panels that moved.** Each was a `PanelContainer`, so a bar that
is already a panel carried four more sunken boxes bolted onto it. They were added straight to the
top bar's HBox, so they packed against the speed buttons and left the right half of the bar
empty. And each was as wide as its text.

That last one is the same `Label` rule as the bullet above, in the place it does the most damage:
a `Label` reports a minimum size that fits its whole string and a container honours it, so
`9.4 TJ / 301.0 TJ` made Energy wider than its neighbours and **every** readout jumped sideways
when a figure crossed into another SI prefix. These are numbers that change constantly and change
width by nature, on a bar across the top of the screen.

So: a `MarginContainer` with no stylebox at all (the bar behind it is the surface); one
`ResourceRow` that expands, with all four sharing it at equal stretch ratios; and `clip_text` on
every label so the text is out of the minimum-size calculation entirely. The clock's spacer
became a fixed 16px gap — a second expander would have split the leftover space with the row and
reproduced the bunching.

`verify_top_bar_chrome` measures the rects. Worth knowing why it asserts the *minimum* sizes and
not only the laid-out widths: at 1920 wide an equal quarter of the row is ~478px, wider than
anything a figure can spell, so the boxes stay equal on expansion alone and the width assertions
cannot fail. It is on a narrow window, where the share drops below the text, that the minimum is
what decides — so that is what the test pins.

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

### Allegiance, and what you know about it

Two features that are one. A colony four hundred light-years out cannot be governed: every
order describes a four-hundred-year-old situation and every answer is four hundred years old on
arrival. An exchange is eight hundred years. What a distant colony has instead of a government
is a memory of one.

So **loyalty drifts at a rate proportional to distance** (`allegiance.gd`), and
`GOVERNABLE_LY_YEARS` sets the scale — a colony holds for roughly `GOVERNABLE_LY_YEARS /
dist_ly` years unattended:

| distance | unattended |
|---|---|
| 10 ly | ~200 000 yr — effectively permanent |
| 100 ly | ~20 000 yr |
| 500 ly | ~4 000 yr |
| 1 000 ly | ~2 000 yr — barely held |

**Divergence multiplies it.** `AllegianceData.divergence()` is the Jaccard distance over spliced
traits, so a population Earth has edited into something else has proportionally less reason to
take Earth's word for anything. That is where the trait system stops being an economic curiosity
and becomes a political fact: two unedited populations are the same people by definition, which
is the right answer for 1945.

**The lever is supply.** A consignment landing restores `CONSIGNMENT_GAIN`, which is what gives
the colony economy a purpose beyond the materials it moves — a civilisation that trades with its
frontier keeps it. Nothing here is a hard timer: a supplied colony never falls and an ignored one
always does, and the distance decides how much attention "not ignored" means.

**Secession is immediate in the simulation and late in the readout.** At zero loyalty the colony
leaves `colonized_stars` on that tick, stops producing and growing, and becomes a state of its
own through `Polities.splinter_of()` with humanity as the parent race — the same route an alien
polity that outgrew its own light-lag already took. Its **lineage goes with it**: `_world_stock`
is erased, so a world that spent 300 kyr working out a sequence nobody else has takes it along.
That is the real cost of letting a colony drift.

But the player does not know. `believed_colonies()` is `colonized_stars` **plus every colony
whose declaration has not reached Sol yet**, and that is what the star map is given — so a
system that stopped being yours two centuries ago is still drawn as yours, because that is still
the last thing anybody heard. The simulation is always truthful; the UI is lagged. The gap is the
feature.

**The post.** `_colony_news[star]` holds the report in hand (`at`/`pop`/`loyalty`/`gone`) and the
one still crossing (`tx`/…), both in one record because a late run holds fifteen thousand of
them. A colony broadcasts continuously, so the next sample is taken as soon as the last lands —
which makes the report between one and two light-crossings old, and its age is shown rather than
hidden ("as of 430 yr ago"). Advanced on a round-robin slice (`ALLEGIANCE_PER_TICK`) like the
economy and lineage passes.

**Deterministic things need no post.** `_colony_infra_at(star, obs_year)` grows the Dyson swarm,
telescopes and lasers from the founding year, so any past state can be computed without storing
it — exactly how `_alien_intel` has always lagged a neighbour's infrastructure. The player's own
colonies simply never used it, and now do: a frontier system is described as it looked when the
light left it.

### Somebody else's probes

The swarm is **exponential**. Every fixed-size antagonist in this game — a set number of
neighbours, an asteroid every few hundred thousand years, a salvo of missiles — becomes
proportionally smaller as it grows, and past a few thousand colonies none of them is a
consideration. A second self-replicating civilisation is the only opponent that stays the same
size relative to the player for ever, because it is running the same process.

The front itself is cheap: the galaxy is already a ~900-cell hex grid that saturates and
diffuses (`_update_regions`), and this is that automaton with one seed at the galactic centre.
**What did not exist was denial.** `_consider_target` asked only whether *we* had taken a star,
so a volume could be entirely somebody else's and the swarm would still fly into it. Now
whoever reaches a volume first holds it, both ways:

- the front's share of a cell is capped by `1 − _player_share(id)`
- `front_denies_pos()` rejects stars **and clusters** in cells past `DENIED_SHARE`

Which turns the swarm's greedy nearest-star rule from an invisible heuristic into a decision:
the nearest star stops being the right answer when the contested boundary is somewhere else.

**The rates are set from the crossing time, not picked.** Cells are 3 753 ly apart, so
`SPREAD_RATE = 2.5e-5` is one cell per 40 000 years — a front advancing at 0.094 c, which is
what a replicator that must decelerate, land, mine and build the next generation manages.
`CLAIM_RATE` is deliberately comparable, so a cell locks in ~50 000 years against 40 000 to
reach the next one and the contested band stays one or two cells deep. **That band is where the
game is**: faster and the front is a wall, slower and it never holds anything.

Sol sits ~26 000 ly out, which is about seven cells of runway:

| Setup | cells | solid | contested | nearest |
|---|---|---|---|---|
| Empty | 0 | — | — | — |
| Distant | 1 | 1 | 0 | 26 000 ly |
| Underway | 37 | 19 | 18 | 16 358 ly |
| Entrenched | 169 | 127 | 42 | 3 753 ly |

A head start is **filled, not simulated** — and as a *gradient*, since a cell `ring` out was
only reached `head − ring × YEARS_PER_CELL` years ago. One flat share made the whole radius a
wall; the gradient makes the interior solid and the frontier barely touched. `verify_vn_front`
asserts Sol's own cell is never denied at setup, because a head start that covered it would make
the run unplayable from the first frame.

**Its signature is light-delayed** like everybody else's, so a front seeded 26 000 ly away is
26 000 years old before Sol hears anything — and is already much nearer than where it appears.
That gap is the reveal, and it comes free from the rule already applied to alien signatures.

**`front_denies_pos` rejects on distance before it touches the hex grid.** `_region_id`
rotates into the galactic basis and rounds onto the lattice, and this is called for every
candidate star inside `_consider_target` — thousands of times per replication, tens of
replications a year. Added unguarded it took `verify_vn` from 189 s to 209 s against the suite's
240 s limit, and over it before the guard existed. Nothing nearer to Sol than the front's own
nearest cell, less a cell's reach, can be inside it; that is almost every candidate for almost
all of a run. The surrounding code defers its transforms for exactly this reason.

**`verify_vn` pins itself to an empty galaxy** (`setup = {"front": 0}`). Everything it measures
is how the swarm routes through unobstructed space — frontier distance, excess over the nearest
colony, whether an enclosed lineage retires — and a front taking the inner disk changes what is
being measured rather than testing it. `verify_vn_front` covers the interaction instead.

Four things that were wrong first time and are worth not repeating:

- `SPREAD_RATE` at `1e-3` was **3.75× lightspeed**, and a 200 000-year head start filled the
  whole galaxy including Sol's cell before the game began.
- The spread roll was salted on `front_year`, which never changes — so a cell either spread on
  its first tick or was frozen out of ever spreading. It is salted on `year`.
- `front_active()` tested `front_year >= 0.0`, and a head start puts the origin a long way BC.
  It seeded 883 cells and then reported no front. Hence `front_on` as its own flag.
- The denial went into the innermost targeting loop with no cheap rejection in front of it, and
  the only thing that caught it was a pre-existing test running out of time.

Advanced on a round-robin slice (`FRONT_PER_TICK`) like the economy, lineage and allegiance
passes: a full pass over 883 cells measured 2.5 ms, a quarter of the whole per-frame simulation
budget, for a process that moves on a clock of millennia. Sliced, 0.44 ms.

**Drawn as territory, under everything else.** `front_map_cells()` hands the panel POSITIONS and
shares, never hex ids — Game owns the region grid and the map has no business knowing what a hex
is. The marks go down before the clusters and stars, so a star inside the front still draws as a
star over the stain saying who holds the volume around it. Cached behind the same camera key the
star and cluster passes use, with the frame origin on the same movement tolerance.

**Solid is exactly what is closed.** A cell past `FrontData.DENIED_SHARE` draws in
`FRONT_HELD_COLOR` and is the same test `front_denies_pos()` applies, so the map cannot paint a
volume as takeable that the targeting refuses. Contested cells draw dimmer, and only alpha is
scaled per mark — which is what lets `verify_vn_front` assert every mark carries the rgb of one
constant or the other.

**An undetected front draws nothing.** `front_map_cells()` returns empty until `front_seen`, so
the first the player gets is the announcement; the stain appears afterwards. And it is a
galactic-scale object — the nearest cell is thousands of light-years out — so like the clusters
and galaxies it is only in band once the map is pulled back. At the default neighbourhood zoom
it is correctly culled, which the test asserts in both directions so the behaviour is recorded
rather than discovered.

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
12. **Nothing expensive goes in a default-argument position.** `Dictionary.get(key, default)`
	evaluates its default **eagerly**, present key or not. `_update_population` carried
	`stats.get("current_population", _total_population())` with a comment explaining that
	re-summing the roster for a bool had cost four milliseconds a tick — and it still did,
	every frame, because the call ran whether the key was there or not. At fifteen thousand
	colonies that was 15 of the tick's 17 ms spent computing a figure that was then discarded.
	An optimisation written as a default argument is not an optimisation. Branch it.
13. **One warning at a time.** `_check_incoming_attacks()` and `_check_asteroid_impact()` run
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
- **A stylebox can be right on a control that never draws it.** `get_theme_stylebox("panel")` on
  a plain `Control` returns an error-pink fallback rather than null, so an assertion about a
  page's background passes on a box nobody renders. `verify_menu_palette` reads the backing
  `Panel` where there is one, the control's own box where the control is a `PanelContainer`,
  `TabContainer` or `Panel`, and otherwise records the page as drawing itself.

Godot's string formatting has no `%e` or `%g`. Use `%f`, `str()` or `Units.format_si`.

New `class_name` scripts are not visible until the project is rescanned:
`godot --headless --path . --import`.
