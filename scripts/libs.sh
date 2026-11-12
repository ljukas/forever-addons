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
# entry in a form this script doesn't read (the short "path: url" form, a key outside an entry, a key
# other than url, tag and "type: git", an entry indented less than the first). Entries may use any
# indentation, as long as all share it.
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
				# Any other key (path, branch, commit, a non-git type) would change what the packager
				# bundles, so it is rejected rather than ignored.
				if ($1 == "url:") { url = value($0); next }
				if ($1 == "tag:") { tag = value($0); next }
				if ($1 == "type:" && value($0) == "git") next
			}
			flush(); print "INVALID", $0
		}
		END { flush() }
	' "$1"
}

# Brings <dir>'s submodules to what its checkout records, at the urls its .gitmodules gives now.
sync_submodules() {
	git -C "$1" submodule sync --quiet --recursive &&
		GIT_TERMINAL_PROMPT=0 git -C "$1" submodule update --quiet --init --recursive --depth 1
}

# Checks out tag <tag> in the checkout <dir>, fetched from origin as refs/tags/<tag> only: unlike
# `clone --branch`, a branch of the same name can never stand in for it.
checkout_tag() {
	GIT_TERMINAL_PROMPT=0 git -C "$1" fetch --quiet --depth 1 --no-tags origin "+refs/tags/$2:refs/tags/$2" &&
		git -C "$1" -c advice.detachedHead=false checkout --quiet --force "refs/tags/$2" &&
		sync_submodules "$1"
}

for pkgmeta in "$ADDONS_DIR"/*/.pkgmeta; do
	[[ -f "$pkgmeta" ]] || continue
	addon_dir="$(dirname "$pkgmeta")"
	while read -r path url tag; do
		[[ "$path" != INVALID ]] || die "$pkgmeta: can't read external line '$url $tag' (only the long form with url and tag, see $0)"
		[[ -n "$url" && -n "$tag" ]] ||
			die "$pkgmeta: external '$path' needs a git url and a pinned tag"
		# Only ever replace folders under Libs/, so a typo can't delete the addon's own files. A
		# trailing slash would put the staging folder inside the library instead of beside it.
		while [[ "$path" == */ ]]; do path="${path%/}"; done
		[[ "$path" == Libs/?* && "/$path/" != */../* && "/$path/" != */./* && "$path" != *//* ]] ||
			die "$pkgmeta: external '$path' must be a path under Libs/"
		dest="$addon_dir/$path"
		label="$(basename "$addon_dir")/$path"
		# No folder on the way may be a link, or the library would land (and be replaced) outside Libs/.
		walked="$addon_dir"
		IFS=/ read -ra parts <<<"$path"
		for part in "${parts[@]}"; do
			walked="$walked/$part"
			[[ ! -L "$walked" ]] || die "$label: ${walked#"$addon_dir"/} is a link; remove it so it can be fetched"
		done
		if [[ -e "$dest" && ! -d "$dest/.git" ]]; then
			die "$label: exists but isn't a fetched library; remove it so it can be fetched"
		fi

		# The url as written in the checkout's config, not after insteadOf rewrites.
		if [[ -d "$dest/.git" && "$(git -C "$dest" config --get remote.origin.url || true)" == "$url" ]]; then
			wanted="$(git -C "$dest" rev-parse -q --verify "refs/tags/$tag^{commit}" || true)"
			if [[ -z "$wanted" || "$wanted" != "$(git -C "$dest" rev-parse HEAD)" ]]; then
				echo "==> Updating $label to $tag"
				checkout_tag "$dest" "$tag"
			else
				sync_submodules "$dest"
			fi
			continue
		fi

		# A new library, or one whose url changed: clone beside it, and only replace it once that worked.
		[[ -d "$dest" ]] && echo "==> $label moved to $url" || echo "==> Fetching $label ($tag)"
		# A new, empty staging folder of its own, so nothing already there is ever deleted.
		mkdir -p "$(dirname "$dest")"
		staging="$(mktemp -d "$dest.fetching.XXXXXX")"
		if ! { git init --quiet "$staging" && git -C "$staging" remote add origin "$url" &&
			checkout_tag "$staging" "$tag"; }; then
			rm -rf "$staging"
			die "$label: couldn't clone $url at $tag"
		fi
		rm -rf "$dest"
		mv "$staging" "$dest"
	done < <(externals_of "$pkgmeta")
done
