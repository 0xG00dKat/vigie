#!/bin/bash
# Compile Vigie en mode release et assemble build/Vigie.app, signée localement.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Vigie
BIN="$(swift build -c release --show-bin-path)/Vigie"
APP="build/Vigie.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Vigie"
cp Support/Info.plist "$APP/Contents/Info.plist"
# Icône de l'app : le document Icon Composer est compilé en Assets.car (macOS 26 et plus, effet verre)
# et en Vigie.icns (macOS 14 et 15). Les clés CFBundleIconName / CFBundleIconFile d'Info.plist les désignent.
xcrun actool Support/Vigie.icon --compile "$APP/Contents/Resources" --platform macosx \
    --minimum-deployment-target 14.0 --app-icon Vigie \
    --output-partial-info-plist "$(mktemp -d)/icone.plist" --output-format human-readable-text >/dev/null
# Icône de barre des menus, générée par scripts/make-icon.swift.
cp Support/MenuBarIcon.png Support/MenuBarIcon@2x.png "$APP/Contents/Resources/"
# Son de l'animation d'ouverture, généré par scripts/make-intro-sound.py.
cp Support/ouverture.m4a "$APP/Contents/Resources/"

# Signature, dans cet ordre :
# 1. le Developer ID de l'éditeur (« Developer ID Application: … »), avec l'exécution renforcée et un horodatage :
#    c'est ce que la notarisation d'Apple exige (scripts/notarize.sh) ;
# 2. le certificat local « Vigie Local Signing » : macOS reconnaît Vigie d'une version à l'autre sur ce Mac ;
# 3. sinon, signature ad hoc (macOS reconnaît l'app à l'empreinte exacte du programme, qui change à chaque build).
# VIGIE_SIGN_IDENTITY force une identité (« - » pour ad hoc).
IDENTITY="${VIGIE_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application:/ { print $2; exit }')
fi
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -p codesigning 2>/dev/null | awk '/"Vigie Local Signing"/ { print $2; exit }')
fi
IDENTITY="${IDENTITY:--}"
case "$IDENTITY" in
    "Developer ID Application:"*)
        codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
        echo "Signature : $IDENTITY (exécution renforcée)" >&2 ;;
    "-")
        codesign --force --sign - "$APP"
        echo "Signature ad hoc" >&2 ;;
    *)
        codesign --force --sign "$IDENTITY" "$APP"
        echo "Signature : certificat local" >&2 ;;
esac
codesign --verify --strict "$APP"

echo "$APP"
