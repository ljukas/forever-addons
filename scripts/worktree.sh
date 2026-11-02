#!/usr/bin/env bash
# Helpers for working in a git worktree (docs/feature-workflow.md, Phase 0). The game's
# AddOns links point at one checkout at a time, so a worktree takes them over to test in
# game and hands them back before it is removed.
#
# Usage: scripts/worktree.sh setup    share .cache/ and .env.local with the main checkout
#        scripts/worktree.sh game     point the game's AddOns links at this checkout
#        scripts/worktree.sh restore  point them back at the main checkout
#        scripts/worktree.sh status   show which checkout each AddOns link points to
set -euo pipefail
source "$(dirname "$0")/lib.sh"

# The main checkout is the parent of the .git directory all worktrees share.
MAIN_ROOT="$(shell_path "$(dirname "$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)")")"
target_dir="$WOW_DIR/Interface/AddOns"

require_game() {
	[[ -d "$WOW_DIR" ]] || die "WoW Forever not found at $WOW_DIR (set WOW_DIR in .env.local)"
}

# Removes the game's links into every checkout of this repo except <keep>, so the game never
# loads a mix of checkouts (link.sh only replaces links for addons the checkout it runs in has).
unlink_all_but() {
	local keep="$1" root link
	while IFS= read -r root; do
		root="$(shell_path "$root")"
		[[ "$root" != "$keep" ]] || continue
		for link in "$target_dir"/*; do
			if [[ -L "$link" && "$(readlink "$link")" == "$root/addons/"* ]]; then
				rm "$link"
				echo "unlinked $(basename "$link") ($root)"
			fi
		done
	done < <(git -C "$ROOT" worktree list --porcelain | sed -n 's/^worktree //p')
}

case "${1:-}" in
setup)
	[[ "$ROOT" != "$MAIN_ROOT" ]] || die "this is the main checkout; run setup from a worktree"
	[[ -d "$MAIN_ROOT/.cache" ]] || echo "note: $MAIN_ROOT has no .cache yet; lint will fetch one here instead"
	for name in .cache .env.local; do
		[[ -e "$MAIN_ROOT/$name" ]] || continue
		if [[ -e "$ROOT/$name" || -L "$ROOT/$name" ]]; then
			echo "kept $name (already present)"
			continue
		fi
		if is_windows && [[ -f "$MAIN_ROOT/$name" ]]; then
			# Junctions can't link files, and a hard link silently breaks when an editor replaces it.
			cp "$MAIN_ROOT/$name" "$ROOT/$name"
			echo "copied $name from $MAIN_ROOT (a snapshot: edit both if you change it)"
			continue
		fi
		link_path "$MAIN_ROOT/$name" "$ROOT/$name"
		echo "linked $name -> $MAIN_ROOT/$name"
	done
	;;
game)
	require_game
	unlink_all_but "$ROOT"
	"$ROOT/scripts/link.sh"
	echo "The game now loads addons from $ROOT. /reload in game; run 'scripts/worktree.sh restore' before removing this worktree."
	;;
restore)
	require_game
	# The main checkout's link.sh reads its own .env.local, so both must name the same game.
	# A new bash, so this checkout's WOW_DIR doesn't leak into the answer the way a subshell's would.
	# shellcheck disable=SC2016
	main_wow_dir="$(bash -c 'source "$1/scripts/lib.sh" && echo "$WOW_DIR"' _ "$MAIN_ROOT")"
	# -ef also matches one folder spelled two ways (C:/... and /c/..., or a different case).
	[[ "$main_wow_dir" == "$WOW_DIR" || "$main_wow_dir" -ef "$WOW_DIR" ]] ||
		die "WOW_DIR here ($WOW_DIR) differs from the main checkout's ($main_wow_dir); make .env.local match first"
	unlink_all_but "$MAIN_ROOT"
	"$MAIN_ROOT/scripts/link.sh"
	;;
status)
	require_game
	for link in "$target_dir"/*; do
		[[ -L "$link" ]] || continue
		dest="$(readlink "$link")"
		[[ -e "$link" ]] && state="" || state=" (missing)"
		echo "$(basename "$link") -> ${dest%/addons/*}$state"
	done
	;;
*)
	die "usage: $0 setup|game|restore|status (see header of $0)"
	;;
esac
