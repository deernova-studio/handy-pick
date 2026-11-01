#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../apps/quick-snap"
case "${1:-}" in
  sign) set -- bash Scripts/package.sh --release ;;
  notarize) set -- bash Scripts/notarize-current.sh ;;
  release) set -- bash Scripts/release.sh ;;
  verify) set -- ;;
  *) echo 'Usage: signing.sh sign|notarize|release|verify' >&2; exit 2 ;;
esac
exec one exec --global --env prod --path /apple/macos \
  --keys MACOS_CERTIFICATE_P12_BASE64,MACOS_CERTIFICATE_PASSWORD,APPLE_ID,APPLE_TEAM_ID,APPLE_APP_SPECIFIC_PASSWORD \
  -- python3 ../../scripts/macos_signing.py -- "$@"
