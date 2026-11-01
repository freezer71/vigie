#!/bin/bash
# Produit les fichiers de distribution de Vigie :
#   build/Vigie-<version>.dmg  image disque : fenêtre illustrée, glisser Vigie dans Applications
#   build/Vigie-<version>.zip  l'app seule
# La mise en page de la fenêtre passe par le Finder : macOS peut demander d'autoriser le terminal à le piloter.
#
# Notarisation (supprime l'avertissement « Apple n'a pas pu confirmer… ») : si le profil du trousseau
# « vigie-notary » existe, le DMG est signé, envoyé à Apple, puis le ticket est agrafé au DMG et à l'app.
# Créer le profil une fois :
#   xcrun notarytool store-credentials vigie-notary --apple-id <e-mail Apple> --team-id 9M6324GD46
# (mot de passe : un « mot de passe pour app » créé sur account.apple.com). NOTARY_PROFILE=… pour un autre nom.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
NAME="Vigie"
DMG="build/$NAME-$VERSION.dmg"
WORK=build/dmg
rm -rf "$WORK" "$DMG" "build/$NAME-$VERSION.zip"
mkdir -p "$WORK/stage/.background"

# Fond 1× et 2× réunis dans un TIFF : le Finder choisit selon l'écran.
swift scripts/make-dmg-background.swift "$WORK" >/dev/null
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/stage/.background/background.tiff" 2>/dev/null
ditto build/Vigie.app "$WORK/stage/Vigie.app"
ln -s /Applications "$WORK/stage/Applications"

# Image modifiable, mise en page par le Finder, puis compression.
hdiutil detach "/Volumes/$NAME" -quiet 2>/dev/null || true
hdiutil create -srcfolder "$WORK/stage" -volname "$NAME" -fs HFS+ -format UDRW -ov "$WORK/rw.dmg" -quiet
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "$WORK/rw.dmg" | awk '/Apple_HFS/ {print $1}')
MOUNT="/Volumes/$NAME"
SetFile -a V "$MOUNT/.background"

# Positions identiques à celles de scripts/make-dmg-background.swift (appCenter, applicationsCenter).
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 840, 548}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 112
        set text size of opts to 13
        set background picture of opts to file ".background:background.tiff"
        set position of item "Vigie.app" of container window to {170, 190}
        set position of item "Applications" of container window to {470, 190}
        update without registering applications
        delay 1
        close
        open
        -- La barre d'état ne disparaît que réglée sur une fenêtre déjà ouverte.
        set statusbar visible of container window to false
        set toolbar visible of container window to false
        set the bounds of container window to {200, 120, 840, 548}
        delay 1
        close
    end tell
end tell
APPLESCRIPT

# Icône du volume, ajoutée après le passage du Finder (qui la supprime sinon).
cp Resources/AppIcon.icns "$MOUNT/.VolumeIcon.icns"
SetFile -c icnC -a V "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT"
chmod -Rf go-w "$MOUNT" || true
sync
hdiutil detach "$DEVICE" -quiet
hdiutil convert "$WORK/rw.dmg" -format ULFO -o "$DMG" -quiet
rm -rf "$WORK"

PROFILE="${NOTARY_PROFILE:-vigie-notary}"
IDENTITY=$(codesign -dv build/Vigie.app 2>&1 | awk -F= '/^Authority=Developer ID Application/ {print $2; exit}')
if [[ -n "$IDENTITY" ]]; then
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
  if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    echo "… notarisation par Apple (quelques minutes)"
    xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple -q "$DMG"
    xcrun stapler staple -q build/Vigie.app     # le ticket couvre aussi l'app contenue dans le DMG
    spctl -a -t open --context context:primary-signature "$DMG" && echo "✔ notarisé et accepté par Gatekeeper"
  else
    echo "⚠ pas de profil « $PROFILE » : DMG signé mais non notarisé (voir l'en-tête du script)"
  fi
fi

# Zip de l'app seule (après l'agrafage, pour qu'il contienne le ticket).
ditto -c -k --sequesterRsrc --keepParent build/Vigie.app "build/$NAME-$VERSION.zip"
echo "✔ $DMG"
echo "✔ build/$NAME-$VERSION.zip"
