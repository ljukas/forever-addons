#!/usr/bin/env bash
# Checks that a pull request title is a Conventional Commit: type(scope)!: description.
# PRs are squash-merged, so the title becomes the commit message on main.
# CI runs this on every PR (.github/workflows/pr-title.yml).
#
# Usage: scripts/check-pr-title.sh "feat(foreverprofessions): show node counts on the world map"
set -euo pipefail
source "$(dirname "$0")/lib.sh"

TYPES=(feat fix perf refactor docs style test build ci chore revert)
# Scopes for changes outside an addon. Each addon's scope is its folder name in lowercase.
OTHER_SCOPES=(ci scripts template types deps)

(($# == 1)) || die "usage: $0 \"<pull request title>\""
title="$1"

scopes=()
for dir in "$ADDONS_DIR"/*/; do
	scopes+=("$(basename "$dir" | tr '[:upper:]' '[:lower:]')")
done
scopes+=("${OTHER_SCOPES[@]}")

failed=0
fail() {
	echo "  $*" >&2
	failed=1
}

pattern='^([a-z]+)(\(([^()]*)\))?(!)?: ([^ ].*)$'
if [[ "$title" =~ $pattern ]]; then
	type="${BASH_REMATCH[1]}"
	scope="${BASH_REMATCH[3]}"

	[[ " ${TYPES[*]} " == *" $type "* ]] || fail "unknown type '$type'"
	if [[ -n "${BASH_REMATCH[2]}" ]]; then
		if [[ "$scope" =~ ^[a-z0-9-]+(,[a-z0-9-]+)*$ ]]; then
			IFS=, read -r -a parts <<<"$scope"
			for part in "${parts[@]}"; do
				[[ " ${scopes[*]} " == *" $part "* ]] || fail "unknown scope '$part'"
			done
		else
			fail "scope '($scope)' must be lowercase names separated by commas"
		fi
	fi
else
	fail "not in the form 'type(scope): description' (the scope is optional)"
fi

if ((failed)); then
	echo "PR title '$title' is not a Conventional Commit:" >&2
	echo "  types:  ${TYPES[*]}" >&2
	echo "  scopes: ${scopes[*]} (comma-separated, optional)" >&2
	echo "  e.g.    feat(foreverprofessions): show node counts on the world map" >&2
	exit 1
fi
echo "PR title OK: $title"
