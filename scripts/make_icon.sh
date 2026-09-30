#!/bin/sh
# Generate all macOS icon sizes from the approved transparent TextStack artwork.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ISET="$ROOT/.build/TextStack.iconset"
mkdir -p "$ISET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ROOT/art/TextStack.png" --out "$ISET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$ROOT/art/TextStack.png" --out "$ISET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ISET" -o "$ROOT/art/AppIcon.icns"
cp "$ROOT/art/AppIcon.icns" "$ROOT/Sources/MrEditorCore/Resources/AppIcon.icns"
echo "$ROOT/art/AppIcon.icns"
