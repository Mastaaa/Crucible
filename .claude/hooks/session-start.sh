#!/bin/bash
# Cloud sessions only: installs Godot 4.7.2, scons, mingw-w64 and the prebuilt
# godot-cpp, and imports the project (native/cloud_setup.sh, idempotent).
set -euo pipefail
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
	exit 0
fi
bash "$CLAUDE_PROJECT_DIR/native/cloud_setup.sh" "$CLAUDE_PROJECT_DIR"
