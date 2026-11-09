#!/bin/bash
# Installe build/Vigie.app dans /Applications en remplaçant l'ancienne copie (jamais par-dessus :
# un fichier qui n'existe plus dans la nouvelle version resterait dans le paquet et casserait la signature).
# Quitte Vigie, copie à côté, échange, vérifie la signature, relance.
#
# Usage : ./scripts/install.sh   (après ./scripts/build-app.sh)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Vigie.app"
TARGET="/Applications/Vigie.app"
NEXT="/Applications/.Vigie-nouvelle.app"
[ -d "$APP" ] || { echo "Pas de $APP : lance d'abord ./scripts/build-app.sh."; exit 1; }
codesign --verify --strict "$APP"

osascript -e 'tell application id "io.github.0xg00dkat.vigie" to quit' 2>/dev/null || true
for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -xq Vigie || break; sleep 0.5; done

rm -rf "$NEXT"
ditto "$APP" "$NEXT"
rm -rf "$TARGET"
mv "$NEXT" "$TARGET"
codesign --verify --strict "$TARGET"
# Gatekeeper n'accepte que les versions notarisées par Apple (scripts/notarize.sh) ; un build local ne l'est pas,
# ce qui ne gêne pas pour l'utiliser sur ce Mac.
spctl --assess --type execute "$TARGET" 2>/dev/null && echo "Gatekeeper : accepté (notarisée)" || echo "Gatekeeper : build local, non notarisé (normal ici)"

open "$TARGET"
echo "Installé : $TARGET"
