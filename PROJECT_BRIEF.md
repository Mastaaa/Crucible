# Crucible: project brief (read this first in every new conversation)

## What it is
Godot 4.7.2 pixel-sim descent game. Mixes Noita (per-pixel physics), Creeper World IXE (network building)
and Dome Keeper. The player never digs: buildings do. Goal: feed and light the Crucible at the bottom of
a 768 x 5120 map. Pacing target: an incremental game that ramps SLOWLY from one pixel at a time to whole
mineshafts and factories in one click. Focus: the player's expansion against a reactive environment;
uncover elements, deposits and curios; exploit reactions or get blindsided by them.

## Where things live
- Repo: github.com/Mastaaa/Crucible (`main`). Alex's clone: C:\Users\alexa\Documents\new-game-project
  (open project.godot). Claude works on a session branch; Alex merges it and pulls.
- Claude's docs, in the repo, read in this order at the start of a session: this brief,
  claude/STATUS.md (lean: the game as it stands, the handoff, test baselines),
  claude/SESSION_SETUP.md (the routine: build, test, deliver), and claude/CODE_MAP.md when about
  to read code. claude/ALPHA_PLAN.md is the Alpha plan's design (read it for A1 onward).
  claude/IDEAS.md is Alex's parking lot (open it only when pointed at an entry).
- The root STATUS.md is the full per-phase history for Alex; Claude adds each phase's section at
  its top and doesn't read the rest.
