# Crucible: code map (as of phase 8)

Where things are, so a new session can go straight to the right function instead of
grepping. Line numbers drift; names don't. Coordinates are cells: x across (0..255),
y down (0..1023), GROUND_Y 40. Resources index as [Stone, Glimmer, Obsidian, Water, Power].

## Files
- `scripts/game.gd` (~3500 lines): the game node. Sections, in order: Setup, Frame loop,
  Buildings, Machines, Movers, Links, Blasts, Network and packets, Research, The Crucible,
  Knowledge maps, Alerts, Camera, Input.
- `scripts/defs.gd`: every tunable and table: material ids, building tables (per-type
  arrays), PALETTE/keys, network ranges, power, machine numbers, Warren, collapse and
  Strut numbers, light and fog radii, TECHS, recipe, layers, hazards.
- `scripts/building.gd`: one placed structure (fields for every type; a Warren's mites,
  a Borer's trail, a Strut's anchors).
- `scripts/materials.gd`: loads data/materials.json into what the sim, game and shader
  use (kinds, dig rates, yields, palette image 256x4).
- `scripts/worldgen.gd`: bands, stone lumps, aquifers, glimmer veins, caves, pockets,
  lava lake, chamber, deposits (coal, sulfur), `_ground` (packed dirt, sand, gravel,
  clay), then `sim.stabilize()`.
- `scripts/warren.gd`: static helpers for the Warren (`tick`, `search`, mite `_step`).
- `scripts/hud.gd`: top bar, Build list, building panel (`_rebuild_info`), alerts,
  depth ruler/minimap, Crucible panel, Help (`_build_help`), Research tab.
- `scripts/overlay.gd`: world-space drawing: buildings, links, packets, ghosts,
  ranges, Warren zones, Strut beams and holds.
- `scripts/sim_factory.gd`: C++ sim if the extension loaded, else `sim.gd` (GDScript
  fallback, no chemistry/light/collapse; stubs for the rest).
- `shaders/terrain.gdshader`: cells + aux + palette + light + fog + memory textures.
- `native/src/crucible_sim.{h,cpp}`: the engine (CrucibleSim, a RefCounted).
- Session tooling in `native/`: `cloud_setup.sh` (run by `.claude/hooks/session-start.sh`),
  `build.sh`, `run_tests.sh`, `lsp_check.py`, `cache/godot-cpp-built.tar.gz`.

## The tick (`game._tick`, 60 a second)
sim.step, erode (every 2nd), weather, wash, collapse (+ `_cave_ins` alert), network
rebuild if dirty, springs, falling buildings, fliers (Thumpers), `_update_buildings`
(each machine; Warrens via `WR.tick`), research, Hub trickles, dispatch and packets,
`_damage_scan` + `_check_struts` (tick % 6 == 0), `_link_scan` (% 6 == 3), heat (20),
sense (30), vision/light (15), Crucible.

## Engine API (CrucibleSim; `sim` in GDScript)
- Cells: `get_cell`, `set_cell`, `get_cells`/`set_cells` (PackedByteArray W*H), `get_aux`,
  `get_aux_bytes`, `touch_rect`, `count(m)`, `checksum`.
- Tick and slow passes: `step`, `erode(samples, y0, y1)`, `weather(samples)`,
  `wash(samples)`, `collapse(rows)`, `stabilize()`, `tremor(n, y0, y1)`.
- Holds: `settle_around(x, y, r, ticks)`/`get_settle` (freshly dug), `hold_circle(x, y,
  r, +1/-1)`/`get_held` (Struts), `set_shields(circles)` (Tremor Dampers).
- Effects: `explode(x, y, radius, power)`, `ignite`, `add_particle`, `particle_count`.
- Light and heat: `light_update(lights, sights, sun, known)`, `get_light`,
  `refresh_heat`, `get_heat`.
- Scans for the game: `hazards_batch(rects, reach)` (NHAZ = 8 ints per building: hot
  liquid, fire, scald, liquid, open, corrosive, ground, structure), `segments_batch`,
  `building_hazards`, `segment_hazards`, `ring_counts`, `materials_in(mask)`.
- Stats: `stat_chunks`, `stat_updates`, `reactions`, `ignitions`, `eroded`, `crumbled`,
  `get_caved`, `get_washed`, `get_last_cave`, `get_tick`; `changed`/`heat_changed` flags.
- Setup: `configure(materials, reactions)`, `set_seed`, `set_threads`.
- Inside: 32x32 chunks with dirty rects, four checkerboard passes (threads), per-chunk
  RNG from (seed, tick, chunk); game-side passes use one stream (`grng`).
  `collapse_row` holds the span rule and `cling` the cohesive (stone) rule.

## Key game functions
- Placing: `footprint`, `snap_place`, `check_place` ("" or a reason), `place`
  (blueprint; `_complete` when paid), `find_link`, `touches_solid`. Struts:
  `strut_rect`, `check_strut`, `place_strut` (instant), `strut_anchors`.
- Losing: `demolish` (50% back), `_destroy(b, cause)` (alert, rubble), `_remove`.
- Anchoring: `_damage_scan` finds unheld buildings, `_settle` keeps those joined to a
  held one, `_come_loose` drops the rest (`_update_falling`, `_land`).
- Damage: `_hurt(b, amount, cause)`, `hurt_link`, repairs via `_requests`.
- Network: `_rebuild_network` (relays, sources, links), `_dispatch`, `_route`,
  `_deliver`, `_bank(pos, res, amount)` (to the nearest Cache in reach, else Hub).
- Research: `tech(id)`, `level(id)`, `_finish_research`, `is_unlocked(type)`,
  `_refresh_unlocks`; tests set `researched[id] = true` then `_refresh_unlocks()`.
- Knowledge: `is_known(x, y)`, `reveal`, `_refresh_vision`; `reveal_all` for tests.
- Alerts: `alert(kind, text, at)` (merges same kind nearby within 20 s), `show_banner`.
- Blasts: `blast(at, radius, power, source)`.
- Tests: `run_ticks(n)`, `new_game(seed)`, `paused = true`, `drill.enabled = false`.

## Tests: the usual harness
`extends SceneTree`; `_initialize` instantiates `scenes/main.tscn`; `_process` runs the
scenarios on frame 2 and prints `FAILURES: n`. Helpers each file defines: `fresh()`
(new_game(7), paused, reveal_all, stock), `fill(r, m)`, `count(...)`, `check(ok, what)`,
`secs(s)` (run_ticks(60 * s)), `build(type, r)` (place, then tick until built).
