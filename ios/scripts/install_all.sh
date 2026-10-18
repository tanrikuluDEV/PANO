#!/bin/zsh
# Builds PANO once (Release, signed) with a new build number and installs that same build on every listed iPhone
# at the same time. A locked phone is retried every 10 s for up to 5 minutes. Ends by printing each phone's build number.
cd "$(dirname "$0")/.."
# Phone UDIDs: PANO_DEVICES, else scripts/devices.local (one per line, not in git; `xcrun devicectl list devices`).
DEVICES=(${=PANO_DEVICES:-$(grep -v '^#' scripts/devices.local 2>/dev/null)})
[ ${#DEVICES} = 0 ] && { echo "no devices: put their UDIDs in scripts/devices.local"; exit 1; }
BUILD=$(date +%y%m%d%H%M)
APP=build/dev/Build/Products/Release-iphoneos/PANO.app

xcodebuild -project PANO.xcodeproj -scheme PANO -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build/dev DEVELOPMENT_TEAM=DR8AY52TR6 CODE_SIGN_STYLE=Automatic CURRENT_PROJECT_VERSION=$BUILD \
  -allowProvisioningUpdates build 2>&1 | grep -E "error:|BUILD" || exit 1

install_one() {
  for i in $(seq 1 30); do
    out=$(xcrun devicectl device install app --device $1 $APP 2>&1)
    if echo "$out" | grep -q "App installed"; then echo "$1: installed (try $i)"; return 0; fi
    [ $i = 1 ] && echo "$1: waiting — unlock the phone ($(echo "$out" | grep -oE 'kAMD[A-Za-z]+|error [0-9]+' | head -1))"
    sleep 10
  done
  echo "$1: FAILED"; return 1
}
for d in $DEVICES; do install_one $d & done
wait

echo "build $BUILD"
for d in $DEVICES; do
  v=""
  for i in 1 2 3; do   # the query sometimes comes back empty while the phone reopens its connection
    v=$(xcrun devicectl device info apps --device $d --bundle-id com.ruzname.pano 2>/dev/null | grep com.ruzname.pano | awk '{print $NF}')
    [ -n "$v" ] && break; sleep 3
  done
  echo "$d: ${v:-?}"
done
