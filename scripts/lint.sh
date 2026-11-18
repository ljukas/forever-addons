#!/usr/bin/env bash
# Static checks for everything under addons/, template/ and types/:
#   1. StyLua formatting (run `stylua addons template types` to fix)
#   2. LuaLS diagnostics against the WoW API annotations + Forever UI source
#   3. TOC sanity: interface matches the current Forever client, listed files exist,
#      and every Lua/XML file is loaded by the TOC (directly or via XML). StyLua, LuaLS and the
#      loaded-by-the-TOC check skip Libs/ (fetched libraries, see scripts/libs.sh).
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
# Libraries from .pkgmeta externals: the TOC checks below need them in place.
"$ROOT/scripts/libs.sh" || die "fetching libraries failed"

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

	# Dependencies must be addons of this repo. A module has three marks: it depends on the core,
	# is in the core's Group, and its title starts with the core's name (colour codes aside). A TOC
	# with any of the three needs all of them: the core finds modules by the dependency alone, so
	# one that only looks like a module would be left out of its list.
	toc_dependencies="$(sed -n -E 's/^## Dependencies: *//p' "$toc" | tr -d '\r ')"
	depends_on_core=0
	while IFS= read -r dependency; do
		[[ -n "$dependency" ]] || continue
		[[ -f "addons/$dependency/$dependency.toc" ]] ||
			fail "$toc: '## Dependencies' names '$dependency', which is not an addon folder under addons/"
		[[ "$dependency" == "$CORE_ADDON" ]] && depends_on_core=1
	done < <(tr ',' '\n' <<<"$toc_dependencies")
	toc_group="$(sed -n -E 's/^## Group: *//p' "$toc" | tr -d '\r' | sed -E 's/ +$//')"
	toc_title="$(sed -n -E 's/^## Title: *//p' "$toc" | tr -d '\r' | sed -E 's/\|c[0-9A-Fa-f]{8}//g; s/\|r//g')"
	in_core_group=0
	has_core_title=0
	[[ "$toc_group" == "$CORE_ADDON" ]] && in_core_group=1
	[[ "$toc_title" == "$CORE_TITLE "* ]] && has_core_title=1
	if ((depends_on_core || in_core_group || has_core_title)); then
		((depends_on_core)) ||
			fail "$toc: looks like a $CORE_ADDON module (Group or title) but lacks '## Dependencies: $CORE_ADDON'"
		((in_core_group)) ||
			fail "$toc: looks like a $CORE_ADDON module (dependency or title) but lacks the line '## Group: $CORE_ADDON'"
		((has_core_title)) ||
			fail "$toc: looks like a $CORE_ADDON module (dependency or Group) but its '## Title:' does not start with '$CORE_TITLE ' (colour codes aside)"
	fi

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
		grep -rqsF --include='*.xml' --exclude-dir=Libs "$name" "$dir" && continue
		fail "$file is not loaded by $toc or any XML file"
	done < <(find "$dir" -path "$dir/Libs" -prune -o -type f \( -name '*.lua' -o -name '*.xml' \) -print | sort)
done

if ((failed)); then
	echo "Lint failed."
	exit 1
fi
echo "All checks passed."
