#!/usr/bin/env python3
"""Use injected credentials through a temporary, explicitly selected keychain."""
import base64
import os
from pathlib import Path
import re
import secrets
import shutil
import signal
import subprocess
import sys
import tempfile

KEYS = (
    "MACOS_CERTIFICATE_P12_BASE64", "MACOS_CERTIFICATE_PASSWORD",
    "APPLE_ID", "APPLE_TEAM_ID", "APPLE_APP_SPECIFIC_PASSWORD",
)


class SigningError(Exception):
    pass


def private_command(label, argv):
    # Never expose command arguments or tool output: both may contain secrets.
    try:
        result = subprocess.run(argv, capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.TimeoutExpired):
        raise SigningError(f"{label} failed / 失败，请检查凭据与网络") from None
    if result.returncode:
        raise SigningError(f"{label} failed / 失败，请检查凭据与钥匙串权限")
    return result.stdout


def run_signed(command, env):
    missing = [key for key in KEYS if not env.get(key)]
    if missing:
        raise SigningError("Missing shared credentials / 缺少共享凭据: " + ", ".join(missing))
    if not re.fullmatch(r"[A-Z0-9]{10}", env["APPLE_TEAM_ID"]):
        raise SigningError("Invalid APPLE_TEAM_ID / 开发者团队 ID 无效")
    try:
        certificate = base64.b64decode("".join(env[KEYS[0]].split()), validate=True)
    except ValueError:
        raise SigningError("Invalid P12 Base64 / 证书编码无效") from None
    if not certificate:
        raise SigningError("Empty P12 / 证书为空")

    directory = Path(tempfile.mkdtemp(prefix="one-macos-signing-"))
    keychain = str(directory / "signing.keychain-db")
    p12 = directory / "identity.p12"
    password = secrets.token_urlsafe(32)
    child = None
    completed = False
    cleanup_error = None
    previous = {}

    def interrupted(signum, _frame):
        raise SystemExit(128 + signum)

    try:
        for sig in (signal.SIGINT, signal.SIGTERM):
            previous[sig] = signal.signal(sig, interrupted)
        p12.write_bytes(certificate)
        p12.chmod(0o600)
        private_command("Create temporary keychain", ["/usr/bin/security", "create-keychain", "-p", password, keychain])
        private_command("Configure keychain", ["/usr/bin/security", "set-keychain-settings", "-lut", "7200", keychain])
        private_command("Unlock keychain", ["/usr/bin/security", "unlock-keychain", "-p", password, keychain])
        ca = Path(__file__).parent / "certificates" / "DeveloperIDG2CA.cer"
        private_command("Import Apple intermediate", ["/usr/bin/security", "import", str(ca), "-k", keychain,
                        "-t", "cert", "-f", "x509"])
        private_command("Import Developer ID", ["/usr/bin/security", "import", str(p12), "-P", env[KEYS[1]], "-k", keychain,
                        "-t", "cert", "-f", "pkcs12", "-T", "/usr/bin/codesign", "-T", "/usr/bin/security"])
        p12.unlink()
        private_command("Authorize signing tools", ["/usr/bin/security", "set-key-partition-list", "-S",
                        "apple-tool:,apple:,codesign:", "-s", "-k", password, keychain])
        identities = private_command("Find Developer ID", ["/usr/bin/security", "find-identity", "-v", "-p", "codesigning", keychain])
        names = re.findall(r'"(Developer ID Application:[^"\n]+)"', identities)
        if len(names) != 1 or not names[0].endswith("(" + env["APPLE_TEAM_ID"] + ")"):
            raise SigningError("P12 must contain one valid Developer ID for APPLE_TEAM_ID / 证书必须包含该团队唯一有效的 Developer ID 私钥")
        private_command("Validate notarization credentials", ["/usr/bin/xcrun", "notarytool", "store-credentials", "one-macos",
                        "--keychain", keychain, "--apple-id", env["APPLE_ID"], "--team-id", env["APPLE_TEAM_ID"],
                        "--password", env["APPLE_APP_SPECIFIC_PASSWORD"]])
        child_env = {key: value for key, value in env.items() if key not in KEYS}
        child_env.update(SIGNING_IDENTITY=names[0], SIGNING_KEYCHAIN=keychain,
                         NOTARY_KEYCHAIN=keychain, NOTARY_PROFILE="one-macos")
        print("Signing credentials verified / 签名与公证凭据验证通过", flush=True)
        code = 0
        if command:
            child = subprocess.Popen(command, env=child_env, start_new_session=True)
            code = child.wait()
        completed = True
    finally:
        for sig in previous:
            signal.signal(sig, signal.SIG_IGN)
        if child is not None and child.poll() is None:
            try:
                os.killpg(child.pid, signal.SIGTERM)
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait()
            except ProcessLookupError:
                pass
        try:
            if Path(keychain).exists():
                private_command("Delete temporary keychain", ["/usr/bin/security", "delete-keychain", keychain])
        except SigningError as error:
            cleanup_error = error
        finally:
            shutil.rmtree(directory)
            for sig, handler in previous.items():
                signal.signal(sig, handler)
        if cleanup_error:
            if completed:
                raise cleanup_error
            print(str(cleanup_error), file=sys.stderr)
    return code if code >= 0 else 128 - code


def main():
    if sys.platform != "darwin":
        raise SigningError("macOS is required / 签名需要 macOS")
    command = sys.argv[1:]
    if command[:1] == ["--"]:
        command = command[1:]
    return run_signed(command, dict(os.environ))


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SigningError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
    except OSError:
        print("Signing setup failed / 签名准备失败", file=sys.stderr)
        sys.exit(1)
