#!/usr/bin/env bash
# Writes the Homebrew cask for Claude Usage Bar.
# Usage: scripts/write-cask.sh <version> <sha256> <output-file> [url]
#   url  defaults to the GitHub release asset for <version>; CI passes a
#        file:// URL to test the cask against a freshly built zip.
set -euo pipefail

if [[ $# -lt 3 ]]; then
    echo "usage: $0 <version> <sha256> <output-file> [url]" >&2
    exit 64
fi

VERSION="$1"
SHA256="$2"
OUTPUT="$3"
URL="${4:-}"
if [[ -z "$URL" ]]; then
    # Single quotes keep the Ruby interpolation for Homebrew to expand.
    URL='https://github.com/zhan9san/claude-usage-bar/releases/download/v#{version}/ClaudeUsageBar-v#{version}.zip'
fi

mkdir -p "$(dirname "$OUTPUT")"
cat > "$OUTPUT" <<EOF
cask "claude-usage-bar" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "${URL}"
  name "Claude Usage Bar"
  desc "Menu bar app that shows Claude subscription usage"
  homepage "https://github.com/zhan9san/claude-usage-bar"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Claude Usage Bar.app"

  # The app is ad-hoc signed and not notarized, so Gatekeeper would refuse
  # to open it while the download quarantine flag is set.
  postflight_steps do
    run "/usr/bin/xattr",
        args:           ["-dr", "com.apple.quarantine", "{{appdir}}/Claude Usage Bar.app"],
        writable_paths: ["Claude Usage Bar.app"],
        writable_base:  :appdir
  end

  uninstall quit: "io.github.zhan9san.claude-usage-bar"

  zap trash: "~/Library/Preferences/io.github.zhan9san.claude-usage-bar.plist"
end
EOF

echo "Wrote $OUTPUT"
