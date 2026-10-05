#!/usr/bin/env python3
"""Run Neovim with private configuration, state, and sockets."""

import os
import subprocess
import sys
import tempfile
from pathlib import Path


def main():
    arguments = sys.argv[1:]
    plugin_flags = ["--noplugin"]
    if "--consumer" in arguments:
        arguments.remove("--consumer")
        plugin_flags = []
    with tempfile.TemporaryDirectory(prefix="as-", dir="/tmp") as directory:
        env = os.environ.copy()
        for key in (
            "TMUX",
            "TMUX_PANE",
            "NVIM",
            "NVIM_SERVER",
            "NVIM_LISTEN_ADDRESS",
            "AGENT_NAME",
            "AGENT_PID",
            "VIMINIT",
            "EXINIT",
            "LUA_INIT",
        ):
            env.pop(key, None)
        for key in (
            "XDG_CONFIG_HOME",
            "XDG_DATA_HOME",
            "XDG_STATE_HOME",
            "XDG_CACHE_HOME",
            "XDG_RUNTIME_DIR",
        ):
            path = Path(directory) / key.lower()
            path.mkdir(mode=0o700)
            env[key] = str(path)
        env["NVIM_APPNAME"] = "agent-stream-test"
        env["NVIM_LOG_FILE"] = str(Path(directory) / "nvim.log")
        result = subprocess.run(
            [env.get("NVIM_BIN", "nvim"), "-i", "NONE", *plugin_flags, *arguments], env=env
        )
        if result.returncode and Path(env["NVIM_LOG_FILE"]).exists():
            print(Path(env["NVIM_LOG_FILE"]).read_text(), file=sys.stderr)
        return result.returncode


if __name__ == "__main__":
    sys.exit(main())
