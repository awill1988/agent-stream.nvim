import unittest

from commit_check import validate


class CommitTests(unittest.TestCase):
    def test_valid(self):
        for message in (
            "feat: add preview",
            "[ABC-12] fix: preserve buffer",
            "chore(release): prepare 1.2.3",
            "fix!: remove fallback\n\nA body with context.",
        ):
            with self.subTest(message=message):
                validate(message)

    def test_invalid(self):
        for message in (
            "",
            "Fix: bug",
            "fix: Bug",
            "fix: " + "x" * 46,
            "fix: bug\nbody",
            "fix: bug\n\n" + "x" * 73,
            "fix: bug\n\nCo-Authored-By: someone",
            "fix: bug\n\nGenerated-By: tool",
            "fix: bug\n\nAssisted-By: tool",
            "fix: bug\n\n🤖 Reviewed with Claude Code",
        ):
            with self.subTest(message=message), self.assertRaises(ValueError):
                validate(message)

    def test_boundaries(self):
        validate("fix: " + "x" * 45 + "\n\n" + "x" * 72)
