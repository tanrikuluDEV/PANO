#!/bin/zsh
# Regenerates PANO/Assets.xcassets/AppIcon.appiconset/icon-1024.png (opaque, full bleed).
cd "$(dirname "$0")/.."
OUT=PANO/Assets.xcassets/AppIcon.appiconset/icon-1024.png
TMP=$(mktemp -d)
swift scripts/make_icon_ios.swift $TMP/icon.png
sips -s format jpeg -s formatOptions 100 $TMP/icon.png --out $TMP/icon.jpg >/dev/null
sips -s format png $TMP/icon.jpg --out $OUT >/dev/null
rm -rf $TMP
