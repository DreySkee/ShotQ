#!/bin/zsh
# Builds ShotQ.app and packages it into a distributable DMG in ./dist.
# Uses a writable intermediate image so Finder can write layout metadata
# (icon view, positions) — without it the Applications symlink renders
# without an icon.
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

hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDRW "$RW"
rm -rf "$STAGE"

MOUNT=$(hdiutil attach "$RW" | awk -F'\t' '/\/Volumes\//{print $NF}')

osascript <<EOF
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 200, 760, 500}
        set icon size of icon view options of container window to 100
        set arrangement of icon view options of container window to not arranged
        set position of item "ShotQ.app" of container window to {150, 130}
        set position of item "Applications" of container window to {410, 130}
        close
    end tell
end tell
EOF

sync
hdiutil detach "$MOUNT" >/dev/null
hdiutil convert "$RW" -format UDZO -o "$DMG" >/dev/null
rm -f "$RW"

echo "Created $DMG"
