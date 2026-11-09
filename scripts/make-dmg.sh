#!/bin/bash
# Fabrique l'image disque de Vigie : fenêtre sur fond noir, Vigie à glisser dans Applications.
# Usage : ./scripts/make-dmg.sh X.Y.Z   →  dist/Vigie-X.Y.Z.dmg (à partir de build/Vigie.app, déjà construite)
# Le .dmg est signé avec la même identité que l'app ; sa notarisation se fait dans release.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?Usage : ./scripts/make-dmg.sh X.Y.Z}"
APP="build/Vigie.app"
DMG="dist/Vigie-$VERSION.dmg"
[ -d "$APP" ] || { echo "$APP n'existe pas : lancer d'abord ./scripts/build-app.sh"; exit 1; }

# dmgbuild (Python) écrit la mise en page de la fenêtre sans piloter le Finder.
# Installé une fois, dans un environnement à part (build/ n'est pas suivi par Git).
VENV="build/dmg-venv"
if [ ! -x "$VENV/bin/dmgbuild" ]; then
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --quiet "dmgbuild==1.6.5"
fi

mkdir -p dist
rm -f "$DMG"
"$VENV/bin/dmgbuild" -s scripts/dmg-reglages.py -D app="$PWD/$APP" "Vigie $VERSION" "$DMG"

# Même identité que l'app : le Developer ID s'il est là, sinon la signature locale.
IDENTITY=$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=\(Developer ID Application:.*\)$/\1/p' | head -1)
if [ -n "$IDENTITY" ]; then
    codesign --force --sign "$IDENTITY" --timestamp "$DMG"
    codesign --verify "$DMG"
fi
echo "Prêt : $DMG ($(du -h "$DMG" | cut -f1))"
