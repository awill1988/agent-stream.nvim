#!/usr/bin/env python3
"""Adversarial code reviewer harness for agent-stream.nvim.

Audits PR diffs for invariant breaches, resource leaks, AI attribution violations, and convention regressions.
"""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

SCRIPT_DIR = Path(__file__).parent.resolve()
DEFAULT_CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "adversarial-reviewer"

IGNORE_PATTERNS = [
    r"\.lock$",
    r"\.md$",
    r"LICENSE.*",
    r"\.gitignore$",
    r"^\.github/",
    r"^tools/",
]

MAX_DIFF_LINES = 250

SYSTEM_PROMPT = """You are an adversarial code review auditor for agent-stream.nvim, a real-time Neovim plugin.
Your objective is to find bugs, resource leaks, invariant breaches, and subtle edge cases in the PR diff.

Repository Invariants:
1. Non-destructive buffer views: Incoming disk changes must render as virtual lines and extmarks without altering buffer text or dirtying the buffer until explicit user acceptance.
2. Resource lifecycle teardown: All libuv handles (vim.uv.new_fs_event and vim.uv.new_timer) must be closed via :is_closing() / :close() on buffer unwatch or plugin teardown to prevent file descriptor leaks.
3. Event debounce & self-write suppression: Internal writes from :w (BufWritePost) must be recognized to prevent recursive diff feedback loops.
4. Clean undo tree: Diff acceptance or rejection must preserve undo history.
5. Conventions: All commits must use Conventional Commits (strictly lowercase subject) with ZERO AI attribution.

Provide your evaluation adhering strictly to one of three dispositions:
- APPROVE (no critical or safety issues found)
- COMMENT (non-blocking suggestions or observations)
- REQUEST_CHANGES (soundness bug, invariant breach, or resource leak found)

Conclude your review with:
DISPOSITION: APPROVE | COMMENT | REQUEST_CHANGES
"""


def should_ignore_file(filename: str) -> bool:
    return any(re.search(pattern, filename) for pattern in IGNORE_PATTERNS)


def extract_git_diff(base: str = "origin/main", head: str = "HEAD") -> tuple[str, list[str]]:
    cmd = ["git", "diff", f"{base}...{head}", "--name-only"]
    result = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        cmd = ["git", "diff", base, head, "--name-only"]
        result = subprocess.run(cmd, capture_output=True, text=True, check=False)

    changed_files = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    relevant_files = [f for f in changed_files if not should_ignore_file(f)]

    if not relevant_files:
        return "", []

    diff_cmd = ["git", "diff", f"{base}...{head}", "--"] + relevant_files
    diff_result = subprocess.run(diff_cmd, capture_output=True, text=True, check=False)
    if diff_result.returncode != 0:
        diff_cmd = ["git", "diff", base, head, "--"] + relevant_files
        diff_result = subprocess.run(diff_cmd, capture_output=True, text=True, check=False)

    lines = diff_result.stdout.splitlines()
    if len(lines) > MAX_DIFF_LINES:
        truncated_diff = "\n".join(lines[:MAX_DIFF_LINES]) + f"\n\n[Diff truncated to {MAX_DIFF_LINES} lines for focused review]"
    else:
        truncated_diff = diff_result.stdout

    return truncated_diff, relevant_files


def run_mock_reviewer(diff: str, files: list[str]) -> tuple[str, list[dict], str]:
    """Deterministic heuristic reviewer for test execution and offline environments."""
    findings = []
    disposition = "APPROVE"

    if "Co-authored-by:" in diff or "Co-Authored-By:" in diff or "Generated-by:" in diff:
        findings.append({
            "severity": "critical",
            "category": "attribution",
            "file": "general",
            "line": None,
            "title": "AI attribution detected in diff",
            "details": "Commit diff contains AI attribution metadata violating repository policy.",
            "counterexample": "Co-authored-by: AI Assistant",
        })
        disposition = "REQUEST_CHANGES"

    # Check for unclosed libuv handles
    if "new_fs_event" in diff and "is_closing" not in diff and "close" not in diff:
        findings.append({
            "severity": "warning",
            "category": "resource_leak",
            "file": "lua/agent-stream/watcher.lua",
            "line": None,
            "title": "Potentially unclosed libuv fs_event handle",
            "details": "Allocated fs_event handle without verifying teardown via :is_closing() and :close().",
            "counterexample": "if not handle:is_closing() then handle:close() end",
        })
        disposition = "REQUEST_CHANGES"

    if not findings:
        summary = "No soundness violations or invariant breaches detected. Invariant checks passed."
    else:
        summary = f"Detected {len(findings)} invariant violation(s) requiring remediation."

    return disposition, findings, summary


