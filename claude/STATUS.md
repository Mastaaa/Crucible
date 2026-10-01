# Crucible: status (lean; read at the start of every session)

The game as it stands, for working on it. Numbers live in scripts/defs.gd and
data/materials.json; this says what exists and how it behaves. The full per-phase
history (what shipped when, old numbers, test notes) is the root STATUS.md:
Claude adds a section at its top each phase and doesn't need to read the rest.

## Handoff
- Last done: A1, temperature and reactions (branch claude/alpha-a1-temperature-w6sw2x).
  Every cell has a temperature; hot rock, boiling, quenching and coal catching fire run
  on it; reactions can name families and carry a catalyst and a temperature window; the
  Lab Bench (title screen) paints any material and shows the field (F6). Unseen ground
  is black. Phase 10 and everything before it are in `main`.
- Next: A2 (wave 1 materials, spec in claude/WAVE1_MATERIALS.md; the spawn-region
  system and the Spoil Heap) and A3 (the machine framework). Plan: claude/ALPHA_PLAN.md.
  A1 left three engine extensions for A2, to arrive with the materials that need them:
  impact triggers (per-cell fall speed), a one-cell-to-many swell, a timed setting stage.
- Placeholder: A3 cuts the current buildings (Hub, Crucible, Conduits, Lab, Lamp, Strut and
  Bulkhead stay; the Warren becomes the Drone Cage). Phase 10's jacket rules (lava shield,
  quenching, drinking), the tuning numbers tied to Borers and research, and the bot's Borer
  and Conduit logistics go with it; don't polish them. The run shell (title, save slot,
  speeds, win and lose, milestones) and the bot's harness (checkpoints, dumps, milestone
  timeline) should carry over.
- Settled in phase 10 (tuned with the bot): mites at v2's pace against the buildings;
  the Turbine's 4/s now reachable (0.4 a cell, as fast as a room of steam rises); water
  still quenches hot rock slowly (a staged steam room would die otherwise) and condensing
  steam loses half, so the jacket's steam stops cycling in a finished tunnel.
- Known rough edges: the screenshot scripts (bar shot_bodies and shot_title), smoke_v2,
  flow and scenario_water* still use v2 coordinates; the top bar clips the Help button
  when the depth label shows; a network rebuild on a dense 380-building network takes
  ~34 ms; an aquifer's spring buried by rubble stops refilling it; a jacket's steam
  still scalds the Conduit line behind it on the way down (Borers that bore down
  through hot rock lose Conduits to it; the bot relays them).

## Test baseline (all must hold before committing)
- `bash native/run_tests.sh` (about 8 minutes): every scenario (twelve, with
  scenario_temperature) and engine_compare end `FAILURES: 0`. Suites that build deep
  set-pieces fix their rows' ambient: scenario_depth's `keep_hot` (hot rock near the
  surface), scenario_bodies' `keep_cool` (a pool in the Magma band).
- Temperature pass (A1): every 8 ticks, 150 to 200 of the map's 3840 chunks awake in a
  fresh game (hot rock, lava and water around the Stone-Magma boundary and the lava
  pockets). It costs about 0.2 ms a tick: a fresh game's bare `sim.step` went from about
  0.1 to 0.3 ms, measured against main on the same container. A loaded run steps exactly
  as the saved one (the pass's awake chunks are saved too).
- Descent probe (tests/descent.gd, seed 7): head at 500 at 1.5 min, 700 at 5.5, 1000 at
  13.5, 1400 at 19.5 (research is the clock early on).
- Autoplay bot (tests/autoplay.gd): on every seed tried (5, 7, 11, 23) the Stone band
  at ~20-21 min, Tier 2 ~21-22, Tier 3 ~26-28, bedrock ~51-52, Tier 4 ~53-54; lit at
  1:00:01 (7), 58:39 (11), 59:07 (23). A run takes about an hour of real time;
  `--save`/`--load` checkpoints and `--threads=1` (three seeds side by side) help.
  Its logistics (water, Stone, lines through steam) still stall some runs: see the
  root STATUS's phase 10 section.
- Network bench (tests/bench_net.gd): about 2.5 ms a tick once its floors cave in (4.1 at
  60 s on the slower container, same as main there).
- `tests/prof_scale.gd`: a fresh game ticks in about 0.7 ms (1.3 ms on a slower
  container, where main measured the same; compare against main on the same machine).
  A1: 1.55 ms against main's 1.40 on the same container (the sim's share 0.11 to 0.39).
