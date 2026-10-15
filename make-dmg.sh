#!/bin/zsh
# Builds the app and packages it as build/LookAway-<version>.dmg
# with an /Applications shortcut for drag-to-install.
#   ./make-dmg.sh 1.2.0
set -euo pipefail
cd "$(dirname "$0")"

export VERSION="${1:-${VERSION:-dev}}"
./build.sh

STAGE="build/dmg"
DMG="build/LookAway-${VERSION}.dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "build/Look Away.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Look Away" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
echo "Created $DMG"
