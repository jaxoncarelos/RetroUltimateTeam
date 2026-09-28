#!/usr/bin/env bash
# Imports the project, runs the GUT unit tests, then a short drive sim and two CPU-vs-CPU
# games as smoke tests.
# Requires $GODOT (see tools/install_godot_linux.sh) — or pass the binary as $1.
set -euo pipefail
GODOT="${1:-${GODOT:?set GODOT to the Godot binary}}"
cd "$(dirname "$0")/.."
"$GODOT" --headless --import >/dev/null 2>&1 || true
"$GODOT" --headless --import 2>&1 | grep -E "SCRIPT ERROR|^ERROR" && { echo "Import errors"; exit 1; } || true
"$GODOT" --headless -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json
SIM_OUT="$("$GODOT" --headless -- --sim=60 2>&1)"
echo "$SIM_OUT" | grep -E "SIM|ERROR"
if echo "$SIM_OUT" | grep -q "SCRIPT ERROR"; then echo "Sim hit script errors"; exit 1; fi
echo "$SIM_OUT" | grep -q "^SIM " || { echo "Sim did not finish"; exit 1; }
AI_OUT="$("$GODOT" --headless -- --ai-vs-ai=2 2>&1)"
echo "$AI_OUT" | grep -E "AIVSAI|ERROR"
if echo "$AI_OUT" | grep -q "SCRIPT ERROR"; then echo "ai_vs_ai hit script errors"; exit 1; fi
echo "$AI_OUT" | grep -q "^AIVSAI " || { echo "ai_vs_ai did not finish"; exit 1; }
