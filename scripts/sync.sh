#!/bin/zsh
# Copies the two working projects into this repo (mac/, ios/), commits and pushes.
# The projects keep living where they are; this repo is only their published copy.
#   scripts/sync.sh "commit message"
set -e
cd "$(dirname "$0")/.."
MAC=${PANO_MAC:-$HOME/Desktop/ajanda/PANO}
IOS=${PANO_IOS:-$HOME/Desktop/PANO-iOS}
EXCLUDES=(--exclude .git --exclude .build --exclude build --exclude .swiftpm --exclude xcuserdata --exclude '*.xcuserstate'
          --exclude .DS_Store --exclude __pycache__ --exclude devices.local)
rsync -a --delete $EXCLUDES "$MAC/" mac/
rsync -a --delete $EXCLUDES "$IOS/" ios/
git add -A
if git diff --cached --quiet; then echo "nothing to publish"; exit 0; fi
git commit -q -m "${1:-Update}"
git push -q
git log -1 --oneline
