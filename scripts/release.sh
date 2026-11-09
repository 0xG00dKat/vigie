#!/bin/bash
# Prépare une version de Vigie : vérifications, tests, construction, archive .zip et notes de version.
# Avec --publish, crée aussi l'étiquette Git et la version sur GitHub (avec le .zip).
#
# Usage : ./scripts/release.sh 0.2.0 [--publish]
#
# Avant : mettre CFBundleShortVersionString à jour dans Support/Info.plist
# et ajouter une section « ## 0.2.0 » dans CHANGELOG.md, puis commiter sur main.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?Usage : ./scripts/release.sh X.Y.Z [--publish]}"
PUBLISH="${2:-}"
TAG="v$VERSION"

branch=$(git rev-parse --abbrev-ref HEAD)
[ "$branch" = "main" ] || { echo "Il faut être sur main (branche actuelle : $branch)."; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Des modifications ne sont pas commitées."; exit 1; }
plist=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Support/Info.plist)
[ "$plist" = "$VERSION" ] || { echo "Support/Info.plist annonce la version $plist, pas $VERSION."; exit 1; }
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then echo "L'étiquette $TAG existe déjà."; exit 1; fi
grep -q "^## $VERSION" CHANGELOG.md || { echo "CHANGELOG.md n'a pas de section « ## $VERSION »."; exit 1; }

swift test
# Les versions publiques sont signées avec le Developer ID et notarisées par Apple (scripts/notarize.sh).
./scripts/notarize.sh

mkdir -p dist
ZIP="dist/Vigie-$VERSION.zip"
NOTES="dist/notes-$VERSION.md"
rm -f "$ZIP"
# ditto garde la signature et les attributs du paquet .app.
ditto -c -k --keepParent build/Vigie.app "$ZIP"
# Notes : la section de cette version dans CHANGELOG.md, jusqu'à la section suivante.
awk -v head="## $VERSION" '/^## / { if (found) exit; if (index($0, head) == 1) { found = 1; next } } found' CHANGELOG.md > "$NOTES"

echo "Prêt : $ZIP ($(du -h "$ZIP" | cut -f1)) et $NOTES"

if [ "$PUBLISH" = "--publish" ]; then
    git tag -a "$TAG" -m "Vigie $VERSION"
    # Envoi avec la connexion de la commande gh (pas besoin de clé SSH).
    git -c credential.helper= -c 'credential.helper=!gh auth git-credential' push origin "$TAG"
    gh release create "$TAG" "$ZIP" --title "Vigie $VERSION" --notes-file "$NOTES"
    echo "Publié : $(gh release view "$TAG" --json url --jq .url)"
else
    echo "Pour publier : ./scripts/release.sh $VERSION --publish"
fi
