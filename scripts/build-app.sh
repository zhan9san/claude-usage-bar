#!/usr/bin/env bash
# Builds "Claude Usage Bar.app" into ./build with the Swift Package Manager.
# Usage: scripts/build-app.sh [--install]
#   --install  copy the app to ~/Applications and launch it
# Environment:
#   APP_VERSION  overrides CFBundleShortVersionString (e.g. 1.2.0)
#   APP_BUILD    overrides CFBundleVersion (e.g. a CI run number)
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Claude Usage Bar"
EXECUTABLE="ClaudeUsageBar"
APP_DIR="build/${APP_NAME}.app"

swift build -c release --product "$EXECUTABLE"
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$APP_DIR/Contents/MacOS/$EXECUTABLE"
PLIST="$APP_DIR/Contents/Info.plist"
cp Resources/Info.plist "$PLIST"
if [[ -n "${APP_VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$PLIST"
fi
if [[ -n "${APP_BUILD:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_BUILD" "$PLIST"
fi

# Ad-hoc signature: enough for local use, Keychain access and launch at login.
codesign --force --sign - --timestamp=none "$APP_DIR"
codesign --verify --strict "$APP_DIR"
echo "Built $APP_DIR"

if [[ "${1:-}" == "--install" ]]; then
    TARGET="$HOME/Applications/${APP_NAME}.app"
    mkdir -p "$HOME/Applications"
    pkill -x "$EXECUTABLE" 2>/dev/null || true
    rm -rf "$TARGET"
    cp -R "$APP_DIR" "$TARGET"
    open "$TARGET"
    echo "Installed and launched $TARGET"
fi
