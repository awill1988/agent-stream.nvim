#!/usr/bin/env python3
"""Convert and validate the checked-in showcase media."""

import argparse
import json
import subprocess
from pathlib import Path


def convert():
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-i",
            "demo/showcase.mp4",
            "-filter_complex",
            "fps=10,scale=1280:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3",
            "-loop",
            "0",
            "demo/showcase.gif",
        ],
        check=True,
    )


def probe(path):
    return json.loads(
        subprocess.check_output(
            ["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", str(path)],
            text=True,
        )
    )


def check():
    readme = Path("README.md").read_text()
    for name in ("showcase.mp4", "showcase.gif"):
        path = Path("demo") / name
        if str(path) not in readme:
            raise ValueError(f"missing readme reference: {path}")
        info = probe(path)
        video = info["streams"][0]
        duration = float(info["format"]["duration"])
        if not 30 <= duration <= 45 or video["width"] != 1280:
            raise ValueError(f"unexpected dimensions or duration: {path}")
        if path.suffix == ".gif":
            # 8 MiB
            if path.stat().st_size >= 8 * 1024 * 1024:
                raise ValueError("gif exceeds 8 mib")
            if b"NETSCAPE2.0\x03\x01\x00\x00" not in path.read_bytes():
                raise ValueError("gif must loop forever")
            if video["r_frame_rate"] != "10/1":
                raise ValueError("gif must use 10 fps")
        elif video["codec_name"] != "h264" or video["pix_fmt"] != "yuv420p":
            raise ValueError("mp4 must use h264/yuv420p")
        print(f"{path}: {duration:.1f}s, {video['width']}px, {path.stat().st_size} bytes")
    events = [json.loads(line) for line in Path("demo/showcase.cast").read_text().splitlines()]
    if events[0]["version"] != 2 or events[1][0] != 0:
        raise ValueError("cast must begin with restored terminal state")
    times = [event[0] for event in events[1:]]
    if times != sorted(times):
        raise ValueError("cast timestamps are not monotonic")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("convert", "check"))
    args = parser.parse_args()
    convert() if args.command == "convert" else check()
