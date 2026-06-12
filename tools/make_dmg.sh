#!/bin/zsh
# Builds ShotQ.app and packages it into a distributable DMG in ./dist.
set -euo pipefail
cd "$(dirname "$0")/.."

./build.sh

VERSION=$(defaults read "$(pwd)/build/ShotQ.app/Contents/Info" CFBundleShortVersionString)
STAGE=$(mktemp -d)
ditto build/ShotQ.app "$STAGE/ShotQ.app"
ln -s /Applications "$STAGE/Applications"

mkdir -p dist
DMG="dist/ShotQ-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "ShotQ $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

echo "Created $DMG"
