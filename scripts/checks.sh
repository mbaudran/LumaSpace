#!/bin/sh
# Run LumaCore checks with the macOS 26 SDK (the 27 SDK needs Xcode's macro plugins).
cd "$(dirname "$0")/.." || exit 1
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
log=$(mktemp)
if ! swift build --product LumaChecks >"$log" 2>&1; then
    grep -E "error:" "$log" | sed 's/.*Sources/Sources/' | sort -u | head -20
    echo "BUILD FAILED"
    exit 1
fi
exec .build/debug/LumaChecks
