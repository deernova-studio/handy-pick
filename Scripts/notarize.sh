#!/bin/bash
# 将已签名的发布候选应用公证，随后生成可离线验证的正式 DMG。
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$#" -ne 1 ] || [ ! -d "$1/Contents" ]; then
  echo "Usage: NOTARY_PROFILE=<钥匙串配置名> $0 <Quick Snap.app 路径>" >&2
  exit 2
fi
if [ -z "${NOTARY_PROFILE:-}" ]; then
  echo '请先用 xcrun notarytool store-credentials 配置公证授权，再设置 NOTARY_PROFILE。' >&2
  exit 1
fi
NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
if [ -n "${NOTARY_KEYCHAIN:-}" ]; then
  NOTARY_ARGS+=(--keychain "$NOTARY_KEYCHAIN")
fi
APP="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo '应用版本号格式不正确。' >&2
  exit 1
fi
SIGNATURE=$(codesign --display --verbose=4 "$APP" 2>&1)
IDENTITY=$(awk '/^Authority=Developer ID Application:/ { sub(/^Authority=/, ""); print; exit }' <<< "$SIGNATURE")
if [ -z "$IDENTITY" ] || [[ "$SIGNATURE" != *"runtime"* ]] || [[ "$SIGNATURE" != *"Timestamp="* ]]; then
  echo '应用必须具有 Developer ID 签名、安全时间戳和强化运行时。' >&2
  exit 1
fi
codesign --verify --deep --strict --verbose=2 "$APP"
if [ "$(xcrun lipo -archs "$APP/Contents/MacOS/QuickSnap")" != arm64 ]; then
  echo 'macOS 发布应用必须仅包含 arm64 架构，请重新运行发布构建。' >&2
  exit 1
fi

WORK="$(dirname "$APP")/notarization"
DEST="build/releases/QuickSnap-${VERSION}-build${BUILD_NUMBER}"
DMG_NAME="QuickSnap-${VERSION}-macOS-arm64.dmg"
if [ -e "$DEST" ]; then
  echo "正式发布目录已存在，请保留该版本：$DEST" >&2
  exit 1
fi
mkdir -p "$WORK" "$(dirname "$DEST")"
STAGING=$(mktemp -d "$(dirname "$DEST")/.notarize.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT

notarize() {
  local artifact="$1" name="$2" receipt status submission wait_exit=0
  receipt="$WORK/${name}-submission.json"
  # 保存提交 ID；中途退出后继续等待原申请，避免重复上传。
  if [ ! -s "$receipt" ]; then
    xcrun notarytool submit "$artifact" "${NOTARY_ARGS[@]}" --output-format json > "$receipt.tmp"
    plutil -extract id raw -o - "$receipt.tmp" >/dev/null
    mv "$receipt.tmp" "$receipt"
  fi
  submission=$(plutil -extract id raw -o - "$receipt")
  echo "等待 Apple 公证：${name}（${submission}）"
  xcrun notarytool wait "$submission" "${NOTARY_ARGS[@]}" --output-format json --timeout 20m > "$WORK/${name}-status.json" || wait_exit=$?
  status=$(plutil -extract status raw -o - "$WORK/${name}-status.json" 2>/dev/null || true)
  case "$status" in
    Accepted|Invalid|Rejected) ;;
    *)
      echo "尚未取得最终公证结果，可重新运行以继续等待申请 ${submission}。" >&2
      exit 1
      ;;
  esac
  xcrun notarytool log "$submission" "${NOTARY_ARGS[@]}" "$WORK/${name}-log.json"
  if [ "$status" != Accepted ] || [ "$wait_exit" -ne 0 ]; then
    echo "公证未通过（${status}），查看 $WORK/${name}-log.json。" >&2
    exit 1
  fi
  echo "$name 公证通过。"
}

ZIP="$WORK/QuickSnap-${VERSION}-macOS-arm64.zip"
if [ ! -f "$ZIP" ]; then
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGING/app.zip"
  mv "$STAGING/app.zip" "$ZIP"
fi
notarize "$ZIP" app
bash Scripts/notary-ticket.sh xcrun stapler staple "$APP"
bash Scripts/notary-ticket.sh xcrun stapler validate "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=2 "$APP"

# 先给应用附上公证票据，再制作 DMG，复制到应用程序后也能离线验证。
DMG="$WORK/$DMG_NAME"
if [ ! -f "$DMG" ]; then
  mkdir -p "$STAGING/volume"
  ditto "$APP" "$STAGING/volume/Quick Snap.app"
  ln -s /Applications "$STAGING/volume/Applications"
  hdiutil create -volname 'Quick Snap' -srcfolder "$STAGING/volume" -format UDZO "$STAGING/$DMG_NAME"
  codesign --sign "$IDENTITY" --timestamp "$STAGING/$DMG_NAME"
  codesign --verify --strict --verbose=2 "$STAGING/$DMG_NAME"
  mv "$STAGING/$DMG_NAME" "$DMG"
fi
notarize "$DMG" dmg
bash Scripts/notary-ticket.sh xcrun stapler staple "$DMG"
bash Scripts/notary-ticket.sh xcrun stapler validate "$DMG"
hdiutil verify "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

mkdir -p "$STAGING/final"
cp "$DMG" "$STAGING/final/$DMG_NAME"
(cd "$STAGING/final" && shasum -a 256 "$DMG_NAME" > SHA256SUMS.txt)
mv "$STAGING/final" "$DEST"
echo "正式签名、公证和 Gatekeeper 验证全部通过：$DEST/$DMG_NAME"
