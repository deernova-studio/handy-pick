#!/bin/bash
# 只在临时 GitHub 托管 Mac 中安装签名身份，不读取开发者本机钥匙串。
set -euo pipefail
if [ "${GITHUB_ACTIONS:-}" != true ] || [ "${RUNNER_ENVIRONMENT:-}" != github-hosted ] || [ "${RUNNER_OS:-}" != macOS ] || [ -z "${RUNNER_TEMP:-}" ]; then
  echo '签名初始化仅允许在 GitHub 托管的 macOS runner 中运行。' >&2
  exit 2
fi
KEYCHAIN_PATH="$RUNNER_TEMP/quick-snap-signing.keychain-db"
CERTIFICATE_PATH="$RUNNER_TEMP/quick-snap-signing.p12"
case "${1:-}" in
  cleanup)
    rm -f "$CERTIFICATE_PATH"
    if [ -e "$KEYCHAIN_PATH" ]; then security delete-keychain "$KEYCHAIN_PATH"; fi
    exit 0
    ;;
  install) ;;
  *) echo "Usage: $0 install|cleanup" >&2; exit 2 ;;
esac
for required in MACOS_CERTIFICATE_P12_BASE64 MACOS_CERTIFICATE_PASSWORD APPLE_ID APPLE_TEAM_ID APPLE_APP_SPECIFIC_PASSWORD; do
  if [ -z "${!required:-}" ]; then
    echo "::error::缺少 ${required}，请按 docs/github-actions.md 配置发布授权。"
    exit 1
  fi
done
if [[ ! "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  echo 'APPLE_TEAM_ID 格式不正确。' >&2
  exit 1
fi
umask 077
export CERTIFICATE_PATH
python3 - <<'PY'
import base64, os
from pathlib import Path
encoded = ''.join(os.environ['MACOS_CERTIFICATE_P12_BASE64'].split())
Path(os.environ['CERTIFICATE_PATH']).write_bytes(base64.b64decode(encoded, validate=True))
PY
KEYCHAIN_PASSWORD=$(openssl rand -hex 32)
echo "::add-mask::$KEYCHAIN_PASSWORD"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 7200 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERTIFICATE_PATH" -P "$MACOS_CERTIFICATE_PASSWORD" -k "$KEYCHAIN_PATH" -t cert -f pkcs12 -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
security list-keychains -d user -s "$KEYCHAIN_PATH" "$HOME/Library/Keychains/login.keychain-db"
IDENTITIES=$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" | awk -F '"' '/"Developer ID Application:/ {print $2}')
if [ "$(printf '%s\n' "$IDENTITIES" | awk 'NF {n++} END {print n+0}')" -ne 1 ] || [[ "$IDENTITIES" != *"($APPLE_TEAM_ID)" ]]; then
  echo 'p12 必须包含该 Team 唯一有效的 Developer ID Application 证书及私钥。' >&2
  exit 1
fi
xcrun notarytool store-credentials quick-snap-ci --keychain "$KEYCHAIN_PATH" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD"
rm -f "$CERTIFICATE_PATH"
{
  printf 'SIGNING_IDENTITY=%s\n' "$IDENTITIES"
  printf 'NOTARY_PROFILE=quick-snap-ci\nNOTARY_KEYCHAIN=%s\n' "$KEYCHAIN_PATH"
} >> "$GITHUB_ENV"
