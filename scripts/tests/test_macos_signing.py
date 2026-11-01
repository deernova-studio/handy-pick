import base64
from contextlib import redirect_stdout, redirect_stderr
import importlib.util
import io
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch, Mock

SPEC = importlib.util.spec_from_file_location("macos_signing", Path(__file__).parents[1] / "macos_signing.py")
signing = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(signing)
with patch.dict(sys.modules, {"macos_signing": signing}):
    SETUP_SPEC = importlib.util.spec_from_file_location("setup_signing", Path(__file__).parents[1] / "setup_signing.py")
    setup = importlib.util.module_from_spec(SETUP_SPEC)
    SETUP_SPEC.loader.exec_module(setup)


class SigningTests(unittest.TestCase):
    def setUp(self):
        self.env = dict(zip(signing.KEYS, [base64.b64encode(b"fake-p12").decode(),
                        "private-p12-password", "test@example.invalid", "ABCDEFGHIJ", "private-notary-password"]))
        self.env["QUICK_SNAP_VERSION"] = "1.2.3"
        self.identities = '1) ABC "Developer ID Application: Test (ABCDEFGHIJ)"\n1 valid identities found'
        self.directory = None
        self.deleted = False
        self.failure = None
        self.output = io.StringIO()

    def apple(self, label, args):
        if "create-keychain" in args:
            path = Path(args[-1])
            self.directory = path.parent
            path.touch()
            self.assertEqual(self.directory.stat().st_mode & 0o777, 0o700)
        if label == self.failure:
            raise signing.SigningError("Simulated setup failure")
        if "import" in args and args[2].endswith(".p12"):
            path = Path(args[2])
            self.assertEqual(path.read_bytes(), b"fake-p12")
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        if "find-identity" in args:
            return self.identities
        if "delete-keychain" in args:
            Path(args[-1]).unlink()
            self.deleted = True
        return ""

    def execute(self, command=(), child=None):
        with patch.object(signing, "private_command", side_effect=self.apple), \
             patch.object(signing.subprocess, "Popen", return_value=child) as popen, \
             redirect_stdout(self.output), redirect_stderr(self.output):
            code = signing.run_signed(command, self.env)
        return code, popen

    def test_verification_deletes_keychain_and_all_private_files(self):
        code, popen = self.execute()
        self.assertEqual(code, 0)
        popen.assert_not_called()
        self.assertTrue(self.deleted)
        self.assertFalse(self.directory.exists())
        for value in self.env.values():
            self.assertNotIn(value, self.output.getvalue())

    def test_child_receives_keychain_not_raw_secrets_and_preserves_failure(self):
        child = Mock()
        child.wait.return_value = 42
        child.poll.return_value = 42
        code, popen = self.execute(["tool", "argument with spaces"], child)
        self.assertEqual(code, 42)
        args, kwargs = popen.call_args
        self.assertEqual(args[0], ["tool", "argument with spaces"])
        for key in signing.KEYS:
            self.assertNotIn(key, kwargs["env"])
        self.assertEqual(kwargs["env"]["QUICK_SNAP_VERSION"], "1.2.3")
        self.assertEqual(kwargs["env"]["SIGNING_KEYCHAIN"], kwargs["env"]["NOTARY_KEYCHAIN"])
        self.assertTrue(kwargs["start_new_session"])
        self.assertTrue(self.deleted)

    def test_cleanup_after_import_or_notary_failure(self):
        for label in ("Import Developer ID", "Validate notarization credentials"):
            with self.subTest(label=label):
                self.failure = label
                self.deleted = False
                with self.assertRaises(signing.SigningError):
                    self.execute()
                self.assertTrue(self.deleted)
                self.assertFalse(self.directory.exists())

    def test_rejects_wrong_team_missing_key_and_ambiguous_identity(self):
        for identities in ('0 valid identities found',
                           '"Developer ID Application: Other (XXXXXXXXXX)"',
                           self.identities + '\n"Developer ID Application: Second (ABCDEFGHIJ)"'):
            with self.subTest(identities=identities):
                self.identities = identities
                with self.assertRaises(signing.SigningError):
                    self.execute()
                self.assertTrue(self.deleted)
                self.assertFalse(self.directory.exists())

    def test_missing_credentials_and_bad_encoding_do_not_create_files(self):
        for key, value in (("APPLE_ID", ""), ("APPLE_TEAM_ID", "bad"), ("MACOS_CERTIFICATE_P12_BASE64", "not@base64")):
            with self.subTest(key=key), patch.dict(self.env, {key: value}), \
                 patch.object(signing.tempfile, "mkdtemp") as mkdtemp:
                with self.assertRaises(signing.SigningError):
                    self.execute()
                mkdtemp.assert_not_called()

    def test_tool_failures_do_not_include_arguments_or_output(self):
        result = subprocess.CompletedProcess([], 1, stdout="private-output", stderr="private-error")
        with patch.object(signing.subprocess, "run", return_value=result):
            with self.assertRaises(signing.SigningError) as caught:
                signing.private_command("Import", ["security", "private-password"])
        self.assertNotIn("private", str(caught.exception))

    def test_cancel_terminates_child_before_cleaning_keychain(self):
        child = Mock(pid=12345)
        child.wait.side_effect = [SystemExit(143), 0]
        child.poll.return_value = None
        before = signal.getsignal(signal.SIGTERM)
        with patch.object(signing.os, "killpg") as kill:
            with self.assertRaises(SystemExit):
                self.execute(["tool"], child)
            kill.assert_called_once_with(12345, signal.SIGTERM)
        self.assertTrue(self.deleted)
        self.assertFalse(self.directory.exists())
        self.assertEqual(signal.getsignal(signal.SIGTERM), before)


class SetupTests(unittest.TestCase):
    def test_uploads_values_only_over_stdin_after_validation(self):
        with tempfile.TemporaryDirectory() as d:
            p12 = Path(d) / "identity.p12"
            p12.write_bytes(b"fake-p12")
            inputs = iter(["y", str(p12), "test@example.invalid", "ABCDEFGHIJ"])
            calls = []
            def one(args, **kwargs):
                calls.append((args, kwargs))
                return subprocess.CompletedProcess(args, 0, '{"location":{"projectName":"shared-credentials"}}', '')
            output = io.StringIO()
            with patch.object(setup.sys.stdin, "isatty", return_value=True), \
                 patch.object(setup.sys, "platform", "darwin"), \
                 patch("builtins.input", side_effect=lambda _: next(inputs)), \
                 patch.object(setup.getpass, "getpass", side_effect=["p12-secret", "notary-secret"]), \
                 patch.object(setup, "run_signed", return_value=0) as validate, \
                 patch.object(setup.subprocess, "run", side_effect=one), redirect_stdout(output):
                self.assertEqual(setup.main(), 0)
            validate.assert_called_once()
            self.assertEqual(len(calls), 6)
            for args, kwargs in calls[1:]:
                self.assertIn("--stdin", args)
                self.assertIn("input", kwargs)
                self.assertNotIn(kwargs["input"], " ".join(args))
                self.assertNotIn(kwargs["input"], output.getvalue())

    def test_unbound_account_does_not_prompt_for_secrets(self):
        with patch.object(setup.sys.stdin, "isatty", return_value=True), \
             patch.object(setup.sys, "platform", "darwin"), \
             patch.object(setup.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, '{"location":null}')), \
             patch.object(setup.getpass, "getpass") as password:
            with self.assertRaises(signing.SigningError):
                setup.main()
            password.assert_not_called()


if __name__ == "__main__":
    unittest.main()
