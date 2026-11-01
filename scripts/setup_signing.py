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


def main():
    if not sys.stdin.isatty() or sys.platform != "darwin":
        raise SigningError("Run interactively on your Mac / 请在 Mac 终端中交互运行")
    result = subprocess.run(["one", "env", "--global", "-o", "json"], capture_output=True, text=True)
    if result.returncode:
        raise SigningError("Run one login first / 请先运行 one login 登录")
    location = json.loads(result.stdout).get("location")
    if not location:
        raise SigningError("Run one login or one env bind --global first / 请先登录并绑定共享凭据")
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
        result = subprocess.run(["one", "env", "set", "--global", "--env", "prod", "--path", "/apple/macos",
                                 "--stdin", "--yes", key], input=values[key], capture_output=True, text=True)
        if result.returncode:
            raise SigningError(f"Upload failed at {key}; rerun setup to finish / 写入失败，请重新运行完成配置")
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
