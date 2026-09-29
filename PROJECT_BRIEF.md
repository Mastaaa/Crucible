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
  to read code. claude/IDEAS.md is Alex's parking lot (open it only when pointed at an entry).
- The root STATUS.md is the full per-phase history for Alex; Claude adds each phase's section at
  its top and doesn't read the rest.
- Spec: claude/SPEC_v2.md, a copy of the Claude Docs doc "Crucible — v2 Spec"
  (https://claude.ai/code/artifact/75beb95f-ed2c-4bdb-9f98-a6388f35f3d6), the design record as of
  phase 6; this brief's roadmap and the lean STATUS are the living versions, so it isn't updated.
- data/materials.json: every material (kinds, physics, burning, collapse, water wear, digging, colours)
  and reactions.
- scripts/: game.gd (controller), defs.gd (all tunables), materials.gd, worldgen.gd, sim_factory.gd,
  sim.gd (GDScript fallback sim), building.gd, hud.gd, overlay.gd, warren.gd. shaders/terrain.gdshader.
- native/: C++ GDExtension sim (godot-cpp 4.5) in src/; bin/ holds the built .dll and .so. Session
  tooling: cloud_setup.sh (run by the SessionStart hook in .claude/), build.sh, run_tests.sh,
  lsp_check.py, cache/ (prebuilt godot-cpp).
- tests/: scenario_* (power, research, chemistry, light, digging, warren, collapse), engine_compare,
  descent (pacing probe), bench, bench_net, mapdump, shot_* (screenshots; shot_help is the F1 panel).

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

8c. Rigid bodies: next. Falling chunks, falling buildings, Thumper collisions.

8d. Mites as bodies (claude/IDEAS.md entry 4).

9. Depth: heat, deeper materials, Crucible power draw.

10. Pacing: incremental curve, bot, tuning.

## Standing decisions
- Engine in C++; Noita-style chunks, dirty rects, checkerboard threading, deterministic per-chunk RNG.
- Materials are data. Alex wants to design a wider material set before more are implemented;
  Coal and Sulfur are the approved first two.
- Coal = 1 Stone + 1 Power. Sulfur = 1 Stone + 1 Glimmer, corrodes nearby structures and links.
- Links break and need a Stone delivery to mend.
- Underground is dark: light (Hub, Lamps, pilot lights, glowing materials, sunlight down open shafts) plus a
  building's sight explores; explored ground shows live only while lit (Terraria-style).
- Every building except Hub and Crucible must stay anchored (rock or a held-up building touching, corners
  count); dislodged ones fall and re-anchor. Real rigid-body physics for this comes with phase 8c.
- The Drill is one fixed machine on the Hub's right: a 30-wide shaft straight down, never buildable.
- Scale (8b): everything built is D.S (10) times its v2 size against the cells; ranges, speeds and
  radii S times, amounts in cells S * S times. World features scale with the world (4x), not the
  buildings. Overhang is a slope and stays as in v2.
- Rigid bodies (8c): unsupported spans break off as solid chunks that shatter to rubble on
  impact; buildings that lose footing fall, take fall damage and relink where they land;
  chunks crush buildings, links and mites by mass and speed.
- Falling has speed (free fall); mites are small and nibble 4x4 bites in bursts of up to 8.
- Thumper: holds a reserve and links when it lands near a relay; the player can drag and throw it (collision
  damage comes with rigid bodies); it yields debris only, for Hoppers. Thumper and Borer are Tier 1.
- Upgrades are techs with levels, each dearer than the last, later levels gated by tier.
- Collapse: a ceiling wider than its material's span caves from the middle into an arch; Struts are
  instant, linkless beams rock to rock that hold rock near both ends. Stone hangs only from stone.
- Ground is mundane data (physics and water only): packed dirt, dirt, sand, gravel, clay, stone.
- Settling: cells next to anything a building digs hold still for SETTLE_S (20 s) before weathering,
  erosion, loosening or powder falls can take them; liquids aren't held.
- The Warren never moves (no Advance); mites never dig its footing. It has no zone picker: a chamber over it,
  then a marker the player sets, which the mites reach their own way.

## Tone and working style
Dry, deadpan, concise, pragmatic. No "Not X, but Y" lines, no triplet-heavy descriptions, no pet names.
Don't give advice or plan next steps unless asked. Start each new conversation by checking prior
conversations (when reachable) and claude/STATUS.md.
