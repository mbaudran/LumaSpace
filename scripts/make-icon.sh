#!/bin/sh
# Redraw Resources/AppIcon.icns from scripts/make-icon.swift.
set -e
cd "$(dirname "$0")/.."
sdk26=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
if [ -d "$sdk26" ]; then export SDKROOT="$sdk26"; fi
tmp=$(mktemp -d)
swift scripts/make-icon.swift "$tmp/icon.png"
set=$tmp/AppIcon.iconset
mkdir "$set"
for s in 16 32 128 256 512; do
    sips -z $s $s "$tmp/icon.png" --out "$set/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$tmp/icon.png" --out "$set/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$set" -o Resources/AppIcon.icns
rm -rf "$tmp"
echo "wrote Resources/AppIcon.icns"
