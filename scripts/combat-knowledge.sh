#!/usr/bin/env bash
# Prints what ForeverCombat has observed in game about the player's DoTs and HoTs: spell IDs
# and ranks, parsed descriptions, tick sizes and intervals, misses and avoids, per spell. Use
# it to verify or correct addons/ForeverCombat/Data/Spells.lua.
#
# The game only writes SavedVariables on /reload, logout or exit, so /rl first.
#
# Usage: scripts/combat-knowledge.sh [spell name filter]
set -euo pipefail
source "$(dirname "$0")/lib.sh"

filter="${1:-}"

# Most recently written ForeverCombat.lua across all accounts.
file="$(ls -t "$WOW_DIR"/WTF/Account/*/SavedVariables/ForeverCombat.lua 2>/dev/null | head -n1 || true)"
[[ -n "$file" ]] || die "no ForeverCombat SavedVariables under $WOW_DIR/WTF yet (enable ForeverCombat, then /rl in game)"

lua="$(command -v luajit || command -v lua5.1 || true)"
[[ -n "$lua" ]] || die "needs luajit or lua 5.1 (brew install luajit)"

modified="$(date -r "$file" '+%Y-%m-%d %H:%M:%S')"
echo "File: $file (written $modified)"
"$lua" "$ROOT/scripts/combat-knowledge.lua" "$file" "$filter"
