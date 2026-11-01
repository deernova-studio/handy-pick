#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
zsh Scripts/build.sh
# Stay in One's process tree so stopping the task also stops the app.
exec "build/Quick Snap.app/Contents/MacOS/QuickSnap" "$@"
