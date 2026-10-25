#!/usr/bin/env bash
# Scaffolds addons/<Name> from template/Addon and links it into the game.
# Usage: scripts/new-addon.sh <Name>     (PascalCase, e.g. MyAddon)
set -euo pipefail
source "$(dirname "$0")/lib.sh"

name="${1:-}"
[[ "$name" =~ ^[A-Z][A-Za-z0-9]+$ ]] || die "usage: $0 <Name>  (PascalCase letters/digits, e.g. MyAddon)"
dest="$ADDONS_DIR/$name"
[[ ! -e "$dest" ]] || die "$dest already exists"

cp -R "$ROOT/template/Addon" "$dest"
mv "$dest/__ADDON__.toc" "$dest/$name.toc"
find "$dest" -type f -exec perl -pi -e "s/__ADDON__/$name/g" {} +

echo "created addons/$name"
"$ROOT/scripts/link.sh" "$name"
echo "In game: /reload and enable $name in the AddOns list (restart the client if it doesn't show up)."
