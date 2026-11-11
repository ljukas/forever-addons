#!/usr/bin/env bash
# Fetches the libraries an addon declares as externals in its .pkgmeta into the addon's own folder
# (addons/<Name>/<path>, gitignored), so the game and lint see what the packager will bundle.
# Only git externals pinned to a tag, at a path under Libs/, are supported:
#
#   externals:
#     Libs/LibEditMode:
#       url: https://github.com/p3lim-wow/LibEditMode
#       tag: "19"
#
# Libraries are never committed or edited: the packager bundles them unmodified at release time.
# Safe to re-run; a library already at its tag (from the same url) is left alone. setup.sh,
# `worktree.sh setup`, link.sh and lint.sh run it.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

# Prints "<path> <url> <tag>" for each external in the .pkgmeta at <file>, or "INVALID <line>" for an
# entry in a form this script doesn't read (the short "path: url" form, a key outside an entry, an
# entry indented less than the first). Entries may use any indentation, as long as all share it.
externals_of() {
	awk '
		function flush() {
			if (path != "") print path, url, tag
			path = ""; url = ""; tag = ""
		}
		function value(line) {
			sub(/^[ \t]*[a-z]+:[ \t]*/, "", line); sub(/[ \t]+#.*$/, "", line); gsub(/["\047]/, "", line)
			return line
		}
		{ sub(/\r$/, "") }
		/^externals:/ { inside = 1; next }
		/^[^ #]/ { if (inside) flush(); inside = 0 }
		!inside { next }
		/^[ \t]*(#|$)/ { next }
		{
			indent = match($0, /[^ ]/) - 1
			if (entry == "") entry = indent
			if (indent == entry && $0 ~ /^ *[^ #][^:]*:[ \t]*$/) {
				flush(); path = $1; sub(/:$/, "", path); next
			}
			if (indent > entry && path != "") {
				if ($1 == "url:") url = value($0)
				else if ($1 == "tag:") tag = value($0)
				next
			}
			flush(); print "INVALID", $0
		}
		END { flush() }
	' "$1"
}

for pkgmeta in "$ADDONS_DIR"/*/.pkgmeta; do
	[[ -f "$pkgmeta" ]] || continue
	addon_dir="$(dirname "$pkgmeta")"
	while read -r path url tag; do
		[[ "$path" != INVALID ]] || die "$pkgmeta: can't read external '$url $tag' (use the long form, see $0)"
		[[ -n "$url" && -n "$tag" ]] ||
			die "$pkgmeta: external '$path' needs a git url and a pinned tag"
		# Only ever replace folders under Libs/, so a typo can't delete the addon's own files.
		[[ "$path" == Libs/* && "/$path/" != */../* && "/$path/" != */./* ]] ||
			die "$pkgmeta: external '$path' must be a path under Libs/"
		dest="$addon_dir/$path"
		label="$(basename "$addon_dir")/$path"
		[[ ! -L "$addon_dir/Libs" && ! -L "$dest" ]] || die "$label: is a link; remove it so it can be fetched"
		if [[ -e "$dest" && ! -d "$dest/.git" ]]; then
			die "$label: exists but isn't a fetched library; remove it so it can be fetched"
		fi

		# The url as written in the checkout's config, not after insteadOf rewrites.
		if [[ -d "$dest/.git" && "$(git -C "$dest" config --get remote.origin.url || true)" == "$url" ]]; then
			wanted="$(git -C "$dest" rev-parse -q --verify "refs/tags/$tag^{commit}" || true)"
			if [[ -z "$wanted" || "$wanted" != "$(git -C "$dest" rev-parse HEAD)" ]]; then
				echo "==> Updating $label to $tag"
				GIT_TERMINAL_PROMPT=0 git -C "$dest" fetch --quiet --depth 1 origin tag "$tag"
				git -C "$dest" checkout --quiet --force "refs/tags/$tag"
			fi
			GIT_TERMINAL_PROMPT=0 git -C "$dest" submodule update --quiet --init --recursive
			continue
		fi

		# A new library, or one whose url changed: clone beside it, and only replace it once that worked.
		[[ -d "$dest" ]] && echo "==> $label moved to $url" || echo "==> Fetching $label ($tag)"
		staging="$dest.fetching"
		rm -rf "$staging"
		GIT_TERMINAL_PROMPT=0 git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$tag" \
			--recurse-submodules --shallow-submodules "$url" "$staging"
		rm -rf "$dest"
		mv "$staging" "$dest"
	done < <(externals_of "$pkgmeta")
done
