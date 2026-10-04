# Crucible: status (lean; read at the start of every session)

The game as it stands, for working on it. Numbers live in scripts/defs.gd and
data/materials.json; this says what exists and how it behaves. The full per-phase
history (what shipped when, old numbers, test notes) is the root STATUS.md:
Claude adds a section at its top each phase and doesn't need to read the rest.

## Handoff
- Last done: A4 part 4, the tethered Thumper (engine `explode_cone`, `bin/` rebuilt; `excavation/thumper.gd`; the Winch runs a lower / lift / drop cycle for a Thumper load in `winch._thump`, plowing rubble under it as it lowers; scenario_excavators E). Before it: A4 part 3, the full Cutter and the Laser Excavator (Hot rock at Drill Bit 4, a mount face on the
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
  - A save keeps modules' positions to within a cell (the Funnel and Winch drift by one cell
    across a load); scenario_run allows 1.5.
  - The Node-as-module question (A3's plan) is settled the cheap way: Node stays a structure
    because the packet network, repairs and fog sight hang off it.
- Next: A4, in order: Macerator and
  Press, the Drone Cage with Chute and Conveyor, then the test and bot rewrite.
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
- `bash native/run_tests.sh` (about 10 minutes): every scenario (sixteen: power, goals, research, chemistry,
  light, collapse, bodies, modules, quarry, movers, excavators, depth, temperature, wave1, run, spawn) and engine_compare end `FAILURES: 0`. Suites
  that build deep set-pieces fix their rows' ambient: scenario_depth's `keep_hot` (hot rock near the
  surface), scenario_bodies' `keep_cool` (a pool in the Magma band).
- Temperature pass (A1): every 8 ticks, 150 to 200 of the map's 3840 chunks awake in a
  fresh game (hot rock, lava and water around the Stone-Magma boundary and the lava
  pockets). It costs about 0.2 ms a tick: a fresh game's bare `sim.step` went from about
  0.1 to 0.3 ms, measured against main on the same container. A loaded run steps exactly
  as the saved one (the pass's awake chunks are saved too).
- Quarry bot (tests/autoplay.gd, seed 7, rig left of the Hub): Drill Bit at 4:26, depth 210 at 5:00,
  306 at 10:00, 452 at 14:00, then the rig stalls on the way up with a full Tank and stays there
  (the same stall on main 0a6bcb8 with the same rig); 11 techs by 1:03. About 7 minutes of real time
  for 90 of game time. Built right of the Hub the rig reaches about 265 and crawls.
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
World: 768 x 5120 cells, seed-generated. Layers: surface (sky to row 200), Topsoil (dirt
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

Modules (Build list buttons, no keys): Cutter Excavator, Tank, Funnel, Winch and Windmill (the
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
