#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="${QUICK_SNAP_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)}"
build_number="${QUICK_SNAP_BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' Resources/Info.plist)}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ ! "$build_number" =~ ^[1-9][0-9]{0,8}$ ]]; then
  echo 'Invalid version/build number / 版本号或构建号无效' >&2
  exit 2
fi
exec bash Scripts/notarize.sh "build/release-candidates/QuickSnap-${version}-build${build_number}/Quick Snap.app"
