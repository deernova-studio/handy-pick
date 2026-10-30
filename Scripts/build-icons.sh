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
# Export the white menu-bar badge with transparent brand-mark cutouts at 22 × 18 points.
swiftc -O Sources/QuickSnap/MenuBarIcon.swift Scripts/render-menu-icon.swift -o build/render-menu-icon
build/render-menu-icon
