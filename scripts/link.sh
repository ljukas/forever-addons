#!/usr/bin/env bash
# Symlinks addons/<Name> into the Forever client's Interface/AddOns, so edits are
# live in game after a /reload. Also removes links to addons that no longer exist.
#
# Usage: scripts/link.sh [Name...]           link the given addons (default: all)
#        scripts/link.sh --unlink [Name...]  remove the links (default: all of ours)
set -euo pipefail
source "$(dirname "$0")/lib.sh"

unlink=false
if [[ "${1:-}" == "--unlink" ]]; then
	unlink=true
	shift
fi

target_dir="$WOW_DIR/Interface/AddOns"
if $unlink; then
	# Unlinking also cleans up after an uninstall, so it only needs the folder.
	[[ -d "$WOW_DIR" ]] || die "WoW Forever not found at $WOW_DIR (set WOW_DIR in .env.local)"
else
	require_game
	mkdir -p "$target_dir"
	# Addons load their libraries from Libs/ (gitignored), so a checkout linked into the game needs
	# them fetched, the main checkout included.
	"$ROOT/scripts/libs.sh" || echo "warning: fetching libraries failed; addons that need them won't load" >&2
fi

names=("$@")
main_root="$(main_checkout)"
if ((${#names[@]} == 0)) && ! $unlink && [[ "$ROOT" != "$main_root" ]]; then
	# Linking every addon from a worktree would take over the links other worktrees are testing.
	die "in a worktree, link with 'scripts/worktree.sh game [Addon...]' (or name the addons here)"
fi
if ((${#names[@]} == 0)); then
	for dir in "$ADDONS_DIR"/*/; do
		names+=("$(basename "$dir")")
	done
fi

# Drop dangling links that point back into this repo (renamed/deleted addons).
for link in "$target_dir"/*; do
	if [[ -L "$link" && ! -e "$link" && "$(readlink "$link")" == "$ADDONS_DIR"/* ]]; then
		rm "$link"
		echo "removed stale link $(basename "$link")"
	fi
done

for name in "${names[@]}"; do
	source_dir="$ADDONS_DIR/$name"
	link="$target_dir/$name"
	if $unlink; then
		if [[ -L "$link" && "$(readlink "$link")" == "$source_dir" ]]; then
			rm "$link"
			echo "unlinked $name"
		fi
		continue
	fi
	[[ -f "$source_dir/$name.toc" ]] || die "$source_dir/$name.toc not found"
	if [[ -e "$link" && ! -L "$link" ]]; then
		echo "skipped $name: $link is a real folder (move it away to link the repo copy)" >&2
		continue
	fi
	link_path "$source_dir" "$link"
	echo "linked $name -> $link"
done
