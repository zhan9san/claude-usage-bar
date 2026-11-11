#!/usr/bin/env bash
# Installs a claude-usage-bar cask file from a throwaway local tap, checks the
# installed app, then uninstalls it and removes the tap.
# Usage: scripts/verify-cask.sh <cask-file>
# Note: this really installs the app into /Applications, so it is meant for CI.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <cask-file>" >&2
    exit 64
fi

CASK_FILE="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
TAP_NAME="local/cask-verify"
CASK="$TAP_NAME/claude-usage-bar"
APP="/Applications/Claude Usage Bar.app"

export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
export HOMEBREW_NO_ENV_HINTS=1

TAP_DIR="$(mktemp -d)"
cleanup() {
    brew uninstall --cask "$CASK" >/dev/null 2>&1 || true
    brew untap "$TAP_NAME" >/dev/null 2>&1 || true
    rm -rf "$TAP_DIR"
}
trap cleanup EXIT

mkdir -p "$TAP_DIR/Casks"
cp "$CASK_FILE" "$TAP_DIR/Casks/claude-usage-bar.rb"
git -C "$TAP_DIR" init -q
git -C "$TAP_DIR" add Casks
git -C "$TAP_DIR" -c user.name=ci -c user.email=ci@localhost commit -q -m "verify cask"

brew tap "$TAP_NAME" "$TAP_DIR"
brew install --cask "$CASK"

/usr/libexec/PlistBuddy \
    -c "Print :CFBundleIdentifier" \
    -c "Print :CFBundleShortVersionString" \
    "$APP/Contents/Info.plist"

if xattr -p com.apple.quarantine "$APP" >/dev/null 2>&1; then
    echo "error: quarantine flag is still set on $APP" >&2
    exit 1
fi
codesign --verify --strict "$APP"

brew uninstall --cask "$CASK"
if [[ -e "$APP" ]]; then
    echo "error: $APP still exists after uninstall" >&2
    exit 1
fi

echo "Cask installed, verified and uninstalled cleanly."
