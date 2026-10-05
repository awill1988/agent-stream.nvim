#!/usr/bin/env python3
"""Validate commit messages without rewriting them."""

import argparse
import re
import subprocess
from pathlib import Path

SUBJECT = re.compile(
    r"^(?:\[[A-Z][A-Z0-9]*-\d+\] )?"
    r"(?:feat|fix|refactor|chore|docs|test|ci|build|perf|style|revert)"
    r"(?:\([a-z0-9_-]+\))?!?: [a-z0-9].*$"
)
FORBIDDEN = re.compile(
    r"co-authored-by\s*:|generated-by\s*:|assisted-by\s*:|reviewed with (?:claude|codex)|🤖|"
    r"(?:generated|assisted|reviewed) (?:by|with) (?:claude|codex|chatgpt|openai|gemini|an? ai)",
    re.I,
)


def validate(message):
    lines = message.strip().splitlines()
    if not lines or not SUBJECT.fullmatch(lines[0]):
        raise ValueError("expected a conventional lowercase subject")
    subject = re.sub(r"^\[[A-Z][A-Z0-9]*-\d+\] ", "", lines[0])
    if subject != subject.lower():
        raise ValueError("subject must be lowercase")
    if len(lines[0]) > 50:
        raise ValueError("subject exceeds 50 characters")
    if len(lines) > 1 and lines[1]:
        raise ValueError("separate subject and body with a blank line")
    if any(len(line) > 72 for line in lines[1:]):
        raise ValueError("body exceeds 72 characters")
    if FORBIDDEN.search(message):
        raise ValueError("prohibited attribution")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("message", nargs="?", type=Path)
    parser.add_argument("--range", nargs=2, metavar=("BASE", "HEAD"))
    parser.add_argument("--title")
    args = parser.parse_args()
    if args.message:
        validate(args.message.read_text())
    if args.title:
        validate(args.title)
    if args.range:
        for revision in args.range:
            if not re.fullmatch(r"[0-9a-f]{40}", revision):
                raise ValueError("range requires full commit ids")
        commits = subprocess.check_output(
            ["git", "rev-list", "--no-merges", "..".join(args.range)], text=True
        ).splitlines()
        for commit in commits:
            validate(
                subprocess.check_output(["git", "show", "-s", "--format=%B", commit], text=True)
            )


if __name__ == "__main__":
    main()
