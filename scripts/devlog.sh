#!/usr/bin/env bash
# Prints what ForeverDev captured in game: Lua errors, blocked/forbidden (taint) actions and
# the addons' ns.log() lines. Defaults to the most recent session.
#
# The game only writes SavedVariables on /reload, logout or exit, so /rl first.
#
# Usage: scripts/devlog.sh [--all] [--errors] [--addon NAME] [--tag TAG]
#   --all         include every stored session, not just the latest
#   --errors      hide log lines; show only errors and blocked actions
#   --addon NAME  only that addon's lines, and errors whose message or stack mention it
#   --tag TAG     only log lines with that tag (TICK, GATHER, PROBE, ...)
# NAME and TAG ignore case.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

sessions=last
kinds=all
addon=""
tag=""
while (($#)); do
	case "$1" in
	--all) sessions=all ;;
	--errors) kinds=errors ;;
	--addon)
		addon="${2:?--addon needs a name}"
		shift
		;;
	--tag)
		tag="${2:?--tag needs a tag}"
		shift
		;;
	*) die "unknown option: $1 (see header of $0)" ;;
	esac
	shift
done

file="$(latest_saved_variables ForeverDev)"
lua="$(lua51)"
print_file_header "$file"
"$lua" "$ROOT/scripts/devlog.lua" "$file" "$sessions" "$kinds" "$addon" "$tag"
