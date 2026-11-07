#!/bin/bash
# Compile Vigie en mode release et assemble build/Vigie.app (signature locale ad hoc).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Vigie
BIN="$(swift build -c release --show-bin-path)/Vigie"
APP="build/Vigie.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Vigie"
cp Support/Info.plist "$APP/Contents/Info.plist"
# Icônes générées par scripts/make-icon.swift.
cp Support/AppIcon.icns Support/MenuBarIcon.png Support/MenuBarIcon@2x.png "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null

echo "$APP"
