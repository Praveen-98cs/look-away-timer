#!/bin/zsh
# Builds "Healthy Pops.app" into ./build. Pass --install to copy it to /Applications.
#   VERSION=1.2.0   sets the app version (default: value in Info.plist)
#   UNIVERSAL=1     builds for both Apple Silicon and Intel (needs full Xcode)
set -euo pipefail
cd "$(dirname "$0")"

if [[ "${UNIVERSAL:-}" == "1" ]]; then
    swift build -c release --arch arm64 --arch x86_64
    BIN=".build/apple/Products/Release/HealthyPops"
else
    swift build -c release
    BIN=".build/release/HealthyPops"
fi

APP="build/Healthy Pops.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/HealthyPops"
cp Info.plist "$APP/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
fi
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    # Also replace the app from before the rename (Look Away), which shares the bundle ID.
    pkill -x HealthyPops 2>/dev/null || true
    pkill -x LookAway 2>/dev/null || true
    rm -rf "/Applications/Healthy Pops.app" "/Applications/Look Away.app"
    cp -R "$APP" /Applications/
    open "/Applications/Healthy Pops.app"
    echo "Installed to /Applications/Healthy Pops.app"
fi
