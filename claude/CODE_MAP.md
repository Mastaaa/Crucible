# Crucible: code map (as of phase 10)

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
  chamber, deposits (coal, sulfur), `_ground` (packed dirt, sand, gravel, clay), `_heat`
  (the Magma band's stone to hot rock, last), then `sim.stabilize()`. `_near` reads 4x4 block masks built with native finds.
- `scripts/warren.gd`: static helpers for the Warren, on 4x4 bites (`tick`, `search`
  over bites with `block_counts`, mite `_step`, `_nibble` bursts). As bodies (8d):
  `_gripping`, `loosen` (a mite becomes a creature body), `_fly` (follow it; walk again
  at rest). `game.mite_bodies` maps body ids to mites; `game.body_momentum(id)`.
- `scripts/hud.gd`: top bar (speed buttons, `speed_label` when the sim can't keep up),
  Build list, building panel (`_rebuild_info`), alerts, depth ruler/minimap, Crucible
  panel, Help (`_build_help`), Research tab, the end panel (`_build_end`, `show_end`).
- `scripts/save.gd` (phase 10): the one save slot. `write(game, path)` (the engine's
  `save_state` plus every name in GAME_VARS and every building's own variables,
  zstd), `read`, `restore`, `peek` (the header for the title), `erase`. Buildings are
  stored by value and referred to by id (`_enc`/`_dec`: {"$b"}, {"$p"}, {"$d"}).
- `scripts/title.gd` (phase 10): the title screen (a CanvasLayer): Continue, Start Run
  with an optional seed, Quit; Esc goes back to a live run.
- `scripts/overlay.gd`: world-space drawing: buildings, links, packets, ghosts,
  ranges, Warren zones, Strut beams and holds.
- `scripts/sim_factory.gd`: C++ sim if the extension loaded (sized D.W x D.H, free fall
  from defs), else `sim.gd` (GDScript fallback, no chemistry/light/collapse; slow
  versions of the rest).
- `shaders/terrain.gdshader`: cells, aux and memory from Texture2DArrays (a 256 x 256
  tile a layer, `tile_at`), palette, and block textures (light, fog, heat, sense).
- `native/src/crucible_sim.{h,cpp}`: the engine (CrucibleSim, a RefCounted).
- `native/src/save.cpp`: `save_state`/`load_state` (everything a run needs to step on
  exactly as before: cells, aux, holds, settle, bodies, RNG, tick).
- `native/src/bodies.cpp`: rigid bodies and collapse into pieces (members of CrucibleSim);
  `native/src/rng.h`: the random helpers both share.
- Session tooling in `native/`: `cloud_setup.sh` (run by `.claude/hooks/session-start.sh`),
  `build.sh`, `run_tests.sh`, `lsp_check.py`, `cache/godot-cpp-built.tar.gz`.

## The tick (`game._tick`, 60 a second)
sim.step (cells, then bodies, then particles), `_bodies` (impacts hurt buildings;
links crossed every 3rd tick), erode (every 2nd), weather, wash, collapse (+ `_cave_ins` alert), network
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
- Bodies: `set_body_params(dict)` (from `D.body_params()`), `make_body(x, y, w, h, vx, vy,
  spin)`, `body_count`, `get_bodies` (7 ints each: id, box, speed, cells), `body_state(id)`
  (10 floats: pose, speeds, cells, age, rest), `take_impacts` (6 ints each: x, y, speed, cells,
  hit a building, body hit), `get_owner(x, y)`, `set_creature(id, on)` (never settles;
  grips on contact), `remove_body(id)`, `get_bodies_made/shattered/settled`.
- Stats: `stat_chunks`, `stat_updates`, `reactions`, `ignitions`, `eroded`, `crumbled`,
  `get_caved`, `get_washed`, `get_last_cave`, `get_tick`; `changed`/`heat_changed` flags.
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
- Bodies (bodies.cpp): a `Body` keeps a bitmap and a pose; its pixels sit in the grid as
  ordinary cells tagged in `owner` (the slow passes skip tagged cells). `body_tick`: drop
  lost pixels, gravity and liquid drag, move in half-cell substeps (`overlap` on edge
  pixels, `body_hit` impulse and friction, push out along the normal), then settle
  (`settle_body`), shatter (`shatter`) or `restamp`. `push_bodies` from `explode`.

## Key game functions
- Placing: `footprint`, `snap_place` (engine `place_spots`, then fog and link),
  `check_place` ("" or a reason), `place` (blueprint; `_complete` when paid),
  `find_link`, `touches_solid`. Struts: `strut_rect` (STRUT_THICK), `check_strut`,
  `place_strut` (instant), `strut_anchors`.
- Machines: `_drill` (`_drill_find` halves down with counts, `_drill_row` digs a row at
  once), `_hopper` (skips an empty rim), `_springs` (`_spring_top` remembers the top),
  generators `_wheel` and `_turbine` (`D.is_generator`).
- Heat (9): `can_cut` / `cut_mask` (obsidian needs the Saw, hot rock the Coolant
  Jacket), `_cool` (tank water, `b.coolant`; else `b.stuck = DRY`), `_vent` (steam into
  open cells, `b.steam_due`), `_tank_full` (a charging Borer waits for it). Coolant
  requests sit after machine power in `_requests`; `_deliver` fills the tank. Mites:
  `WR.can_dig(m, teeth, ember)`, mask "ember".
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
- Jacket and lava (phase 10): `_quench` (a Drill or Borer facing lava turns it to
  obsidian from its tank), `_jacket_drink` (water on a jacketed Borer fills its tank);
  `_damage_scan` lets a jacketed Borer boil JACKET_LAVA_WATER instead of burning.
- Worth: `D.cell_units(m)` (units a cell of m banks; data "worth").
- Drawing: `_upload` (dirty tiles near the view), `view_rect(pad)`, float `zoom`.
- Losing: `demolish` (50% back), `_destroy(b, cause)` (alert, rubble), `_remove`.
- Anchoring: `_damage_scan` finds unheld buildings, `_settle` keeps those joined to a
  held one, `_come_loose` drops the rest (`_update_falling`, `_land`: fall damage).
- Bodies: `_bodies` (impacts on buildings), `_crush_links`; Thumper bumps in
  `_update_fliers` via `_bump`.
- Damage: `_hurt(b, amount, cause)`, `hurt_link`, repairs via `_requests`.
- Network: `_rebuild_network` (relays, sources, links), `_dispatch`, `_route`,
  `_deliver`, `_bank(pos, res, amount)` (to the nearest Cache in reach, else Hub).
- Research: `tech(id)`, `level(id)`, `_finish_research`, `is_unlocked(type)`,
  `_refresh_unlocks`; tests set `researched[id] = true` then `_refresh_unlocks()`.
- Knowledge: `is_known(x, y)`, `reveal`, `_refresh_vision`; `reveal_all` for tests.
- Alerts: `alert(kind, text, at)` (merges same kind nearby within 20 s), `show_banner`.
- Blasts: `blast(at, radius, power, source)`.
- Tests: `run_ticks(n)`, `new_game(seed)`, `paused = true`, `drill.enabled = false`.

## The autoplay bot (tests/autoplay.gd, phase 10)
Plays a run headless through the game's own calls and prints milestones with times
(`--seed`, `--max`, `--quiet`, `--save=SECONDS` for a checkpoint, `--load=PATH`,
`--dump=SECONDS --rect=x,y,w,h` for a map of an area). It knows the map. `think()` runs
its jobs once a game second: research (PLAN), shaft_chain, place_conduits (its own
Conduit queue: exact spots, sliding to a wall), drive_borers (routes of legs; turns
checked every 10 ticks by `_turns`), deep (the column), glimmer, tap, lava (a Thumper
down to lava: Tier 3), descent (`lava_free_legs`: a search over 30-cell blocks clear of
lava and caves), obsidian (jacketed dives into a lava pocket), plug, crucible (two
Caches by the plug, then charge). Its state `st` is plain data saved beside a checkpoint
(`.bot`), so a run resumes from any checkpoint.

## Tests: the usual harness
`extends SceneTree`; `_initialize` instantiates `scenes/main.tscn`; `_process` runs the
scenarios on frame 2 and prints `FAILURES: n`. Helpers each file defines: `fresh()`
(new_game(7), paused, reveal_all, stock), `fill(r, m)`, `count(...)`, `check(ok, what)`,
`secs(s)` (run_ticks(60 * s)), `build(type, r)` (place, then tick until built).
Phase 8b tests also define `P(x, y)` / `R(x, y, w, h)`: a v2 cell or rectangle near the
Hub, scaled by D.S about the pad's middle at ground level.
scenario_bodies walls its rooms in bedrock (`arena`), which never caves, and counts bodies
locally (`bodies_in`): the seed's own caves shed pieces all over the map.
