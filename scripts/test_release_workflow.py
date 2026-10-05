import hashlib
import unittest
from unittest.mock import patch

import release


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.version = "1.0.0"
        self.tag_sha = "commit"
        self.pull = {
            "merged_at": "date",
            "base": {"ref": "main"},
            "head": {"ref": "release/v1.0.0"},
            "merge_commit_sha": "commit",
        }
        digest = "sha256:" + hashlib.sha256(b"media").hexdigest()
        self.release = {
            "id": 1,
            "tag_name": "v1.0.0",
            "name": "v1.0.0",
            "body": "notes",
            "prerelease": False,
            "draft": False,
            "assets": [
                {"name": name, "digest": digest} for name in ("showcase.mp4", "showcase.gif")
            ],
        }
        self.mutations = []

    def api(self, path, data=None, **kwargs):
        if data is not None:
            self.mutations.append((path, data))
            return self.release
        if path.startswith("commits/"):
            return [self.pull]
        if path.startswith("git/ref/tags/"):
            return {"object": {"type": "commit", "sha": self.tag_sha}}
        if path.startswith("releases/tags/"):
            return self.release
        raise AssertionError(path)

    def run_publish(self):
        with (
            patch.object(release, "validate_change", return_value=(self.version, "0.0.0", True)),
            patch.object(
                release, "git", side_effect=lambda *args: "" if args[0] == "tag" else "commit"
            ),
            patch.object(release, "api", side_effect=self.api),
            patch.object(release, "notes"),
            patch.object(release.Path, "read_text", return_value="notes"),
            patch.object(release.Path, "read_bytes", return_value=b"media"),
            patch.object(release.subprocess, "run") as run,
        ):
            release.publish("base")
            return run.call_args_list

    def test_duplicate_is_read_only(self):
        calls = self.run_publish()
        self.assertFalse(self.mutations)
        self.assertEqual(len(calls), 1)  # ancestry check only

    def test_mismatched_tag_never_mutates(self):
        self.tag_sha = "other"
        with self.assertRaisesRegex(ValueError, "different commit"):
            self.run_publish()
        self.assertFalse(self.mutations)

    def test_mismatched_notes_never_mutates(self):
        self.release["body"] = "other"
        with self.assertRaisesRegex(ValueError, "notes differ"):
            self.run_publish()
        self.assertFalse(self.mutations)

    def test_mismatched_asset_never_overwrites(self):
        self.release["assets"][0]["digest"] = "other"
        with self.assertRaisesRegex(ValueError, "asset mismatch"):
            self.run_publish()
        self.assertFalse(self.mutations)

    def test_requires_merged_version_pr(self):
        self.pull["merged_at"] = None
        with self.assertRaisesRegex(ValueError, "merged version"):
            self.run_publish()
        self.assertFalse(self.mutations)

    def test_draft_prerelease_is_not_latest(self):
        self.version = "1.0.0-rc.1"
        self.pull["head"]["ref"] = "release/v1.0.0-rc.1"
        self.release.update(tag_name="v1.0.0-rc.1", name="v1.0.0-rc.1", prerelease=True, draft=True)
        self.run_publish()
        self.assertEqual(self.mutations, [("releases/1", {"draft": False, "make_latest": "false"})])

    def test_draft_resumes_missing_assets(self):
        self.release.update(draft=True, assets=[])
        calls = self.run_publish()
        self.assertEqual(len(calls), 3)
        self.assertEqual(self.mutations, [("releases/1", {"draft": False, "make_latest": "true"})])


class VersionChangeTests(unittest.TestCase):
    def test_initial_baseline_does_not_publish(self):
        with (
            patch.object(release.Path, "read_text", return_value="0.0.0\n"),
            patch.object(release, "git", return_value=""),
        ):
            self.assertEqual(release.validate_change("a" * 40), ("0.0.0", "0.0.0", False))

    def test_initial_nonzero_version_fails(self):
        with (
            patch.object(release.Path, "read_text", return_value="1.0.0\n"),
            patch.object(release, "git", return_value=""),
            self.assertRaisesRegex(ValueError, "initial VERSION"),
        ):
            release.validate_change("a" * 40)

    def test_mixed_release_changes_fail(self):
        with (
            patch.object(release.Path, "read_text", return_value="1.0.0\n"),
            patch.object(
                release,
                "git",
                side_effect=["commit", "VERSION", "0.0.0", "commit", "VERSION\nlua/change.lua"],
            ),
            self.assertRaisesRegex(ValueError, "only VERSION"),
        ):
            release.validate_change("a" * 40)

    def test_version_only_change_passes(self):
        with (
            patch.object(release.Path, "read_text", return_value="1.0.0\n"),
            patch.object(
                release, "git", side_effect=["commit", "VERSION", "0.0.0", "commit", "VERSION"]
            ),
        ):
            self.assertEqual(release.validate_change("a" * 40), ("1.0.0", "0.0.0", True))
