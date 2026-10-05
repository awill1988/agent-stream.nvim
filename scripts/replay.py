#!/usr/bin/env python3
"""Replay recorded terminal output with its original relative timing."""

import json
import sys
import termios
import time
import tty
from pathlib import Path


def main():
    terminal = termios.tcgetattr(sys.stdin.fileno())
    tty.setraw(sys.stdin.fileno())
    try:
        events = [json.loads(line) for line in Path(sys.argv[1]).read_text().splitlines()][1:]
        start = time.monotonic()
        for timestamp, kind, data in events:
            time.sleep(max(0, start + timestamp - time.monotonic()))
            if kind == "o":
                sys.stdout.write(data)
                sys.stdout.flush()
        time.sleep(2)
    finally:
        termios.tcsetattr(sys.stdin.fileno(), termios.TCSANOW, terminal)


if __name__ == "__main__":
    main()
