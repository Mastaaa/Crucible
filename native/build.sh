#!/usr/bin/env bash
# Builds both engine libraries into bin/ and checks the DLL needs nothing beside it.
# One line per platform. Run from anywhere: bash native/build.sh
cd "$(dirname "$0")"
P="build_profile=build_profile.json target=template_release"
for plat in linux "windows use_mingw=yes"; do
	if scons -j2 platform=$plat $P > /tmp/crucible_build.log 2>&1; then
		echo "built ${plat%% *}"
	else
		echo "FAILED ${plat%% *}:"; grep -E "error|Error" /tmp/crucible_build.log | head -20; exit 1
	fi
done
imports=$(x86_64-w64-mingw32-objdump -p ../bin/libcrucible_sim.windows.x86_64.dll | grep "DLL Name" | awk '{print $3}' | tr '\n' ' ')
echo "dll imports: $imports"
