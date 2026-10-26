#!/usr/bin/env bash
# Prints what ForeverDev captured in game: Lua errors, blocked/forbidden (taint)
# actions and ForeverDev_Log() output. Defaults to the most recent session.
#
# The game only writes SavedVariables on /reload, logout or exit, so /rl first.
#
# Usage: scripts/devlog.sh [--all] [--errors]
#   --all     include every stored session, not just the latest
#   --errors  hide log lines; show only errors and blocked actions
set -euo pipefail
source "$(dirname "$0")/lib.sh"

sessions=last
kinds=all
for arg in "$@"; do
	case "$arg" in
	--all) sessions=all ;;
	--errors) kinds=errors ;;
	*) die "unknown option: $arg (see header of $0)" ;;
	esac
done

# Most recently written ForeverDev.lua across all accounts.
file="$(ls -t "$WOW_DIR"/WTF/Account/*/SavedVariables/ForeverDev.lua 2>/dev/null | head -n1 || true)"
[[ -n "$file" ]] || die "no ForeverDev SavedVariables under $WOW_DIR/WTF yet (enable ForeverDev, then /rl in game)"

lua="$(command -v luajit || command -v lua5.1 || true)"
[[ -n "$lua" ]] || die "needs luajit or lua 5.1 (brew install luajit)"

modified="$(date -r "$file" '+%Y-%m-%d %H:%M:%S')"
echo "File: $file (written $modified)"
"$lua" "$ROOT/scripts/devlog.lua" "$file" "$sessions" "$kinds"
