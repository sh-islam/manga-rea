#!/usr/bin/env bash
# Compile the iOS app (App) for the phone without installing. Mirrors what ship-all.sh does.
set -u
ROOT="/mnt/e/Python Projects/reverse-engineering-projects"
PROJ="$ROOT/manga-rea"
DEST="$HOME/apps/manga-rea"
mkdir -p "$DEST"
rsync -a --delete --exclude .build --exclude xtool --exclude .swiftpm --exclude .shipped --exclude re --exclude .git --exclude '*.apk' "$PROJ/" "$DEST/"
mkdir -p "$DEST/App/Sources/Kumo/Shared" && cp "$ROOT/common/ios-shared/"*.swift "$DEST/App/Sources/Kumo/Shared/"
cd "$DEST/App" && xtool dev build 2>&1 | grep -vE "^\[|^$|Compiling|Emitting|LSP|skipLSP|restart your editor|Swift 6 language mode|Failed frontend command|swift-frontend -frontend|^\s*\||^\s*[0-9]+ \|"
echo "build exit ${PIPESTATUS[0]}"
