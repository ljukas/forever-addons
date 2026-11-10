#!/usr/bin/env bash
# Fetches the libraries an addon declares as externals in its .pkgmeta into the addon's own folder
# (addons/<Name>/<path>, gitignored), so the game and lint see what the packager will bundle.
# Only git externals pinned to a tag are supported:
#
#   externals:
#     Libs/LibEditMode:
#       url: https://github.com/p3lim-wow/LibEditMode
#       tag: "19"
#
# Libraries are never committed or edited: the packager bundles them unmodified at release time.
# Safe to re-run; a library already at its tag is left alone. setup.sh, `worktree.sh setup` and
# lint.sh run it.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

# Prints "<path> <url> <tag>" for each external in the .pkgmeta at <file>.
externals_of() {
	awk '
		function flush() {
			if (path != "") print path, url, tag
			path = ""; url = ""; tag = ""
		}
		{ sub(/\r$/, "") }
		/^externals:/ { inside = 1; next }
		/^[^ #]/ { if (inside) flush(); inside = 0 }
		!inside { next }
		/^  [^ #][^:]*:[ \t]*$/ { flush(); path = $1; sub(/:$/, "", path); next }
		/^    url:/ { url = $2 }
		/^    tag:/ { tag = $2; gsub(/["\047]/, "", tag) }
		END { flush() }
	' "$1"
}

for pkgmeta in "$ADDONS_DIR"/*/.pkgmeta; do
	[[ -f "$pkgmeta" ]] || continue
	addon_dir="$(dirname "$pkgmeta")"
	while read -r path url tag; do
		[[ -n "$url" && -n "$tag" ]] ||
			die "$pkgmeta: external '$path' needs a git url and a pinned tag"
		dest="$addon_dir/$path"
		label="$(basename "$addon_dir")/$path"
		if [[ -d "$dest/.git" ]]; then
			wanted="$(git -C "$dest" rev-parse -q --verify "refs/tags/$tag^{commit}" || true)"
			if [[ -n "$wanted" && "$wanted" == "$(git -C "$dest" rev-parse HEAD)" ]]; then
				continue
			fi
			echo "==> Updating $label to $tag"
			GIT_TERMINAL_PROMPT=0 git -C "$dest" fetch --quiet --depth 1 origin tag "$tag"
			git -C "$dest" checkout --quiet --force "refs/tags/$tag"
		else
			echo "==> Fetching $label ($tag)"
			rm -rf "$dest"
			GIT_TERMINAL_PROMPT=0 git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$tag" "$url" "$dest"
		fi
	done < <(externals_of "$pkgmeta")
done
