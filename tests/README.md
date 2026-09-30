# Tests

Headless regression tests. There is no test framework: each file is a `SceneTree` script that
Godot runs with `--script`, and the harness is Godot itself.

```bash
tests/run.sh              # everything
tests/run.sh polities     # only tests whose name contains "polities"
GODOT=/path/to/godot tests/run.sh
```

A test loads `node_3d.tscn`, pokes `Game` directly, and prints `FAILS: n`. The runner reads that
line; anything else counts as not reporting.

## Writing one

Copy the preamble from any existing test. Four traps, each of which has cost real time:

- **A script error aborts `_run()` before `quit()`**, so the test hangs instead of failing. The
  runner's timeout turns that into a result — a test that "times out" is almost always a typo'd
  method name.
- **`class_name` types are unreachable** from a `--script` runner when the class depends on an
  autoload. Use `load("res://x.gd")`, or reach the node and call through it.
- **The harness runs at thousands of frames a second**, so `await process_frame` 150 times may be
  0.025 s of simulated time — nowhere near a 0.25 s UI throttle. Drive throttled code directly.
- **Godot's `String %` has no `%e` or `%g`.** Use `%f`, `str()`, or `Units.format_si`.

Two more that are specific to this game:

- **Pin the RNG before the scene loads.** `Game._ready` does `galaxy_seed = randi()`, so anything
  touching generated stars, polities or colonies is a coin toss unless the test calls
  `seed(20260927)` first. Several tests were intermittently red for exactly this reason.
- **An event card pauses the game and the tree.** A loop driving the simulation has to clear
  `SolarSystem.paused`, `SolarSystem.ui_paused` and `get_tree().paused` each iteration, or the
  thing being measured quietly stops. And a craft is moved by the satellite node's own
  `_process`, so the tree must really process frames — calling `Game._process()` by hand advances
  the simulation but never the craft.

`tests/fixtures/` holds real save files from earlier in development. They are regression
material: do not regenerate them, or the thing they test is gone.

## What each test covers

| Test | Covers |
|---|---|
| `regression.gd` | The pristine Sun against values captured before stellar engineering existed, plus a sweep of the systems each feature touched |
| `verify_fate.gd` | Fate regimes: giant branch above 0.5 M☉, helium dwarf below it, extinguished below 0.08 |
| `verify_shkadov.gd` | Thrust law, the published Class-A acceleration, aiming, drift milestones, save/load |
| `verify_speed.gd` | The speed ladder and its year-gated unlocks |
| `verify_chunks.gd` | Chunk determinism, the density law, the 6:4 standing:future split, the year filter |
| `verify_sky.gd` | The sky refills as Sol travels, thins with the density law, and empties to the catalogue outside the galaxy |
| `verify_polities.gd` | Races vs polities, name/temperament agreement, the setup's hostile count in polities |
| `verify_expansion.gd` | Alien colonisation extends existing states or splits them, never invents new ones |
| `verify_wars.gd` | Aggressive polities take systems from each other within reach |
| `verify_cluster.gd` | A cluster fills from 0% at the region rate off one probe, and announces once |
| `verify_valid.gd` | Body kinds and the mission target/arrival rules |
| `verify_station.gd` | The Orbital Construction Station, its capacity off-world, and the two carriers |
| `verify_delivery.gd` | A structure carrier charges its bill at the origin and is refused elsewhere |
| `verify_path.gd` | The carrier flies to its lane berth and never through the star |
| `verify_clusters.gd` | Clusters are not stars: alien-populated per the setup rules, no trade or alliance with a volume of space, missiles take random systems, berserkers sterilise a rising share |
| `verify_infra_band.gd` | Every solar-orbit structure sits inside Mercury's perihelion and clear of the Sun, and the orbital planes stay spread |
| `verify_compute_panel.gd` | The compute panel's slider drives the research/forecast split, is locked until the research lands, and the split survives a save |
| `verify_forecast.gd` | Compute buys foresight on a squared-cost curve, and what it predicts is what the simulation then actually does — target, year and severity |
| `verify_orbit_blur.gd` | Above 100× the bodies hide and their orbits draw as blurred rings; slowing down or pausing brings them back; the year alone no longer decides |
| `verify_starmap_panel.gd` | The star map's action panel stays bound 10 px in from the right edge at any map width, and wide content moves its left edge out rather than pushing its right edge off-screen |
| `verify_salvo.gd` | A salvo is one track on the map carrying its count, and lands as one event reporting that count truthfully; separate launches and weapons stay separate, and stacked labels stay legible |
| `verify_timeline_focus.gd` | A "Signature detected" card carries its star, invites a click, and takes the player to that star on the map — landing it on screen, clear of Sol |
| `verify_vn.gd` | Von Neumann probes propagate outward through the stars instead of saturating the bubble Earth's telescopes can resolve |
| `verify_sandbox.gd` | The generated sandbox save: full Dyson swarm, every star-capable structure present and research-open, and it settles instead of sliding |
| `verify_determinism.gd` | Reloading a save cannot re-roll a catastrophe: the rolls, and the death toll through the real event path, are identical across a differently-played replay |
| `audit_saveload.gd` | Save → wipe → load round trip across every mutated field |
| `audit_schema.gd` | The save file and `SaveSchema.FIELDS` agree both ways; every plain field survives a round trip; a nearly empty save still loads |
| `audit_oldsaves.gd` | Four genuine pre-table save files (29–64 keys, no version stamp) load and run |
| `audit_fastlaunch.gd` | In-system flights land on the fast-mode clock too, not only in day mode |
