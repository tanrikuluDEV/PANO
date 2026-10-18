#!/bin/zsh
# Usage: scripts/shot.sh <Tab name, e.g. Bugün> <out.png> [wait seconds]
# Installs the last simulator build on the iPhone 17 simulator, opens that tab and saves a screenshot.
SIM=${SIM:-A4642363-BC2C-41C9-8074-65869104A037}
APP=build/dd/Build/Products/Debug-iphonesimulator/PANO.app
xcrun simctl boot $SIM 2>/dev/null
xcrun simctl install $SIM $APP
xcrun simctl terminate $SIM com.ruzname.pano 2>/dev/null
xcrun simctl launch $SIM com.ruzname.pano -startTab "$1" -screenshots YES -radioVolume 0 ${=EXTRA} >/dev/null
sleep ${3:-8}
xcrun simctl io $SIM screenshot "$2" >/dev/null 2>&1
sips -Z 1000 "$2" >/dev/null
