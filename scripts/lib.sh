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

# Path of an addon's most recently written SavedVariables file across all accounts. Dies when
# there is none yet. The game only writes SavedVariables on /reload, logout or exit.
latest_saved_variables() {
	local file
	file="$(ls -t "$WOW_DIR"/WTF/Account/*/SavedVariables/"$1".lua 2>/dev/null | head -n1 || true)"
	[[ -n "$file" ]] || die "no $1 SavedVariables under $WOW_DIR/WTF yet (enable $1, then /rl in game)"
	echo "$file"
}

# A Lua 5.1 interpreter for the scripts/*.lua SavedVariables readers.
lua51() {
	command -v luajit || command -v lua5.1 || die "needs luajit or lua 5.1 (brew install luajit)"
}

# Prints which file is being read and when the game wrote it.
print_file_header() {
	echo "File: $1 (written $(date -r "$1" '+%Y-%m-%d %H:%M:%S'))"
}
