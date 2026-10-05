import unittest

from release import decision, version_key


class ReleaseTests(unittest.TestCase):
    def test_unchanged(self):
        for version in ("0.0.0", "1.0.0", "1.2.3-rc.1"):
            self.assertFalse(decision(version, version, "commit"))

    def test_increases(self):
        for current, previous in (
            ("0.1.0", "0.0.0"),
            ("1.0.0", "1.0.0-rc.1"),
            ("1.0.0-rc.10", "1.0.0-rc.2"),
        ):
            self.assertTrue(decision(current, previous, "commit"))

    def test_invalid(self):
        for version in ("v1.0.0", "01.0.0", "1.0", "1.0.0-01", "1.0.0\n", "1.0.0-", ""):
            with self.subTest(version=version), self.assertRaises(ValueError):
                version_key(version)

    def test_downgrade_and_equal_precedence(self):
        for current, previous in (
            ("0.0.0", "1.0.0"),
            ("1.0.0-rc.1", "1.0.0"),
            ("1.0.0+b", "1.0.0+a"),
        ):
            with self.assertRaises(ValueError):
                decision(current, previous, "commit")

    def test_duplicate_and_mismatched_tag(self):
        release = {"tag_name": "v1.0.0", "prerelease": False}
        self.assertTrue(decision("1.0.0", "0.0.0", "commit", "commit", release))
        for tag in (None, "other"):
            with self.assertRaises(ValueError):
                decision("1.0.0", "0.0.0", "commit", tag, release)
        with self.assertRaises(ValueError):
            decision("1.0.0", "0.0.0", "commit", "other")

    def test_prerelease_state(self):
        release = {"tag_name": "v1.0.0-rc.1", "prerelease": True}
        self.assertTrue(decision("1.0.0-rc.1", "0.0.0", "commit", "commit", release))
        release["prerelease"] = False
        with self.assertRaises(ValueError):
            decision("1.0.0-rc.1", "0.0.0", "commit", "commit", release)
