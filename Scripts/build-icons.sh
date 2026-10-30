#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
iconset="$PWD/build/QuickSnap.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o Resources/QuickSnap.icns
# Remove empty margins only; retain the exact generated mark and its alpha.
sips -c 1040 1040 Resources/MenuIcon-source.png --out build/menu-icon-cropped.png >/dev/null
sips -z 38 38 build/menu-icon-cropped.png --out Resources/MenuIcon.png >/dev/null
