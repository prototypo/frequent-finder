#!/bin/bash
# Builds build/FrequentFinder.app and build/FrequentFinderDeck.app, and installs ff to ~/.local/bin.
# --install also copies the apps to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)"
APP=build/FrequentFinder.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/FrequentFinder" "$APP/Contents/MacOS/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>org.hyland-wood.FrequentFinder</string>
    <key>CFBundleName</key><string>Frequent Finder</string>
    <key>CFBundleExecutable</key><string>FrequentFinder</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>org.hyland-wood.FrequentFinder.project</string>
            <key>CFBundleURLSchemes</key><array><string>frequentfinder</string></array>
        </dict>
    </array>
    <key>UTImportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key><string>org.hyland-wood.openpmtools.project</string>
            <key>UTTypeConformsTo</key><array><string>public.json</string></array>
            <key>UTTypeDescription</key><string>OpenPMTools Project</string>
        </dict>
    </array>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"

# The Deck experiment: the same projects as cards, read from two Obsidian vaults.
# It has no URL scheme, so project links still go to the main app.
DECK=build/FrequentFinderDeck.app
rm -rf "$DECK"
mkdir -p "$DECK/Contents/MacOS" "$DECK/Contents/Resources"
cp "$BIN/FrequentFinderDeck" "$DECK/Contents/MacOS/"
cp Resources/AppIcon.icns "$DECK/Contents/Resources/"
cat > "$DECK/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>org.hyland-wood.FrequentFinderDeck</string>
    <key>CFBundleName</key><string>Frequent Finder Deck</string>
    <key>CFBundleExecutable</key><string>FrequentFinderDeck</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$DECK"

mkdir -p "$HOME/.local/bin"
cp "$BIN/ff" "$HOME/.local/bin/ff"
echo "Built $APP and $DECK; installed ff to ~/.local/bin/ff"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/FrequentFinder.app
    cp -R "$APP" /Applications/
    echo "Installed /Applications/FrequentFinder.app"
    rm -rf /Applications/FrequentFinderDeck.app
    cp -R "$DECK" /Applications/
    echo "Installed /Applications/FrequentFinderDeck.app"
fi
