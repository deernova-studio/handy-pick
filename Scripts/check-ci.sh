#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
for script in Scripts/*.sh; do
  if [[ "$script" == Scripts/build.sh || "$script" == Scripts/build-icons.sh ]]; then
    zsh -n "$script"
  else
    bash -n "$script"
  fi
done
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Scripts/tests -v
xcrun swift test
xcrun swift build --triple arm64-apple-macosx14.0 -c release --product QuickSnap
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo '发布脚本测试、Swift 核心测试、Mac arm64 Release 编译通过。真实鼠标、输入框和权限交互需要在实际 Mac 验证。' >> "$GITHUB_STEP_SUMMARY"
fi
