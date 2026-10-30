#!/bin/sh
# Build build/LumaSpace.app with SwiftPM (no Xcode). --install copies it to /Applications.
# --no-sdk leaves the VITURE SDK out (release builds: the app's "Set Up VITURE SDK…" adds it).
set -e
cd "$(dirname "$0")/.."
install=no
nosdk=no
for arg in "$@"; do
    case "$arg" in
        --install) install=yes ;;
        --no-sdk|--sim) nosdk=yes ;;
        *) echo "unknown option $arg"; exit 1 ;;
    esac
done
# Newer Command Line Tools ship a macOS 27 SDK whose macros need Xcode, so prefer 26 when it's
# installed; otherwise use the default SDK.
sdk26=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
if [ -d "$sdk26" ]; then export SDKROOT="$sdk26"; fi

sdk=vendor/viture-sdk/aarch64/libglasses.dylib
if [ "$nosdk" = no ] && [ ! -f "$sdk" ]; then
    # Unpack the SDK zip if it's sitting in the repo or in Downloads.
    zip=$(ls -t ./VITURE*SDK*MacOS*.zip ~/Downloads/VITURE*SDK*MacOS*.zip 2>/dev/null | head -1 || true)
    if [ -n "$zip" ]; then
        echo "unpacking $zip into vendor/viture-sdk/"
        mkdir -p vendor/viture-sdk
        unzip -oq "$zip" -d vendor/viture-sdk
    fi
fi
if [ "$nosdk" = no ] && [ ! -f "$sdk" ]; then
    # Or an already-unzipped SDK somewhere in the repo or Downloads (e.g. a nested folder).
    found=$(find . ~/Downloads -path ./.build -prune -o -path ./build -prune -o \
            -name libglasses.dylib -path '*aarch64*' -print 2>/dev/null | grep -v '\.app/' | head -1 || true)
    if [ -n "$found" ]; then
        echo "using the SDK found at $(dirname "$found")"
        mkdir -p vendor/viture-sdk/aarch64
        cp "$(dirname "$found")"/*.dylib vendor/viture-sdk/aarch64/
    fi
fi
if [ "$nosdk" = no ] && [ ! -f "$sdk" ]; then
    echo "error: VITURE SDK not found — without it LumaSpace can't talk to the glasses."
    echo "  Download 'VITURE XR Glasses SDK for macOS' from https://www.viture.com/developer"
    echo "  and put the zip in this folder or ~/Downloads, then rerun this script."
    echo "  (Or pass --no-sdk and use \"Set Up VITURE SDK…\" in the app's menu.)"
    exit 1
fi
swift build -c release --product LumaSpace

app=build/LumaSpace.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks"
cp .build/release/LumaSpace "$app/Contents/MacOS/LumaSpace"
cp Resources/Info.plist "$app/Contents/Info.plist"
mkdir -p "$app/Contents/Resources"
cp -R Resources/Theater "$app/Contents/Resources/Theater"
if [ "$nosdk" = no ]; then
    # libcarina_vio ships next to libglasses (the SDK's own demo bundles both).
    for lib in vendor/viture-sdk/aarch64/*.dylib; do
        cp "$lib" "$app/Contents/Frameworks/"
        # The SDK zip comes from a browser download; macOS refuses to load a quarantined dylib.
        xattr -d com.apple.quarantine "$app/Contents/Frameworks/$(basename "$lib")" 2>/dev/null || true
    done
else
    echo "note: built without the VITURE SDK — use \"Set Up VITURE SDK…\" in the app's menu"
fi
# iCloud-synced folders (e.g. Documents) tag the bundle with attributes codesign refuses and
# xattr can't remove, so sign a clean copy outside and copy it back.
signdir=$(mktemp -d)
ditto --noextattr "$app" "$signdir/$(basename "$app")"
xattr -cr "$signdir/$(basename "$app")"
codesign --force --deep -s - "$signdir/$(basename "$app")"
rm -rf "$app"
ditto "$signdir/$(basename "$app")" "$app"
rm -rf "$signdir"
codesign --verify --deep "$app"
echo "built $app"

if [ "$install" = yes ]; then
    rm -rf /Applications/LumaSpace.app
    cp -R "$app" /Applications/
    echo "installed /Applications/LumaSpace.app"
fi
