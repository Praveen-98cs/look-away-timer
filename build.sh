#!/bin/zsh
# Builds "Look Away.app" into ./build. Pass --install to copy it to /Applications.
#   VERSION=1.2.0   sets the app version (default: value in Info.plist)
#   UNIVERSAL=1     builds for both Apple Silicon and Intel (needs full Xcode)
set -euo pipefail
cd "$(dirname "$0")"

if [[ "${UNIVERSAL:-}" == "1" ]]; then
    swift build -c release --arch arm64 --arch x86_64
    BIN=".build/apple/Products/Release/LookAway"
else
    swift build -c release
    BIN=".build/release/LookAway"
fi

APP="build/Look Away.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LookAway"
cp Info.plist "$APP/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
fi
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x LookAway 2>/dev/null || true
    rm -rf "/Applications/Look Away.app"
    cp -R "$APP" /Applications/
    open "/Applications/Look Away.app"
    echo "Installed to /Applications/Look Away.app"
fi
