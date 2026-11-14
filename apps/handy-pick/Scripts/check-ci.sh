#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash -n ../../scripts/bootstrap-one.sh ../../scripts/signing.sh
for script in Scripts/*.sh; do
  if [[ "$script" == Scripts/build.sh || "$script" == Scripts/build-icons.sh ]]; then
    zsh -n "$script"
  else
    bash -n "$script"
  fi
done
# SM-01: build a real distributable app using the production packaging path.
# This ad-hoc signed development artifact is not a notarized release.
bash Scripts/package.sh --dev
echo 'PASS SM-01: Release 开发包构建、资源封装及签名完整性校验通过。'
echo 'SM-02–SM-10 未由此脚本执行；按 docs/smoke.md 完成人工或发布验收。'
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo 'SM-01 构建打包冒烟通过；其他用例未自动执行，见 docs/smoke.md。' >> "$GITHUB_STEP_SUMMARY"
fi
