#!/bin/zsh
# Builds ShotQ.app and packages it into a distributable DMG in ./dist using
# create-dmg (brew install create-dmg), which renders the Applications drop
# target correctly and leaves no .fseventsd cruft in the volume.
set -euo pipefail
cd "$(dirname "$0")/.."

./build.sh

VERSION=$(defaults read "$(pwd)/build/ShotQ.app/Contents/Info" CFBundleShortVersionString)
mkdir -p dist
DMG="dist/ShotQ-$VERSION.dmg"
rm -f "$DMG"

# create-dmg adds the /Applications symlink itself (--app-drop-link) with the
# proper folder icon. Staging dir holds only the app.
STAGE=$(mktemp -d)
ditto build/ShotQ.app "$STAGE/ShotQ.app"

create-dmg \
    --volname "ShotQ $VERSION" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 110 \
    --icon "ShotQ.app" 150 190 \
    --app-drop-link 450 190 \
    --hide-extension "ShotQ.app" \
    --no-internet-enable \
    "$DMG" \
    "$STAGE"

rm -rf "$STAGE"
echo "Created $DMG"
