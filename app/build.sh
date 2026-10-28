#!/bin/bash
# Bouwt "Superclean Dreammachine.app", signeert ad-hoc en installeert in /Applications.
# Geen Xcode-project nodig: enkel Command Line Tools (swiftc, sips, iconutil, codesign).
#
# Gebruik:   bash app/build.sh
set -euo pipefail

# --- Paden -------------------------------------------------------------------
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"      # .../Hans-Prisma-Shuffle/app
PROJECT_DIR="$(cd "$APP_DIR/.." && pwd)"                      # .../Hans-Prisma-Shuffle
# Bouwen buiten iCloud Drive: iCloud zet anders FinderInfo-attributen op de bestanden
# en dan weigert codesign ("resource fork, Finder information ... not allowed").
BUILD_DIR="${SCD_BUILD_DIR:-$HOME/Library/Caches/superclean-dreammachine/build}"
ASSETS_DIR="$APP_DIR/assets"

APP_NAME="Superclean Dreammachine"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
EXEC_NAME="SupercleanDreammachine"
ICON_URL="https://thumbnailer.mixcloud.com/unsafe/600x600/profile/2/4/4/2/4af2-6368-4410-9710-607e92f9e29c"

echo "==> Projectmap : $PROJECT_DIR"
echo "==> Bouwmap    : $BUILD_DIR"

rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$ASSETS_DIR"

# --- 1. Swift compileren (universeel: Apple Silicon + Intel, macOS 13+) -------
# macOS 13 is het laagste doel waarvoor de huidige Command Line Tools nog voor Intel linken.
bash "$APP_DIR/fetch-sparkle.sh"
SPARKLE_DIR="$(ls -d "$APP_DIR"/vendor/Sparkle-* | tail -1)"
MIN_MACOS="13.0"

echo "==> Swift compileren (arm64 + x86_64, macOS $MIN_MACOS+) ..."
for ARCH in arm64 x86_64; do
    swiftc -O -target "$ARCH-apple-macos$MIN_MACOS" \
        -F "$SPARKLE_DIR" -framework Sparkle \
        -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
        -o "$BUILD_DIR/$EXEC_NAME-$ARCH" \
        "$APP_DIR/main.swift"
done
lipo -create -output "$APP_BUNDLE/Contents/MacOS/$EXEC_NAME" \
    "$BUILD_DIR/$EXEC_NAME-arm64" "$BUILD_DIR/$EXEC_NAME-x86_64"
rm -f "$BUILD_DIR/$EXEC_NAME-arm64" "$BUILD_DIR/$EXEC_NAME-x86_64"

# Sparkle-framework insluiten (ditto behoudt de symlinks in het framework).
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
ditto "$SPARKLE_DIR/Sparkle.framework" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

# --- 2. Info.plist -----------------------------------------------------------
# Standaard gebruikt de app de ingebouwde HTML (geen toegang tot ~/Documents nodig).
# Dev-modus (SCD_DEV=1 bash app/build.sh): HTML live uit de projectmap laden, zodat
# wijzigingen meteen zichtbaar zijn met ⌘R. macOS vraagt dan wel om toegang tot de map.
if [ "${SCD_DEV:-0}" = "1" ]; then
    echo "==> Info.plist schrijven (dev-modus: HTML live uit $PROJECT_DIR) ..."
    LIVE_DIR="$PROJECT_DIR"
else
    echo "==> Info.plist schrijven ..."
    LIVE_DIR=""
fi
sed "s#__HPS_PROJECT_DIR__#$LIVE_DIR#g" \
    "$APP_DIR/Info.plist" > "$APP_BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

# HTML mee in de app (Contents/Resources): zo werkt de app ook zelfstandig (DMG),
# los van de projectmap. Op het dev-toestel krijgt de map-kopie voorrang (zie main.swift).
cp "$PROJECT_DIR/hans-prisma-shuffle.html" "$APP_BUNDLE/Contents/Resources/"

# --- 3. Icoon ----------------------------------------------------------------
# Profielfoto van Hans ophalen (eenmalig) en naar AppIcon.icns omzetten.
ICON_SRC="$ASSETS_DIR/hans-600.png"
if [ ! -s "$ICON_SRC" ]; then
    echo "==> Profielfoto downloaden ..."
    if ! curl -fsSL --max-time 30 -o "$ICON_SRC" "$ICON_URL"; then
        echo "   ! download mislukt — app wordt zonder eigen icoon gebouwd."
        rm -f "$ICON_SRC"
    fi
fi

if [ -s "$ICON_SRC" ] && sips -g pixelWidth "$ICON_SRC" >/dev/null 2>&1; then
    echo "==> Icoon maken ..."
    # 3D "knop"-icoon renderen (afgeronde vorm, glans, schaduw) uit de foto.
    ICON_BASE="$ICON_SRC"
    if swiftc -O -o "$BUILD_DIR/makeicon" "$APP_DIR/makeicon.swift" 2>/dev/null \
        && "$BUILD_DIR/makeicon" "$ICON_SRC" "$ASSETS_DIR/appicon-1024.png"; then
        ICON_BASE="$ASSETS_DIR/appicon-1024.png"
    else
        echo "   ! 3D-icoon mislukt — val terug op ruwe foto."
    fi
    ICONSET="$BUILD_DIR/AppIcon.iconset"
    mkdir -p "$ICONSET"
    make_png() { sips -s format png -z "$1" "$1" "$ICON_BASE" --out "$ICONSET/$2" >/dev/null; }
    make_png 16   "icon_16x16.png"
    make_png 32   "icon_16x16@2x.png"
    make_png 32   "icon_32x32.png"
    make_png 64   "icon_32x32@2x.png"
    make_png 128  "icon_128x128.png"
    make_png 256  "icon_128x128@2x.png"
    make_png 256  "icon_256x256.png"
    make_png 512  "icon_256x256@2x.png"
    make_png 512  "icon_512x512.png"
    make_png 1024 "icon_512x512@2x.png"
    iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
else
    echo "   ! geen bruikbare bronafbeelding — zonder eigen icoon."
fi

# --- 4. Ad-hoc signeren ------------------------------------------------------
echo "==> Ad-hoc signeren ..."
# Uitgebreide attributen (quarantine/FinderInfo van de download) weghalen; codesign
# weigert anders met "resource fork ... not allowed".
xattr -cr "$APP_BUNDLE"
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --verbose "$APP_BUNDLE" || true

# --- 5. Installeren in /Applications (vorige versie naar Archived/) ----------
DEST="/Applications/$APP_NAME.app"
if [ -d "$DEST" ]; then
    echo "==> Vorige versie archiveren ..."
    mkdir -p "$PROJECT_DIR/Archived"
    TS="$(date +%Y%m%d-%H%M%S)"
    mv "$DEST" "$PROJECT_DIR/Archived/$APP_NAME-$TS.app"
fi
echo "==> Installeren in /Applications ..."
cp -R "$APP_BUNDLE" "/Applications/"

echo ""
echo "✅ Klaar: $DEST"
echo "   Start met:  open \"$DEST\""
