# Crucible: status (lean; read at the start of every session)

The game as it stands, for working on it. Numbers live in scripts/defs.gd and
data/materials.json; this says what exists and how it behaves. The full per-phase
history (what shipped when, old numbers, test notes) is the root STATUS.md:
Claude adds a section at its top each phase and doesn't need to read the rest.

## Handoff
- Last done: phase 8 (collapse, Struts, Tremor Dampers, mundane ground). Then the move
  to git and Claude Code on the web: docs in claude/, a SessionStart hook runs
  native/cloud_setup.sh, sync.py retired.
- Next: phase 8b, the rescale (plan below). Then 8c, rigid bodies.
- Open with Alex: nothing pending.

## Phase 8b plan: the 10x rescale (decided 2026-09-28)
- Structures 10x bigger against the pixels (Hub 80x60, Drill 30x30, Conduit 20x20...).
- World 2-3x wider, 4-5x deeper (e.g. 640 x 4608 or 768 x 5120 cells). Benchmark first.
- Touches: C++ W/H (compile-time 256 x 1024 in crucible_sim.h), worldgen and the
  fog/explored maps (GDScript loops over every cell; KW/KH are 4x4 blocks), the single
  map texture (split into tiles), minimap, camera and zoom, every tunable counted in
  cells (ranges, spans, speeds, CELLS_PER_UNIT, light and sight radii), and the tests'
  hard-coded coordinates (most tests build set-pieces on seed 7 near the Hub).

## Test baseline (all must hold before committing)
- `bash native/run_tests.sh`: every scenario and engine_compare end `FAILURES: 0`.
- Descent probe (tests/descent.gd, seed 7): depth 140 at 2 min, 200 at 5, 280 at 8.
- Network bench (tests/bench_net.gd): about 1.1 ms a tick once its opening cave-ins settle.
- `python3 native/lsp_check.py . <changed .gd files>`: no warnings.

## The game now
World: 256 x 1024 cells, seed-generated. Layers: surface (sky to row 40), Topsoil (dirt
to ~300, packed dirt thickening toward its bottom, stone lumps, sand pockets, gravel
patches, coal seams, two aquifers lined with clay and settled into arches), a gravel bed
at the boundary, Stone (to ~600: glimmer veins with lodes, caves, water pockets, coal,
sulfur nodules), Magma (lava pockets, a lava lake, sulfur crusts), and the Chamber
(bedrock shell, the Crucible on an altar under a plug). Worldgen features draw from their
own noise or RNG so each seed's layout stays put.

Engine (C++ GDExtension, Noita-style): 32x32 chunks with dirty rects, four checkerboard
passes (threads), per-chunk RNG. Materials and reactions are data. Each cell has an aux
byte (burn time or gas life). Powders, liquids (density sorting), gases (buoyancy, life),
fire that needs air, free particles, blasts by rays, light per cell (sky down open
shafts, glowing materials, lamps; rock shadows), and slow passes: erosion, weathering
(ceiling drip), wash (water wear), collapse (spans), tremors. The GDScript fallback sim
(sim.gd) lacks chemistry, per-cell light, settling, collapse, holds and wash.

Collapse: every ground material has a span (widest open run it roofs), an overhang and
a cave rate. Wider ceilings cave from the middle a row at a time into an arch or until
their rubble props them. Stone is cohesive (hangs only from stone or never-giving rock).
Settling holds freshly dug ground 20 s. Strut holds are permanent. Worldgen runs
`stabilize` so the map starts standing.

Ground (spans): gravel 4 (fast, water-proof), dirt 7 (weathers; water turns it to sand),
coal and sulfur 9 (coal comes down twice as fast as dirt), clay 11 (water-proof), stone 15
(cohesive; water turns it to dirt, slowly), packed dirt 24 (slow to dig, water softens it
slowly), glimmer/obsidian/bedrock never. Sand is a powder that water carries off.

Resources: Stone, Glimmer, Obsidian, Water, Power. A unit is 6 cells (CELLS_PER_UNIT).
Coal pays Stone + Power, sulfur Stone + Glimmer.

Network: the Hub sends packets along Conduits (relays, 16) and Relay Masts (28); every
other building links to a relay within 8. Blueprints fill by packet. Machines hold a
10-power reserve refilled by packet from the nearest Hub, Cache or Waterwheel with stock.
Links have HP (fire, sulfur, lava wear them); broken links and hurt buildings ask for a
Stone. Struts need no link.

Buildings (key): Hub; fixed Drill (right of the Hub, 3-wide shaft straight down; Drill
Bit / Drill Shaft upgrades); Conduit 1; Thumper 2 (timed blasts, thrown by them,
draggable); Hopper 3; Bulkhead 4 (drag a wall); Lab 5; Spout 6; Floodgate 7; Waterwheel
8; Cache 9; Lamp 0; Borer B (points four ways; Homing); Relay Mast M; Warren G (mites dig
a chamber, then tunnel to a marker and dig a circle); Strut X (instant beam rock to rock,
up to 16, props and holds rock within 5 of each end; snaps without its anchors).
Everything but the Hub and Crucible must stay anchored (rock or a held-up building
touching, corners count) or it falls; placement ghosts snap to legal spots within 5.

Hazards: water drowns Conduits, lava destroys them, steam scalds them; fire, corrosion
(sulfur) and lava hurt buildings; blasts hurt nearby buildings and links; aquifer
breaches (pause on the first); weathering and cave-ins; Crucible tremors (Tremor Dampers:
none within 12 of a Strut).

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
  wide rooms cave). Measure collapse locally, not with the global `get_caved()`.
- Cave-in alerts fire only on explored ground.
- The autoplay bot (tests/autoplay.gd) predates v2 and doesn't work; rebuilt in phase 10.
- Not yet: sound, title screen, saving, a lose state.
