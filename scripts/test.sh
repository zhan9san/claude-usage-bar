#!/usr/bin/env bash
# Runs the unit tests. With only the Command Line Tools installed (no Xcode),
# SwiftPM does not find the swift-testing framework on its own, so point the
# compiler and the dynamic linker at it.
set -euo pipefail

cd "$(dirname "$0")/.."

DEV="$(xcode-select -p)"
if [[ "$DEV" == *CommandLineTools* ]]; then
    FW="$DEV/Library/Developer/Frameworks"
    LIB="$DEV/Library/Developer/usr/lib"
    exec swift test \
        -Xswiftc -F -Xswiftc "$FW" \
        -Xlinker -F -Xlinker "$FW" \
        -Xlinker -rpath -Xlinker "$FW" \
        -Xlinker -rpath -Xlinker "$LIB" \
        "$@"
fi

exec swift test "$@"
