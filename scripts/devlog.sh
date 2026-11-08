#!/usr/bin/env bash
# Prints what ForeverDev captured in game: Lua errors, blocked/forbidden (taint) actions and
# the addons' ns.log() lines. Defaults to the most recent session.
#
# The game only writes SavedVariables on /reload, logout or exit, so /rl first.
#
# In a worktree it shows only the addons that worktree holds in game (scripts/worktree.sh game),
# so parallel sessions each see their own; --addon or --all-addons overrides that.
#
# Usage: scripts/devlog.sh [--all] [--errors] [--addon NAME[,NAME...]] [--all-addons] [--tag TAG]
#   --all         include every stored session, not just the latest
#   --errors      hide log lines; show only errors and blocked actions
#   --addon NAME  only those addons' lines, and errors whose message or stack mention them
#   --all-addons  every addon's lines, also in a worktree
#   --tag TAG     only log lines with that tag (TICK, GATHER, PROBE, ...)
# NAME and TAG ignore case.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

sessions=last
kinds=all
addon=""
all_addons=false
tag=""
while (($#)); do
	case "$1" in
	--all) sessions=all ;;
	--errors) kinds=errors ;;
	--addon)
		addon="${2:?--addon needs a name}"
		shift
		;;
	--all-addons) all_addons=true ;;
	--tag)
		tag="${2:?--tag needs a tag}"
		shift
		;;
	*) die "unknown option: $1 (see header of $0)" ;;
	esac
	shift
done

file="$(latest_saved_variables ForeverDev)"
if [[ -z "$addon" ]] && ! $all_addons && [[ "$ROOT" != "$(main_checkout)" ]]; then
	addon="$(held_addons "$ROOT" | paste -sd, -)"
	if [[ -n "$addon" ]]; then
		echo "Showing ${addon//,/, }: the addons this worktree holds in game (--all-addons for every addon)."
	fi
fi
lua="$(lua51)"
print_file_header "$file"
"$lua" "$ROOT/scripts/devlog.lua" "$file" "$sessions" "$kinds" "$addon" "$tag"
