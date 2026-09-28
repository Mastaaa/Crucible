#!/usr/bin/env bash
# Sets up a fresh cloud container to build and test Crucible. Idempotent: rerun it
# any time. The SessionStart hook (.claude/hooks/session-start.sh) runs it in cloud
# sessions; see claude/SESSION_SETUP.md for the whole routine.
#   bash native/cloud_setup.sh [project dir]      (default: the repo this script is in)
# Gives: godot (4.7.2, Linux) on PATH, scons, mingw-w64 (posix threads) for the
# Windows DLL, godot-cpp 4.5 already built for both platforms (from
# native/cache/godot-cpp-built.tar.gz, so only our two .cpp files compile), and
# the project imported.
set -e
P=${1:-$(cd "$(dirname "$0")/.." && pwd)}
T=${CRUCIBLE_TOOLS:-/opt/crucible-tools}
mkdir -p "$T"
cd "$T"
if [ ! -x Godot_v4.7.2-stable_linux.x86_64 ]; then
	curl -sSL -o godot.zip https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
	unzip -qo godot.zip
	chmod +x Godot_v4.7.2-stable_linux.x86_64
fi
ln -sf "$T/Godot_v4.7.2-stable_linux.x86_64" /usr/local/bin/godot
command -v scons >/dev/null || pip install --break-system-packages -q scons 2>/dev/null
if ! command -v x86_64-w64-mingw32-g++-posix >/dev/null; then
	apt-get install -y -q mingw-w64 >/dev/null 2>&1 || (apt-get update -q >/dev/null 2>&1 && apt-get install -y -q mingw-w64 >/dev/null 2>&1)
fi
update-alternatives --set x86_64-w64-mingw32-g++ /usr/bin/x86_64-w64-mingw32-g++-posix >/dev/null
update-alternatives --set x86_64-w64-mingw32-gcc /usr/bin/x86_64-w64-mingw32-gcc-posix >/dev/null
cd "$P/native"
if [ ! -d godot-cpp ]; then
	if [ -f cache/godot-cpp-built.tar.gz ]; then
		tar -xzf cache/godot-cpp-built.tar.gz
	else
		git clone -q --depth 1 -b 4.5 https://github.com/godotengine/godot-cpp godot-cpp
	fi
fi
cd "$P"
timeout 300 godot --headless --path . --import >/dev/null 2>&1 || true
echo "ready: $(godot --version)  scons ok  mingw $(x86_64-w64-mingw32-g++ --version | head -1 | awk '{print $NF}')"
