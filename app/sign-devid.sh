#!/bin/bash
# Ondertekent de app met Developer ID (hardened runtime + tijdstempel), inclusief het
# ingesloten Sparkle-framework. Sparkle's hulpprogramma's worden van binnen naar buiten
# ondertekend, zoals de Sparkle-documentatie voorschrijft.
#
# Gebruik:  bash app/sign-devid.sh "<pad naar .app>" "<Developer ID-identiteit>"
# Let op: niet in een iCloud Drive-map uitvoeren (iCloud zet FinderInfo terug).
set -euo pipefail

APP="$1"
ID="$2"
FW="$APP/Contents/Frameworks/Sparkle.framework"
SIGN=(codesign --force --options runtime --timestamp --sign "$ID")

xattr -cr "$APP"
if [ -d "$FW" ]; then
    "${SIGN[@]}" "$FW/Versions/B/XPCServices/Installer.xpc"
    "${SIGN[@]}" --preserve-metadata=entitlements "$FW/Versions/B/XPCServices/Downloader.xpc"
    "${SIGN[@]}" "$FW/Versions/B/Autoupdate"
    "${SIGN[@]}" "$FW/Versions/B/Updater.app"
    "${SIGN[@]}" "$FW"
fi
"${SIGN[@]}" "$APP"
codesign --verify --deep --strict --verbose=1 "$APP"
