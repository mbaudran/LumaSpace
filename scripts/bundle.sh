#!/bin/sh
# Build build/LumaSpace.app with SwiftPM (no Xcode). --install copies it to /Applications.
# --sim builds without the VITURE SDK (simulator only).
set -e
cd "$(dirname "$0")/.."
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk

sdk=vendor/viture-sdk/aarch64/libglasses.dylib
if [ ! -f "$sdk" ]; then
    # Unpack the SDK zip if it's sitting in the repo or in Downloads.
    zip=$(ls -t ./VITURE*SDK*MacOS*.zip ~/Downloads/VITURE*SDK*MacOS*.zip 2>/dev/null | head -1 || true)
    if [ -n "$zip" ]; then
        echo "unpacking $zip into vendor/viture-sdk/"
        mkdir -p vendor/viture-sdk
        unzip -oq "$zip" -d vendor/viture-sdk
    fi
fi
if [ ! -f "$sdk" ]; then
    # Or an already-unzipped SDK somewhere in the repo or Downloads (e.g. a nested folder).
    found=$(find . ~/Downloads -path ./.build -prune -o -path ./build -prune -o \
            -name libglasses.dylib -path '*aarch64*' -print 2>/dev/null | grep -v '\.app/' | head -1 || true)
    if [ -n "$found" ]; then
        echo "using the SDK found at $(dirname "$found")"
        mkdir -p vendor/viture-sdk/aarch64
        cp "$(dirname "$found")"/*.dylib vendor/viture-sdk/aarch64/
    fi
fi
if [ ! -f "$sdk" ] && [ "$1" != "--sim" ] && [ "$2" != "--sim" ]; then
    echo "error: VITURE SDK not found — without it LumaSpace can't talk to the glasses."
    echo "  Download 'VITURE XR Glasses SDK for macOS' from https://www.viture.com/developer"
    echo "  and put the zip in this folder or ~/Downloads, then rerun this script."
    echo "  (Or pass --sim to build the simulator only.)"
    exit 1
fi
swift build -c release --product LumaSpace

app=build/LumaSpace.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks"
cp .build/release/LumaSpace "$app/Contents/MacOS/LumaSpace"
cp Resources/Info.plist "$app/Contents/Info.plist"
if [ -f "$sdk" ]; then
    # libcarina_vio ships next to libglasses (the SDK's own demo bundles both).
    for lib in vendor/viture-sdk/aarch64/*.dylib; do
        cp "$lib" "$app/Contents/Frameworks/"
        # The SDK zip comes from a browser download; macOS refuses to load a quarantined dylib.
        xattr -d com.apple.quarantine "$app/Contents/Frameworks/$(basename "$lib")" 2>/dev/null || true
    done
else
    echo "note: vendor/viture-sdk/aarch64/libglasses.dylib not found — app will run in simulator mode"
fi
codesign --force --deep -s - "$app"
echo "built $app"

if [ "$1" = "--install" ] || [ "$2" = "--install" ]; then
    rm -rf /Applications/LumaSpace.app
    cp -R "$app" /Applications/
    echo "installed /Applications/LumaSpace.app"
fi
