#!/bin/bash
# Produit les fichiers de distribution de Vigie :
#   build/Vigie-<version>.dmg  image disque : fenêtre illustrée, glisser Vigie dans Applications
#   build/Vigie-<version>.zip  l'app seule
# La mise en page de la fenêtre passe par le Finder : macOS peut demander d'autoriser le terminal à le piloter.
#
# Notarisation (supprime l'avertissement « Apple n'a pas pu confirmer… »), avant la création du DMG :
#   - avec le profil du trousseau « vigie-notary » s'il existe (notarytool : l'app puis le DMG sont notarisés) ;
#     le créer une fois : xcrun notarytool store-credentials vigie-notary --apple-id <e-mail> --team-id 9M6324GD46
#   - sinon avec le compte connecté dans Xcode (archive .xcarchive envoyée par xcodebuild ; l'app est notarisée).
# NOTARIZE=0 pour s'en passer.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" Resources/Info.plist)
ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" Resources/Info.plist)
PROFILE="${NOTARY_PROFILE:-vigie-notary}"
IDENTITY=$(codesign -dvv build/Vigie.app 2>&1 | awk -F= '/^Authority=Developer ID Application/ {print $2}')
TEAM=$(codesign -dv build/Vigie.app 2>&1 | awk -F= '/^TeamIdentifier=/ {print $2}')
HAS_PROFILE=0
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 && HAS_PROFILE=1

if [[ -n "$IDENTITY" && "${NOTARIZE:-1}" != "0" ]]; then
  echo "… notarisation de l'app par Apple"
  if [[ $HAS_PROFILE == 1 ]]; then
    ditto -c -k --keepParent build/Vigie.app build/notarize.zip
    xcrun notarytool submit build/notarize.zip --keychain-profile "$PROFILE" --wait
    rm -f build/notarize.zip
  else
    # Compte Xcode : une archive minimale, exportée vers le service de notarisation.
    ARCHIVE=build/Vigie.xcarchive
    rm -rf "$ARCHIVE" build/notarized
    mkdir -p "$ARCHIVE/Products/Applications"
    ditto build/Vigie.app "$ARCHIVE/Products/Applications/Vigie.app"
    cat > "$ARCHIVE/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>ApplicationProperties</key><dict>
    <key>ApplicationPath</key><string>Applications/Vigie.app</string>
    <key>Architectures</key><array><string>arm64</string></array>
    <key>CFBundleIdentifier</key><string>$ID</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>SigningIdentity</key><string>$IDENTITY</string>
    <key>Team</key><string>$TEAM</string>
  </dict>
  <key>ArchiveVersion</key><integer>2</integer>
  <key>CreationDate</key><date>$(date -u +%Y-%m-%dT%H:%M:%SZ)</date>
  <key>Name</key><string>Vigie</string>
  <key>SchemeName</key><string>Vigie</string>
</dict></plist>
PLIST
    cat > build/export-options.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
</dict></plist>
PLIST
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath build/notarize-upload \
               -exportOptionsPlist build/export-options.plist 2>&1 | grep -E "Uploaded|SUCCEEDED|FAILED|error"
    # Attente de la validation (en général moins d'une minute).
    for _ in $(seq 1 60); do
      xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath build/notarized >/dev/null 2>&1 && break
      sleep 10
    done
    [[ -d build/notarized/Vigie.app ]] || { echo "✘ notarisation non terminée"; exit 1; }
    rm -rf build/Vigie.app && ditto build/notarized/Vigie.app build/Vigie.app
    rm -rf "$ARCHIVE" build/notarized build/notarize-upload build/export-options.plist
  fi
  xcrun stapler staple -q build/Vigie.app
  spctl -a -t exec build/Vigie.app && echo "✔ app notarisée, acceptée par Gatekeeper"
fi

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

if [[ -n "$IDENTITY" ]]; then
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
  if [[ $HAS_PROFILE == 1 && "${NOTARIZE:-1}" != "0" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple -q "$DMG"
  fi
fi

# Zip de l'app seule (après l'agrafage, pour qu'il contienne le ticket).
ditto -c -k --sequesterRsrc --keepParent build/Vigie.app "build/$NAME-$VERSION.zip"
echo "✔ $DMG"
echo "✔ build/$NAME-$VERSION.zip"
