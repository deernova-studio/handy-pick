import hashlib
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
import urllib.parse

SPEC = importlib.util.spec_from_file_location("github_release", Path(__file__).parents[1] / "github_release.py")
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class FakeGitHub:
    def __init__(self, release, *, private=True, draft=None, ref=None, corrupt_upload=False):
        self.release = release
        self.private = private
        self.draft = draft
        self.ref = ref
        self.assets = []
        self.mutations = []
        self.corrupt_upload = corrupt_upload

    def releases(self):
        return iter([self.draft] if self.draft else [])

    def request(self, method, path, payload=None, file=None, missing_ok=False):
        if method == "GET":
            if path == "":
                return {"private": self.private}
            if path.startswith("/git/ref/"):
                return self.ref
            if path.endswith("/assets"):
                return self.assets
        self.mutations.append((method, path))
        if method == "POST" and path == "/releases":
            self.draft = {
                **payload, "id": 42,
                "upload_url": f"https://uploads.github.com/repos/{self.release.repository}/releases/42/assets{{?name,label}}",
            }
            return self.draft
        if method == "POST" and path.startswith("https://uploads.github.com/"):
            name = urllib.parse.parse_qs(urllib.parse.urlsplit(path).query)["name"][0]
            digest = "0" * 64 if self.corrupt_upload else hashlib.sha256(file.read_bytes()).hexdigest()
            self.assets.append({"name": name, "state": "uploaded", "size": file.stat().st_size, "digest": "sha256:" + digest})
            return self.assets[-1]
        if method == "PATCH" and path == "/releases/42":
            self.draft.update(payload)
            self.draft["html_url"] = f"https://github.com/{self.release.repository}/releases/tag/{self.release.tag}"
            return self.draft
        raise AssertionError((method, path))


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.env = {
            "GITHUB_REF": "refs/heads/main", "QUICK_SNAP_VERSION": "0.2.11", "QUICK_SNAP_BUILD_NUMBER": "13",
            "GITHUB_REPOSITORY": "owner/quick-snap", "GITHUB_SHA": "a" * 40, "GITHUB_RUN_ID": "123",
        }
        self.release = MODULE.Release.from_env(self.env)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.dmg = self.directory / self.release.dmg_name
        self.dmg.write_bytes(b"test artifact bytes")
        self.sums = self.directory / "SHA256SUMS.txt"
        self.sums.write_text(f"{hashlib.sha256(self.dmg.read_bytes()).hexdigest()}  {self.dmg.name}\n")

    def managed_draft(self):
        return {
            "id": 42, "tag_name": self.release.tag, "draft": True,
            "target_commitish": self.release.sha, "body": self.release.body,
            "upload_url": "https://uploads.github.com/repos/owner/quick-snap/releases/42/assets{?name,label}",
        }

    def test_rejects_untrusted_version_build_and_ref(self):
        for field, value in [
            ("QUICK_SNAP_VERSION", "../0.2.11"), ("QUICK_SNAP_VERSION", "0.2.11\nEVIL=value"),
            ("QUICK_SNAP_VERSION", "00.2.11"), ("QUICK_SNAP_VERSION", "$(touch /tmp/quick-snap-test)"),
            ("QUICK_SNAP_BUILD_NUMBER", "0"), ("QUICK_SNAP_BUILD_NUMBER", "13; echo bad"),
            ("GITHUB_REF", "refs/heads/feature"), ("GITHUB_SHA", "main"),
        ]:
            with self.subTest(field=field, value=value), self.assertRaises(MODULE.ReleaseError):
                MODULE.Release.from_env({**self.env, field: value})

    def test_rejects_modified_artifact_before_github_mutations(self):
        self.dmg.write_bytes(b"changed")
        api = FakeGitHub(self.release)
        with self.assertRaises(MODULE.ReleaseError):
            MODULE.publish(api, self.release, self.directory)
        self.assertEqual(api.mutations, [])

    def test_rejects_missing_and_symlinked_artifact(self):
        self.dmg.unlink()
        with self.assertRaises(MODULE.ReleaseError):
            MODULE.verified_files(self.directory, self.release)
        self.dmg.symlink_to(self.sums)
        with self.assertRaises(MODULE.ReleaseError):
            MODULE.verified_files(self.directory, self.release)

    def test_rejects_public_repository(self):
        api = FakeGitHub(self.release, private=False)
        with self.assertRaises(MODULE.ReleaseError):
            MODULE.publish(api, self.release, self.directory)
        self.assertEqual(api.mutations, [])

    def test_does_not_overwrite_published_release_or_unrelated_draft(self):
        for changes in [{"draft": False}, {"body": None}, {"target_commitish": "b" * 40}, {"body": "another run"}]:
            api = FakeGitHub(self.release, draft={**self.managed_draft(), **changes})
            with self.subTest(changes=changes), self.assertRaises(MODULE.ReleaseError):
                MODULE.publish(api, self.release, self.directory)
            self.assertEqual(api.mutations, [])

    def test_does_not_move_existing_tag(self):
        for draft in [None, self.managed_draft()]:
            api = FakeGitHub(self.release, draft=draft, ref={"object": {"type": "commit", "sha": "b" * 40}})
            with self.assertRaises(MODULE.ReleaseError):
                MODULE.preflight(api, self.release)
            self.assertEqual(api.mutations, [])

    def test_publishes_only_after_both_asset_digests_match(self):
        api = FakeGitHub(self.release)
        url = MODULE.publish(api, self.release, self.directory)
        self.assertEqual(url, "https://github.com/owner/quick-snap/releases/tag/v0.2.11")
        self.assertEqual(len(api.assets), 2)
        self.assertEqual(api.mutations[-1], ("PATCH", "/releases/42"))
        self.assertEqual(api.draft["target_commitish"], self.release.sha)

    def test_corrupt_remote_asset_stays_draft(self):
        api = FakeGitHub(self.release, corrupt_upload=True)
        with self.assertRaises(MODULE.ReleaseError):
            MODULE.publish(api, self.release, self.directory)
        self.assertTrue(api.draft["draft"])
        self.assertFalse(any(method == "PATCH" for method, _ in api.mutations))

    def test_resumes_own_draft_without_reuploading_verified_asset(self):
        api = FakeGitHub(self.release, draft=self.managed_draft())
        api.assets = [{"name": self.dmg.name, "state": "uploaded", "size": self.dmg.stat().st_size,
                       "digest": "sha256:" + hashlib.sha256(self.dmg.read_bytes()).hexdigest()}]
        MODULE.publish(api, self.release, self.directory)
        uploads = [path for method, path in api.mutations if method == "POST"]
        self.assertEqual(len(uploads), 1)
        self.assertIn("SHA256SUMS.txt", uploads[0])

    def test_unexpected_or_incomplete_remote_asset_stops_resume(self):
        for asset in [
            {"name": "other-file"},
            {"name": self.dmg.name, "state": "starter", "size": 0, "digest": None},
        ]:
            api = FakeGitHub(self.release, draft=self.managed_draft())
            api.assets = [asset]
            with self.assertRaises(MODULE.ReleaseError):
                MODULE.publish(api, self.release, self.directory)
            self.assertEqual(api.mutations, [])

    def test_never_uploads_to_another_host(self):
        draft = {**self.managed_draft(), "upload_url": "https://example.com/assets"}
        api = FakeGitHub(self.release, draft=draft)
        with self.assertRaises(MODULE.ReleaseError):
            MODULE.publish(api, self.release, self.directory)
        self.assertEqual(api.mutations, [])


if __name__ == "__main__":
    unittest.main()
