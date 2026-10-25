#!/usr/bin/env bash
# Static checks for everything under addons/, template/ and types/:
#   1. StyLua formatting (run `stylua addons template types` to fix)
#   2. LuaLS diagnostics against the WoW API annotations + Forever UI source
#   3. TOC sanity: interface matches the current Forever client, listed files exist,
#      and every Lua/XML file is loaded by the TOC (directly or via XML)
# Exits non-zero if any check fails.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
cd "$ROOT"

failed=0
fail() {
	echo "  $*"
	failed=1
}

if [[ ! -d "$CACHE_DIR/wow-api" || ! -d "$CACHE_DIR/wow-ui-source" ]]; then
	"$ROOT/scripts/setup.sh" || die "setup failed"
fi

echo "==> StyLua"
stylua --check addons template types || failed=1

echo "==> LuaLS"
# Strip colours and the progress bar so the output stays readable in logs.
lua-language-server --check="$ROOT" --checklevel=Warning --check_format=pretty --logpath="$CACHE_DIR/luals" 2>&1 |
	sed -E $'s/\x1b\\[[0-9;]*m//g' | tr '\r' '\n' | grep -v -E '^ *(>|Initializing|$)'
((PIPESTATUS[0] == 0)) || failed=1

echo "==> TOC"
interface="$(interface_from_version "$(head -n1 "$CACHE_DIR/wow-ui-source/version.txt")")"
for toc in addons/*/*.toc template/Addon/*.toc; do
	dir="$(dirname "$toc")"

	toc_interface="$(sed -n -E 's/^## Interface: *//p' "$toc" | tr -d '\r ')"
	[[ ",$toc_interface," == *",$interface,"* ]] ||
		fail "$toc: '## Interface: $toc_interface' does not include current Forever interface $interface"

	# Files the TOC loads, minus inline [directives]; lines using [Variables] are skipped.
	loaded="$(grep -v -E '^\s*(#|$)' "$toc" | sed -E 's/ *\[(AllowLoad|ExcludeLoad)[^]]*\]//g; s/\r$//; s/ +$//' | tr '\\' '/')"
	while IFS= read -r file; do
		[[ -z "$file" || "$file" == *"["* ]] && continue
		[[ -f "$dir/$file" ]] || fail "$toc: lists '$file', which does not exist"
	done <<<"$loaded"

	while IFS= read -r file; do
		rel="${file#"$dir"/}"
		name="$(basename "$file")"
		[[ "$name" == "Bindings.xml" ]] && continue
		grep -qxF "$rel" <<<"$loaded" && continue
		grep -rqsF --include='*.xml' "$name" "$dir" && continue
		fail "$file is not loaded by $toc or any XML file"
	done < <(find "$dir" -type f \( -name '*.lua' -o -name '*.xml' \) | sort)
done

if ((failed)); then
	echo "Lint failed."
	exit 1
fi
echo "All checks passed."
