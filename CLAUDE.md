# Crucible

Godot 4.7.2 pixel-sim descent game with a C++ GDExtension engine. Before any work, read
`PROJECT_BRIEF.md`, then `claude/STATUS.md` (handoff and test baselines), then
`claude/SESSION_SETUP.md` (build, test, deliver). `claude/CODE_MAP.md` says where code lives.

- Build: `bash native/build.sh` (both libraries into `bin/`). Commit `bin/` only when the engine changed.
- Test: `bash native/run_tests.sh [names...]`; all must end `FAILURES: 0` before committing.
- Warnings: `python3 native/lsp_check.py . <changed .gd files>`.
- Tone for docs and replies: dry, deadpan, concise. No "Not X, but Y" lines, no triplets.
