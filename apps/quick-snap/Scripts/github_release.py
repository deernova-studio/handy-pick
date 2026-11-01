#!/usr/bin/env python3
"""Publish only verified, notarized artifacts from the manual main-branch workflow."""
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass


class ReleaseError(Exception):
    pass


@dataclass(frozen=True)
class Release:
    version: str
    build: str
    repository: str
    sha: str
    run_id: str
    notes: str = ""

    @classmethod
    def from_env(cls, env):
        if env.get("GITHUB_REF") != "refs/heads/main":
            raise ReleaseError("发布只允许从 main 手动触发。")
        fields = {
            "QUICK_SNAP_VERSION": r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)",
            "QUICK_SNAP_BUILD_NUMBER": r"[1-9][0-9]{0,8}",
            "GITHUB_REPOSITORY": r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+",
            "GITHUB_SHA": r"[0-9a-f]{40}",
            "GITHUB_RUN_ID": r"[1-9][0-9]*",
        }
        for key, pattern in fields.items():
            if not re.fullmatch(pattern, env.get(key, "")):
                raise ReleaseError(f"{key} 格式不正确。")
        notes = env.get("QUICK_SNAP_RELEASE_NOTES", "").strip()
        if len(notes) > 4000 or "\x00" in notes:
            raise ReleaseError("更新说明不能超过 4000 字或包含空字符。")
        return cls(*(env[key] for key in fields), notes)

    @property
    def tag(self):
        return f"v{self.version}"

    @property
    def dmg_name(self):
        return f"HandyPick-{self.version}-macOS-arm64.dmg"

    @property
    def marker(self):
        return f"<!-- quick-snap-release:sha={self.sha};run={self.run_id};build={self.build} -->"

    @property
    def body(self):
        details = (
            "适用于 M 系列 Mac，需 macOS 14 或更新版本。\n\n"
            "下载下方 DMG，打开后将「HandyPick」拖入「应用程序」。\n\n"
            f"{self.marker}"
        )
        return f"{self.notes}\n\n{details}" if self.notes else details


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class GitHub:
    def __init__(self, repository, token):
        if not token:
            raise ReleaseError("缺少 GitHub 发布授权。")
        self.base = f"https://api.github.com/repos/{repository}"
        self.token = token
        self.opener = urllib.request.build_opener(NoRedirect)

    def request(self, method, path, payload=None, file=None, missing_ok=False):
        url = path if path.startswith("https://") else self.base + path
        parsed = urllib.parse.urlsplit(url)
        if parsed.scheme != "https" or parsed.netloc not in {"api.github.com", "uploads.github.com"}:
            raise ReleaseError("GitHub 返回了非预期的上传地址。")
        data = file.read_bytes() if file else (json.dumps(payload).encode() if payload is not None else None)
        headers = {
            "Authorization": f"Bearer {self.token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "HandyPick-release-workflow",
            "Content-Type": "application/octet-stream" if file else "application/json",
        }
        try:
            request = urllib.request.Request(url, data=data, headers=headers, method=method)
            with self.opener.open(request, timeout=120) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if error.code == 404 and missing_ok:
                return None
            raise ReleaseError(f"GitHub {method} 请求失败：HTTP {error.code}，路径 {parsed.path}。") from None
        except (urllib.error.URLError, TimeoutError):
            raise ReleaseError("GitHub 连接失败，可在 Actions 中重新运行此任务。") from None

    def releases(self):
        page = 1
        while True:
            items = self.request("GET", f"/releases?per_page=100&page={page}")
            yield from items
            if len(items) < 100:
                return
            page += 1


def preflight(api, release):
    if api.request("GET", "").get("private") is not True:
        raise ReleaseError("此发布流程只允许发布到私有仓库。")
    existing = next((item for item in api.releases() if item["tag_name"] == release.tag), None)
    if existing:
        if not existing["draft"]:
            raise ReleaseError(f"{release.tag} 已发布，请使用新版本号；不会覆盖旧版本。")
        if release.marker not in (existing.get("body") or "") or existing["target_commitish"] != release.sha:
            raise ReleaseError("存在其他发布任务的同名草稿，请先检查该草稿。")
    ref = api.request("GET", f"/git/ref/tags/{release.tag}", missing_ok=True)
    if ref:
        if not existing or ref["object"]["type"] != "commit" or ref["object"]["sha"] != release.sha:
            raise ReleaseError("版本标签已存在或指向其他提交；不会移动已有标签。")
    return existing


