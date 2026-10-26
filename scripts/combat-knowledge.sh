#!/usr/bin/env bash
# Prints what ForeverCombat has observed in game about the player's DoTs and HoTs: spell IDs
# and ranks, parsed descriptions, tick sizes and intervals, misses and avoids, per spell. Use
# it to verify or correct addons/ForeverCombat/Data/Spells.lua. The observations are kept by
# ForeverDev (ForeverDevDB.observed), the learned tick sizes by ForeverCombat.
#
# The game only writes SavedVariables on /reload, logout or exit, so /rl first.
#
# Usage: scripts/combat-knowledge.sh [spell name filter]
set -euo pipefail
source "$(dirname "$0")/lib.sh"

filter="${1:-}"

dev_file="$(latest_saved_variables ForeverDev)"
combat_file="$(latest_saved_variables ForeverCombat)"
lua="$(lua51)"
print_file_header "$dev_file"
print_file_header "$combat_file"
"$lua" "$ROOT/scripts/combat-knowledge.lua" "$dev_file" "$combat_file" "$filter"
