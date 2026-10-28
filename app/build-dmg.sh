#!/bin/bash
# Bouwt de app én verpakt ze in een deelbare .dmg (sleep-naar-Applications-installer).
# De app is zelfstandig: de HTML zit mee in het app-pakket, dus de DMG werkt op elke Mac.
#
# Twee modi (automatisch gekozen):
#   • Ad-hoc (standaard)  — geen Apple-account nodig; fans krijgen 1x een Gatekeeper-waarschuwing.
#   • Developer ID + notarisatie — als er een "Developer ID Application"-certificaat is én
#     notarytool-inloggegevens, dan wordt de app ondertekend, genotariseerd en gestapled,
#     zodat de waarschuwing verdwijnt. Instellen: zie onderaan dit bestand.
#
# Gebruik:  bash app/build-dmg.sh
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$APP_DIR/.." && pwd)"
APP_NAME="Superclean Dreammachine"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_DIR/Info.plist")"

# --- 1. App bouwen (build.sh bouwt + installeert; we gebruiken de build-kopie) --
bash "$APP_DIR/build.sh"
BUILT="${SCD_BUILD_DIR:-$HOME/Library/Caches/superclean-dreammachine/build}/$APP_NAME.app"
[ -d "$BUILT" ] || { echo "App niet gevonden: $BUILT"; exit 1; }

# Ondertekenen/verpakken in een tijdelijke map buiten iCloud Drive: iCloud zet anders
# FinderInfo-attributen terug en dan weigert codesign ("detritus not allowed").
WORK="$(mktemp -d "${TMPDIR:-/tmp}/scd-dmg.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
ditto --norsrc --noextattr "$BUILT" "$WORK/$APP_NAME.app"
APP_SRC="$WORK/$APP_NAME.app"

# Distributiekopie: geen lokaal projectpad meegeven; de app gebruikt dan de ingebouwde HTML.
/usr/libexec/PlistBuddy -c "Set :HPSProjectDir ''" "$APP_SRC/Contents/Info.plist"

# --- 2. Developer ID + notarisatie? ------------------------------------------
# SIGN_ID: certificaatnaam. Standaard het meest recent uitgegeven Developer ID Application-
# certificaat, zodat na een naamswijziging (Pixerang BVBA → Bamati BV) automatisch het nieuwe
# wordt gebruikt. Overschrijven kan met SCD_SIGN_ID="Developer ID Application: …".
# NOTARY_PROFILE: naam van het notarytool-keychainprofiel (zie onderaan).
newest_devid() {
    security find-identity -v -p codesigning 2>/dev/null \
        | awk -F'"' '/Developer ID Application/{print $2}' | sort -u \
        | while IFS= read -r name; do
            start="$(security find-certificate -c "$name" -p 2>/dev/null \
                | openssl x509 -noout -startdate 2>/dev/null | cut -d= -f2)"
            [ -n "$start" ] && echo "$(date -j -f "%b %e %T %Y %Z" "$start" +%s 2>/dev/null || echo 0)|$name"
          done | sort -t'|' -k1,1n | tail -1 | cut -d'|' -f2-
}
SIGN_ID="${SCD_SIGN_ID:-$(newest_devid)}"
NOTARY_PROFILE="${SCD_NOTARY_PROFILE:-scd-notary}"

DO_NOTARIZE=0
if [ -n "$SIGN_ID" ] && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    DO_NOTARIZE=1
fi

if [ "$DO_NOTARIZE" = "1" ]; then
    echo "==> Ondertekenen met Developer ID: $SIGN_ID"
    # Hardened runtime + veilige tijdstempel zijn vereist voor notarisatie.
    bash "$APP_DIR/sign-devid.sh" "$APP_SRC" "$SIGN_ID"

    echo "==> Notariseren (kan 1–3 min duren) ..."
    ZIP="$WORK/scd-notarize.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP_SRC" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    rm -f "$ZIP"

    echo "==> Ticket aanhechten (stapler) ..."
    xcrun stapler staple "$APP_SRC"
else
    echo "==> Geen Developer ID + notarytool-profiel gevonden → ad-hoc DMG."
    echo "    (Fans krijgen 1x de Gatekeeper-waarschuwing. Instellen: zie onderaan build-dmg.sh.)"
fi

# --- 3. Staging: .app + snelkoppeling naar /Applications ----------------------
echo "==> DMG samenstellen ..."
DMG_DIR="$WORK/dmg"
rm -rf "$DMG_DIR"; mkdir -p "$DMG_DIR"
cp -R "$APP_SRC" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

# --- 4. DMG maken (vorige versie → Archived/, niet weggooien) -----------------
OUT="$PROJECT_DIR/Superclean-Dreammachine-$VERSION.dmg"
if [ -f "$OUT" ]; then
    mkdir -p "$PROJECT_DIR/Archived"
    mv "$OUT" "$PROJECT_DIR/Archived/Superclean-Dreammachine-$VERSION-$(date +%Y%m%d-%H%M%S).dmg"
fi
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_DIR" -ov -format UDZO "$OUT" >/dev/null

# De DMG zelf ook ondertekenen, notariseren en stapelen.
if [ "$DO_NOTARIZE" = "1" ]; then
    echo "==> DMG ondertekenen + notariseren ..."
    codesign --force --timestamp --sign "$SIGN_ID" "$OUT"
    xcrun notarytool submit "$OUT" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$OUT"
fi

echo ""
echo "✅ DMG klaar: $OUT"
[ "$DO_NOTARIZE" = "1" ] && echo "   Ondertekend + genotariseerd — opent zonder waarschuwing." \
                         || echo "   Ad-hoc — deelbaar, maar met eenmalige Gatekeeper-stap."

# -----------------------------------------------------------------------------
# EENMALIGE SETUP voor notarisatie (nadat Apple je inschrijving goedkeurde):
#
#  1. Developer ID Application-certificaat aanmaken en installeren:
#     - Zonder Xcode: Sleutelhangertoegang → Certificaatassistent → "Vraag een certificaat
#       aan bij een certificaatinstantie" → bewaar een CSR-bestand.
#     - developer.apple.com/account → Certificates → + → "Developer ID Application" →
#       upload de CSR → download het .cer → dubbelklik om te installeren.
#  2. Team ID opzoeken: developer.apple.com/account → Membership details.
#  3. App-specifiek wachtwoord maken: appleid.apple.com → Inloggen en beveiliging →
#     App-specifieke wachtwoorden.
#  4. notarytool-inloggegevens bewaren in de keychain (eenmalig):
#       xcrun notarytool store-credentials "scd-notary" \
#         --apple-id "jouw-apple-id@voorbeeld.be" \
#         --team-id "JOUWTEAMID" \
#         --password "xxxx-xxxx-xxxx-xxxx"
#
#  Daarna volstaat weer:  bash app/build-dmg.sh   (notariseert nu automatisch).
# -----------------------------------------------------------------------------
