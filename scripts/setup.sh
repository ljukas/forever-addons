#!/usr/bin/env bash
# Fetches (or refreshes) local reference material into .cache/:
#   wow-api/        Ketho's LuaLS annotations for the WoW API (used by LuaLS + lint)
#   wow-ui-source/  Blizzard's UI source + generated API docs for the Forever client
# Safe to re-run; it just updates the shallow clones.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

# clone_or_update <dir> <repo url> <branch> [sparse paths...]
clone_or_update() {
	local dir="$1" url="$2" branch="$3"
	shift 3
	if [[ -d "$dir/.git" ]]; then
		echo "==> Updating $(basename "$dir") ($branch)"
		git -C "$dir" fetch --quiet --depth 1 origin "$branch"
		git -C "$dir" checkout --quiet --force FETCH_HEAD
	else
		echo "==> Cloning $(basename "$dir") ($branch)"
		git clone --quiet --depth 1 --branch "$branch" --filter=blob:none ${1:+--sparse} "$url" "$dir"
		if (($#)); then
			git -C "$dir" sparse-checkout set "$@"
		fi
	fi
}

mkdir -p "$CACHE_DIR"
clone_or_update "$CACHE_DIR/wow-api" https://github.com/Ketho/vscode-wow-api.git master Annotations/Core
clone_or_update "$CACHE_DIR/wow-ui-source" https://github.com/Gethe/wow-ui-source.git forever Interface

source_version="$(head -n1 "$CACHE_DIR/wow-ui-source/version.txt" | awk '{print $1}')"
echo "==> wow-ui-source is Forever $source_version (interface $(interface_from_version "$source_version"))"

if client_version="$(installed_client_version)" && [[ -n "$client_version" ]]; then
	echo "==> Installed client is Forever $client_version (interface $(interface_from_version "$client_version"))"
	if [[ "$client_version" != "$source_version" ]]; then
		echo "warning: wow-ui-source ($source_version) and the installed client ($client_version) differ." >&2
	fi
fi
