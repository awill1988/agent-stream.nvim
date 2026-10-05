import os
import subprocess
import tempfile
import unittest
from pathlib import Path

import release


class ReleaseHistoryTests(unittest.TestCase):
    def setUp(self):
        self.original = Path.cwd()
        self.directory = tempfile.TemporaryDirectory(prefix="release-test-")
        self.addCleanup(self.directory.cleanup)
        self.addCleanup(os.chdir, self.original)
        os.chdir(self.directory.name)
        self.run_git("init", "-q", "-b", "main")
        self.run_git("config", "user.name", "Adam Williams")
        self.run_git("config", "user.email", "adam@williams.engineer")
        self.run_git("config", "commit.gpgsign", "false")
        self.run_git("config", "core.hooksPath", "/dev/null")
        Path("VERSION").write_text("0.0.0\n")
        Path("cliff.toml").write_text((self.original / "cliff.toml").read_text())
        Path(".coverage").mkdir()
        self.commit("chore: initialize")
        self.base = self.run_git("rev-parse", "HEAD")
        Path("VERSION").write_text("0.1.0\n")
        self.commit("chore(release): prepare 0.1.0")

    def run_git(self, *args):
        return subprocess.check_output(["git", *args], text=True).strip()

    def commit(self, message):
        self.run_git("add", "VERSION", "cliff.toml")
        self.run_git("commit", "-q", "-m", message)

    def test_real_version_only_diff(self):
        self.assertEqual(release.validate_change(self.base), ("0.1.0", "0.0.0", True))

    def test_note_recovery_is_identical_after_tag_creation(self):
        release.notes("0.1.0")
        before = Path(".coverage/release-notes.md").read_text()
        self.run_git("-c", "tag.gpgsign=false", "tag", "v0.1.0")
        release.notes("0.1.0")
        self.assertEqual(before, Path(".coverage/release-notes.md").read_text())
        self.assertIn("0.1.0", before)

    def test_notes_after_previous_release_exclude_older_changes(self):
        self.run_git("-c", "tag.gpgsign=false", "tag", "v0.1.0")
        Path("VERSION").write_text("0.2.0\n")
        self.commit("feat: second feature")
        release.notes("0.2.0")
        notes = Path(".coverage/release-notes.md").read_text()
        self.assertIn("second feature", notes)
        self.assertNotIn("initialize", notes)
        self.assertNotIn("prepare 0.1.0", notes)
