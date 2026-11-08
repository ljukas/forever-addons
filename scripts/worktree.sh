#!/usr/bin/env bash
# Helpers for working in a git worktree (docs/feature-workflow.md, Phase 0). Each of the game's
# AddOns links points at one checkout, so several worktrees can test in game at once as long as
# they work on different addons: each claims only its own addons and hands them back when done.
#
# Usage: scripts/worktree.sh setup             share .cache/ and .env.local with the main checkout
#        scripts/worktree.sh game [Addon...]   point those addons' links at this checkout (default:
#                                              the addons this branch changed against origin/main)
#        scripts/worktree.sh restore           point this checkout's links back at the main checkout
#        scripts/worktree.sh reset             point every link back at the main checkout (from any
#                                              checkout), dropping links into worktrees removed from
#                                              .claude/worktrees
#        scripts/worktree.sh status            show which checkout each AddOns link points to
set -euo pipefail
source "$(dirname "$0")/lib.sh"

MAIN_ROOT="$(main_checkout)"
target_dir="$WOW_DIR/Interface/AddOns"

checkouts=()
while IFS= read -r checkout; do
	checkouts+=("$(shell_path "$checkout")")
done < <(git -C "$ROOT" worktree list --porcelain | sed -n 's/^worktree //p')

# Prints the checkout of this repo that <link> points into, or nothing for a link (or folder) that
# isn't ours. A link into a removed worktree under the main checkout still prints its path.
holder_of() {
	local link="$1" dest checkout known
	[[ -L "$link" ]] || return 0
	dest="$(readlink "$link")"
	[[ "$dest" == */addons/"$(basename "$link")" ]] || return 0
	checkout="${dest%/addons/*}"
	if [[ "$checkout" == "$MAIN_ROOT"/* ]]; then
		echo "$checkout"
		return 0
	fi
	for known in ${checkouts[@]+"${checkouts[@]}"}; do
		if [[ "$checkout" == "$known" ]]; then
			echo "$checkout"
			return 0
		fi
	done
}

# A checkout as people say it: "main" or the worktree's folder name.
label() {
	if [[ "$1" == "$MAIN_ROOT" ]]; then echo main; else basename "$1"; fi
}

lower() {
	tr '[:upper:]' '[:lower:]' <<<"$1"
}

# Prints <name> as this checkout's addon folder spells it. Windows and macOS file systems ignore
# case, so "forevertooltip" would otherwise replace another worktree's ForeverTooltip link unseen.
addon_folder() {
	local wanted dir
	wanted="$(lower "$1")"
	for dir in "$ADDONS_DIR"/*/; do
		dir="$(basename "$dir")"
		if [[ "$(lower "$dir")" == "$wanted" && -f "$ADDONS_DIR/$dir/$dir.toc" ]]; then
			echo "$dir"
			return 0
		fi
	done
	die "no addon $1 in $ADDONS_DIR"
}

# The addons under addons/ that this branch touched against <base>: committed, staged, unstaged
# or untracked. A rename lists both names, so the old one can be unlinked.
touched_addons() {
	{
		git -C "$ROOT" diff --name-only --no-renames "$1" -- addons
		git -C "$ROOT" ls-files --others --exclude-standard -- addons
	} | sed -n 's#^addons/\([^/]*\)/.*#\1#p' | sort -u
}

# Dies unless the main checkout's link.sh, which reads its own .env.local, links into the same game.
require_same_game_as_main() {
	local main_wow_dir
	# A new bash, so this checkout's WOW_DIR doesn't leak into the answer the way a subshell's would.
	# shellcheck disable=SC2016
	main_wow_dir="$(bash -c 'source "$1/scripts/lib.sh" && echo "$WOW_DIR"' _ "$MAIN_ROOT")"
	# -ef also matches one folder spelled two ways (C:/... and /c/..., or a different case).
	[[ "$main_wow_dir" == "$WOW_DIR" || "$main_wow_dir" -ef "$WOW_DIR" ]] ||
		die "WOW_DIR here ($WOW_DIR) differs from the main checkout's ($main_wow_dir); make .env.local match first"
}

# Removes the links that <holder> holds (every non-main holder when <holder> is "any"), then has
# the main checkout link every addon it has (<all> is "all"), or only those plus any of its
# addons with no link at all, such as one 'game' unlinked because the branch renames it.
hand_back_to_main() {
	local holder="$1" all="$2" link held name names=()
	for link in "$target_dir"/*; do
		held="$(holder_of "$link")"
		[[ -n "$held" && "$held" != "$MAIN_ROOT" ]] || continue
		[[ "$holder" == any || "$held" == "$holder" ]] || continue
		rm "$link"
		echo "unlinked $(basename "$link") ($(label "$held"))"
		names+=("$(basename "$link")")
	done
	if [[ "$all" == all ]]; then
		"$MAIN_ROOT/scripts/link.sh"
		return
	fi
	if ((${#names[@]} == 0)); then
		echo "This worktree holds no links in game."
	fi
	local main_names=()
	for name in ${names[@]+"${names[@]}"}; do
		# An addon that only exists in the worktree stays unlinked.
		if [[ -f "$MAIN_ROOT/addons/$name/$name.toc" ]]; then main_names+=("$name"); fi
	done
	for link in "$MAIN_ROOT"/addons/*/; do
		name="$(basename "$link")"
		if [[ -f "$MAIN_ROOT/addons/$name/$name.toc" && ! -e "$target_dir/$name" && ! -L "$target_dir/$name" ]]; then
			main_names+=("$name")
		fi
	done
	if ((${#main_names[@]})); then
		"$MAIN_ROOT/scripts/link.sh" "${main_names[@]}"
	fi
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
	shift
	names=()
	removed=()
	if (($#)); then
		for name in "$@"; do
			folder="$(addon_folder "$name")"
			names+=("$folder")
		done
	else
		base="$(git -C "$ROOT" merge-base origin/main HEAD)" || die "no merge base with origin/main; name the addons: $0 game <Addon...>"
		while IFS= read -r name; do
			if [[ -f "$ADDONS_DIR/$name/$name.toc" ]]; then names+=("$name"); else removed+=("$name"); fi
		done < <(touched_addons "$base")
		((${#names[@]})) || die "this branch changes no addon yet; name the ones to test: $0 game <Addon...>"
	fi
	# Check every addon before touching any link, so a refusal leaves the game as it was.
	conflicts=()
	for name in "${names[@]}"; do
		held="$(holder_of "$target_dir/$name")"
		# A link into a removed worktree (it no longer resolves) is free to take.
		if [[ -n "$held" && "$held" != "$ROOT" && "$held" != "$MAIN_ROOT" && -e "$target_dir/$name" ]]; then
			conflicts+=("$name ($(label "$held"))")
		fi
	done
	if ((${#conflicts[@]})); then
		die "another worktree holds ${conflicts[*]}; run 'scripts/worktree.sh restore' there first (or 'reset')"
	fi
	# An addon this branch deletes or renames would otherwise still load from main beside the new one.
	for name in ${removed[@]+"${removed[@]}"}; do
		held="$(holder_of "$target_dir/$name")"
		if [[ "$held" == "$MAIN_ROOT" || "$held" == "$ROOT" ]]; then
			rm "$target_dir/$name"
			echo "unlinked $name: this branch removes or renames it ('restore' links it again)"
		fi
	done
	"$ROOT/scripts/link.sh" "${names[@]}"
	missed=()
	for name in "${names[@]}"; do
		[[ "$(holder_of "$target_dir/$name")" == "$ROOT" ]] || missed+=("$name")
	done
	((${#missed[@]} == 0)) || die "not linked: ${missed[*]} (see above)"
	echo "The game now loads ${names[*]} from $ROOT. /reload in game; run 'scripts/worktree.sh restore' when done."
	;;
restore)
	require_game
	[[ "$ROOT" != "$MAIN_ROOT" ]] || die "this is the main checkout; 'scripts/worktree.sh reset' hands every worktree's links back"
	require_same_game_as_main
	hand_back_to_main "$ROOT" only
	;;
reset)
	require_game
	require_same_game_as_main
	hand_back_to_main any all
	;;
status)
	require_game
	for link in "$target_dir"/*; do
		[[ -L "$link" ]] || continue
		held="$(holder_of "$link")"
		[[ -e "$link" ]] && state="" || state=" (missing)"
		if [[ -n "$held" ]]; then
			where="$(label "$held")"
			[[ "$held" == "$ROOT" && "$ROOT" != "$MAIN_ROOT" ]] && where+=" (this worktree)"
		else
			where="$(readlink "$link")"
		fi
		echo "$(basename "$link") -> $where$state"
	done
	;;
*)
	die "usage: $0 setup|game [Addon...]|restore|reset|status (see header of $0)"
	;;
esac
