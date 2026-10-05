#!/usr/bin/env bash
# Runs the scenario tests (or the ones named) and prints one line each, plus any
# FAIL / SCRIPT ERROR lines. The full suite takes about 15 minutes.
#   bash native/run_tests.sh                      all scenarios + engine_compare
#   bash native/run_tests.sh scenario_collapse    just the ones named
cd "$(dirname "$0")/.."
tests=("$@")
[ ${#tests[@]} -eq 0 ] && tests=(scenario_power scenario_goals scenario_research scenario_chemistry scenario_light \
	scenario_collapse scenario_bodies scenario_modules scenario_quarry scenario_movers scenario_excavators scenario_processing scenario_logistics scenario_goods scenario_interior scenario_vault scenario_thermal scenario_haulers scenario_depth scenario_temperature scenario_wave1 scenario_run scenario_spawn engine_compare)
for t in "${tests[@]}"; do
	out=$(timeout 1200 godot --headless --path . --script "tests/$t.gd" 2>&1)
	res=$(echo "$out" | grep -E "^FAILURES" | tail -1)
	echo "$t: ${res:-no FAILURES line (crashed or timed out?)}"
	echo "$out" | grep -E "FAIL |SCRIPT ERROR|Parse Error" | head -10 | sed 's/^/    /'
done
