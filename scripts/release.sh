#!/bin/sh
# Build a downloadable build/LumaSpace-<version>.zip. It never contains the VITURE SDK, which
# isn't ours to redistribute; users add it with "Set Up VITURE SDK…" in the app's menu.
set -e
cd "$(dirname "$0")/.."
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
scripts/bundle.sh --no-sdk
if [ -n "$(find build/LumaSpace.app -name '*.dylib')" ]; then
    echo "error: the release app contains a dylib; the VITURE SDK must not be shipped"
    exit 1
fi
zip=build/LumaSpace-$version.zip
rm -f "$zip"
ditto -c -k --norsrc --keepParent build/LumaSpace.app "$zip"
echo "built $zip"
