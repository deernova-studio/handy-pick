#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app='build/distribution-dev/HandyPick.app'
dmg='build/distribution-dev/HandyPick-local.dmg'
[[ -d "$app" ]] || { echo 'Run task pack / 请运行 task pack' >&2; exit 1; }
stage=$(mktemp -d "${TMPDIR:-/tmp}/quick-snap-dmg.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/HandyPick.app"
ln -s /Applications "$stage/Applications"
hdiutil create -ov -format UDZO -volname 'HandyPick' -srcfolder "$stage" "$dmg"
hdiutil verify "$dmg"
echo "$dmg"
