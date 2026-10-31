#!/bin/bash
# stapler 的 CloudKit 连接中断返回 68；仅重试这一临时错误，不跳过验证。
set -u
for attempt in 1 2 3 4 5; do
  status=0
  "$@" || status=$?
  if [ "$status" -eq 0 ]; then exit 0; fi
  if [ "$status" -ne 68 ] || [ "$attempt" -eq 5 ]; then exit "$status"; fi
  echo "Apple 公证票据服务暂时不可用，稍后重试（${attempt}/5）。" >&2
  sleep "$((attempt * 3))"
done
