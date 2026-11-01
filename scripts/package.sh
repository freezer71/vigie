#!/bin/bash
# Produit les fichiers de distribution de Vigie :
#   build/Vigie-<version>.zip  l'app seule
#   build/Vigie-<version>.pkg  l'installateur macOS (installe dans /Applications puis lance Vigie)
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" Resources/Info.plist)
WORK=build/pkg
rm -rf "$WORK" "build/Vigie-$VERSION.zip" "build/Vigie-$VERSION.pkg"
mkdir -p "$WORK/root/Applications" "$WORK/resources"

# Zip de l'app seule.
ditto -c -k --sequesterRsrc --keepParent build/Vigie.app "build/Vigie-$VERSION.zip"

# Paquet du composant : l'app, installée à /Applications, jamais « déplacée » vers une autre copie.
ditto build/Vigie.app "$WORK/root/Applications/Vigie.app"
pkgbuild --analyze --root "$WORK/root" "$WORK/component.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Add :0:BundleIsRelocatable bool false" "$WORK/component.plist"
pkgbuild --root "$WORK/root" --component-plist "$WORK/component.plist" \
         --identifier "$ID" --version "$VERSION" --install-location / \
         --scripts installer/scripts "$WORK/Vigie-component.pkg" >/dev/null

# Assistant d'installation : accueil, fond avec le logo, vérification du Mac, conclusion.
cp installer/resources/*.html "$WORK/resources/"
cp design/logo/vigie-icon.png "$WORK/resources/background.png"
cat > "$WORK/distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>Vigie $VERSION</title>
    <welcome file="welcome.html" mime-type="text/html"/>
    <conclusion file="conclusion.html" mime-type="text/html"/>
    <background file="background.png" alignment="bottomleft" scaling="proportional"/>
    <background-darkAqua file="background.png" alignment="bottomleft" scaling="proportional"/>
    <options customize="never" require-scripts="false" hostArchitectures="arm64"/>
    <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
    <allowed-os-versions><os-version min="14.0"/></allowed-os-versions>
    <choices-outline><line choice="default"><line choice="$ID"/></line></choices-outline>
    <choice id="default"/>
    <choice id="$ID" visible="false"><pkg-ref id="$ID"/></choice>
    <pkg-ref id="$ID" version="$VERSION" onConclusion="none">Vigie-component.pkg</pkg-ref>
</installer-gui-script>
XML
productbuild --distribution "$WORK/distribution.xml" --resources "$WORK/resources" \
             --package-path "$WORK" "build/Vigie-$VERSION.pkg" >/dev/null
rm -rf "$WORK"
echo "✔ build/Vigie-$VERSION.zip"
echo "✔ build/Vigie-$VERSION.pkg"
