#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash Scripts/package.sh --release
exec bash Scripts/notarize-current.sh
