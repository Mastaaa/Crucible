# Crucible's simulation, in C++

The falling-sand simulation runs as a Godot extension: `src/` builds into
`../bin/libcrucible_sim.*` (a `.dll` for Windows, a `.so` for Linux), which Godot
loads through `../bin/crucible_sim.gdextension`. The game makes it through
`scripts/sim_factory.gd` and feeds it `data/materials.json`. If the library isn't
there, the game falls back to the old GDScript simulation in `scripts/sim.gd`
(slower, and it ignores the data file). F3 in game says which one is running.

Godot ignores this folder (`.gdignore`).

## How it works

It follows the engine Petri Purho described in his GDC 2019 talk on Noita:

- The 256 x 1024 grid is cut into 32 x 32 chunks, each with a dirty rectangle. Only
  cells inside a chunk's rectangle are visited next tick, so settled ground costs
  nothing; anything that changes wakes its neighbourhood.
- Cells update in place, bottom-up, alternating direction row by row. A per-cell
  stamp stops anything moving twice in one tick.
- Chunks run in four checkerboard passes. Within a pass, active chunks are two
  apart and nothing moves more than a few cells, so they can run on separate
  threads without locks. Each chunk seeds its random stream from (seed, tick,
  chunk), so the result is the same on one thread or many.
- Materials (kind, density, how liquids spread, how gases age, what erodes,
  crumbles or glows) and reactions come from `data/materials.json`.
- Light (light_update) spreads per cell from the lights the game passes, glowing
  materials and the sky, brightest first through a bucket queue, fading faster
  through liquid and rock; only chunks near explored or watched ground are lit.

## Building

Needs Python, SCons (`pip install scons`), a C++17 compiler, and godot-cpp's
`4.5` branch checked out as `native/godot-cpp` (or pointed to by `GODOT_CPP`):

    git clone --depth 1 --branch 4.5 https://github.com/godotengine/godot-cpp.git

Then, from this folder:

    scons platform=linux target=template_release build_profile=build_profile.json
    scons platform=windows target=template_release build_profile=build_profile.json   # with MSVC on Windows
    scons platform=windows use_mingw=yes target=template_release build_profile=build_profile.json   # cross-building from Linux

The Windows build shipped in `bin/` was cross-built with MinGW-w64 and links its
C++ runtime statically, so it needs nothing beside it.