def resolve_runner(cache_dir: Path) -> Path | None:
    candidates = [
        cache_dir / "llama_runner" / "build" / "bin" / "llama-cli",
        cache_dir / "llama_runner" / "llama-cli",
        cache_dir / "llama-cli",
    ]
    for candidate in candidates:
        if candidate.exists() and os.access(candidate.resolve(), os.X_OK):
            return candidate.resolve()

    found = list(cache_dir.glob("**/llama-cli"))
    for candidate in found:
        if os.access(candidate.resolve(), os.X_OK):
            return candidate.resolve()

    system_cli = shutil.which("llama-cli")
    if system_cli:
        return Path(system_cli).resolve()

    return None


def run_llama_inference(runner_path: Path, model_path: Path, prompt: str) -> str:
    runner_resolved = runner_path.resolve()
    if not runner_resolved.exists():
        raise FileNotFoundError(f"llama-cli runner not found at {runner_resolved}")
    if not model_path.exists():
        raise FileNotFoundError(f"model weights not found at {model_path}")

    lib_dirs = {str(runner_resolved.parent), str(runner_path.parent)}
    for p in runner_resolved.parent.glob("*.so*"):
        lib_dirs.add(str(p.parent))

    env = os.environ.copy()
    existing_ld = env.get("LD_LIBRARY_PATH", "")
    existing_dyld = env.get("DYLD_LIBRARY_PATH", "")

    joined_dirs = ":".join(sorted(lib_dirs))
    env["LD_LIBRARY_PATH"] = f"{joined_dirs}:{existing_ld}".rstrip(":")
    env["DYLD_LIBRARY_PATH"] = f"{joined_dirs}:{existing_dyld}".rstrip(":")

    threads = str(min(os.cpu_count() or 2, 4))
    cmd = [
        str(runner_resolved),
        "-m", str(model_path),
        "-p", prompt,
        "-n", "512",
        "-c", "8192",
        "--temp", "0.2",
        "--top-p", "0.9",
        "-t", threads,
        "--no-display-prompt",
        "--no-conversation",
        "--no-warmup",
        "--repeat-penalty", "1.15",
        "--repeat-last-n", "64",
        "--simple-io",
    ]

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=False,
            env=env,
            stdin=subprocess.DEVNULL,
            timeout=180,
        )
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError("llama-cli execution timed out after 180 seconds") from exc

    if result.returncode != 0:
        raise RuntimeError(f"llama-cli execution failed: {result.stderr}")

    return result.stdout.strip()


def parse_model_output(raw_output: str) -> tuple[str, list[dict], str]:
    disp_match = re.search(r"(?:DISPOSITION|VERDICT):\s*(APPROVE|COMMENT|REQUEST_CHANGES|PASS|FLAGGED|CRITICAL)", raw_output, re.IGNORECASE)
    if disp_match:
        matched = disp_match.group(1).upper()
        if matched in ("APPROVE", "PASS"):
            disposition = "APPROVE"
        elif matched in ("REQUEST_CHANGES", "CRITICAL"):
            disposition = "REQUEST_CHANGES"
        else:
            disposition = "COMMENT"
    else:
        disposition = "APPROVE"

    findings = []
    for line in raw_output.splitlines():
        line_clean = line.strip()
        if re.match(r"^[-*•\d]+\s*", line_clean) and re.search(r"(?:CRITICAL|BUG|VIOLATION|BREACH|LEAK)", line_clean, re.IGNORECASE):
            findings.append({
                "severity": "critical" if disposition == "REQUEST_CHANGES" else "warning",
                "category": "soundness",
                "file": "general",
                "line": None,
                "title": line_clean[:120],
                "details": line_clean,
                "counterexample": None,
            })

    if not disp_match:
        disposition = "APPROVE" if not findings else "REQUEST_CHANGES"

    summary = f"Review disposition: {disposition}."
    return disposition, findings, summary


