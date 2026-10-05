import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import agent_review as review


class ReviewTests(unittest.TestCase):
    def test_changes_requested_fails_after_all_chunks_are_reviewed(self):
        pending = [{"file": "a.lua", "diff": "a"}, {"file": "b.lua", "diff": "b"}]
        answers = [
            {
                "disposition": "REQUEST_CHANGES",
                "findings": [{"file": "a.lua", "line": 1, "detail": "counterexample"}],
            },
            {"disposition": "APPROVE", "findings": []},
        ]
        with (
            tempfile.TemporaryDirectory() as root,
            patch.object(review, "commit", side_effect=lambda x: x),
            patch.object(review, "chunks", return_value=pending),
            patch.object(review.shutil, "which", return_value="runner"),
            patch.object(review, "model", return_value=Path(root) / "model"),
            patch.object(review, "infer", side_effect=answers),
        ):
            output = Path(root) / "report"
            self.assertEqual(3, review.run_review("base", "head", Path(root), output, "runner"))
            result = json.loads((output / "review.json").read_text())
            self.assertTrue(result["complete"])
            self.assertEqual(2, len(result["chunks"]))

    def test_dispositions(self):
        for disposition in ("APPROVE", "COMMENT", "REQUEST_CHANGES"):
            findings = (
                []
                if disposition != "REQUEST_CHANGES"
                else [{"file": "a.lua", "line": 1, "detail": "counterexample"}]
            )
            result = {"disposition": disposition, "findings": findings}
            self.assertEqual(result, review.parse(json.dumps(result), "a.lua"))

    def test_invalid_results_never_approve(self):
        for value in (
            "",
            "approved",
            "{}",
            "null",
            '{"disposition":"APPROVE"}',
            '{"disposition":"REQUEST_CHANGES","findings":[]}',
            '{"disposition":"OTHER","findings":[]}',
        ):
            with self.subTest(value=value), self.assertRaises((ValueError, TypeError)):
                review.parse(value, "a.lua")

    def test_unrelated_finding_is_invalid(self):
        value = {
            "disposition": "REQUEST_CHANGES",
            "findings": [{"file": "another.lua", "line": 1, "detail": "bug"}],
        }
        with self.assertRaises(ValueError):
            review.parse(json.dumps(value), "a.lua")

    def test_chunks_preserve_all_diff_content(self):
        diff = "a" * 14000
        with (
            patch.object(review, "commit", side_effect=lambda x: x),
            patch.object(
                review, "git", side_effect=[b"a.lua\0demo/showcase.cast\0", diff.encode()]
            ),
        ):
            chunks = review.chunks("base", "head")
        self.assertEqual(diff, "".join(c["diff"] for c in chunks))
        self.assertEqual([0, 6000, 12000], [c["offset"] for c in chunks])

    def test_runner_missing_fails_and_reports_incomplete(self):
        with (
            tempfile.TemporaryDirectory() as root,
            patch.object(review, "commit", side_effect=lambda x: x),
            patch.object(review, "chunks", return_value=[{"file": "a.lua"}]),
            patch.object(review.shutil, "which", return_value=None),
        ):
            output = Path(root) / "report"
            with self.assertRaises(RuntimeError):
                review.run_review("base", "head", Path(root), output, "missing")
            self.assertFalse(json.loads((output / "review.json").read_text())["complete"])

    def test_inference_failure_is_not_a_mock_approval(self):
        with (
            tempfile.TemporaryDirectory() as root,
            patch.object(review, "commit", side_effect=lambda x: x),
            patch.object(review, "chunks", return_value=[{"file": "a.lua", "diff": "x"}]),
            patch.object(review.shutil, "which", return_value="runner"),
            patch.object(review, "model", return_value=Path(root) / "model"),
            patch.object(review, "infer", side_effect=TimeoutError("timeout")),
        ):
            output = Path(root) / "report"
            with self.assertRaises(TimeoutError):
                review.run_review("base", "head", Path(root), output, "runner")
            self.assertFalse(json.loads((output / "review.json").read_text())["complete"])

    def test_bad_model_download_rejected(self):
        import io

        with (
            tempfile.TemporaryDirectory() as root,
            patch.object(review, "urlopen", return_value=io.BytesIO(b"invalid model")),
            self.assertRaisesRegex(ValueError, "checksum"),
        ):
            review.model(Path(root))

    def test_workflow_inputs_resolve_to_commits(self):
        with patch.object(review, "git", return_value=b"a" * 40 + b"\n") as git:
            self.assertEqual("a" * 40, review.commit("origin/main"))
            git.assert_called_once_with("rev-parse", "--verify", "origin/main^{commit}")
        with self.assertRaises(ValueError):
            review.commit("--help")

    def test_relevant_paths(self):
        for path in (
            "lua/a.lua",
            "tests/a.lua",
            "scripts/test.py",
            ".github/workflows/ci.yml",
            "Makefile",
        ):
            self.assertTrue(review.relevant(path))
        for path in ("demo/showcase.mp4", "demo/showcase.cast", "README.md"):
            self.assertFalse(review.relevant(path))
