#!/bin/bash
# Builds PANO.app (release) into ./build.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG=${1:-release}
# UNIVERSAL=1 builds for both Apple Silicon and Intel (for sharing); default is this Mac's architecture only.
ARCH_FLAGS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then ARCH_FLAGS=(--arch arm64 --arch x86_64); fi
swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN=$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/PANO

APP=build/PANO.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PANO"
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"
cp Resources/local-stations.json "$APP/Contents/Resources/"
cp Resources/city-links.json "$APP/Contents/Resources/"
cp Resources/districts.json "$APP/Contents/Resources/"

# Icon
ICONSET=$(mktemp -d)/AppIcon.iconset; mkdir -p "$ICONSET"
swift scripts/make_icon.swift "$ICONSET/base.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ICONSET/base.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$ICONSET/base.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
rm "$ICONSET/base.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>PANO</string>
  <key>CFBundleDisplayName</key><string>PANO</string>
  <key>CFBundleIdentifier</key><string>com.ruzname.app</string>
  <key>CFBundleExecutable</key><string>PANO</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Bugün ekranında günün takvim etkinliklerini göstermek için.</string>
  <key>NSCalendarsUsageDescription</key><string>Bugün ekranında günün takvim etkinliklerini göstermek için.</string>
  <key>NSLocationUsageDescription</key><string>Yerel sekmesinde bulunduğun il ve ilçenin haberlerini göstermek için.</string>
  <key>NSLocationWhenInUseUsageDescription</key><string>Yerel sekmesinde bulunduğun il ve ilçenin haberlerini göstermek için.</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
  <key>LSApplicationCategoryType</key><string>public.app-category.news</string>
</dict></plist>
PL
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"
