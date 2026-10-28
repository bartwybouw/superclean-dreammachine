#!/bin/bash
# Brengt een nieuwe versie uit naar alle gebruikers:
#   1. bouwt, ondertekent en notariseert de DMG (build-dmg.sh)
#   2. maakt de GitHub-release aan met de DMG als bijlage
#   3. ondertekent de DMG met de Sparkle-sleutel en zet appcast.xml bij
#   4. pusht appcast.xml → geïnstalleerde apps zien de update binnen een dag
#      (of meteen via "Zoek naar updates…").
#
# Vooraf: verhoog CFBundleShortVersionString (bv. 1.5) én CFBundleVersion (bv. 6)
#         in app/Info.plist.
# Gebruik:  bash app/publish.sh "Eerste punt van wat er nieuw is" "Tweede punt" ...
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$APP_DIR/.." && pwd)"
REPO="bartwybouw/superclean-dreammachine"
SPARKLE_ACCOUNT="superclean-dreammachine"
PL="$APP_DIR/Info.plist"

[ "$#" -ge 1 ] || { echo "Geef minstens één regel release-notes mee."; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PL")"
BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PL")"
MINOS="$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$PL")"
TAG="v$VERSION"
DMG_NAME="Superclean-Dreammachine-$VERSION.dmg"
DMG="$PROJECT_DIR/$DMG_NAME"

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "Release $TAG bestaat al. Verhoog eerst de versie in app/Info.plist."; exit 1
fi
echo "==> Uitbrengen: versie $VERSION (build $BUILD)"

# --- 0. Versiebump committen, zodat de release-tag naar de juiste code wijst ---
cd "$PROJECT_DIR"
if ! git diff --quiet -- app/Info.plist; then
    git add app/Info.plist
    git commit -q -m "Versie $VERSION (build $BUILD)"
fi
git push -q origin main

# --- 1. Bouwen + notariseren -----------------------------------------------------
bash "$APP_DIR/build-dmg.sh"
if ! spctl -a -t open --context context:primary-signature "$DMG" >/dev/null 2>&1; then
    echo "De DMG is niet genotariseerd — afgebroken (gebruikers zouden een waarschuwing krijgen)."
    exit 1
fi

# --- 2. Release-notes opbouwen -------------------------------------------------
NOTES_MD=""
NOTES_HTML="<ul>"
for line in "$@"; do
    NOTES_MD+="- $line"$'\n'
    esc="${line//&/&amp;}"; esc="${esc//</&lt;}"; esc="${esc//>/&gt;}"
    NOTES_HTML+="<li>$esc</li>"
done
NOTES_HTML+="</ul>"

# --- 3. GitHub-release met de DMG ------------------------------------------------
gh release create "$TAG" "$DMG#Superclean Dreammachine $VERSION (macOS)" \
    --repo "$REPO" --title "Superclean Dreammachine $VERSION" --latest \
    --notes "$(printf '### Nieuw in %s\n%s\n### Installeren\nHeb je de app al? Dan krijg je deze versie automatisch aangeboden (of via **Zoek naar updates…** in het app-menu).\n\nNieuw? Download de DMG hieronder, sleep **Superclean Dreammachine** naar **Programma'"'"'s** en dubbelklik.\n' "$VERSION" "$NOTES_MD")"

# --- 4. Sparkle-appcast ----------------------------------------------------------
SPARKLE_DIR="$(ls -d "$APP_DIR"/vendor/Sparkle-* | tail -1)"
SIG_ATTRS="$("$SPARKLE_DIR/bin/sign_update" --account "$SPARKLE_ACCOUNT" "$DMG")"
PUBDATE="$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")"
URL="https://github.com/$REPO/releases/download/$TAG/$DMG_NAME"

cat > "$PROJECT_DIR/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Superclean Dreammachine</title>
    <link>https://github.com/$REPO</link>
    <description>Updates voor de Superclean Dreammachine Mac-app.</description>
    <language>nl</language>
    <item>
      <title>Versie $VERSION</title>
      <pubDate>$PUBDATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MINOS</sparkle:minimumSystemVersion>
      <description><![CDATA[$NOTES_HTML]]></description>
      <enclosure url="$URL" type="application/octet-stream" $SIG_ATTRS />
    </item>
  </channel>
</rss>
EOF

git add appcast.xml
git commit -q -m "Appcast: versie $VERSION"
git push -q origin main

echo ""
echo "✅ Versie $VERSION is uit."
echo "   Release : https://github.com/$REPO/releases/tag/$TAG"
echo "   Appcast : https://raw.githubusercontent.com/$REPO/main/appcast.xml"
