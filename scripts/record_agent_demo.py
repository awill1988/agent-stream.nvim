#!/usr/bin/env python3
"""Record a live Codex session beside Neovim in an isolated tmux server."""

import argparse
import fcntl
import json
import os
import pty
import select
import shlex
import struct
import subprocess
import tempfile
import termios
import threading
import time
from pathlib import Path


def main():
    repo = Path.cwd()
    root = Path(tempfile.mkdtemp(prefix="as-live-", dir="/tmp"))
    fixture = root / "fixture"
    fixture.mkdir()
    source = repo / "demo/live"
    parser = argparse.ArgumentParser()
    parser.add_argument("--codex-home", type=Path, required=True)
    args = parser.parse_args()
    config = str(args.codex_home.expanduser().resolve())
    if not Path(config).is_dir():
        raise ValueError("codex configuration directory does not exist")
    (fixture / "totals.py").write_text(
        "def sum_positive(numbers):\n    total = 0\n    for number in numbers:\n"
        "        total += number\n    return total\n"
    )
    (fixture / "test_totals.py").write_text((source / "test_totals.py").read_text())
    for stage in ["fix", "cosmetic"]:
        (root / f"{stage}.prompt").write_text((source / f"{stage}.prompt").read_text())
    (root / "agent").write_text("""#!/usr/bin/env bash
    set -uo pipefail
    stage=$1
codex exec --sandbox workspace-write --skip-git-repo-check --ephemeral \\
  --color always -C "$PWD" - < "../$stage.prompt" 2>&1 | tee "../$stage.log"
    result=${PIPESTATUS[0]}
    printf '%s' "$result" > "../$stage.done"
    exit "$result"
    """)
    (root / "agent").chmod(0o755)
    (root / "init.lua").write_text(
        "vim.opt.rtp:prepend("
        + json.dumps(str(repo))
        + ")\n"
        + """
    vim.cmd('runtime plugin/agent-stream.lua')
    vim.o.swapfile = false
    vim.o.cmdheight = 3
    vim.o.number = true
    vim.o.signcolumn = 'yes'
    vim.o.termguicolors = true
    vim.o.laststatus = 2
    vim.o.statusline = ' Neovim | external edits need review '
    vim.cmd.colorscheme('habamax')
    require('agent-stream').setup({rpc={enabled=false},show_explorer_badges=false,
      attribution={check_tmux=false}})
    """
    )
    env = os.environ.copy()
    for key in ["TMUX", "TMUX_PANE", "NVIM", "NVIM_LISTEN_ADDRESS"]:
        env.pop(key, None)
    env.update(TERM="xterm-256color", CODEX_HOME=config, PROFILE_ROUTER_ACTIVE="1", PS1="agent> ")
    for key in [
        "XDG_CONFIG_HOME",
        "XDG_DATA_HOME",
        "XDG_STATE_HOME",
        "XDG_CACHE_HOME",
        "XDG_RUNTIME_DIR",
    ]:
        folder = root / key.lower()
        folder.mkdir(mode=0o700)
        env[key] = str(folder)
    socket = str(root / "nvim.sock")
    tmux = ["tmux", "-L", root.name, "-f", "/dev/null"]

    def tm(*args):
        return subprocess.check_output(tmux + list(args), env=env, text=True).strip()

    def remote(code):
        expr = "luaeval(" + json.dumps(code) + ")"
        return subprocess.check_output(
            ["nvim", "--server", socket, "--remote-expr", expr],
            env=env,
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=5,
        ).strip()

    def state():
        return json.loads(
            remote(
                "(function() local s=require('agent-stream'); "
                "local b=vim.api.nvim_get_current_buf(); "
                "return vim.json.encode({buffer=vim.api.nvim_buf_get_lines(b,0,-1,false),"
                "pending=s.renderer.active_state[b]~=nil}) end)()"
            )
        )

    def wait_for(fn, timeout=240):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                value = fn()
                if value:
                    return value
            except (
                subprocess.CalledProcessError,
                json.JSONDecodeError,
                FileNotFoundError,
                subprocess.TimeoutExpired,
            ):
                pass
            time.sleep(0.15)
        raise RuntimeError("demo condition timed out")

    events = []
    stop = threading.Event()
    process = None
    master = None
    try:
        cmd = shlex.join(
            [
                "nvim",
                "-i",
                "NONE",
                "--noplugin",
                "-u",
                str(root / "init.lua"),
                "--listen",
                socket,
                str(fixture / "totals.py"),
            ]
        )
        left = tm(
            "new-session",
            "-d",
            "-s",
            "showcase",
            "-x",
            "93",
            "-y",
            "29",
            "-c",
            str(fixture),
            "-P",
            "-F",
            "#{pane_id}",
            cmd,
        )
        right = tm(
            "split-window",
            "-h",
            "-p",
            "50",
            "-t",
            left,
            "-c",
            str(fixture),
            "-P",
            "-F",
            "#{pane_id}",
            "bash --noprofile --norc",
        )
        tm("set-option", "-t", "showcase", "status-interval", "0")
        tm("set-option", "-t", "showcase", "status-left-length", "30")
        tm("set-option", "-t", "showcase", "status-right-length", "55")
        tm("set-option", "-t", "showcase", "status-left", " agent-stream.nvim ")
        tm("set-option", "-t", "showcase", "status-right", "Neovim preview | live Codex agent ")
        tm("set-option", "-t", "showcase", "status-style", "bg=colour236,fg=colour252")
        tm("select-pane", "-t", left)
        wait_for(lambda: Path(socket).exists(), 15)
        original = wait_for(state, 15)["buffer"]
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 29, 93, 0, 0))
        start = time.monotonic()
        process = subprocess.Popen(
            tmux + ["attach-session", "-t", "showcase"],
            stdin=slave,
            stdout=slave,
            stderr=slave,
            env=env,
        )
        os.close(slave)

        def read_output():
            while not stop.is_set():
                if select.select([master], [], [], 0.1)[0]:
                    try:
                        data = os.read(master, 65536)
                    except OSError:
                        break
                    if not data:
                        break
                    events.append(
                        [time.monotonic() - start, "o", data.decode("utf-8", errors="replace")]
                    )

        thread = threading.Thread(target=read_output)
        thread.start()
        time.sleep(1)
        for stage in ["fix", "cosmetic"]:
            print("running live agent:", stage, flush=True)
            tm(
                "set-option",
                "-t",
                "showcase",
                "status-right",
                "agent editing | buffer remains unchanged ",
            )
            tm("send-keys", "-t", right, "../agent " + stage, "Enter")
            wait_for(lambda stage=stage: (root / f"{stage}.done").exists())
            assert (root / f"{stage}.done").read_text() == "0", (root / f"{stage}.log").read_text()[
                -2000:
            ]
            preview = wait_for(lambda: state() if state()["pending"] else None, 15)
            assert preview["buffer"] == original
            tm(
                "set-option",
                "-t",
                "showcase",
                "status-right",
                "review external diff | buffer unchanged ",
            )
            time.sleep(5)
            command = "AgentStreamAccept" if stage == "fix" else "AgentStreamReject"
            tm("send-keys", "-t", left, "Escape", ":" + command, "Enter")
            wait_for(lambda: not state()["pending"], 15)
            if stage == "fix":
                original = (fixture / "totals.py").read_text().splitlines()
                assert state()["buffer"] == original
                tm(
                    "set-option",
                    "-t",
                    "showcase",
                    "status-right",
                    "accepted agent fix | buffer updated ",
                )
            else:
                assert (fixture / "totals.py").read_text().splitlines() == original
                tm(
                    "set-option",
                    "-t",
                    "showcase",
                    "status-right",
                    "rejected cosmetic edit | accepted fix preserved ",
                )
            (root / f"{stage}.verified.json").write_text(json.dumps(state(), indent=2))
            time.sleep(5)
        tm("send-keys", "-t", right, "python3 -m unittest -v", "Enter")
        result = subprocess.run(
            ["python3", "-m", "unittest", "-v"], cwd=fixture, capture_output=True, text=True
        )
        assert result.returncode == 0, result.stderr
        time.sleep(5)
        print("verified live accept/reject and 3 passing tests", flush=True)
    finally:
        stop.set()
        if "thread" in globals():
            thread.join(timeout=2)
        if process:
            process.terminate()
            process.wait(timeout=5)
        if master is not None:
            os.close(master)
        subprocess.run(tmux + ["kill-server"], env=env, capture_output=True)
        (repo / ".deps/live-artifact-path").write_text(str(root))
        (root / "raw-events.json").write_text(json.dumps(events))

    # Preserve every output event; compress idle gaps and fit the review excerpt.
    compact = []
    previous = 0
    elapsed = 0
    for timestamp, kind, data in events:
        elapsed += min(timestamp - previous, 2)
        compact.append([elapsed, kind, data])
        previous = timestamp
    scale = 32 / max(elapsed, 0.001)
    header = {
        "version": 2,
        "width": 93,
        "height": 29,
        "title": "agent-stream.nvim: live Codex in tmux, accept and reject",
        "env": {"TERM": "xterm-256color"},
    }
    with (repo / "demo/showcase.cast").open("w") as handle:
        handle.write(json.dumps(header) + "\n")
        for i, (timestamp, kind, data) in enumerate(compact):
            handle.write(
                json.dumps([0 if i == 0 else round(timestamp * scale, 6), kind, data]) + "\n"
            )
        handle.write(json.dumps([35, "o", ""]) + "\n")
    print("recorded live tmux demo; artifacts:", root, flush=True)


if __name__ == "__main__":
    main()
