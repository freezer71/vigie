#!/bin/bash
# Compile Vigie en release et assemble build/Vigie.app (signature ad hoc).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Vigie"

APP=build/Vigie.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Vigie"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"   # régénérer : python3 scripts/make-logo.py
codesign --force --sign - "$APP"
echo "✔ $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Vigie 2>/dev/null || true
  rm -rf /Applications/Vigie.app
  cp -R "$APP" /Applications/
  open /Applications/Vigie.app
  echo "✔ installée dans /Applications et lancée"
fi
