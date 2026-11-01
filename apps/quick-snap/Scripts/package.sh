#!/bin/bash
# 仅构建 Apple 芯片（arm64）应用；本地使用临时签名，--release 使用 Developer ID 正式签名。
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${QUICK_SNAP_VERSION:-$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)}"
BUILD_NUMBER="${QUICK_SNAP_BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" Resources/Info.plist)}"
if [[ ! "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]{0,8}$ ]]; then
  echo '版本号必须为 x.y.z，构建号必须为最多 9 位的正整数。' >&2
  exit 2
fi
RELEASE=false
case "${1:-}" in
  "") APP="build/distribution-dev/Quick Snap.app" ;;
  --dev) APP="build/distribution-dev/Quick Snap.app" ;;
  --release)
    RELEASE=true
    APP="build/release-candidates/QuickSnap-${VERSION}-build${BUILD_NUMBER}/Quick Snap.app"
    if [ -e "$APP" ]; then
      echo "发布候选应用已存在：${APP}。请保留该版本，更新版本号后再构建。" >&2
      exit 1
    fi
    if [ -z "${SIGNING_IDENTITY:-}" ]; then
      IDENTITIES=()
      while IFS= read -r identity; do
        IDENTITIES+=("$identity")
      done < <(security find-identity -v -p codesigning | awk -F '"' '/"Developer ID Application:/ { print $2 }')
      if [ "${#IDENTITIES[@]}" -ne 1 ]; then
        echo '请用 SIGNING_IDENTITY 指定一个有效的 Developer ID Application 签名身份。' >&2
        exit 1
      fi
      SIGNING_IDENTITY="${IDENTITIES[0]}"
    fi
    if [[ "$SIGNING_IDENTITY" != "Developer ID Application: "* ]]; then
      echo '正式构建必须使用完整的 Developer ID Application 签名身份名称。' >&2
      exit 1
    fi
    ;;
  *) echo "Usage: $0 [--dev|--release]" >&2; exit 2 ;;
esac
BUILD_ARGS=(--triple arm64-apple-macosx14.0 -c release)
if "$RELEASE"; then
  BUILD_ARGS+=(--scratch-path .build/distribution-arm64 --disable-local-rpath)
fi
xcrun swift build "${BUILD_ARGS[@]}" --product QuickSnap
BINARY="$(xcrun swift build "${BUILD_ARGS[@]}" --show-bin-path)/QuickSnap"
if [ "$(xcrun lipo -archs "$BINARY")" != arm64 ]; then
  echo 'macOS 应用必须仅包含 arm64 架构。' >&2
  exit 1
fi
mkdir -p "$(dirname "$APP")"
STAGING=$(mktemp -d "$(dirname "$APP")/.package.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
STAGED_APP="$STAGING/Quick Snap.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BINARY" "$STAGED_APP/Contents/MacOS/QuickSnap"
cp Resources/QuickSnap.icns Resources/MenuIcon.png "$STAGED_APP/Contents/Resources/"
cp Resources/Info.plist "$STAGED_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $VERSION" "$STAGED_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set CFBundleVersion $BUILD_NUMBER" "$STAGED_APP/Contents/Info.plist"
plutil -lint "$STAGED_APP/Contents/Info.plist"
if "$RELEASE"; then
  KEYCHAIN_ARGS=()
  if [ -n "${SIGNING_KEYCHAIN:-}" ]; then KEYCHAIN_ARGS=(--keychain "$SIGNING_KEYCHAIN"); fi
  codesign --force --sign "$SIGNING_IDENTITY" "${KEYCHAIN_ARGS[@]}" --options runtime --timestamp "$STAGED_APP"
else
  codesign --force --sign - "$STAGED_APP"
fi
codesign --verify --deep --strict --verbose=2 "$STAGED_APP"
if [ -f "$APP/Contents/MacOS/QuickSnap" ] && /usr/sbin/lsof -t "$APP/Contents/MacOS/QuickSnap" >/dev/null 2>&1; then
  echo "应用正在运行，请先关闭对应版本再更新：$APP" >&2
  exit 1
fi
rm -rf "$APP"
mv "$STAGED_APP" "$APP"
if "$RELEASE"; then
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$(dirname "$APP")/QuickSnap-${VERSION}-macOS-arm64-signed.zip"
  echo '正式签名完成；尚未完成 Apple 公证。请运行 Scripts/notarize.sh 后再对外分发。'
fi
echo "$APP"