- `tests/bench_bodies.gd`: 100 slabs falling at once, about 3.5 ms a tick (worst 14).
- Saving (phase 10): a 45-minute run writes in about 80 ms (sim snapshot ~30 ms, 47 MB
  raw, ~480 KB on disk) and loads in about 50-100 ms.
- `python3 native/lsp_check.py . <changed .gd files>`: no warnings.

## Scale (phase 8b)
- D.S = 10: everything built is S times its v2 size; ranges, speeds and radii S times;
  amounts counted in cells S * S times. World layout 3x across, 5x down, features 4x.
- Tests lay v2 set-pieces out with P(x, y) / R(x, y, w, h), scaling about the Hub's pad
  (see any scenario_*.gd); pieces too far out for that get their own origin.
- Mites work in 4 x 4 bites (warren.gd); light, fog and sense in 4 x 4 blocks.

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
buildings rest on it; the slow passes leave it alone). It falls like everything else
(900 cells/s^2, up to 600), turns, bounces a little, slides and tips over edges, sinks
through liquid at up to 96 cells/s (pushing the liquid up), and is shoved by blasts. An
impact faster than its toughness (90 cells/s + 20 per point of durability: dirt 130, a
drop of about 9 cells; stone 190, about 20) shatters it into what its ground crumbles
into (mostly powder falling on, an eighth thrown as debris); a gentler one leaves it
lying, and after half a second still it's ground again. Cells knocked off it (blasts,
drills, burning) are lost from it; under 12 cells left and it crumbles.
Settling holds freshly dug ground 20 s. Strut holds are permanent. Worldgen runs
`stabilize` so the map starts standing.

Ground (spans): gravel 40 (fast, water-proof), dirt 70 (weathers; water turns it to sand),
coal and sulfur 90 (coal comes down twice as fast as dirt), clay 110 (water-proof), stone
150 (cohesive; water turns it to dirt, slowly), hot rock 150 (as stone; water on it heats
past 100 and boils off, and enough of it cools the face under 250, to stone), packed dirt
240 (slow to dig, water softens it slowly), glimmer/obsidian/bedrock never. Sand is a
powder that water carries off.

