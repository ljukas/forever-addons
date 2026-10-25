#!/usr/bin/env bash
# Symlinks addons/<Name> into the Forever client's Interface/AddOns, so edits are
# live in game after a /reload. Also removes links to addons that no longer exist.
#
# Usage: scripts/link.sh [Name...]           link the given addons (default: all)
#        scripts/link.sh --unlink [Name...]  remove the links (default: all of ours)
set -euo pipefail
source "$(dirname "$0")/lib.sh"

[[ -d "$WOW_DIR" ]] || die "WoW Forever not found at $WOW_DIR (set WOW_DIR in .env.local)"
target_dir="$WOW_DIR/Interface/AddOns"
mkdir -p "$target_dir"

unlink=false
if [[ "${1:-}" == "--unlink" ]]; then
	unlink=true
	shift
fi

names=("$@")
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
	ln -sfn "$source_dir" "$link"
	echo "linked $name -> $link"
done
