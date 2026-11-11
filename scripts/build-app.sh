#!/usr/bin/env bash
# Builds "Claude Usage Bar.app" into ./build with the Swift Package Manager.
# Usage: scripts/build-app.sh [--install]
#   --install  copy the app to ~/Applications and launch it
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
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"

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
