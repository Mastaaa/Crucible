# Crucible: session setup (read after PROJECT_BRIEF and claude/STATUS.md)

The routine for a cloud session (Claude Code on the web), cheapest first. Nothing here
needs re-deciding.

## Start
- The repo is cloned fresh and the SessionStart hook (`.claude/hooks/session-start.sh`)
  has already run `native/cloud_setup.sh`: Godot 4.7.2 (`godot`), scons, mingw
  (posix) and a prebuilt godot-cpp are ready, and the project is imported. If `godot`
  is missing, run `bash native/cloud_setup.sh` (idempotent, about 10 s).
- Work on the branch the session names; start it from `origin/main`.
No directory listings needed.

## Work
- Build both libraries: `bash native/build.sh` (about 16 s for both; prints the DLL's
  imports, which must be KERNEL32 and msvcrt only). Alex tests the Windows DLL.
  Rebuilds aren't byte-identical, so only commit `bin/` when the engine changed;
  otherwise `git checkout -- bin/`.
- Tests: `bash native/run_tests.sh [names...]` prints one line per test plus any FAIL.
  Run the phase's own test while working, all of them before committing (about 6 min).
- Warnings: `python3 native/lsp_check.py . <files>` ("checked N files" alone is clean).
- Screenshot: `xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-method
  gl_compatibility --rendering-driver opengl3 --path . --script tests/shot_X.gd -- --out=/tmp/x`
- Map: `godot --headless --path . --script tests/mapdump.gd -- --seed=7 --out=/tmp/map.png` (`--biomes` outlines them; `tests/shot_biomes.gd` shoots the F7 view)
- Pacing and speed: tests/autoplay.gd (quarry bot), tests/bench_net.gd (baselines in claude/STATUS.md).
- Read code by grep and targeted Read offset/limit; claude/CODE_MAP.md says where things live.
- Keep command output short (grep, tail): output costs as much as reading does.

## Deliver
1. Commit to the session's branch and push. Several commits a session is fine; stop at
   clean pause points.
2. Keep the docs current in the same commits: `claude/STATUS.md` (lean status and
   handoff), `claude/CODE_MAP.md` when code moves, `PROJECT_BRIEF.md` when the roadmap or
   standing decisions change. Add each phase's section to the top of the root
   `STATUS.md` (history for Alex) with a small insert, without reading the rest.
3. Alex merges the branch into `main` and pulls on the PC. When `bin/` changed, Godot
   must be closed before pulling and restarted after, so it loads the new library.

## Traps
- Tests that carve rooms into seed 7 wall them with plain dirt first (or bedrock, which
  never caves); measure collapse and bodies locally, not with the global `get_caved()` or
  `get_bodies_*` counters: the seed's own caves shed pieces all over the map. Lay v2-style set-pieces out with P / R
  (see claude/CODE_MAP.md); the map is only 1024 wide, so far-out pieces need their own
  origin or to go below the Hub.
- Anything per cell in GDScript is 100x the work it was in v2: count, dig or mark in
  the engine (count_in_rect, block_counts, dig_rect, block_circles) and loop in
  GDScript only over what's left.
- New building: extend every per-type array in defs.gd at the same index (B_NAMES,
  B_LETTERS, B_SIZES, B_HP, B_COSTS, B_COLORS, B_BLURBS), then PALETTE / PALETTE_KEYS,
  `uses_power`, `needs_link`, and a tech with "building".
- New material: an entry in data/materials.json (fixed id) and a constant in defs.gd; it
  renders from the data file (so does mapdump). The GDScript fallback sim needs a stub
  for any new sim method the game calls.
- Worldgen additions use their own noise or RNG (tests lean on seed 7's layout).
- GDScript: no class_name, preload constants, untyped `sim`; watch integer division and
  shadowing. Commit the `.uid` files Godot generates for new scripts.
