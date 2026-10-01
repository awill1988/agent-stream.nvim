import unittest
from pathlib import Path
from unittest.mock import patch

from adversarial_review import (
    build_markdown_report,
    parse_model_output,
    run_mock_reviewer,
    should_ignore_file,
    submit_pr_review,
)
from fetch_model import load_env

SCRIPT_DIR = Path(__file__).parent.resolve()


class AdversarialReviewerTests(unittest.TestCase):
    def test_should_ignore_file(self):
        self.assertTrue(should_ignore_file("README.md"))
        self.assertTrue(should_ignore_file("LICENSE"))
        self.assertTrue(should_ignore_file(".gitignore"))
        self.assertTrue(should_ignore_file(".github/workflows/adversarial-review.yml"))
        self.assertTrue(should_ignore_file("tools/adversarial_reviewer/model.env"))

        self.assertFalse(should_ignore_file("lua/agent-stream/watcher.lua"))
        self.assertFalse(should_ignore_file("lua/agent-stream/diff_engine.lua"))
        self.assertFalse(should_ignore_file("plugin/agent-stream.lua"))
        self.assertFalse(should_ignore_file("bin/agent-ctl"))

    def test_mock_reviewer_passes_clean_diff(self):
        diff = "+ local res = vim.diff(s1, s2)"
        disp, findings, summary = run_mock_reviewer(diff, ["lua/agent-stream/diff_engine.lua"])
        self.assertEqual(disp, "APPROVE")
        self.assertEqual(len(findings), 0)
        self.assertIn("No soundness violations", summary)

    def test_mock_reviewer_flags_ai_attribution(self):
        diff = "+ Co-authored-by: assistant <assistant@ai.com>"
        disp, findings, _ = run_mock_reviewer(diff, ["lua/agent-stream/init.lua"])
        self.assertEqual(disp, "REQUEST_CHANGES")
        self.assertTrue(any(f["category"] == "attribution" for f in findings))

    def test_mock_reviewer_flags_unclosed_handle(self):
        diff = "+ local handle = vim.uv.new_fs_event()\n+ handle:start(path)"
        disp, findings, _ = run_mock_reviewer(diff, ["lua/agent-stream/watcher.lua"])
        self.assertEqual(disp, "REQUEST_CHANGES")
        self.assertTrue(any(f["category"] == "resource_leak" for f in findings))

    def test_parse_model_output_dispositions(self):
        disp, _, _ = parse_model_output("Review complete.\nDISPOSITION: APPROVE")
        self.assertEqual(disp, "APPROVE")

        disp, _, _ = parse_model_output("Critical flaw found.\nDISPOSITION: REQUEST_CHANGES")
        self.assertEqual(disp, "REQUEST_CHANGES")

        disp, _, _ = parse_model_output("Minor suggestion.\nDISPOSITION: COMMENT")
        self.assertEqual(disp, "COMMENT")

    def test_build_markdown_report_formatting(self):
        findings = [{
            "severity": "critical",
            "category": "soundness",
            "file": "lua/agent-stream/watcher.lua",
            "line": 42,
            "title": "Unclosed fs_event handle",
            "details": "Handle never closed on buffer wipeout",
            "counterexample": "handle:close()",
        }]
        report = build_markdown_report("PR #1", "REQUEST_CHANGES", findings, "raw output", ["lua/agent-stream/watcher.lua"])
        self.assertIn("## 🔴 Adversarial Code Review: PR #1", report)
        self.assertIn("`REQUEST_CHANGES`", report)
        self.assertIn("[SOUNDNESS]", report)
        self.assertIn("handle:close()", report)

    def test_load_model_env_parses_attributes(self):
        config = load_env(SCRIPT_DIR / "model.env")
        self.assertIn("MODEL_NAME", config)
        self.assertIn("MODEL_SHA256", config)
        self.assertIn("PRIMARY_MODEL_URL", config)
        self.assertEqual(config["MODEL_NAME"], "qwen2.5-coder-0.5b-instruct-q4_k_m.gguf")

    @patch("adversarial_review.subprocess.run")
    def test_submit_pr_review_flags(self, mock_run):
        mock_run.return_value.returncode = 0

        submit_pr_review(1, "APPROVE", "body")
        mock_run.assert_called_with(["gh", "pr", "review", "1", "--approve", "--body", "body"], capture_output=True, text=True, check=False)

        submit_pr_review(1, "REQUEST_CHANGES", "body")
        mock_run.assert_called_with(["gh", "pr", "review", "1", "--request-changes", "--body", "body"], capture_output=True, text=True, check=False)

        submit_pr_review(1, "COMMENT", "body")
        mock_run.assert_called_with(["gh", "pr", "review", "1", "--comment", "--body", "body"], capture_output=True, text=True, check=False)


if __name__ == "__main__":
    unittest.main()
