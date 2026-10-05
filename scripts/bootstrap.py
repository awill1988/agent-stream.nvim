#!/usr/bin/env python3
"""Fetch test dependencies at reviewed immutable commits."""

import os
import subprocess
from pathlib import Path

DEPENDENCIES = {
    "plenary.nvim": ("nvim-lua/plenary.nvim", "74b06c6c75e4eeb3108ec01852001636d85a932b"),
    "luacov": ("lunarmodules/luacov", "2634de4f4ad366ebd266d884eecd01c3ccc61ec8"),
}


def main():
    for name, (repository, revision) in DEPENDENCIES.items():
        if name == "plenary.nvim" and os.environ.get("PLENARY_DIR"):
            if not (Path(os.environ["PLENARY_DIR"]) / "plugin/plenary.vim").is_file():
                raise SystemExit("invalid PLENARY_DIR")
            continue
        target = Path(".deps") / name
        if not target.exists():
            subprocess.run(
                ["git", "clone", "--quiet", f"https://github.com/{repository}", str(target)],
                check=True,
            )
        actual = subprocess.check_output(
            ["git", "-C", str(target), "rev-parse", "HEAD"], text=True
        ).strip()
        if actual != revision:
            subprocess.run(["git", "-C", str(target), "checkout", "--quiet", revision], check=True)
        if subprocess.check_output(["git", "-C", str(target), "status", "--porcelain"], text=True):
            raise SystemExit(f"modified dependency: {target}")


if __name__ == "__main__":
    main()
