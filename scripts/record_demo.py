#!/usr/bin/env python3
"""Record the real, asserted demo session into an asciicast v2 file."""

import fcntl
import json
import os
import pty
import select
import struct
import subprocess
import tempfile
import termios
import time
from pathlib import Path


def main():
    # Match the terminal grid rendered by demo/showcase.tape.
    columns, rows = 93, 29
    with tempfile.TemporaryDirectory(prefix="as-demo-", dir="/tmp") as directory:
        env = os.environ.copy()
        for name in ("TMUX", "TMUX_PANE", "NVIM", "NVIM_LISTEN_ADDRESS", "AGENT_NAME", "AGENT_PID"):
            env.pop(name, None)
        env.update(
            TERM="xterm-256color",
            DEMO_FILE=f"{directory}/greet.lua",
            DEMO_ERROR=f"{directory}/error",
        )
        for name in (
            "XDG_CONFIG_HOME",
            "XDG_DATA_HOME",
            "XDG_STATE_HOME",
            "XDG_CACHE_HOME",
            "XDG_RUNTIME_DIR",
        ):
            env[name] = directory
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0))
        start = time.monotonic()
        process = subprocess.Popen(
            ["nvim", "-i", "NONE", "--noplugin", "-u", "demo/session.lua"],
            stdin=slave,
            stdout=slave,
            stderr=slave,
            env=env,
        )
        os.close(slave)
        events = []
        try:
            while process.poll() is None:
                if time.monotonic() - start > 45:
                    raise RuntimeError("demo exceeded deadline")
                if select.select([master], [], [], 0.1)[0]:
                    data = os.read(master, 65536)
                    if data:
                        events.append(
                            [
                                round(time.monotonic() - start, 6),
                                "o",
                                data.decode("utf-8", errors="replace"),
                            ]
                        )
            if process.returncode:
                raise RuntimeError(
                    Path(env["DEMO_ERROR"]).read_text()
                    if Path(env["DEMO_ERROR"]).exists()
                    else str(events[-5:])
                )
        finally:
            if process.poll() is None:
                process.kill()
            process.wait()
            os.close(master)
        # Keep the full startup state at time zero; omit terminal teardown.
        output = []
        initial = ""
        for timestamp, kind, data in events:
            if timestamp < 1:
                initial += data
            elif timestamp < 35.8:
                output.append([timestamp - 1, kind, data])
        header = {
            "version": 2,
            "width": columns,
            "height": rows,
            "title": "agent-stream.nvim: accept and reject",
            "env": {"TERM": "xterm-256color"},
        }
        with Path("demo/showcase.cast").open("w") as handle:
            for row in (header, [0, "o", initial], *output, [35, "o", ""]):
                handle.write(json.dumps(row) + "\n")


if __name__ == "__main__":
    main()