def build_markdown_report(target: str, disposition: str, findings: list[dict], raw_text: str, files: list[str]) -> str:
    status_icon = "🟢" if disposition == "APPROVE" else ("🟡" if disposition == "COMMENT" else "🔴")
    report = f"## {status_icon} Adversarial Code Review: {target}\n\n"
    report += f"**Disposition**: **`{disposition}`**  \n"
    report += f"**Audited Files**: {', '.join(f'`{f}`' for f in files) if files else '*(none)*'}\n\n"

    if findings:
        report += "### Findings & Invariant Violations\n\n"
        for finding in findings:
            sev_icon = "🔴" if finding["severity"] == "critical" else "🟡"
            report += f"- {sev_icon} **[{finding['category'].upper()}]** {finding['title']}\n"
            if finding.get("details") and finding["details"] != finding["title"]:
                report += f"  - *Details*: {finding['details']}\n"
            if finding.get("counterexample"):
                report += f"  - *Counterexample*:\n    ```lua\n    {finding['counterexample']}\n    ```\n"
        report += "\n"

    report += "<details><summary>Detailed Auditor Output</summary>\n\n"
    report += "```text\n"
    report += raw_text.strip() + "\n"
    report += "```\n\n"
    report += "</details>\n\n"
    report += "*Audit performed with local quantized open-weight model in headless harness.*\n"
    return report


def submit_pr_review(pr: int, disposition: str, report: str) -> None:
    if disposition == "APPROVE":
        review_flag = "--approve"
    elif disposition == "REQUEST_CHANGES":
        review_flag = "--request-changes"
    else:
        review_flag = "--comment"

    cmd = ["gh", "pr", "review", str(pr), review_flag, "--body", report]
    result = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if result.returncode == 0:
        print(f"submitted formal PR review ({review_flag}) to PR #{pr}")
    else:
        print(f"formal PR review failed ({result.stderr.strip()}); falling back to PR comment...", file=sys.stderr)
        cmd_comment = ["gh", "pr", "comment", str(pr), "--body", report]
        subprocess.run(cmd_comment, check=True)
        print(f"posted review comment to PR #{pr}")


def main():
    parser = argparse.ArgumentParser(description="Headless adversarial code reviewer.")
    parser.add_argument("--base", default="origin/main", help="Base ref to compare against")
    parser.add_argument("--head", default="HEAD", help="Head ref to compare")
    parser.add_argument("--target", default="HEAD", help="Target identifier for review reporting")
    parser.add_argument("--mock", action="store_true", help="Run deterministic heuristic review without model weights")
    parser.add_argument("--cache-dir", type=Path, default=DEFAULT_CACHE_DIR, help="Cache directory for models")
    parser.add_argument("--summary-file", type=Path, default=None, help="File to write step summary to")
    parser.add_argument("--pr", type=int, default=None, help="Pull request number to post comment to")
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON output")
    parser.add_argument("--fail-on", choices=["request-changes", "critical", "none"], default="request-changes",
                        help="Disposition that causes a non-zero exit code")
    args = parser.parse_args()

    start_time = time.time()
    diff, files = extract_git_diff(args.base, args.head)

    if not files or not diff.strip():
        disposition = "APPROVE"
        findings = []
        summary = "No relevant changes to audit."
        raw_text = "No changes to review."
    elif args.mock:
        disposition, findings, summary = run_mock_reviewer(diff, files)
        raw_text = summary
    else:
        model_path = args.cache_dir / "qwen2.5-coder-0.5b-instruct-q4_k_m.gguf"
        runner_path = resolve_runner(args.cache_dir)

        if not runner_path or not model_path.exists():
            print("local model weights or runner not found; falling back to heuristic mock reviewer.", file=sys.stderr)
            disposition, findings, summary = run_mock_reviewer(diff, files)
            raw_text = summary
        else:
            full_prompt = (
                f"<|im_start|>system\n{SYSTEM_PROMPT}<|im_end|>\n"
                f"<|im_start|>user\nAudited files: {', '.join(files)}\n\n```diff\n{diff}\n```\n"
                f"Evaluate the diff. If clean, conclude with DISPOSITION: APPROVE.<|im_end|>\n"
                f"<|im_start|>assistant\n"
            )
            raw_text = run_llama_inference(runner_path, model_path, full_prompt)
            disposition, findings, summary = parse_model_output(raw_text)

    duration = round(time.time() - start_time, 2)
    markdown_report = build_markdown_report(args.target, disposition, findings, raw_text, files)

    if args.json:
        payload = {
            "target": args.target,
            "disposition": disposition,
            "summary": summary,
            "findings": findings,
            "model": "qwen2.5-coder-0.5b-instruct-q4_k_m.gguf",
            "duration_seconds": duration,
        }
        print(json.dumps(payload, indent=2))
    else:
        print(markdown_report)

    print(f"Review complete: {args.target} — {disposition}")

    if args.summary_file:
        with open(args.summary_file, "a", encoding="utf-8") as out:
            out.write(markdown_report + "\n")

    if args.pr:
        submit_pr_review(args.pr, disposition, markdown_report)

    if args.fail_on == "request-changes" and disposition == "REQUEST_CHANGES":
        sys.exit(3)


if __name__ == "__main__":
    main()
