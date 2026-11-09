#!/bin/bash
# Construit Vigie signée avec le Developer ID, l'envoie à Apple pour la notarisation, attend le verdict,
# agrafe le ticket à l'app et vérifie que Gatekeeper l'accepte. Rien n'est publié.
#
# Prérequis (une fois, sur ce Mac) :
#   - le certificat « Developer ID Application: … » avec sa clé privée dans le trousseau ;
#   - les identifiants de notarisation : xcrun notarytool store-credentials vigie --apple-id … --team-id …
#     (VIGIE_NOTARY_PROFILE pour un autre nom de profil).
#
# Usage : ./scripts/notarize.sh        → build/Vigie.app notarisée et agrafée, et dist/Vigie-notarisee.zip
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${VIGIE_NOTARY_PROFILE:-vigie}"
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application:/ { print $2; exit }')
[ -n "$IDENTITY" ] || { echo "Aucun certificat « Developer ID Application » utilisable dans le trousseau."; exit 1; }

VIGIE_SIGN_IDENTITY="$IDENTITY" ./scripts/build-app.sh >/dev/null
APP="build/Vigie.app"

mkdir -p dist
ZIP="dist/Vigie-a-notariser.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "Envoi à Apple pour notarisation (quelques minutes)…"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait | tee dist/notarisation.log
if ! grep -q "status: Accepted" dist/notarisation.log; then
    ID=$(awk '/^  id:/ { print $2; exit }' dist/notarisation.log)
    [ -n "$ID" ] && xcrun notarytool log "$ID" --keychain-profile "$PROFILE" dist/notarisation-erreurs.json || true
    echo "Notarisation refusée : voir dist/notarisation.log et dist/notarisation-erreurs.json."
    exit 1
fi

# Le ticket agrafé permet à Gatekeeper d'accepter l'app même hors ligne.
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" dist/Vigie-notarisee.zip
echo "Notarisée et agrafée : $APP (archive : dist/Vigie-notarisee.zip)"
