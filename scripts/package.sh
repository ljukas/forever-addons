#!/usr/bin/env bash
# Builds a release zip for one addon with the BigWigs packager (the same tool CI uses).
#
# The packager assumes one addon per git repo and takes the version from a git tag,
# so the addon's files are staged into a throwaway repo, tagged, and packaged there.
#
# Usage: scripts/package.sh <Name> [version]
#   version  e.g. v1.2.0 (release), v1.2.0-beta1 (beta). Omit for an untagged alpha build.
# Output:  .release/<Name>/<Name>-<version>.zip
#
# Uploads are skipped unless PACKAGER_ARGS is set to something without -d; CI does
# this, uploading to CurseForge/Wago only when the API key secret and the TOC's
# X-Curse-Project-ID / X-Wago-ID are both present.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

PACKAGER_VERSION="v2.6.1"

name="${1:-}"
version="${2:-}"
[[ -n "$name" && -f "$ADDONS_DIR/$name/$name.toc" ]] || die "usage: $0 <Name> [version]  (addons/<Name>/<Name>.toc must exist)"
[[ -z "$version" || "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || die "version must look like v1.2.3 or v1.2.3-beta1"

packager="$CACHE_DIR/packager-$PACKAGER_VERSION/release.sh"
if [[ ! -f "$packager" ]]; then
	mkdir -p "$(dirname "$packager")"
	curl -fsSL "https://raw.githubusercontent.com/BigWigsMods/packager/$PACKAGER_VERSION/release.sh" -o "$packager"
fi

# Stage the working-tree copy of the addon (tracked + untracked, minus ignored files).
stage="$CACHE_DIR/package/$name"
rm -rf "$stage"
mkdir -p "$stage"
(cd "$ROOT" && git ls-files -z --cached --others --exclude-standard -- "addons/$name") |
	(cd "$ROOT" && xargs -0 tar -cf -) | tar -xf - -C "$stage" --strip-components=2

git -C "$stage" init --quiet
git -C "$stage" add --all
git -C "$stage" -c user.name="forever-addons" -c user.email="packager@localhost" \
	commit --quiet -m "Package $name ${version:-(alpha)}"
if [[ -n "$version" ]]; then
	git -C "$stage" tag "$version"
fi

release_dir="$ROOT/.release/$name"
rm -rf "$release_dir"
# shellcheck disable=SC2086 # PACKAGER_ARGS is intentionally word-split
bash "$packager" -t "$stage" -r "$release_dir" ${PACKAGER_ARGS--d}

echo "==> $(ls "$release_dir"/*.zip)"
