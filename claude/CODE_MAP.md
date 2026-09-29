# Crucible: code map (as of phase 8b)

Where things are, so a new session can go straight to the right function instead of
grepping. Line numbers drift; names don't. Coordinates are cells: x across (0..767),
y down (0..5119), GROUND_Y 200; D.S (10) is the scale of everything built. Resources
index as [Stone, Glimmer, Obsidian, Water, Power].

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
- `scripts/worldgen.gd`: v2's layout scaled (SX 3, SY 5, features F 4): bands (whole
  rows copied), stone lumps, aquifers, glimmer veins, caves, pockets, lava lake,
  chamber, deposits (coal, sulfur), `_ground` (packed dirt, sand, gravel, clay), then
  `sim.stabilize()`. `_near` reads 4x4 block masks built with native finds.
- `scripts/warren.gd`: static helpers for the Warren, on 4x4 bites (`tick`, `search`
  over bites with `block_counts`, mite `_step`, `_nibble` bursts).
- `scripts/hud.gd`: top bar, Build list, building panel (`_rebuild_info`), alerts,
  depth ruler/minimap, Crucible panel, Help (`_build_help`), Research tab.
- `scripts/overlay.gd`: world-space drawing: buildings, links, packets, ghosts,
  ranges, Warren zones, Strut beams and holds.
- `scripts/sim_factory.gd`: C++ sim if the extension loaded (sized D.W x D.H, free fall
  from defs), else `sim.gd` (GDScript fallback, no chemistry/light/collapse; slow
  versions of the rest).
- `shaders/terrain.gdshader`: cells, aux and memory from Texture2DArrays (a 256 x 256
  tile a layer, `tile_at`), palette, and block textures (light, fog, heat, sense).
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
- Size and motion: `set_size(w, h)` (multiples of 32; clears everything), `get_width`,
  `get_height`, `set_fall(accel, max_speed)`.
- Cells: `get_cell`, `set_cell`, `get_cells`/`set_cells` (PackedByteArray W*H), `get_aux`,
  `get_aux_bytes`, `touch_rect`, `count(m)`, `checksum`.
- Tick and slow passes: `step`, `erode(samples, y0, y1)`, `weather(samples)`,
  `wash(samples)`, `collapse(rows)`, `stabilize()`, `tremor(n, y0, y1)`.
- Holds: `settle_around(x, y, r, ticks)`/`get_settle` (freshly dug), `hold_circle(x, y,
  r, +1/-1)`/`get_held` (Struts), `set_shields(circles)` (Tremor Dampers).
- Effects: `explode(x, y, radius, power)`, `ignite`, `add_particle`, `particle_count`.
- Light and heat: `light_update(lights, sights, sun, known)` (per 4x4 block; copies
  live blocks into the remembered map), `set_light_view(x0, y0, x1, y1)`, `get_light`
  (a byte per block), `refresh_heat`, `get_heat`, `block_circles(circles)`.
- Rendering: `take_dirty_tiles`, `take_mem_tiles`, `get_tile(which, tile)` (0 cells, 1
  aux, 2 remembered), `reset_memory`, `get_tiles_across/down`.
- Rectangles: `count_in_rect(x, y, w, h, mask)`, `rect_counts`, `block_counts(bx, by,
  bw, bh, mask)`, `dig_rect(x, y, w, h, mask, settle_r, ticks)`, `place_spots(x, y, w,
  h, radius, open_mask, solid_mask)`. Masks: `Mats.mask(name)` (open, closed, solid,
  dig, liquid, powder, ...) and `WR.mask(name)`.
- Scans for the game: `hazards_batch(rects, reach)` (NHAZ = 8 ints per building: hot
  liquid, fire, scald, liquid, open, corrosive, ground, structure), `segments_batch`,
  `building_hazards`, `segment_hazards`, `ring_counts`, `materials_in(mask)`.
- Stats: `stat_chunks`, `stat_updates`, `reactions`, `ignitions`, `eroded`, `crumbled`,
  `get_caved`, `get_washed`, `get_last_cave`, `get_tick`; `changed`/`heat_changed` flags.
- Setup: `configure(materials, reactions)`, `set_seed`, `set_threads`.
- Inside: 32x32 chunks with dirty rects, four checkerboard passes (threads), per-chunk
  RNG from (seed, tick, chunk); game-side passes use one stream (`grng`). Nothing moves
  more than 15 cells a tick (`fall`, liquid `spread`), so passes stay independent.
  `collapse_row` holds the span rule and `cling` the cohesive (stone) rule;
  `hazards_at` caches corrosive counts per chunk.

## Key game functions
- Placing: `footprint`, `snap_place` (engine `place_spots`, then fog and link),
  `check_place` ("" or a reason), `place` (blueprint; `_complete` when paid),
  `find_link`, `touches_solid`. Struts: `strut_rect` (STRUT_THICK), `check_strut`,
  `place_strut` (instant), `strut_anchors`.
- Machines: `_drill` (`_drill_find` halves down with counts, `_drill_row` digs a row at
  once), `_hopper` (skips an empty rim), `_springs` (`_spring_top` remembers the top).
- Drawing: `_upload` (dirty tiles near the view), `view_rect(pad)`, float `zoom`.
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
Phase 8b tests also define `P(x, y)` / `R(x, y, w, h)`: a v2 cell or rectangle near the
Hub, scaled by D.S about the pad's middle at ground level.
