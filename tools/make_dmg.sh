#!/bin/zsh
# Builds ShotQ.app and packages it into a distributable DMG in ./dist.
#
# Two-pass approach for a clean result:
#   1. A throwaway writable image is mounted so Finder can author the icon-view
#      layout; we harvest only its .DS_Store.
#   2. The shipping DMG is built straight from a staging FOLDER (folder-sourced
#      images never accrue .fseventsd/.Trashes), with that .DS_Store dropped in.
set -euo pipefail
cd "$(dirname "$0")/.."

./build.sh

VERSION=$(defaults read "$(pwd)/build/ShotQ.app/Contents/Info" CFBundleShortVersionString)
VOLNAME="ShotQ $VERSION"

STAGE=$(mktemp -d)
ditto build/ShotQ.app "$STAGE/ShotQ.app"
ln -s /Applications "$STAGE/Applications"

mkdir -p dist
RW="dist/ShotQ-rw.dmg"
DMG="dist/ShotQ-$VERSION.dmg"
rm -f "$RW" "$DMG"

# --- Pass 1: author layout on a writable image, harvest .DS_Store ---
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -format UDRW -ov "$RW" >/dev/null
MOUNT=$(hdiutil attach "$RW" | awk -F'\t' '/\/Volumes\//{print $NF}')

osascript <<EOF
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 200, 760, 520}
        set theViewOptions to icon view options of container window
        set icon size of theViewOptions to 100
        set arrangement of theViewOptions to not arranged
        set position of item "ShotQ.app" of container window to {150, 160}
        set position of item "Applications" of container window to {410, 160}
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF

sync
cp "$MOUNT/.DS_Store" "$STAGE/.DS_Store"
hdiutil detach "$MOUNT" >/dev/null
rm -f "$RW"

# --- Pass 2: ship a clean folder-sourced compressed image ---
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"

echo "Created $DMG"
