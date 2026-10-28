#!/bin/bash
# Haalt het Sparkle-updateframework op (vastgepinde versie, SHA-256 gecontroleerd)
# naar app/vendor/. Wordt automatisch door build.sh aangeroepen; doet niets als het er al is.
#
# Gebruik:  bash app/fetch-sparkle.sh
set -euo pipefail

SPARKLE_VERSION="2.10.0"
SPARKLE_SHA256="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"
SPARKLE_URL="https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$APP_DIR/vendor/Sparkle-$SPARKLE_VERSION"

if [ -d "$DEST/Sparkle.framework" ]; then
    exit 0
fi

echo "==> Sparkle $SPARKLE_VERSION ophalen ..."
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sparkle.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL --max-time 120 -o "$TMP/sparkle.tar.xz" "$SPARKLE_URL"

GOT="$(shasum -a 256 "$TMP/sparkle.tar.xz" | awk '{print $1}')"
if [ "$GOT" != "$SPARKLE_SHA256" ]; then
    echo "   ! SHA-256 klopt niet (verwacht $SPARKLE_SHA256, kreeg $GOT) — afgebroken."
    exit 1
fi

mkdir -p "$TMP/x"
tar -xJf "$TMP/sparkle.tar.xz" -C "$TMP/x"
mkdir -p "$DEST"
ditto "$TMP/x/Sparkle.framework" "$DEST/Sparkle.framework"
ditto "$TMP/x/bin" "$DEST/bin"
echo "   Sparkle $SPARKLE_VERSION staat in $DEST"
