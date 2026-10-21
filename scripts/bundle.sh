#!/bin/sh
# Build build/LumaSpace.app with SwiftPM (no Xcode). --install copies it to /Applications.
set -e
cd "$(dirname "$0")/.."
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
swift build -c release --product LumaSpace

app=build/LumaSpace.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks"
cp .build/release/LumaSpace "$app/Contents/MacOS/LumaSpace"
cp Resources/Info.plist "$app/Contents/Info.plist"
if [ -f vendor/viture-sdk/aarch64/libglasses.dylib ]; then
    cp vendor/viture-sdk/aarch64/libglasses.dylib "$app/Contents/Frameworks/"
    # The SDK zip comes from a browser download; macOS refuses to load a quarantined dylib.
    xattr -d com.apple.quarantine "$app/Contents/Frameworks/libglasses.dylib" 2>/dev/null || true
else
    echo "note: vendor/viture-sdk/aarch64/libglasses.dylib not found — app will run in simulator mode"
fi
codesign --force --deep -s - "$app"
echo "built $app"

if [ "$1" = "--install" ]; then
    rm -rf /Applications/LumaSpace.app
    cp -R "$app" /Applications/
    echo "installed /Applications/LumaSpace.app"
fi
