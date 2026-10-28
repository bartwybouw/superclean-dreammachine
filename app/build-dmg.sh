#!/bin/bash
# Bouwt de app én verpakt ze in een deelbare .dmg (sleep-naar-Applications-installer).
# De app is zelfstandig: de HTML zit mee in het app-pakket, dus de DMG werkt op elke Mac.
#
# Gebruik:  bash app/build-dmg.sh
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$APP_DIR/.." && pwd)"
APP_NAME="Superclean Dreammachine"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_DIR/Info.plist")"

# --- 1. App bouwen (build.sh bouwt + installeert; we gebruiken de build-kopie) --
bash "$APP_DIR/build.sh"
APP_SRC="$APP_DIR/build/$APP_NAME.app"
[ -d "$APP_SRC" ] || { echo "App niet gevonden: $APP_SRC"; exit 1; }

# --- 2. Staging: .app + snelkoppeling naar /Applications ----------------------
echo "==> DMG samenstellen ..."
DMG_DIR="$APP_DIR/build/dmg"
rm -rf "$DMG_DIR"; mkdir -p "$DMG_DIR"
cp -R "$APP_SRC" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

# --- 3. DMG maken (vorige versie → Archived/, niet weggooien) -----------------
OUT="$PROJECT_DIR/Superclean-Dreammachine-$VERSION.dmg"
if [ -f "$OUT" ]; then
    mkdir -p "$PROJECT_DIR/Archived"
    mv "$OUT" "$PROJECT_DIR/Archived/Superclean-Dreammachine-$VERSION-$(date +%Y%m%d-%H%M%S).dmg"
fi
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_DIR" -ov -format UDZO "$OUT" >/dev/null

echo ""
echo "✅ DMG klaar: $OUT"
echo "   Delen kan direct, of als GitHub Release-bijlage."
