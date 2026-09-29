#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Preserve the supplied artwork; generate only the standard macOS icon sizes.
ICON_BUILD_DIR="${ACA_BUILD_DIR:-.build-local}"
ICONSET="$ICON_BUILD_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -z "$retina_size" "$retina_size" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil --convert icns "$ICONSET" --output "$ICON_BUILD_DIR/AppIcon.icns"
