# Crucible: code map (as of the A3 legacy cut)

Where things are, so a new session can go straight to the right function instead of
grepping. Line numbers drift; names don't. Coordinates are cells: x across (0..767),
y down (0..5119), GROUND_Y 200; D.S (10) is the scale of everything built. Resources
index as [Stone, Glimmer, Obsidian, Water, Power].

## Files
- `scripts/game.gd` (~3000 lines): the game node. Sections, in order: Setup, Frame loop,
  Buildings, Upkeep, Braces, Links, Blasts, Network and packets, Research, The Crucible,
  Knowledge maps, Alerts, Camera, Input.
- `scripts/defs.gd`: every tunable and table: material ids, building tables (per-type
  arrays: Hub, Node, Bulkhead, Crucible, Brace), PALETTE/keys, network ranges, power, quarry
  numbers (`SHAFT_REACHES`), collapse and Brace numbers, light and fog radii (`LIGHT_PILOT`,
  `SIGHT_MACHINE`), TECHS, recipe, layers, hazards.
- `scripts/building.gd`: one placed structure (Hub, Node, Bulkhead, Brace, Crucible): link
  and network fields, anchoring and falling, a Brace's anchors.
- `scripts/materials.gd`: loads data/materials.json into what the sim, game and shader
  use (kinds, dig rates, yields, palette image 256x4). A1: temperature keys (kind
  defaults for `conduct` and `sink`), `families` (name to bit) and `family_of` (bits per
  id), `members(name)` (a material or a family's ids), `families_of(m)`, and
  `expand_reactions(rules)` (family rules to material pairs, material rules first).
  A2: `_wave1(e, m)` reads the wave 1 keys (`heat_mass`, `sets`, `blast`, `absorbs`, `plume`,
  `bursts`, `grows`, `body`, `burn.wet`, `burn.catalyst`) into the sim's dictionary; a
  reaction can carry `emit` and `emit_chance`. The data file's `_about` documents each key.
- `scripts/worldgen.gd`: v2's layout scaled (SX 3, SY 5, features F 4): bands (whole
  rows copied), stone lumps, aquifers, glimmer veins, caves, pockets, lava lake,
  chamber, deposits (coal, sulfur), `_ground` (packed dirt, sand, gravel, clay), `_heat`
  (the Magma band's stone to hot rock, last), then `sim.stabilize()`. `_near` reads 4x4 block masks built with native finds.
  `bench(sim)` (A1) builds the lab bench instead: open air over a bedrock floor at
  `BENCH_FLOOR`, the Hub's pad.
- `scripts/spawn_regions.gd` (A2) + `data/spawn_regions.json`: `load_table`, `place(g, w, h, table,
  seed, ctx, resolve)` paints areas (mound, patch) and spawn rows (home range, hosts, clumps) into
  worldgen's grid; worldgen calls it once, after `_heat`, and returns its report as `spawned`.
  Rows are blobs, speckles, or seams (`aspect`); the second half of the table is wave 1's home
  ranges. Cells come out of `set_cells` at their `placed` temperature (Rime is cold).
- `scripts/hud.gd`: top bar (speed buttons, `speed_label` when the sim can't keep up),
  Build list (structures by key, then `MC.add_build_buttons` for the modules; `MC.refresh_buttons`
  shows a tech-gated one once it opens), building panel (`_rebuild_info`), alerts, depth
  ruler/minimap (structures and modules), Crucible panel, Help (`_build_help`), Research tab,
  the end panel (`_build_end`, `show_end`).
- `scripts/goals.gd` (A3): static helpers; state is `game.goals`. `tick` (hook in `_tick`),
  `delivered` (hooks in `_bank` and `_deliver`), `skip_tutorial`, `research_mats` (used by
  `tech_mats_needed`). Orders, chapters and research goods are in `data/instructions.json`.
  `scripts/goals_panel.gd`: the HUD panel (built by hud.gd).
- `scripts/save.gd` (phase 10): the one save slot. `write(game, path)` (the engine's
  `save_state` plus every name in GAME_VARS and every building's own variables,
  zstd), `read`, `restore`, `peek` (the header for the title), `erase`. Buildings are
  stored by value and referred to by id (`_enc`/`_dec`: {"$b"}, {"$p"}, {"$d"}).
- `scripts/title.gd` (phase 10): the title screen (a CanvasLayer): Continue, Start Run
  with an optional seed, Quit; Esc goes back to a live run.
- `scripts/overlay.gd`: world-space drawing: buildings, links, packets, ghosts,
  ranges, Brace beams and holds, and the module hook (`MC.draw`).
- `scripts/sim_factory.gd`: C++ sim if the extension loaded (sized D.W x D.H, free fall,
  temperature params and the ambient from defs), else `sim.gd` (GDScript fallback, no chemistry/light/collapse; slow
  versions of the rest).
- `shaders/terrain.gdshader`: cells, aux and memory from Texture2DArrays (a 256 x 256
  tile a layer, `tile_at`), palette, and block textures (light, fog, heat, sense).
- `native/src/crucible_sim.{h,cpp}`: the engine (CrucibleSim, a RefCounted).
- `native/src/save.cpp`: `save_state`/`load_state` (everything a run needs to step on
  exactly as before: cells, aux, holds, settle, bodies, RNG, tick; version 2 adds the
  temperatures, the temperature pass's awake chunks and body temperatures). `write_state` runs
  twice, counting the bytes and then writing them into one buffer.
- `native/src/bodies.cpp`: rigid bodies and collapse into pieces (members of CrucibleSim);
  `native/src/rng.h`: the random helpers both share.
- `native/src/modules.cpp` (A3): the engine side of machine modules: `set_module` (a
  body that never settles; saved as a flag), `body_info` (size, centre of mass, pixels),
  `body_pixels` (its bitmap), `body_set_pixel` (opens and closes ports, knocks out walls),
  `drive_body(id, vx, vy)` (no gravity, that velocity for two ticks: call it every tick to hold or haul a rig).
- `scripts/machines/` (A3 framework): `faces.gd` (face types, `layout` turns a template
  into pixels and faces in the body's frame), `casing.gd` (stand-in material, `integrity`,
  `breach_at` floods from the cavity), `machines.gd` (the registry: `place`/`check_place`,
  `tick` every 6 ticks: integrity, breach spill, wreckage, joining and leaving faces,
  contents; `knock_out`; Build-list buttons, `click`, `key`), `test_modules.gd` (Box,
  Plug, Cap). State is plain data in `game.modules` (saved via GAME_VARS).
- `scripts/machines/` (A3 starter kit): `module_data.gd` loads `data/modules/{logistics,excavation,movers,power}.json`
  (one file per group, `FILES` lists them: logistics, excavation, movers, power, support) into definitions; a definition's `kind` names its behaviour
  script, registered in machines.gd (`kinds`), each with `scan` (every 6 ticks), `step` (every tick),
  `info` and `draw`. `mu.gd` is what machines.gd and the behaviours share without a preload cycle:
  `defs`, `frame`/`world`/`turn`, `front`, `partner`, `bounds`, `capacity`/`stored`/`add`, `networked`
  (a Node or the Hub in reach, via `find_link`), `take_power` (the Hub's stock). `logistics/tank.gd`
  (capacity from the hollow, `pack` and Tank Size; draws its fill), `logistics/funnel.gd` (banks what it
  holds through `_bank`), `excavation/cutter.gd` (`front_of`, `slice`, hardness masks from the Drill Bit
  level, wobbling 30-wide window, `room` rows clear ahead), `movers/winch.gd` (the rig, states docked /
  down / up, `drive_body` on every rig module each tick, halt reasons keyed on Drill Bit and Drill
  Shaft), `power/windmill.gd` (gusts, open sky, network reach), `support/lab.gd` (A3 cut: power and goods
  from the Hub's stock into `game.current_tech`) and `support/lamp.gd` (`lit` while the stock pays).
  A module's `tech` (a definition key) gates its Build button (`unlocked`); `count_named` counts
  built modules by name (goals); `lights` and `sensing` give the game's light and sight passes the
  modules' pilot lights, lit Lamps and the Cutter's sense; `deepest`/`deepest_module` feed
  `game.deepest_point()` and `_track_depth`; `place` marks "First <name> built". machines.gd also has `snap` (a picked
  module snaps onto a free matching face within 12 cells), `click` (snaps, charges the definition's
  `cost`), `module_at`, `info`, `generating`, `draw` (the overlay's hook: ghost, cable, readout) and
  `_motion` (every tick: `anchored` modules hold still, behaviours step). A `tether` module's links
  never break by distance.
- Session tooling in `native/`: `cloud_setup.sh` (run by `.claude/hooks/session-start.sh`),
  `build.sh`, `run_tests.sh`, `lsp_check.py`, `cache/godot-cpp-built.tar.gz`.

## The tick (`game._tick`, 60 a second)
sim.step (cells, then bodies, then particles), `_bodies` (impacts hurt buildings;
links crossed every 3rd tick), erode (every 2nd), weather, wash, collapse (+ `_cave_ins` alert), network
rebuild if dirty, springs, falling buildings, `_update_buildings`
(the Hub's upkeep, Nodes' drowning and relinking), `MC.tick` (modules), research, Hub trickles, dispatch and packets,
`_damage_scan` + `_check_braces` (tick % 6 == 0), `_link_scan` (% 6 == 3), heat (20),
sense (30), vision/light (15), Crucible. The engine's temperature pass runs inside
`step`, every 8th tick.

## Engine API (CrucibleSim; `sim` in GDScript)
- Size and motion: `set_size(w, h)` (multiples of 32; clears everything), `get_width`,
  `get_height`, `set_fall(accel, max_speed)`.
- Cells: `get_cell`, `set_cell`, `get_cells`/`set_cells` (PackedByteArray W*H), `get_aux`,
  `get_aux_bytes`, `touch_rect`, `count(m)`, `checksum`.
- Tick and slow passes: `step`, `erode(samples, y0, y1)`, `weather(samples)`,
  `wash(samples)`, `collapse(rows)`, `stabilize()`, `tremor(n, y0, y1)`.
- Holds: `settle_around(x, y, r, ticks)`/`get_settle` (freshly dug), `hold_circle(x, y,
  r, +1/-1)`/`get_held` (Braces), `set_shields(circles)` (Tremor Dampers).
- Effects: `explode(x, y, radius, power)`, `ignite`, `add_particle`, `particle_count`.
- Light and heat: `light_update(lights, sights, sun, known)` (per 4x4 block; copies
  live blocks into the remembered map), `set_light_view(x0, y0, x1, y1)`, `get_light`
  (a byte per block), `refresh_heat` (the hottest cell per 4x4 block, (deg + 60) / 6),
  `get_heat`, `block_circles(circles)`.
- Temperature (A1): `get_temp(x, y)`, `set_temp(x, y, deg)`, `heat_rect(x, y, w, h,
  deg)` and `heat_circle(x, y, r, deg)` (add degrees), `rect_temp(x, y, w, h)` (min,
  max, mean), `set_ambient(rows)` (`D.ambient_rows()`), `reset_temps()` (every cell to
  its row's ambient), `set_temp_params(dict)` (`D.temp_params()`: every, sink_every,
  sink), `get_stat_tchunks`, `get_temp_chunks`. `paint_circle(x, y, r, m, keep_fixed)`
  is the bench brush. Inside: `step_temperature` swaps `tnext` into `tcur` and runs
  `temp_chunk` over those chunks on the checkerboard (`pass_mode` 1); `placed_temp`
  (set_cell) and `init_temp` (cells made inside) pick a new cell's degrees.
- Rendering: `take_dirty_tiles`, `take_mem_tiles`, `get_tile(which, tile)` (0 cells, 1
  aux, 2 remembered), `reset_memory`, `get_tiles_across/down`.
- Rectangles: `count_in_rect(x, y, w, h, mask)`, `rect_counts`, `block_counts(bx, by,
  bw, bh, mask)`, `dig_rect(x, y, w, h, mask, settle_r, ticks)`, `place_spots(x, y, w,
  h, radius, open_mask, solid_mask)`. Masks: `Mats.mask(name)` (open, closed, solid,
  dig, liquid, powder, ...).
- Scans for the game: `hazards_batch(rects, reach)` (NHAZ = 8 ints per building: hot
  liquid, fire, scald, liquid, open, corrosive, ground, structure), `segments_batch`,
  `building_hazards`, `segment_hazards`, `ring_counts`, `materials_in(mask)`.
- Bodies: `set_body_params(dict)` (from `D.body_params()`), `make_body(x, y, w, h, vx, vy,
  spin)`, `body_count`, `get_bodies` (7 ints each: id, box, speed, cells), `body_state(id)`
  (10 floats: pose, speeds, cells, age, rest), `take_impacts` (6 ints each: x, y, speed, cells,
  hit a building, body hit), `get_owner(x, y)`, `set_creature(id, on)` (never settles;
  grips on contact), `remove_body(id)`, `get_bodies_made/shattered/settled`.
- Stats: `stat_chunks`, `stat_updates`, `reactions`, `ignitions`, `eroded`, `crumbled`,
  `get_caved`, `get_washed`, `get_last_cave`, `get_tick`; `changed`/`heat_changed` flags.
  A2: `get_blasts` (detonations run), `get_forged` (bodies forged by a reaction's `emit`).
- Setup: `configure(materials, reactions)`, `set_seed`, `set_threads`.
- Saving (phase 10): `save_state()` (PackedByteArray), `load_state(bytes)`.
- Inside: 32x32 chunks with dirty rects, four checkerboard passes (threads), per-chunk
  RNG from (seed, tick, chunk); game-side passes use one stream (`grng`). Nothing moves
  more than 15 cells a tick (`fall`, liquid `spread`), so passes stay independent.
  `collapse_row` holds the span rule (`due` per cell) and `cling` the cohesive (stone)
  rule, comparing `kin_of` (a material's `kin`: hot rock counts as stone); in play each stretch due to go goes to `give_way` (bodies.cpp): narrow or low
  ones crumble a cell at a time, others `break_off` a piece as a body.
  `hazards_at` caches corrosive counts per chunk. `update_cell` keeps a cell with a
  reaction partner beside it awake (water resting on hot rock keeps boiling).
  Wave 1 (A2), all in `update_cell` and friends: `sets_to` counts a cell's aux down (`set_speed`,
  `set_catalyst`); `blast_*` goes off through `detonate` (a hard landing is checked in `powder`,
  fire in `heat_neighbour`) and queues a `Blast` in the worker's `Ctx`; `absorb`/`burst` are the
  swell (aux holds the soaked liquid's id); `grow_cell` is Weft; `heat_mass` divides a cell's
  change in `temp_chunk`; a reaction's `emit` queues an `Emit`. After the cell passes `step` runs
  `run_blasts` (sorted by position; a blast sets off the like of itself within its radius a
  few ticks later) and `run_emits` (fills a free rectangle with the `body_w` x `body_h` material
  and calls `make_body_from`), then bodies. A reaction side that keeps its material isn't rewritten.
- Bodies (bodies.cpp): a `Body` keeps a bitmap and a pose; its pixels sit in the grid as
  ordinary cells tagged in `owner` (the slow passes skip tagged cells). `body_tick`: drop
  lost pixels, gravity and liquid drag, move in half-cell substeps (`overlap` on edge
  pixels, `body_hit` impulse and friction, push out along the normal), then settle
  (`settle_body`), shatter (`shatter`) or `restamp`. `push_bodies` from `explode`.

## Key game functions
- Placing: `footprint`, `snap_place` (engine `place_spots`, then fog and link),
  `check_place` ("" or a reason), `place` (blueprint; `_complete` when paid),
  `find_link`, `touches_solid`. Braces: `brace_rect` (BRACE_THICK), `check_brace`,
  `place_brace` (instant), `brace_anchor_ok`. Modules are placed by machines.gd (`click`).
- Upkeep: `_springs` (`_spring_top` remembers the top), `_update_buildings` (the Hub's
  `_hub_upkeep`; Node drowning in `_damage_scan`'s hysteresis).
- Crucible: `activate_crucible`, `_update_crucible` (power draw from `c_power`,
  `c_starved`, drain, tremors); its power request leads `_requests`.
- A run (phase 10): `new_game` = `_label_sim`, `_reset(seed)`, `_start`; `save_run`,
  `continue_run(path)` (then `_loaded` rebuilds caches); `open_title`, `start_run`,
  `continue_game`, `quit_game`. Its end: `frozen` (won or lost, not carrying on),
  `keep_going`, `_lose(cause)`; milestones with `mark(text, major)`, `_track_depth`.
  The Hub: `_hub_upkeep` (patches itself), and `_destroy` of it calls `_lose`.
- Speed: `set_speed(i)` over SPEEDS; the frame loop runs ticks until TICK_BUDGET_US.
- Lines (phase 10): `line_points` (spacing by type), `lay_line` (places what it can,
  plans the rest), `plans`/`_try_plans` (every 30 ticks), `plan_at`, `cut_plans`;
  input `dragged_line`.
- Worth: `D.cell_units(m)` (units a cell of m banks; data "worth").
- Drawing: `_upload` (dirty tiles near the view), `view_rect(pad)`, float `zoom`.
- Losing: `demolish` (50% back), `_destroy(b, cause)` (alert, rubble), `_remove`.
- Anchoring: `_damage_scan` finds unheld buildings, `_settle` keeps those joined to a
  held one, `_come_loose` drops the rest (`_update_falling`, `_land`: fall damage).
- Bodies: `_bodies` (impacts on buildings), `_crush_links`.
- Damage: `_hurt(b, amount, cause)`, `hurt_link`, repairs via `_requests`.
- Network: `_rebuild_network` (relays, sources, links), `_dispatch`, `_route`,
  `_deliver`, `_bank(pos, res, amount)` (into the Hub's stock; Funnels and Labs use it).
- Research: `tech(id)`, `level(id)`, `_finish_research`, `is_unlocked(type)`,
  `_refresh_unlocks`; tests set `researched[id] = true` then `_refresh_unlocks()`.
- Knowledge: `is_known(x, y)`, `reveal`, `_refresh_vision`; `reveal_all` for tests.
- Alerts: `alert(kind, text, at)` (merges same kind nearby within 20 s), `show_banner`.
- Blasts: `blast(at, radius, power, source)`.
- Tests: `run_ticks(n)`, `new_game(seed)`, `paused = true`.
- Lab bench (A1): `start_bench(fresh)`, `_bench_mats` (every material, then Heat, Cool,
  Blast), `brush_list`/`brush_material`, `_paint` (engine `paint_circle`, or
  `heat_circle` for Heat and Cool); `bench`, `brush_r`, `temp_view` (F6; the shader's
  `temp_view`). `_reset` turns the bench's reveal, brush and view off.

## The quarry bot (tests/autoplay.gd, A3 cut)
A pacing probe, not a run. Flattens a strip left of the Hub, then each second places Nodes down
it (blueprints fill by packet), the rig (Cutter, Tank, Funnel, Winch), a Lab and a Windmill,
and picks research from `ORDER`; prints the tutorial steps, research and the 500-row depth
marks (`--seed`, `--max`, `--quiet`). The phase 10 bot (Borers, Conduit logistics, checkpoints)
is gone; the full bot comes back at the end of A4.

## Tests: the usual harness
`extends SceneTree`; `_initialize` instantiates `scenes/main.tscn`; `_process` runs the
scenarios on frame 2 and prints `FAILURES: n`. Helpers each file defines: `fresh()`
(new_game(7), paused, reveal_all, stock), `fill(r, m)`, `count(...)`, `check(ok, what)`,
`secs(s)` (run_ticks(60 * s)), `build(type, r)` (place, then tick until built); module tests use `MC.place(game, def, at, 0)`
on a strip they flatten first (a module that falls far shatters).
Phase 8b tests also define `P(x, y)` / `R(x, y, w, h)`: a v2 cell or rectangle near the
Hub, scaled by D.S about the pad's middle at ground level.
scenario_bodies walls its rooms in bedrock (`arena`), which never caves, and counts bodies
locally (`bodies_in`): the seed's own caves shed pieces all over the map.
Deep or shallow set-pieces fix their rows' ambient: scenario_depth `keep_hot(r)`,
scenario_bodies `keep_cool(r)`. scenario_temperature runs on bench sims of its own
(`bench_sim(threads, rules)`), no game; tests/shot_temperature.gd screenshots the bench,
its F6 view and the fog.
