#!/bin/zsh
# Builds ShotQueue.app into ./build and ad-hoc signs it.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/ShotQueue.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ShotQueue "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
IDENTITY="ScreenshotVault Dev Signing"
if security find-identity -v -p codesigning | grep -q "$IDENTITY" \
    && codesign --force --sign "$IDENTITY" "$APP" 2>/dev/null; then
    echo "Signed with stable identity: $IDENTITY"
else
    codesign --force --sign - "$APP"
    echo "WARNING: ad-hoc signed — TCC grants reset on every rebuild"
fi

echo "Built $APP"
echo "Install: ditto $APP ~/Applications/ShotQueue.app && open ~/Applications/ShotQueue.app"
