#!/bin/bash
# Pin the merged Swift support until it ships in a stable One release.
set -euo pipefail
cd "$(dirname "$0")/.."
commit=bc73b921d85e1896044167c0be96a2b8936edf54
checksum=a46d8a00f79b049b6588dbea3e90e43d063f9cbd118304b6d5d953824a74c29d
root="$PWD/.cache/one"
mkdir -p "$root/bin"
stage=$(mktemp -d "$root/bootstrap.XXXXXX")
trap 'rm -rf "$stage"' EXIT
curl --fail --silent --show-error --location --retry 3 --max-time 120 \
  "https://codeload.github.com/1cli-team/one-cli/tar.gz/$commit" -o "$stage/source.tar.gz"
actual=$(shasum -a 256 "$stage/source.tar.gz" | awk '{print $1}')
[[ "$actual" == "$checksum" ]] || { echo 'One source checksum mismatch / One 源码校验失败' >&2; exit 1; }
mkdir "$stage/source"
tar -xzf "$stage/source.tar.gz" -C "$stage/source" --strip-components=1
(
  cd "$stage/source"
  go run ./packages/cli/tools/sync-resources bundled
  go build -trimpath -ldflags "-s -w -X main.version=0.1.24-swift.${commit:0:7}" \
    -o "$stage/one" ./packages/cli/cmd/one
)
install -m 755 "$stage/one" "$root/bin/one"
"$root/bin/one" --version
echo "One installed / One 已安装: $root/bin/one"
