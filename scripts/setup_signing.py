#!/usr/bin/env python3
"""One-time interactive import; secrets travel to One over stdin, never argv."""
import base64
import getpass
import json
import os
from pathlib import Path
import subprocess
import sys

from macos_signing import KEYS, SigningError, run_signed


def safe_error(result):
    """Only display known error codes, never raw API output or submitted values."""
    explanations = {
        "INFISICAL_FOLDER_NOT_FOUND": "Cloud folder prod /apple/macos is missing / 云端签名目录不存在",
        "INFISICAL_AUTH_MISSING": "Run one login / 请先登录 One",
        "INFISICAL_AUTH_FAILED": "Run one login again / One 登录已失效，请重新登录",
        "INFISICAL_NETWORK_ERROR": "Cannot reach Infisical / 无法连接凭据服务",
        "INFISICAL_API_ERROR": "Infisical rejected the request / 凭据服务拒绝了请求，请检查写入权限",
    }
    for output in (result.stdout, result.stderr):
        try:
            code = json.loads(output).get("error", {}).get("code")
        except (ValueError, TypeError, AttributeError):
            continue
        if code in explanations:
            return f"{code}: {explanations[code]}"
    return "One credential operation failed / One 凭据操作失败（原始输出未显示，避免泄露敏感值）"


def main():
    if not sys.stdin.isatty() or sys.platform != "darwin":
        raise SigningError("Run interactively on your Mac / 请在 Mac 终端中交互运行")
    result = subprocess.run(["one", "env", "--global", "-o", "json"], capture_output=True, text=True)
    if result.returncode:
        raise SigningError("Run one login first / 请先运行 one login 登录")
    location = json.loads(result.stdout).get("location")
    if not location:
        raise SigningError("Run one login or one env bind --global first / 请先登录并绑定共享凭据")
    # Probe folder access before asking for passwords. The current One global
    # setter does not create a missing folder on the first write.
    check = subprocess.run(["one", "env", "list", "--global", "--env", "prod", "--path", "/apple/macos", "-o", "json"],
                           capture_output=True, text=True)
    if check.returncode:
        raise SigningError(safe_error(check))
    print("Destination / 目标共享凭据库:")
    print(json.dumps(location, ensure_ascii=False, indent=2))
    print("Environment / 环境: prod; folder / 目录: /apple/macos")
    if input("Replace the five signing entries here? / 将在这里写入或更新五项签名凭据，继续？[y/N] ").strip().lower() != "y":
        return 0
    p12 = Path(input("Developer ID P12 file path / P12 文件路径: ").strip()).expanduser()
    values = {
        KEYS[0]: base64.b64encode(p12.read_bytes()).decode(),
        KEYS[1]: getpass.getpass("P12 password / P12 导出密码: "),
        "APPLE_ID": input("Apple account email / Apple 账户邮箱: ").strip(),
        "APPLE_TEAM_ID": input("Developer Team ID / 开发者团队 ID: ").strip(),
        "APPLE_APP_SPECIFIC_PASSWORD": getpass.getpass("Apple app-specific password / Apple App 专用密码: "),
    }
    # Reject invalid signing material before replacing cloud values.
    run_signed([], {**os.environ, **values})
    for key in KEYS:
        while True:
            result = subprocess.run(["one", "env", "set", "--global", "--env", "prod", "--path", "/apple/macos",
                                     "--stdin", "--yes", "-o", "json", key], input=values[key], capture_output=True, text=True)
            if not result.returncode:
                break
            print(f"{key}: {safe_error(result)}", file=sys.stderr)
            if input("Retry this upload without re-entering passwords? / 修复后重试当前项，无需重输密码 [r/N] ").strip().lower() != "r":
                raise SigningError(f"Upload stopped at {key} / 导入已停止，之前成功的项目保留在云端")
        print("Saved / 已保存: " + key)
    print("Ready / 已配置。换 Mac 后登录同一组织即可使用，无需再次导入 P12。")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SigningError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
    except (OSError, ValueError, EOFError, KeyboardInterrupt):
        print("Setup incomplete / 配置未完成，未输出任何凭据值", file=sys.stderr)
        sys.exit(1)
