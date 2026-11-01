#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
app_dir="$PWD/build/HandyPick.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/QuickSnap" "$app_dir/Contents/MacOS/QuickSnap"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp Resources/QuickSnap.icns Resources/MenuIcon.png "$app_dir/Contents/Resources/"
codesign --force --sign "${QUICK_SNAP_SIGN_IDENTITY:--}" --identifier studio.deernova.quick-snap "$app_dir"
touch "$app_dir"
print -r -- "$app_dir"
