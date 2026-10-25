# Shared helpers for scripts/*.sh. Source it; don't run it.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Per-machine overrides (e.g. WOW_DIR) live in the gitignored .env.local.
if [[ -f "$ROOT/.env.local" ]]; then
	# shellcheck disable=SC1091
	source "$ROOT/.env.local"
fi

WOW_DIR="${WOW_DIR:-/Applications/World of Warcraft/_forever_}"
ADDONS_DIR="$ROOT/addons"
CACHE_DIR="$ROOT/.cache"

die() {
	echo "error: $*" >&2
	exit 1
}

# Convert a client version like 1.60.1 to its TOC interface number (16001).
interface_from_version() {
	local major minor patch
	IFS=. read -r major minor patch _ <<<"$1"
	echo $((major * 10000 + minor * 100 + patch))
}

# Version of the installed Forever client (e.g. 1.60.1.70532), from the launcher's .build.info.
installed_client_version() {
	local info="$WOW_DIR/../.build.info"
	[[ -f "$info" ]] || return 1
	awk -F'|' '
		NR == 1 { for (i = 1; i <= NF; i++) { split($i, h, "!"); col[h[1]] = i } next }
		$col["Product"] == "wowf" { print $col["Version"]; exit }
	' "$info"
}
