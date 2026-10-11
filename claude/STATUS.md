# Crucible: status (lean; read at the start of every session)

The game as it stands, for working on it. Numbers live in scripts/defs.gd and
data/materials.json; this says what exists and how it behaves. The full per-phase
history (what shipped when, old numbers, test notes) is the root STATUS.md:
Claude adds a section at its top each phase and doesn't need to read the rest.

## Handoff
- Last done: A7 part 2, bot upkeep (delivered Stone in the report, research after the fixed order, a lost Node rebuilt; tests/autoplay.gd only). A7 part 1 (PR #47): the climb plow shaves a ledge touching the hull (`winch.gd` `PLOW_EDGE`; the re-baselined cheated bot had stopped at depth 946 because a Cutter snagged on a zero-clearance ledge and dropped off the Tank; scenario_quarry L; no engine change). Before it: A6 part 3 second half, the local ambient grid (ENGINE: `ambient_off` per 32 x 32 chunk added to the row ambient in `temp_chunk` and `reset_temps`; `set_ambient_offsets(chunks, wake)`; a patch area's `ambient` data, `SR.chunk_offsets` with a 40 cell fade; set by worldgen and after a load; Dunes +20, Fen -10, Salt flats -60, Sulfur vents +40, Gall caverns +40 (proposal said +50; Sulfur kindles at 600), Brine row from 1900; scenario_temperature N, O, P; `bin/` rebuilt). Before it: A6 part 4, the surface generators (Solar Panel `power/solar.gd`: 0.4 power/s under a clear line to the sky, times `params.biomes[name]`, Dunes 1.8; Waterwheel `power/waterwheel.gd`: water over its casing runs through it for 0.0125 power a cell, 40 cells a second; spawn rows may carry `spring: true` and the Fen's Water pockets have springs; both researched; scenario_generators; no engine change). Before it: A6 part 3 first half, the ambient ramp (`D.ambient_at` warms the Stone band by a smoothstep from 90 at row 2600 to 550 at 3000 instead of a 50 row cliff; worldgen caves and water pockets keep their centres above row 2525 (`WET_BOTTOM`) and the Salt flats' Brine above 2650 so no liquid starts hot enough to boil; scenario_temperature M; data only, no engine change). Before it: A6 part 2, biomes as data (`spawn_regions.gd` patches have a rim, a flank (`side`, `opposite`), an anchor (box, surface, lava pocket), `avoid`, a ground recipe (`ground` rules with `not_near`) and clip their resident rows; six biomes in `data/spawn_regions.json`: Dunes, Fen, Salt flats, Ferrite hills, Sulfur vents, Gall caverns, rows moved into them, outliers of Ferrite, Flux and Rime kept in the Hub's middle third; `SR.biome_at`, `game.biome_at`, F7 biome view, `mapdump --biomes`, `shot_biomes.gd`; scenario_spawn F and G; scenario_excavators E tries places until a Thumper rig gets through; no engine change). Before it: A6 part 1, the world is 1024 wide (`D.W`, `terrain.gdshader` `map_size`, worldgen `SX` 4 with per-world feature counts scaled by 4/3, `spawn_regions.gd` scales `world` rows by `REF_W` 768, sampling constants scale with the width, save version 3; the Hub moves from x 384 to x 512 so 14 bench scenarios moved +128; scenario_processing B waits a tick at a time, scenario_excavators E moved 6 cells because a Thumper that lands tilted can wedge at the shaft floor; no engine change; Alex picked "Engine grid" and "Solar and Waterwheel" on the A6 draft, plans/a6-draft.md). Before it: A5 part 3, wave 2 materials (twelve new materials, ids 54 to 68 with three derived, 35 reactions, seven spawn rows, the Electrolyser, `residue` face on the Boiler, Chillant from the Chiller, Wire from the Furnace, `acid` strengths in `casing.wear`; claude/WAVE2_MATERIALS.md; scenario_wave2; no engine change; Alex dropped Recoil and Hover) and the Winch's "goods bank is full" message (scenario_quarry K); the Cutter wades through Brine (`WADE`, scenario_fluids G), found when a Brine pocket at depth 2714 stopped the cheated bot, which now reaches "Bedrock ahead" at depth 4493 at 144:15 (the Gall pocket at 3391 costs a Pump swap and about 18 minutes). Before it: A5 part 9 seventh piece (the cheated seed 7 bot now reaches depth 4473 at 126:00 and stops on the chamber's bedrock; `--cheat` sets Drill Shaft 9, new `--plug` flag stands the rig over the plug but wedges at depth 461 on seed 7; tests/autoplay.gd only; a full run still needs the plug, a ~55 Node chain and the delivery). Before it: A5 part 9 sixth piece (springs at a quarter of their rate, `D.SPRING_CELLS_PER_S`, Alex's "Slow it"; scenario_depth H; scenario_power C and scenario_collapse loosened where they leaned on the old pace; the cheated bot now reaches depth 3835 at 121:20 with no flood and runs out of cable; no engine change). Before it: A5 part 9 fifth piece (Ferrite seams moved to depth 1600-2300 above the Sulfur, Alex's call, in `spawn_regions.json`; `funnel.gd` takes Throughput through `MU.rate`; the Cutter's `counts_ahead` leaves out its own casing cells, found when a bot stalled on "Obsidian ahead" that was one corner pixel of its own casing; scenario_upgrades C and scenario_quarry J; no engine change; a shaft floods to the surface because springs have no ceiling, raised for Alex). Before it: A5 part 9 fourth piece, Plating gets the bot past the Sulfur (bot researches Plating twice and rebuilds a lost digger; Ferrite is cheated into the bank, its blobs sit at depth 2400+ with the Sulfur; `cutter.gd` drinks oil only while the goods bank has room, because a full bank holds the Funnel's goods back and a Tank of oil then sits Emptying for good; trips to 2756 and on with Plating Mk II; next wall is surface water, steam and Obsidian under the dock after minute 117; no engine change). Before it: A5 part 9 third piece, the Cutter wades through oil (`cutter.gd` `WADE`, `drinkable()`; Alex picked "Wade through"; scenario_fluids F on Sourwater, G new; the cheated bot now reaches depth 2500 by minute 79, where Sulfur corrodes the Tank casing and the Cutter is lost at 84:31, and nothing rebuilds it; no engine change). Before it: A5 part 9 second half, the rig gets down and up (the Winch plow clears static plug rock on the climb, `plow_mask()`; `_plow_down` clears powder beside and under every non-Excavator module on the way down, found when a rubble cell held the Tank at depth 638 and the Cutter tore loose; scenario_quarry H and I; the bot hangs the swapped digger with `_hang` and logs halts with depth; no engine change). The cheated bot loops on the oil: the Cutter halts on Slick at depth 778 to 792, the Pump drains, the Cutter goes back, and the pool has refilled by the next trip; no depth gained in 40 game minutes and each Cutter costs Stone. Before it: A5 part 9 first half, the Pump leads a rig (`pump.gd` reports `room` / `stuck` / `stop`, powered through the Winch; the Winch `_key` includes the digger so a swap lifts a halt; `machines.gd` `_join_rig`; scenario_fluids F; bot swaps Cutter and Pump; no engine change). Alex asked for the Pump beside the Cutter; a shaft is 30 wide so it takes the Cutter's place instead. The cheated bot still stalls: oil at 9:20 sends the rig up and the climb stops at about depth 770 in a plug of cave-in Stone and Dirt. Before it: A5 part 8, Mk I to IV upgrades paid in goods (research steps carry `goods`, `Goals.research_bank`, per-tier `research_bank` in instructions.json, `game.tech_bank`; Throughput, Efficiency and Plating techs act through `MU.rate`, `MU.take_power` and `Casing.wear`; scenario_upgrades; no engine change; the bot has not learned to bank goods for research yet). Before it: A5 part 7, sensors and the Thermoelectric Plate (`sensing/sensor.gd`: Thermometer, Material Sensor and Timer set `m["signal"]`; a module with a signal face named `gate` touching a sensor works only while it is on, `machines.gd` `gated`; `power/thermoelectric.gd` pays for a temperature difference between its two strips; scenario_sensing; no engine change). Before it: A5 part 6, the Shorer (`support/shorer.gd`: powder set as pressed rock into the open air of a strip along its front side; definitions may carry `accepts`, `MU.accepts`; scenario_shorer; no engine change; how a rig carries it beside a Cutter is untried). Before it: A5 part 5, Pump, Sieve and Centrifuge (`logistics/pump.gd` lifts the liquid in front of its mouth into a Tank, a rig module like the Cutter; `pass` may be a list of rules with `power`, `kinds`, `mats`, `heavy`, `light`; `processing/separator.gd`; `M.density_of`; scenario_fluids; no engine change; the Electrolyser waits for wave 2). Before it: A5 part 4, heat processing (`processing/thermal.gd` is the Boiler, Chiller and Furnace by target temperature: it heats the occupied interior cells with `heat_rect`, run by run; `pass` rules take `kinds` / `mats` (`MU.passes`); `processing/caster.gd` casts a liquid slab into a block body (data `casts_to`); `power/combustor.gd` burns `fuel` cells into Hub power; `casing.gd` `wear` takes casing pixels for interior heat past `melts` and for acid; `MU.add` lays solids from the floor up; scenario_thermal; no engine change). Before it: breach leaks scale with the damage (`Casing.leak`: 60 a scan at the edge of wreckage, at least 1; scenario_interior E; no engine change). Before it: A5 part 3 prep, the family mask widened from 16 to 32 bits (engine: uint32 family fields in `crucible_sim.h`, `bin/` rebuilt; `Mats.families` allows 32; checked by hand with two throwaway materials in tags 17 and 30; the first wave 2 materials will test it for good). Before it: machine interiors parts 2 and 3 (`interior_layer.gd` draws every interior in its cavity; the flag is on Press, Macerator, Bus Hopper, Cutter and Laser too; shot_interior.gd). Before it: machine interiors part 1 (Alex wants it before more A5): `"interior": true` in a definition gives a module a sim of its own, `scripts/machines/interior.gd`, engine `put_cells` / `take_cells`; Tank only; `MU.add` / `MU.take` move cells, `contents` is a count recounted at each scan; scenario_interior. Parts 2 (draw it) and 3 (any hollow module, Tank Size resizes) follow, then A5 resumes at part 3. Before it: A5 part 2, Vault cells (`logistics/vault.gd`, data `vault` in logistics.json; `game.power_cap()`, `goods_cap()`, `_trim_to_caps`; scenario_vault; no engine change). Before it: A5 part 1, the goods bank and the Bus Hopper (`game.goods`, `bank_cells`, data `good`; `logistics/bus_hopper.gd`; `goods_panel.gd`; scenario_goods; no engine change). Part 2 is Vault cells (a size for the bank, and the Crucible's power store); the A5 order is in PROJECT_BRIEF. Before it: A4 end, the bot (`--cheat`, alerts, shaft look; tests/autoplay.gd) and what it found: a cheated bot stalls at depth 803 (oil stops the Cutter, then a flooded, caved-in shaft plugs the climb); the fair-pace bot loses its Cutter to cave-ins at 67 min. The Magma-band goal is open, see "Known issues" below. Before it: A4 part 7, the Drone Cage (`haulers/drone_cage.gd`; four drones fetch loose powder from a square round the cage, a click changes the square; scenario_haulers). Before it: A4 part 6, Chute and Conveyor (`logistics/chute.gd` a `pass` pipe; `logistics/conveyor.gd` a belt: powder queue with travel time, bodies driven with `drive_body`, click reverses; scenario_logistics; Bus Hopper to A5). Before it: A4 part 5, Macerator and Press (`processing/macerator.gd` grinds loose bodies at its mouth to what they shatter to and passes it on; `processing/press.gd` squeezes powder into a 96 cell block body; `M.ground_of`, `M.pressed_of`; scenario_processing). Before it: A4 part 4, the tethered Thumper (engine `explode_cone`, `bin/` rebuilt; `excavation/thumper.gd`; the Winch runs a lower / lift / drop cycle for a Thumper load in `winch._thump`, plowing rubble under it as it lowers; scenario_excavators E). Before it: A4 part 3, the full Cutter and the Laser Excavator (Hot rock at Drill Bit 4, a mount face on the Before it: A5 part 2, Vault cells (`logistics/vault.gd`, data `vault` in logistics.json; `game.power_cap()`, `goods_cap()`, `_trim_to_caps`; scenario_vault; no engine change). Before it: A5 part 1, the goods bank and the Bus Hopper (`game.goods`, `bank_cells`, data `good`; `logistics/bus_hopper.gd`; `goods_panel.gd`; scenario_goods; no engine change). Part 2 is Vault cells (a size for the bank, and the Crucible's power store); the A5 order is in PROJECT_BRIEF. Before it: A4 end, the bot (`--cheat`, alerts, shaft look; tests/autoplay.gd) and what it found: a cheated bot stalls at depth 803 (oil stops the Cutter, then a flooded, caved-in shaft plugs the climb); the fair-pace bot loses its Cutter to cave-ins at 67 min. The Magma-band goal is open, see "Known issues" below. Before it: A4 part 7, the Drone Cage (`haulers/drone_cage.gd`; four drones fetch loose powder from a square round the cage, a click changes the square; scenario_haulers). Before it: A4 part 6, Chute and Conveyor (`logistics/chute.gd` a `pass` pipe; `logistics/conveyor.gd` a belt: powder queue with travel time, bodies driven with `drive_body`, click reverses; scenario_logistics; Bus Hopper to A5). Before it: A4 part 5, Macerator and Press (`processing/macerator.gd` grinds loose bodies at its mouth to what they shatter to and passes it on; `processing/press.gd` squeezes powder into a 96 cell block body; `M.ground_of`, `M.pressed_of`; scenario_processing). Before it: A4 part 4, the tethered Thumper (engine `explode_cone`, `bin/` rebuilt; `excavation/thumper.gd`; the Winch runs a lower / lift / drop cycle for a Thumper load in `winch._thump`, plowing rubble under it as it lowers; scenario_excavators E). Before it: A4 part 3, the full Cutter and the Laser Excavator (Hot rock at Drill Bit 4, a mount face on the
  Cutter, `rig_of` and `powered` set by every mover, `excavation/laser.gd` with Filler; scenario_excavators).
  Before it: A4 part 2, Turntable (`movers/turntable.gd`; the engine's `drive_body` gained a spin, `bin/`
  rebuilt; `MU.drive` takes a spin; the hub holds each joined module on its pose in the hub's frame and stops
  with "Blocked." when an arm is held back). Before it: A4 part 1, Piston and Gantry (`movers/slide.gd`; `MU.drive` sums the velocity every mover
  asks of a module and machines.gd hands it to the engine once; `MU.rig` is the shared load walk; a placed
  module joins free faces at once (its scan still waits: scanning the Winch at placement shifts the rig's rest
  height and the Cutter's front slice can read its own wall, a latent edge in cutter.gd); clicking a mover cycles run / out / back; scenario_movers). A mover is bolted and
  its load is the module at its mech face, so a mover carried by another mover waits for the Turntable PR
  (the engine change for rotation). Before it: A3 legacy hard cut (branch claude/alpha-legacy-cut-v5z1ft). The Drill, Thumper, Borer,
  Hopper, Spout, Floodgate, Waterwheel, Steam Turbine, Cache, Relay Mast and Warren are gone from
  the code, the data and the save (VERSION 2). What stands: Hub and Crucible (fixed), Node (the old
  Conduit), Bulkhead and Brace (the old Strut) as structures in `scripts/building.gd`, and the Lab
  and the Lamp as modules (data/modules/support.json, scripts/machines/support/). The Warren returns in
  A4 as the Drone Cage. The tutorial in data/instructions.json is written around the quarry (rig,
  30 Stone, Lab, one research, depth 500, 20 Water). Machines draw power from the Hub's stock while
  a Node or the Hub is in reach (`MU.networked`); the packet network is Hub-only and still carries
  blueprints, repairs and the Crucible's goods and power. Modules now see and glow
  (`D.LIGHT_PILOT`, `D.SIGHT_MACHINE`, a lit Lamp `D.LIGHT_LAMP`, the Cutter senses pockets) because
  the Drill used to be what lit the descent. Retired tests: scenario_digging, scenario_warren,
  descent, smoke_v2, and the shots of removed buildings. scenario_power, scenario_research,
  scenario_light, scenario_bodies, scenario_depth, scenario_run, scenario_chemistry and scenario_goals
  were cut down or rewritten to what is left. tests/autoplay.gd is a small quarry bot now. No engine
  change: `bin/` is untouched.
- Gaps the cut exposes (written down, none fixed here):
  - Tier 2 is out of a fair run's reach (A7 baseline): the last tier 1 cable level is 1200 rows and the first Glimmer on seed 7 is at row 1680 to 1720, so a fair rig stops at 1200 with nothing to open. The cheated bot starts at cable 4350 and never meets it. A proposal waits on Alex (plans/a7-tuning-proposal.md, change A).
  - Pacing. The quarry bot on seed 7 has banked 25 Stone after 90 game-minutes, so Instruction 2 (30
    Stone) is still slow: a trip banks a few Stone and the rig waits on power. The Hub trickles 0.2 power/s and a Lab eats 2/s, so research starves until Windmills
    land; the quarry's first Tank is a few Stone; a rig hits Stone at about row 200 on seed 7 and
    waits on Drill Bit (see the bot baseline below). Tuning belongs to the end of Alpha.
  - (Fixed after the cut.) The rig no longer stalls "jammed on the way up" on seed 7 at about row 450.
    Cause: loose sand slumps into the shaft behind the rig, lodges in the Tank's open hook hole and
    piles on its roof, and bodies can't push powder. Fix: a cable's hook stays shut (`_join` skips
    tether faces) and the Winch ploughs loose powder (not rock) off the rig's path on the way up
    (`winch.gd` `_plow`; the spoil is lost; `plowed` counts it). A rig under a rubble of loose powder
    gets through the same way; a static plug or a rigid body above it still jams it. scenario_quarry G.
  - Tiers 2 and 3 have no techs of their own (only upgrade levels), so discovering Glimmer and
    lava opens nothing new until A5.
  - The Crucible draws 4 power/s from a 100-power Hub store: the Caches that used to bank it are
    gone, so lighting it wants far more Windmills than the starter kit supplies (a battery or
    Vault module is the fix; A5).
  - No breach alerts or pause (water or lava breaks into a tunnel) and no cells-drilled stat.
    The jacket, Saw, Homing, Ember Brood, Sounding, Thumper Charge and Steam Turbine techs went
    with their buildings.
  - Water and lava have no machine that handles them but the Cutter's Tank and the Funnel; the
    Funnel only banks, nothing pumps or pours.
  - The framework's three test modules (Box, Plug, Cap) still sit at the bottom of the Build list.
  - The quarry bot (below) is a pacing probe, not a run: the full bot returns at the end of A4.
  - A Thumper that lands tilted can wedge at the floor of its shaft: the Winch lifts against it and the cable does not shorten for the whole 400 seconds the
    test watched (scenario_excavators E, three of six trial x positions; where it wedges depends on the ground). Untouched; whether it frees itself later is untried.
  - A save keeps modules' positions to within a cell (the Funnel and Winch drift by one cell
    across a load); scenario_run allows 1.5.
  - The Node-as-module question (A3's plan) is settled the cheap way: Node stays a structure
    because the packet network, repairs and fog sight hang off it.
- Next: A6 is done. A7 (re-baseline the bot on the 1024 world and the biomes, tune the economy) is next; nothing is queued. The proposal for the grid is plans/a6-engine-grid-proposal.md. Earlier note: the A5 plan is done. Part 9 is closed (Alex, 10-08: "Stop here"): the bot digs to the chamber's bedrock at depth 4473 and the Crucible delivery waits for a later phase (it needs a rig over the plug, a hole through it, a Node chain of about 55 Nodes and the delivery of 32 Glimmer, 48 Obsidian, 64 Water at 4 power/s). Part 3 is done without Recoil and Hover (Alex: skip the exotic materials for now); they stay in `/mnt/project-files/plans/a5-wave2-draft.md` for a later pass. Thirteenth slot: wave 2 has twelve, so the world has 24 authored materials; Pumice returns as a Caster product if wanted. The full-bank card is closed ("Leave it"). The end-of-A5 usage checkpoint is next, then A6, which needs Alex's separate go. Open from A4, Alex's call: what answers the shaft hazards.
  Plan: claude/ALPHA_PLAN.md. The spawn-region system and the Spoil Heap are in `main` (PR #6).
  The wave 1 rows only place pockets and seams by depth band, with no placement relative to
  aquifers, lava or Sulfur (the table has none); A6's biomes can do better.
- A3 starter kit modules (PR #9): Cutter Excavator, Tank, Winch, Funnel and Windmill, built from
  data/modules/*.json and a behaviour script each under
  scripts/machines/{excavation,logistics,movers,power}/; scenario_quarry covers them. A rig is a Tank
  hooked to a bolted-down Winch with a Cutter joined under it and a bolted Funnel above: the Cutter
  cuts a 30-wide tunnel (soft ground; Drill Bit raises the hardness), the Winch lowers the rig as rows
  open and hauls it up when the Tank is full, the Funnel banks what the Tank passes into the Hub.
  Cable length is Drill Shaft's; Tank Size is a new upgrade. The engine changed there
  (`drive_body`, a body that takes its velocity from the game). Still open: welding modules into one
  body (links are logical, the Winch moves each rig module at the same velocity), casing melting
  and corrosion, power faces (power moves through the stock).
- Before the cut: A2 wave 1 materials (twelve new materials and seven made by reactions, ids 35
  to 53; claude/WAVE1_MATERIALS.md says what each does, and "Built as" there lists where the build
  differs from the table, plus spawn rows for all of them and scenario_wave1; the engine changed),
  and A1, temperature and reactions (every cell has a temperature, reactions name families, the
  Lab Bench on the title screen paints any material and shows the field with F6, unseen ground is
  black). Phase 10 and everything before it are in `main`.
- A3 machine framework core (PR #5): modules as rigid bodies with typed faces, casing
  integrity, breach and wreckage, in scripts/machines/ and native/src/modules.cpp. Test
  modules only; the module groups build on it. Casing melting and corrosion are still
  TODO (casing.gd), now that A1's temperature field exists.
- A3 goal layer v1 (in `main`, PR #4): `scripts/goals.gd` + `data/instructions.json`
  (Hub orders, skippable tutorial, chapters, per-tier research goods), `scripts/goals_panel.gd`,
  Hub trickle 2 -> 0.2 power/s, `game.goals` in the save. The tutorial steps were rewritten
  around the quarry in the A3 cut.
- Settled in phase 10: water still quenches hot rock slowly (a staged steam room would die
  otherwise) and condensing steam loses half, so a boil cycle in a finished tunnel dies away.
- Known rough edges: the screenshot scripts that remain (shot_bodies, shot_chemistry,
  shot_quarry, shot_goals, shot_help, shot_title, shot_temperature), flow and scenario_water* may
  still use v2 coordinates; the top bar clips the Help button when the depth label shows; a
  network rebuild on a dense 380-building network takes ~34 ms; an aquifer's spring buried by
  rubble stops refilling it.

## Test baseline (all must hold before committing)
- `bash native/run_tests.sh` (about 35 minutes): every scenario (twenty-nine: power, goals, research, chemistry,
  light, collapse, bodies, modules, quarry, movers, excavators, processing, logistics, goods, interior, vault, thermal, fluids, shorer, sensing, upgrades, haulers, depth, temperature, generators, wave1, wave2, run, spawn) and engine_compare end `FAILURES: 0`. Suites
  that build deep set-pieces fix their rows' ambient: scenario_depth's `keep_hot` (hot rock near the
  surface), scenario_bodies' `keep_cool` (a pool in the Magma band).
- Temperature pass (A1): every 8 ticks, 150 to 200 of the map's 3840 chunks awake in a
  fresh game (hot rock, lava and water around the Stone-Magma boundary and the lava
  pockets). It costs about 0.2 ms a tick: a fresh game's bare `sim.step` went from about
  0.1 to 0.3 ms, measured against main on the same container. A loaded run steps exactly
  as the saved one (the pass's awake chunks are saved too).
- Quarry bot (tests/autoplay.gd, seed 7, rig left of the Hub, A4): fair pace, Drill Bit at 4:26, depth 500 at
  23:20, about 640 at 55:00, Weft at 61:00, cave-ins from depth 600 up the shaft, Cutter lost at 67:00. `--cheat`:
  depth 803 at about 20 minutes, then halted by Slick (oil) and jammed on the climb by a plug of static rock
  and water. About 7 minutes of real time for 90 of game time; a 6 hour cheated run takes about 25.
- Network bench (tests/bench_net.gd, Nodes and Bulkheads only since the cut): 368 buildings, a rebuild in
  about 22 ms and 3.5 to 6.5 ms a tick over the first minute on this container.
- `tests/prof_scale.gd`: a fresh game ticks in about 0.7 ms (1.3 ms on a slower
  container, where main measured the same; compare against main on the same machine).
  A1: 1.55 ms against main's 1.40 on the same container (the sim's share 0.11 to 0.39).
  A2 (wave 1 spawn rows in the world): 2.92 ms against main's 2.47 on this container, the
  sim's share 1.29 against 0.58 right after worldgen. Bisected: no single material owns it;
  Sourwater, Quickmire, Weft and Wisp pockets keep the most chunks awake. It settles to
  about 1.0 ms of sim (37 chunks awake against 13) after 3000 ticks.
- `tests/bench_bodies.gd`: 100 slabs falling at once, about 3.5 ms a tick (worst 14).
- Saving (phase 10): a 45-minute run writes in about 80 ms (sim snapshot ~30 ms, 47 MB
  raw, ~480 KB on disk) and loads in about 50-100 ms.
- `python3 native/lsp_check.py . <changed .gd files>`: no warnings.

## Scale (phase 8b)
- D.S = 10: everything built is S times its v2 size; ranges, speeds and radii S times;
  amounts counted in cells S * S times. World layout 3x across, 5x down, features 4x.
- Tests lay v2 set-pieces out with P(x, y) / R(x, y, w, h), scaling about the Hub's pad
  (see any scenario_*.gd); pieces too far out for that get their own origin.
- Light, fog and sense work in 4 x 4 blocks.

## The game now
World: 1024 x 5120 cells (768 before A6), seed-generated. Layers: surface (sky to row 200), Topsoil (dirt
to ~1500, packed dirt thickening toward its bottom, stone lumps, sand pockets, gravel
patches, coal seams, two aquifers lined with clay and settled into arches), a gravel bed
at the boundary, Stone (to ~3000: glimmer veins with lodes, caves, water pockets, coal,
sulfur nodules), Magma (hot rock from a wobbling line near 3000, lava pockets, a lava
lake, sulfur crusts), and the Chamber (bedrock shell, the Crucible on an altar under a
40-wide plug of hot rock). Worldgen features draw from their
own noise or RNG so each seed's layout stays put.

Engine (C++ GDExtension, Noita-style): 32x32 chunks with dirty rects, four checkerboard
passes (threads), per-chunk RNG, then rigid bodies and particles; the size is set at
runtime (set_size). Materials and
reactions are data. Each cell has an aux byte (burn time or gas life) and a fall speed.
Powders, liquids (density sorting, free fall), gases (buoyancy, life), fire that needs
air, free particles, blasts by rays, light per 4x4 block (sky down open shafts, glowing
materials, lamps; rock shadows; only near what's watched or explored on screen), and slow
passes: erosion, weathering (ceiling drip), wash (water wear), collapse (spans), tremors,
temperature (A1). A cell with a reaction partner beside it stays awake until it reacts.

Temperature (A1): an int16 per cell in eighths of a degree. Every 8 ticks a pass over
the chunks flagged for it (same checkerboard, threads) moves each cell toward each
neighbour by the pair's lower `conduct` (rock 0.2, powder 0.12, liquid 0.4, gas and air
0.04), sources toward what they `hold` (lava 1100, fire 450, a burning cell its burn
`temp`), and every cell toward its row's ambient by its `sink` (rock 1, powder 0.25,
else 0; rock feels no pull within 32 degrees of it). Then `heats`/`cools` turn a cell into its
hot or cold form (water boils at 100 for 60 degrees; hot rock under 250 is stone, stone
over 800 hot rock, over 1200 lava; lava under 600 obsidian) and `kindle` lights fuel with
an open side (coal 700). A chunk sleeps once no cell in it moves more than an eighth of
a degree a pass. Ambient by depth (`D.ambient_at`): 15 at the surface, 30 at Topsoil's bottom, 90
at the Stone band's, climbing over 50 rows to 550 in the Magma band; the bench is a
flat 20. A cell placed from outside (set_cell) keeps the temperature of what it replaced
unless its data has `temp` (water 20, steam 110, hot rock 550); one made inside the sim
(a reaction, a transition) keeps the cell's. Bodies carry their cells' temperatures.
`refresh_heat` keeps the hottest cell per 4x4 block for the shader (hot rock's glow,
the F6 view).

Reactions (A1): a side can name a family (`family` tags in the data: Fuel for coal and
sulfur, Corrosive for sulfur and its fumes, Molten for lava). `Mats.expand_reactions`
writes every member pair out, material pairs first, and the engine keeps the first rule
for a pair, so a rule written for two materials overrides the family's. Optional
`min_temp`/`max_temp` (the first cell's), `heat` (degrees both outputs gain) and
`catalyst` + `boost` (a member of that family among the 8 neighbours multiplies the
chance). Today's rules: Molten + Water to obsidian and steam, Fire + Water to steam; hot
rock's boiling moved to the temperature pass.

Lab Bench (A1): Lab Bench on the title builds a flat open room over a bedrock floor
(`WorldGen.bench`, ambient 20), the whole map known, the brush in hand with every
material plus Heat, Cool and Blast (F9; [ ] material, Shift + [ ] size). F6 paints the
temperature over the map anywhere; the cursor line reads the cell's degrees (and its
families on the bench). It never touches the save.
It also keeps the "as last seen" map and flags 256 x 256 render tiles that changed. The GDScript fallback sim
(sim.gd) lacks chemistry, per-cell light, settling, collapse, holds and wash.

Collapse: every ground material has a span (widest open run it roofs), an overhang (the
slope an arch narrows by, cells a row) and a cave rate. Wider ceilings cave from the
middle into an arch or until their rubble props them: each stretch of ceiling due to go,
with its cave rate a sweep, breaks off a piece (24-64 wide, 6-20 deep, ragged, narrowing
upward like the arch) as a rigid body. Stretches under 4 wide, or over a gap under 20
tall (a crawlspace), crumble a cell at a time as before. Stone is cohesive (hangs only
from stone or never-giving rock; a notch with stone within 8 cells above it doesn't cut
the row); hot rock is stone's kin, so the two hang from each other.

Rigid bodies (engine, bodies.cpp): a piece keeps its own bitmap and pose, and sits in
the grid as ordinary cells tagged with its id (powder piles on it, water flows round it,
buildings and modules rest on it; the slow passes leave it alone). It falls like everything else
(900 cells/s^2, up to 600), turns, bounces a little, slides and tips over edges, sinks
through liquid at up to 96 cells/s (pushing the liquid up), and is shoved by blasts. An
impact faster than its toughness (90 cells/s + 20 per point of durability: dirt 130, a
drop of about 9 cells; stone 190, about 20) shatters it into what its ground crumbles
into (mostly powder falling on, an eighth thrown as debris); a gentler one leaves it
lying, and after half a second still it's ground again. Cells knocked off it (blasts,
burning) are lost from it; under 12 cells left and it crumbles.
Settling holds freshly dug ground 20 s. Brace holds are permanent. Worldgen runs
`stabilize` so the map starts standing.

Ground (spans): gravel 40 (fast, water-proof), dirt 70 (weathers; water turns it to sand),
coal and sulfur 90 (coal comes down twice as fast as dirt), clay 110 (water-proof), stone
150 (cohesive; water turns it to dirt, slowly), hot rock 150 (as stone; water on it heats
past 100 and boils off, and enough of it cools the face under 250, to stone), packed dirt
240 (slow to dig, water softens it slowly), glimmer/obsidian/bedrock never. Sand is a
powder that water carries off.

Heat (phase 9, on the temperature field since A1): hot rock is the Magma band's stone,
held hot by its 550-degree ambient; dug up and carried shallow it cools to stone within
half a minute. Water boils on it at about the old rate, and enough of it cools the face
under 250 back to stone. The Cutter reads the material, not the degrees: hot rock and lava
are past what Drill Bit opens (the jacket and Saw techs went with the Borer). Condensing
steam: half becomes water, half is lost (Steam's expires_alt/alt_chance), so a boil cycle in
a finished tunnel dies away.

Resources: Stone, Glimmer, Obsidian, Water, Power. A unit is 600 cells (CELLS_PER_UNIT).
Goods (A5): a material with data `good` banks as units under its own id in `game.goods` (a cell pays `worth` / 600; all
goods have worth 6), listed in the HUD's Goods terminal. Funnels and Bus Hoppers bank them; a Bus Hopper spits them back out.
The goods bank holds `HUB_GOODS_CAP` (30) units in all kinds together, the power store `HUB_POWER_CAP` (100); every Vault
cell in a bank (cells side by side join by power faces) with a Node or the Hub in reach adds 150 power and 40 goods
(`game.power_cap()`, `goods_cap()`). Full, a Funnel and a Bus Hopper hold goods back (stockpile materials still bank).
Lose a cell and power over the new cap is lost, goods scale down together, and an alert says so. Power that coal
banked over the cap stays until a cell is lost.
Coal pays Stone + Power, sulfur Stone + Glimmer. Deposits are worth more a cell (data
"worth": glimmer, obsidian, coal, sulfur and their shards 6x; `D.cell_units(m)`).

Network: the Hub sends packets along Nodes (relays, 160 apart); a blueprint or a repair links to
a relay within 80. Blueprints fill by packet, and so do the Crucible's goods and power. Modules
need no link of their own: they draw power from the Hub's stock (cap 100, 0.2/s trickle, plus
Windmills) while a Node or the Hub is within 80 (`MU.networked`). Links have HP (fire, sulfur,
lava wear them); broken links and hurt buildings ask for a Stone. A Brace needs no link. Dragging
with a build tool lays a line (Nodes 0.75 of their range apart, Bulkheads side by side, 40 at
most); what can't go down yet is a plan that goes down once the network reaches it; right-click
cuts it.

Buildings (key): Hub; Node 1; Bulkhead 2 (drag a wall); Brace 3 (instant beam rock to rock, up
to 160 long and 10 thick, props and holds rock within 50 of each end; snaps without its anchors;
needs the Brace tech). Everything but the Hub and Crucible must stay anchored (rock, resting
powder under it, or a held-up building touching; corners count) or it falls straight down (600
cells/s^2, up to 400; through liquid at most 100) and relinks where it lands; past 200 cells/s
it's hurt, up to 75% of its HP at 400, and so is a building it lands on. Placement ghosts snap
to legal spots within 50.

Modules (Build list buttons, no keys; the Bus Hopper after its tech): Cutter Excavator, Tank, Funnel, Winch and Windmill (the
starter kit, from the start), Lab (from the start) and Lamp (the Lamp tech). The Lab turns up to 2
power/s of the Hub's stock into research and takes the goods the tech wants out of it too; a Lamp
lights 200 cells while the stock pays its 0.1/s. Every module glows a little (30 cells) and watches
its surroundings, so a quarry is never dark; the Cutter also senses hidden pockets. A module placed
for the first time is a minor milestone.

Hazards: water drowns Nodes, lava destroys them, steam scalds them; fire, corrosion
(sulfur) and lava hurt buildings; blasts hurt nearby buildings and links; falling rock
hurts a building it hits (6e-4 HP per cell of it per cell/s: an 800-cell slab at 300
does 144) and a link it falls through (1e-4 the same way, once); weathering and cave-ins;
Crucible tremors (Tremor Dampers: none within 120 of a Brace). There are no breach alerts
since the Drill left.

Research: Labs turn power (and Stone, Glimmer, Obsidian or Water for later tiers) into the picked
tech (T). Tiers open by discovery: 2 at the first Glimmer banked, 3 at the first lava seen, 4 when
the Crucible is in view. The techs are the Lamp, the Brace and Tremor Dampers (tier 4), plus the
Upgrades column with levels: Drill Bit (the Cutter's hardness and speed), Drill Shaft (the Winch's
cable) and Tank Size. A Lab turns at most 2 power/s into research.

Fog and light: underground is dark; a block is explored when it's lit and within sight
of a building; explored ground shows live while lit, as last seen (dimmed) when not.
Since A1, ground never seen is black, bedrock and the chamber shell included; the
glimmer glints and lava glow that showed through the fog are gone. A Cutter's sense
outline still shows.

Crucible: 32 Glimmer, 48 Obsidian, 64 Water delivered while charging (1.5 packets a
second: about 1.6 min), and 4 power/s drawn from a 20-power reserve (filled ahead of
every machine); the charge drains if packets stop for 5 s or it's out of power for 5 s;
tremors every 15 s while charging. The Hub's packets take ~10 s to get down there. With the
Caches gone its power has to come out of the Hub's 100-power store: see the gaps.

A run (phase 10): the Hub can be destroyed (it patches itself with its own Stone every
10 s at most under 60% HP, warns under 35%); then the run is lost and its save erased.
Title screen (Continue, Start Run with an optional seed, Quit; Esc), one save slot
(user://run.save: on quit, going to the title, every 5 minutes), speeds (pause, 1x,
2x, 4x), milestones and an end panel (Keep going after a win, Replay, New seed, Title).

## Standing quirks worth knowing
- Tests that carve rooms into seed 7 wall them with plain dirt first (sand pockets pour,
  wide rooms cave), and sweep loose powder out of a spot before placing (erosion drops
  a few cells into any shaft). Measure collapse locally, not with the global `get_caved()`.
- Light is only worked out near what buildings watch and explored ground in the view:
  a test that reads light elsewhere explores the spot and points the camera there.
- Cave-in alerts fire only on explored ground.
- A cell set from outside keeps the temperature of what it replaced: a test room carved
  over the Magma band's lava is full of 1100-degree air. Set the rows' ambient with
  `sim.set_ambient(rows)` and call `sim.reset_temps()` once the room is built.
- The quarry bot (tests/autoplay.gd) builds the rig, a Lab and a Windmill on a strip it
  flattens beside the Hub and researches in a fixed order. It measures the pace; it isn't a
  test and isn't in run_tests.sh.
- A test that places a module hands it ground to stand on: a module that falls far enough
  shatters or settles (the engine drops it from the registry), so tests flatten a strip and
  place on it.
- Not yet: sound.
