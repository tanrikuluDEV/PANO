#!/bin/bash
# Builds a universal PANO.app and wraps it in a shareable DMG (app + Applications shortcut + how-to-open note).
# Usage: ./scripts/make_dmg.sh [output-dir]   (default: ./build)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:-build}
UNIVERSAL=1 ./scripts/build_app.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/PANO.app/Contents/Info.plist)
STAGE=$(mktemp -d)/PANO
mkdir -p "$STAGE"
cp -R build/PANO.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Önce Beni Oku.txt" <<'TXT'
PANO — kurulum

1. PANO'yu yandaki Applications (Uygulamalar) klasörüne sürükle.
2. Uygulamalar'dan PANO'yu aç.

İlk açılışta "PANO açılamıyor, geliştirici doğrulanamadı" uyarısı çıkarsa
(uygulama App Store dışından paylaşıldığı için Apple imzası yok):

  • "Bitti"ye bas, sonra Sistem Ayarları › Gizlilik ve Güvenlik'e git.
  • Aşağıda "PANO engellendi" satırındaki "Yine de Aç" düğmesine bas,
    parolanı gir ve tekrar "Aç"a bas.

Bu yalnızca ilk açılışta gerekir.

Alternatif (Terminal'i biliyorsan):
  xattr -dr com.apple.quarantine /Applications/PANO.app

Gereksinim: macOS 14 (Sonoma) veya üstü. Apple Silicon ve Intel Mac'lerde çalışır.
Notların, görevlerin ve arşivin yalnızca senin Mac'inde saklanır.
TXT

mkdir -p "$OUT"
DMG="$OUT/PANO-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "PANO" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$DMG" >/dev/null
rm -rf "$(dirname "$STAGE")"
echo "Built $DMG"