def verified_files(directory, release):
    directory = Path(directory)
    dmg = directory / release.dmg_name
    sums = directory / "SHA256SUMS.txt"
    for path in (dmg, sums):
        if path.is_symlink() or not path.is_file() or path.stat().st_size == 0:
            raise ReleaseError(f"缺少有效发布文件：{path.name}")
    digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
    if sums.read_text().strip() != f"{digest}  {dmg.name}":
        raise ReleaseError("DMG 与 SHA256SUMS.txt 不匹配，停止发布。")
    return [dmg, sums]


def verify_assets(assets, files):
    expected = {path.name: path for path in files}
    if len(assets) != len(expected) or {asset["name"] for asset in assets} != set(expected):
        raise ReleaseError("Release 附件不完整或包含非预期文件。")
    for asset in assets:
        path = expected[asset["name"]]
        if (asset.get("state") != "uploaded" or asset.get("size") != path.stat().st_size
                or asset.get("digest") != "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()):
            raise ReleaseError(f"GitHub 附件校验失败：{path.name}。草稿已保留，不会发布。")


def publish(api, release, directory):
    files = verified_files(directory, release)
    draft = preflight(api, release)
    if not draft:
        draft = api.request("POST", "/releases", {
            "tag_name": release.tag, "target_commitish": release.sha,
            "name": f"HandyPick {release.version}", "body": release.body,
            "draft": True, "prerelease": False,
        })
    release_path = f'/releases/{draft["id"]}'
    assets = api.request("GET", release_path + "/assets")
    expected = {path.name: path for path in files}
    if any(asset["name"] not in expected for asset in assets):
        raise ReleaseError("草稿有非预期附件，停止发布。")
    for asset in assets:
        verify_assets([asset], [expected[asset["name"]]])
    upload_url = draft["upload_url"].split("{", 1)[0]
    expected_url = f'https://uploads.github.com/repos/{release.repository}{release_path}/assets'
    if upload_url != expected_url:
        raise ReleaseError("GitHub 返回了非预期的上传地址。")
    for path in files:
        if not any(asset["name"] == path.name for asset in assets):
            api.request("POST", upload_url + "?" + urllib.parse.urlencode({"name": path.name}), file=path)
    verify_assets(api.request("GET", release_path + "/assets"), files)
    # 上传过程中仓库或草稿可能被更改，公开版本前重新核对。
    current = preflight(api, release)
    if not current or current["id"] != draft["id"]:
        raise ReleaseError("发布草稿发生变化，停止发布。")
    published = api.request("PATCH", release_path, {"draft": False, "make_latest": "true"})
    if published.get("draft") is not False or published.get("tag_name") != release.tag:
        raise ReleaseError("GitHub 尚未确认发布成功，请检查 Release 页面。")
    return published["html_url"]


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in {"preflight", "publish"}:
        raise ReleaseError("Usage: github_release.py preflight | publish <artifact-directory>")
    release = Release.from_env(os.environ)
    api = GitHub(release.repository, os.environ.get("GH_TOKEN", ""))
    if sys.argv[1] == "preflight":
        preflight(api, release)
        print(f"{release.tag} / build {release.build} 可以发布，目标提交 {release.sha}。")
    else:
        if len(sys.argv) != 3:
            raise ReleaseError("publish 需要安装包所在目录。")
        url = publish(api, release, sys.argv[2])
        print(f"发布成功：{url}")
        if os.environ.get("GITHUB_STEP_SUMMARY"):
            with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
                summary.write(f"HandyPick {release.version} 已发布：[下载 Release]({url})\n")


if __name__ == "__main__":
    try:
        main()
    except ReleaseError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
