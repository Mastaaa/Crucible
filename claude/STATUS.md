# Crucible: status (lean; read at the start of every session)

The game as it stands, for working on it. Numbers live in scripts/defs.gd and
data/materials.json; this says what exists and how it behaves. The full per-phase
history (what shipped when, old numbers, test notes) is the root STATUS.md:
Claude adds a section at its top each phase and doesn't need to read the rest.

## Handoff
- Last done: phase 8c, rigid bodies. Ceilings break off in pieces that tumble and
  shatter; falling rock crushes buildings, links and mites; falls hurt buildings;
  Thumper collisions. On branch claude/charming-mayer-evn3ro.
- Next: phase 8d, mites as bodies (claude/IDEAS.md entry 4), then 9 (depth).
- Open with Alex: whether to merge 8c into main; mite pace (about 2-3x slower than v2
  against building size) is for phase 10.
- Known rough edges: the screenshot scripts (bar shot_bodies), smoke_v2, flow and
  scenario_water* still use v2 coordinates; the top bar clips the Help button when the
  depth label shows; a network rebuild on a dense 380-building network takes ~34 ms.

## Test baseline (all must hold before committing)
- `bash native/run_tests.sh` (about 7 minutes): every scenario (nine, with
  scenario_bodies) and engine_compare end `FAILURES: 0`.
- Descent probe (tests/descent.gd, seed 7): head at 700 at 2 min, 1000 at 5, 1400 at 7.
- Network bench (tests/bench_net.gd): about 2.5 ms a tick once its floors cave in (4.1 at
  60 s on the slower container, same as main there).
- `tests/prof_scale.gd`: a fresh game ticks in about 0.7 ms (1.3 ms on a slower
  container, where main measured the same; compare against main on the same machine).
- `tests/bench_bodies.gd`: 100 slabs falling at once, about 3.5 ms a tick (worst 14).
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
sulfur nodules), Magma (lava pockets, a lava lake, sulfur crusts), and the Chamber
(bedrock shell, the Crucible on an altar under a 40-wide plug). Worldgen features draw from their
own noise or RNG so each seed's layout stays put.

Engine (C++ GDExtension, Noita-style): 32x32 chunks with dirty rects, four checkerboard
passes (threads), per-chunk RNG, then rigid bodies and particles; the size is set at
runtime (set_size). Materials and
reactions are data. Each cell has an aux byte (burn time or gas life) and a fall speed.
Powders, liquids (density sorting, free fall), gases (buoyancy, life), fire that needs
air, free particles, blasts by rays, light per 4x4 block (sky down open shafts, glowing
materials, lamps; rock shadows; only near what's watched or explored on screen), and slow
passes: erosion, weathering (ceiling drip), wash (water wear), collapse (spans), tremors.
It also keeps the "as last seen" map and flags 256 x 256 render tiles that changed. The GDScript fallback sim
(sim.gd) lacks chemistry, per-cell light, settling, collapse, holds and wash.

Collapse: every ground material has a span (widest open run it roofs), an overhang (the
slope an arch narrows by, cells a row) and a cave rate. Wider ceilings cave from the
middle into an arch or until their rubble props them: each stretch of ceiling due to go,
with its cave rate a sweep, breaks off a piece (24-64 wide, 6-20 deep, ragged, narrowing
upward like the arch) as a rigid body. Stretches under 4 wide, or over a gap under 20
tall (a crawlspace), crumble a cell at a time as before. Stone is cohesive (hangs only
from stone or never-giving rock; a notch with stone within 8 cells above it doesn't cut
the row).

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
150 (cohesive; water turns it to dirt, slowly), packed dirt 240 (slow to dig, water softens
it slowly), glimmer/obsidian/bedrock never. Sand is a powder that water carries off.

Resources: Stone, Glimmer, Obsidian, Water, Power. A unit is 600 cells (CELLS_PER_UNIT).
Coal pays Stone + Power, sulfur Stone + Glimmer.

Network: the Hub sends packets along Conduits (relays, 160) and Relay Masts (280); every
other building links to a relay within 80. Blueprints fill by packet. Machines hold a
10-power reserve refilled by packet from the nearest Hub, Cache or Waterwheel with stock.
Links have HP (fire, sulfur, lava wear them); broken links and hurt buildings ask for a
Stone. Struts need no link.

Buildings (key): Hub; fixed Drill (right of the Hub, 3-wide shaft straight down; Drill
Bit / Drill Shaft upgrades; 30 wide); Conduit 1; Thumper 2 (timed blasts, thrown by them,
draggable); Hopper 3; Bulkhead 4 (drag a wall); Lab 5; Spout 6; Floodgate 7; Waterwheel
8; Cache 9; Lamp 0; Borer B (points four ways; Homing); Relay Mast M; Warren G (mites
nibble a chamber in 4x4 bites, then tunnel to a marker and dig a circle); Strut X
(instant beam rock to rock, up to 160 long and 10 thick, props and holds rock within 50
of each end; snaps without its anchors). Everything but the Hub and Crucible must stay
anchored (rock, resting powder under it, or a held-up building touching; corners count)
or it falls straight down (600 cells/s^2, up to 400; through liquid at most 100) and
relinks where it lands; past 200 cells/s it's hurt, up to 75% of its HP at 400, and so
is a building it lands on. Placement ghosts snap to legal spots within 50.

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
Phase-9 techs (Steam Turbine, Coolant Jacket) show but can't be picked.

Fog and light: underground is dark; a block is explored when it's lit and within sight
of a building; explored ground shows live while lit, as last seen when not.

Crucible: 32 Glimmer, 48 Obsidian, 64 Water delivered while charging; the charge drains
if packets stop for 5 s; tremors every 15 s while charging.

## Standing quirks worth knowing
- Tests that carve rooms into seed 7 wall them with plain dirt first (sand pockets pour,
  wide rooms cave), and sweep loose powder out of a spot before placing (erosion drops
  a few cells into any shaft). Measure collapse locally, not with the global `get_caved()`.
- Light is only worked out near what buildings watch and explored ground in the view:
  a test that reads light elsewhere explores the spot and points the camera there.
- Cave-in alerts fire only on explored ground.
- The autoplay bot (tests/autoplay.gd) predates v2 and doesn't work; rebuilt in phase 10.
- Not yet: sound, title screen, saving, a lose state.
