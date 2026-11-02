# Shared helpers for scripts/*.sh. Source it; don't run it.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Per-machine overrides (e.g. WOW_DIR) live in the gitignored .env.local.
if [[ -f "$ROOT/.env.local" ]]; then
	# shellcheck disable=SC1091
	source "$ROOT/.env.local"
fi

die() {
	echo "error: $*" >&2
	exit 1
}

# Git Bash (MSYS) on Windows.
is_windows() {
	[[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]]
}

if is_windows; then
	# pwd keeps the case the path was typed in, but links are compared against git's paths, which
	# have the real case.
	ROOT="$(cygpath -u "$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || echo "$ROOT")")"
	# Through cygpath, since Cygwin mounts C: at /cygdrive/c where Git Bash uses /c.
	WOW_DIR="${WOW_DIR:-$(cygpath -u 'C:\Program Files (x86)\World of Warcraft\_forever_')}"
else
	WOW_DIR="${WOW_DIR:-/Applications/World of Warcraft/_forever_}"
fi
ADDONS_DIR="$ROOT/addons"
CACHE_DIR="$ROOT/.cache"

# Dies unless WOW_DIR holds an installed Forever client: the game's executable is only there while
# it is installed, so a folder left behind by an uninstall doesn't count.
require_game() {
	local game
	[[ -d "$WOW_DIR" ]] || die "WoW Forever not found at $WOW_DIR (set WOW_DIR in .env.local)"
	if is_windows; then game="Wow.exe"; else game="World of Warcraft.app"; fi
	[[ -e "$WOW_DIR/$game" ]] ||
		die "no $game in $WOW_DIR: is WoW Forever installed there? (set WOW_DIR in .env.local)"
}

# A path as this shell spells it. On Windows git prints C:/..., while pwd and readlink give /c/...
shell_path() {
	if is_windows; then cygpath -u "$1"; else echo "$1"; fi
}

# Points <link> at <target>, replacing <link> if it is already a link. On Windows, Git Bash's
# `ln -s` silently copies instead (real symlinks need Developer Mode), so this makes an NTFS
# junction, which needs no admin rights but only works for folders.
link_path() {
	local target="$1" link="$2"
	if ! is_windows; then
		ln -sfn "$target" "$link"
		return
	fi
	[[ -d "$target" ]] || die "can't link $target: Windows junctions only link folders"
	if [[ -L "$link" ]]; then
		rm "$link"
	fi
	# Paths go through the environment so spaces and "(x86)" survive the trip, and through cmd's
	# mklink because PowerShell's New-Item reads [ ] in the target as a wildcard.
	JUNCTION_LINK="$(cygpath -w "$link")" JUNCTION_TARGET="$(cygpath -w "$target")" \
		powershell.exe -NoProfile -NonInteractive -Command \
		'cmd /c mklink /J "$env:JUNCTION_LINK" "$env:JUNCTION_TARGET" > $null; exit $LASTEXITCODE'
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
