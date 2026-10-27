#!/bin/bash
# Bouwt "Superclean Dreammachine.app", signeert ad-hoc en installeert in /Applications.
# Geen Xcode-project nodig: enkel Command Line Tools (swiftc, sips, iconutil, codesign).
#
# Gebruik:   bash app/build.sh
set -euo pipefail

# --- Paden -------------------------------------------------------------------
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"      # .../Hans-Prisma-Shuffle/app
PROJECT_DIR="$(cd "$APP_DIR/.." && pwd)"                      # .../Hans-Prisma-Shuffle
BUILD_DIR="$APP_DIR/build"
ASSETS_DIR="$APP_DIR/assets"

APP_NAME="Superclean Dreammachine"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
EXEC_NAME="SupercleanDreammachine"
ICON_URL="https://thumbnailer.mixcloud.com/unsafe/600x600/profile/2/4/4/2/4af2-6368-4410-9710-607e92f9e29c"

echo "==> Projectmap : $PROJECT_DIR"
echo "==> Bouwmap    : $BUILD_DIR"

rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$ASSETS_DIR"

# --- 1. Swift compileren -----------------------------------------------------
echo "==> Swift compileren ..."
swiftc -O \
    -o "$APP_BUNDLE/Contents/MacOS/$EXEC_NAME" \
    "$APP_DIR/main.swift"

# --- 2. Info.plist (projectpad invullen) -------------------------------------
echo "==> Info.plist schrijven ..."
sed "s#__HPS_PROJECT_DIR__#$PROJECT_DIR#g" \
    "$APP_DIR/Info.plist" > "$APP_BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

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