- Spec: claude/SPEC_v2.md, a copy of the Claude Docs doc "Crucible — v2 Spec"
  (https://claude.ai/code/artifact/75beb95f-ed2c-4bdb-9f98-a6388f35f3d6), the design record as of
  phase 6; this brief's roadmap and the lean STATUS are the living versions, so it isn't updated.
- data/materials.json: every material (kinds, physics, burning, collapse, water wear, digging, colours)
  and reactions.
- scripts/: game.gd (controller), defs.gd (all tunables), materials.gd, worldgen.gd, sim_factory.gd,
  sim.gd (GDScript fallback sim), building.gd, hud.gd, overlay.gd, machines/ (the module framework and
  its groups). shaders/terrain.gdshader.
- native/: C++ GDExtension sim (godot-cpp 4.5) in src/; bin/ holds the built .dll and .so. Session
  tooling: cloud_setup.sh (run by the SessionStart hook in .claude/), build.sh, run_tests.sh,
  lsp_check.py, cache/ (prebuilt godot-cpp).
- tests/: scenario_* (power, research, chemistry, light, collapse, bodies, depth, run, goals, modules, quarry, movers, excavators,
  temperature, wave1, spawn, goods, vault), engine_compare, autoplay (the quarry bot, a pacing probe), bench, bench_net,
  mapdump, shot_* (screenshots; shot_help is the F1 panel, shot_title the title, win and loss screens).

## Working with a cloud session (how Claude works on it)
- Claude Code on the web: the repo is cloned fresh each session and the SessionStart hook sets up
  Godot and the toolchain; claude/SESSION_SETUP.md has the routine. Deliver by commit and push.
- Windows Godot won't run under Wine, so Alex tests the DLL.
- Spend tokens on the work, not the setup: no directory listings, grep and targeted reads over whole
  files, short command output, the lean STATUS over the history.
- Stop at clean pause points: Alex watches usage limits.

## Roadmap (v3)

1. Scale and fog: done.

2. Power: done.

3. Research: done.

4. C++ engine: done.

5. Chemistry: done, plus light/shadow fog and building anchoring.

6. Digging: done.
   - Fixed Drill with Drill Bit / Drill Shaft levels (to the bedrock over the chamber).
   - Thumper: timed blasts, thrown by them, draggable.
   - Borer (Homing at Tier 2), Relay Mast, Obsidian Saw.
   - Tech tree redrawn with an Upgrades column.

7. Warren: done.
   - Mites hollow a half-circle chamber over the Warren, then tunnel toward a marker by a
     simple rule (nearest reachable cell to it, with a per-cell wobble) and dig a circle there.
   - They keep the Warren's footing, and burn, drown, choke or get crushed.
   - Sounding, Hard Teeth, Ember Brood (fireproof).
   - Engine settling: dug ground holds 20 s before physics takes it.

8. Collapse: done.
   - Spans and arches (per-material span, overhang and cave rate); worldgen settles caves
     into arches.
   - Struts: beams rock to rock that prop what rests on them and hold rock near both ends.
   - Tremor Dampers.
   - Mundane ground: packed dirt, gravel, sand, clay; cohesive stone; water wash.

8b. Rescale: done.
   - Structures 10x bigger against the pixels (D.S); the world 768 x 5120, features 4x.
   - Free fall for powders and liquids; mites nibble in 4x4 bites.
   - Light, fog and rendering reworked for the size (blocks, tiles).

8c. Rigid bodies: done.
   - Engine bodies: pixel pieces stamped into the grid, turning, bouncing, shattering on
     hard impacts, settling back into ground at rest; blasts shove them.
   - Ceilings break off in pieces (crawlspaces still crumble).
   - Falling rock crushes buildings, links and mites; falls hurt buildings; Thumper collisions.

8d. Mites as bodies: done. A mite walks and clings as before; when it loses its grip or a
   blast catches it, it's a small engine body that falls, tumbles and piles up, then walks
   again from where it lands. Rock crushes it by weight and speed; a long fall kills it.

9. Depth: done.
   - Hot rock fills the Magma band; water boils on it and slowly quenches it to stone.
   - Coolant Jacket: the Drill and Borers cut hot rock for water, vented as steam.
   - Steam Turbine; the Crucible draws 4 power/s while charging.

10. Pacing: done. The pre-alpha is complete.
   - A run: the Hub can be destroyed (the run is lost), a summary on the win (keep going
     after), speeds, a title screen, one save slot (Continue / Start Run).
   - Dragged lines of buildings, planned where they can't go yet.
   - An autoplay bot that plays a whole run on the map it knows, and a retune to it:
     a first run about 2 hours, the bot about 1.
   - Deposits worth 6x a cell; the Coolant Jacket takes on lava; condensing steam loses half.

## Alpha roadmap (A1 to A7; design in claude/ALPHA_PLAN.md)

Agreed with Alex; A1 and A2 are done. The player is an autonomous machine built to
reach and light the Crucibles; Hub orders are flat instructions. Three focus areas: more
materials with real chemistry, modular machines (Create-like), and biomes.

1. A1, temperature and reactions: a per-cell temperature field (slow pass), melting and
   boiling points as data, family-tag reaction rules, hot rock rebuilt on it, a lab bench mode.
   Done; the impact, swell and setting extensions moved to A2.
2. A2, materials wave 1 (about 12) and a spawn-region system, with a hand-placed Spoil Heap
   near the Hub. Done: 12 materials and 7 made by reactions (claude/WAVE1_MATERIALS.md), the
   engine's setting, blast, swell, growth, heat-mass and body-forging extensions, spawn rows.
3. A3, machine framework and the hard cut: legacy buildings go (Hub, Crucible, Nodes, Lab,
   Lamp, Brace and Bulkhead stay; the Warren returns in A4 as the Drone Cage). The starter quarry
   (Cutter Excavator, Tank, Winch, Funnel, Windmill, Nodes), Chute, Conveyor, Bus Hopper, a
   skippable tutorial as Hub instructions, research that consumes produced goods, and the Hub's
   trickle cut to about 0.2 power/s. Done: the framework core, the goal layer, the five starter
   modules, and the cut (the Drill, Thumper, Borer, Hopper, Spout, Floodgate, Waterwheel, Turbine,
   Cache, Mast and Warren removed; Lab and Lamp are modules; Node, Bulkhead and Brace stay
   structures; the tutorial is rewritten around the quarry; the bot is a quarry pacing probe).
   Left: Bus Hopper (moved to A5 with Vault cells; Chute and Conveyor are in A4). The gaps the cut exposes are listed
   in claude/STATUS.md.
4. A4, movers and excavators (Piston, Gantry, Turntable, full Cutter, Laser, Thumper, Macerator, Press, Chute, Conveyor and Drone Cage done): Gantry, Piston, Turntable, full Cutter, Laser Excavator, tethered
   Thumper, Macerator, Press, the Drone Cage; tests and the bot rewritten.
5. A5, materials wave 2 (about 25 in all), processing chains, sensors, Mk I to IV upgrades,
   Vault cells; the bot completes a run again. Order (one PR each): goods bank and Bus Hopper (done), Vault cells (done),
   wave 2 materials, heat processing (Boiler, Chiller, Furnace, Caster, Combustor, casing wear: done; the Thermoelectric Plate goes to sensors), fluids and separation
   (Pump, Sieve, Centrifuge: done; the Electrolyser comes with wave 2), the Shorer (done), sensors, Mk upgrades paid in goods, the bot.
6. A6, a slightly wider world and biome patches built on the spawn-region system.
7. A7, pacing and polish against the bot.

Parked past Alpha: enemies, curios and wreckage, weather, Schematics, logic wiring, randomised
chemistry (a "pocket dimension" update), more than one Crucible per world. Between A3 and A5 no
run can be finished; the cut removed phase 10's jacket rules, building-tied tuning and the bot's
logistics, and the full bot returns at the end of A4.

## Standing decisions
(The v3 decisions below hold until the Alpha plan replaces them. Where they conflict, claude/ALPHA_PLAN.md
wins: buildings, the Drill, the Warren and mites, the Hub's power, and heat as a material.)
The A3 cut retired the decisions below about the Drill, Thumper, Borer, Hopper, Spout, Floodgate, Waterwheel,
Cache, Turbine, Relay Mast, Warren and mites, and the Conduit and Strut names (now Node and Brace); they stay as history.

- Engine in C++; Noita-style chunks, dirty rects, checkerboard threading, deterministic per-chunk RNG.
- Materials are data. Alex wants to design a wider material set before more are implemented;
  Coal and Sulfur are the approved first two, hot rock (phase 9's heat) the third. Deeper
  materials and curios wait until after phase 10.
- Coal = 1 Stone + 1 Power. Sulfur = 1 Stone + 1 Glimmer, corrodes nearby structures and links.
- Links break and need a Stone delivery to mend.
- Underground is dark: light (Hub, Lamps, pilot lights, glowing materials, sunlight down open shafts) plus a
  building's sight explores; explored ground shows live only while lit (Terraria-style). Fog (A1): ground
  never seen is opaque black; seen but unlit shows as last seen, dimmed. Nothing hints through it.
- Every building except Hub and Crucible must stay anchored (rock or a held-up building touching, corners
  count); dislodged ones fall straight down, are hurt by a long fall, and re-anchor.
- The Drill is one fixed machine on the Hub's right: a 30-wide shaft straight down, never buildable.
- Scale (8b): everything built is D.S (10) times its v2 size against the cells; ranges, speeds and
  radii S times, amounts in cells S * S times. World features scale with the world (4x), not the
  buildings. Overhang is a slope and stays as in v2.
- Rigid bodies (8c): unsupported spans break off as solid chunks that shatter to rubble on
  impact (a gentle landing settles back into ground; a ceiling over a crawlspace crumbles);
  buildings that lose footing fall, take fall damage and relink where they land; chunks
  crush buildings, links and mites by mass and speed. Buildings stay upright boxes.
- Falling has speed (free fall); mites are small and nibble 4x4 bites in bursts of up to 8.
- Mites (8d) are creature-controlled while they cling and bodies (3x3, material Mite) while
  physics has them; the switch is automatic both ways.
- Thumper: holds a reserve and links when it lands near a relay; the player can drag and throw it (hitting
  rock or a building sideways or upward past 300 cells/s hurts both; landing never does); it yields debris
  only, for Hoppers. Thumper and Borer are Tier 1.
- Upgrades are techs with levels, each dearer than the last, later levels gated by tier.
- Collapse: a ceiling wider than its material's span caves from the middle into an arch (in pieces, 8c); Struts are
  instant, linkless beams rock to rock that hold rock near both ends. Stone hangs only from stone.
- Ground is mundane data (physics and water only): packed dirt, dirt, sand, gravel, clay, stone.
- Temperature (A1): every cell has one, leaking slowly between neighbours and settling toward its
  depth's ambient (550 in the Magma band). Melting, boiling, freezing and kindling points are
  material data. Hot rock is still its own material (stone's kin for hanging), made and unmade by
  temperature: the Magma band's stone held hot. Until A3 it stops the Drill and Borers without the
  Coolant Jacket and mites without Ember Brood. Steam for the Turbine comes only from what the player
  stages.
- Reactions (A1): rules name materials or families (one or two tags a material); a material pair's
  rule overrides its families'. A rule can carry a temperature window, heat, and a catalyst family
  that multiplies its chance (A2: it can also leave a body behind, `emit`). Wave 1 adds data keys for
  a setting stage, blasts (impact, heat, fire), a swell, growth and heat mass; data/materials.json's
  `_about` lists them. The family list holds up to 32 tags (a bit each in a uint32; wave 1 used 16, A5 part 3 widened it).
- Settling: cells next to anything a building digs hold still for SETTLE_S (20 s) before weathering,
  erosion, loosening or powder falls can take them; liquids aren't held.
- A run (10): lost when the Hub is destroyed (it takes damage like any building and patches itself with its
  own Stone); won when the Crucible is lit, and the player can keep going. One save slot, no Load menu: the
  title has Continue and Start Run; it saves on quit, on going to the title and every 5 minutes; a loss
  erases it, a win keeps it. A random seed unless one is typed in.
- Pacing (10): a first run about 2 hours; research power is the early clock; Tier 1 is v2 x3, later tiers x4.
  The phase 10 bot is gone (the A3 cut); the quarry bot only probes the starter loop.
- Deposits (10): glimmer, obsidian, coal and sulfur (and their shards) bank 6x a cell ("worth" in the data).
- Steam (10): condensing, half of it turns back to water and half is lost, so boil cycles die out.
- Dragged lines (10): Nodes spaced to link, Bulkheads side by side; what can't go down yet is planned and
  goes down when the network reaches it.

## Tone and working style
Dry, deadpan, concise, pragmatic. No "Not X, but Y" lines, no triplet-heavy descriptions, no pet names.
Don't give advice or plan next steps unless asked. Start each new conversation by checking prior
conversations (when reachable) and claude/STATUS.md.
