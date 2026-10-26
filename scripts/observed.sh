#!/usr/bin/env bash
# Prints the evidence addons keep through ForeverDev (ForeverDevDB.observed): what they saw in
# game across sessions, e.g. gathering spell IDs or skill line IDs. Each addon documents its
# layout in its Knowledge.lua. scripts/combat-knowledge.sh is a richer view of ForeverCombat's.
#
# The game only writes SavedVariables on /reload, logout or exit, so /rl first.
#
# Usage: scripts/observed.sh [addon] [filter]
#   addon   e.g. ForeverProfessions; without it, lists the addons that observed something
#   filter  only entries whose name contains it (e.g. a node or spell name)
# Both ignore case.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

file="$(latest_saved_variables ForeverDev)"
lua="$(lua51)"
print_file_header "$file"
"$lua" "$ROOT/scripts/observed.lua" "$file" "${1:-}" "${2:-}"