Heat (phase 9, on the temperature field since A1): hot rock is the Magma band's stone,
held hot by its 550-degree ambient; dug up and carried shallow it cools to stone within
half a minute. Water boils on it at about the old rate. The machines still read the
material, not the degrees: hot rock stops the Drill and Borers until the Coolant Jacket; then each
cuts it for 1 Water per 2000 cells from a 4-Water tank the network fills (a Borer
charging up waits for it while there's water), and the water goes up as steam from the
cut (a Borer steps past it, so it leaves by its tail). Mites dig it with Ember Brood;
Thumpers break it like stone. Phase 10: Borers stop short of lava ("Lava ahead");
with the jacket a Drill or Borer facing lava quenches it to obsidian from its tank
(a cell of water a cell) and cuts it with the Saw; a jacketed Borer touching lava or
flames boils 0.05 water/s instead of burning; water that lands on or against a
jacketed Borer goes into its tank. Condensing steam: half becomes water, half is lost
(Steam's expires_alt/alt_chance), so a boil cycle in a finished tunnel dies away.

Resources: Stone, Glimmer, Obsidian, Water, Power. A unit is 600 cells (CELLS_PER_UNIT).
Coal pays Stone + Power, sulfur Stone + Glimmer. Deposits are worth more a cell (data
"worth": glimmer, obsidian, coal, sulfur and their shards 6x; `D.cell_units(m)`).

Network: the Hub sends packets along Conduits (relays, 160) and Relay Masts (280); every
other building links to a relay within 80. Blueprints fill by packet. Machines hold a
10-power reserve refilled by packet from the nearest Hub, Cache or generator with stock.
Links have HP (fire, sulfur, lava wear them); broken links and hurt buildings ask for a
Stone. Struts need no link. Dragging with a build tool lays a line (relays 0.75 of
their range apart, Lamps a light apart, the rest side by side, 40 at most); what can't
go down yet is a plan that goes down once the network reaches it; right-click cuts it.

Buildings (key): Hub; fixed Drill (right of the Hub, 3-wide shaft straight down; Drill
Bit / Drill Shaft upgrades; 30 wide); Conduit 1; Thumper 2 (timed blasts, thrown by them,
draggable); Hopper 3; Bulkhead 4 (drag a wall); Lab 5; Spout 6; Floodgate 7; Waterwheel
8; Cache 9; Lamp 0; Borer B (points four ways; Homing; digs at 0.3 of full pace since phase 10); Relay Mast M; Steam Turbine U
(steam rising into its bottom leaves by its top; 0.4 power a v2 cell up to 4/s, about
the 1000 cells a second a room of steam pushes through its core); Warren G (mites
nibble a chamber in 4x4 bites, then tunnel to a marker and dig a circle); Strut X
(instant beam rock to rock, up to 160 long and 10 thick, props and holds rock within 50
of each end; snaps without its anchors). Everything but the Hub and Crucible must stay
anchored (rock, resting powder under it, or a held-up building touching; corners count)
or it falls straight down (600 cells/s^2, up to 400; through liquid at most 100) and
relinks where it lands; past 200 cells/s it's hurt, up to 75% of its HP at 400, and so
is a building it lands on. Placement ghosts snap to legal spots within 50.

Mites (8d): a mite walks and clings on its own (warren.gd), at v2's pace against the
buildings since phase 10 (MITE_SPEED 4, MITE_MOVE_PER_S 20 S); when it has nothing within two
bites to cling to, or a blast reaches it, it becomes a 3x3 body of material Mite (a
creature body: it never turns into ground) that falls, tumbles and piles up, and once
it's lain still a third of a second it walks again from the bite it's in (heading home).
A landing faster than 480 cells/s (a fall of about 130 cells) kills it; on contact it
grips (no rolling); a body moving into it with
3000 or more (cells x cells/s) crushes it, less squeezes it into an open bite beside.

Hazards: water drowns Conduits, lava destroys them, steam scalds them; fire, corrosion
(sulfur) and lava hurt buildings; blasts hurt nearby buildings and links; falling rock
hurts a building it hits (6e-4 HP per cell of it per cell/s: an 800-cell slab at 300
does 144) and a link it falls through (1e-4 the same way, once), and kills mites; a
flying Thumper hitting rock or a building sideways or upward past 300 cells/s is hurt,
and so is the building (0.25 HP per cell/s over); aquifer
breaches (pause on the first); weathering and cave-ins; Crucible tremors (Tremor Dampers:
none within 120 of a Strut).

Research: Labs turn power (and Glimmer/Obsidian for later tiers) into the picked tech
(T). Tiers open by discovery: 2 at the first Glimmer mined, 3 at the first lava seen,
4 when the Crucible is in view. Plain techs by tier plus an Upgrades column with levels.
Phase 10 costs: v2's power x3 at Tier 1 and x4 from Tier 2 (Borer 450, Coolant Jacket
and Obsidian Saw 1000 each), Glimmer x2; a Lab turns at most 2 power/s into research.

Fog and light: underground is dark; a block is explored when it's lit and within sight
of a building; explored ground shows live while lit, as last seen (dimmed) when not.
Since A1, ground never seen is black, bedrock and the chamber shell included; the
glimmer glints and lava glow that showed through the fog are gone. The Drill's sense
outline still shows.

Crucible: 32 Glimmer, 48 Obsidian, 64 Water delivered while charging (1.5 packets a
second: about 1.6 min), and 4 power/s drawn from a 20-power reserve (filled ahead of
every machine); the charge drains if packets stop for 5 s or it's out of power for 5 s;
tremors every 15 s while charging. The Hub's packets take ~10 s to get down there, so
it needs Caches nearby to hold its power.

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
- The autoplay bot (tests/autoplay.gd) plays a whole run on the map it knows, on the
  Hub's power alone (the aquifer it taps drains in a minute, so a Waterwheel there
  pays little). It measures the pace; it isn't a test and isn't in run_tests.sh.
- Not yet: sound.
