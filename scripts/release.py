#!/usr/bin/env python3
"""Version-only release preparation and fail-closed publication."""

import argparse
import base64
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import Request, urlopen

SEMVER = re.compile(
    r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
)


def version_key(value):
    match = SEMVER.fullmatch(value)
    if not match:
        raise ValueError(f"invalid semver: {value}")
    pre = match[4]
    identifiers = []
    for item in pre.split(".") if pre else []:
        if item.isdecimal():
            if len(item) > 1 and item.startswith("0"):
                raise ValueError("numeric prerelease identifiers cannot have leading zeros")
            identifiers.append((0, int(item)))
        else:
            identifiers.append((1, item))
    return tuple(map(int, match.group(1, 2, 3))), pre is None, tuple(identifiers)


def decision(current, previous, sha, tag_sha=None, release=None):
    current_key, previous_key = version_key(current), version_key(previous)
    if current_key < previous_key:
        raise ValueError("version downgrade")
    if current == previous:
        return False
    if current_key == previous_key:
        raise ValueError("version must increase semver precedence")
    if current == "0.0.0":
        return False
    if tag_sha is not None and tag_sha != sha:
        raise ValueError("tag points at a different commit")
    if release is not None:
        if tag_sha != sha or release["tag_name"] != f"v{current}":
            raise ValueError("release does not match the validated tag")
        if release["prerelease"] != (not current_key[1]):
            raise ValueError("release prerelease state mismatch")
    return True


def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()


def api(path, data=None, method=None, missing=False):
    request = Request(
        f"https://api.github.com/repos/{os.environ['GITHUB_REPOSITORY']}/{path}",
        data=json.dumps(data).encode() if data is not None else None,
        method=method,
        headers={
            "Authorization": f"Bearer {os.environ['GH_TOKEN']}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    try:
        with urlopen(request, timeout=30) as response:
            body = response.read()
            return json.loads(body) if body else None
    except HTTPError as error:
        if error.code == 404 and missing:
            return None
        raise


def validate_change(base):
    if not re.fullmatch(r"[0-9a-f]{40}", base):
        raise ValueError("base must be a full commit id")
    current = Path("VERSION").read_text().strip()
    git("rev-parse", "--verify", f"{base}^{{commit}}")
    if not git("ls-tree", "--name-only", base, "VERSION"):
        if current != "0.0.0":
            raise ValueError("initial VERSION must be 0.0.0")
        return current, "0.0.0", False
    previous = git("show", f"{base}:VERSION")
    release = decision(current, previous, git("rev-parse", "HEAD"))
    if release and git("diff", "--name-only", base, "HEAD").splitlines() != ["VERSION"]:
        raise ValueError("release change must modify only VERSION")
    return current, previous, release


def notes(version):
    tags = git("tag", "--merged", "HEAD^", "--list", "v*").splitlines()
    tags = [tag for tag in tags if version_key(tag[1:]) < version_key(version)]
    previous = max(tags, key=lambda tag: version_key(tag[1:])) if tags else None
    head = git("rev-parse", "HEAD")
    revision = f"{previous}..{head}" if previous else head
    subprocess.run(
        [
            "git-cliff",
            "--config",
            "cliff.toml",
            revision,
            "--tag",
            f"v{version}",
            "--strip",
            "header",
            "--output",
            ".coverage/release-notes.md",
        ],
        check=True,
    )


def prepare(version):
    from commit_check import validate

    previous = Path("VERSION").read_text().strip()
    if not decision(version, previous, git("rev-parse", "HEAD")):
        raise ValueError("release version must increase")
    title = f"chore(release): prepare {version}"
    validate(title)
    branch = f"release/v{version}"
    base = git("rev-parse", "HEAD")
    owner = os.environ["GITHUB_REPOSITORY"].split("/")[0]
    pulls = api(f"pulls?state=open&head={quote(owner + ':' + branch)}&base=main")
    if pulls:
        pull = pulls[0]
    else:
        if api(f"git/ref/heads/{quote(branch, safe='/')}", missing=True):
            raise ValueError("release branch already exists without an open pull request")
        api("git/refs", {"ref": f"refs/heads/{branch}", "sha": base})
        blob = api("contents/VERSION?ref=" + base)
        api(
            "contents/VERSION",
            {
                "message": title,
                "content": base64.b64encode((version + "\n").encode()).decode(),
                "sha": blob["sha"],
                "branch": branch,
            },
            method="PUT",
        )
        body = (
            f"Sets `VERSION` to `{version}`. Merging publishes the validated commit "
            "after all release gates pass.\n\nAffected module: release metadata."
            "\n\nManual steps: none."
        )
        pull = api("pulls", {"title": title, "head": branch, "base": "main", "body": body})
    if pull["title"] != title:
        raise ValueError("existing pull request title differs")
    api(
        "actions/workflows/ci.yml/dispatches",
        {"ref": branch, "inputs": {"base_sha": pull["base"]["sha"]}},
    )
    print(pull["html_url"])


def publish(base):
    version, previous, changed = validate_change(base)
    if not changed:
        print("version unchanged; no release")
        return
    sha = git("rev-parse", "HEAD")
    subprocess.run(["git", "merge-base", "--is-ancestor", sha, "origin/main"], check=True)
    pulls = api(f"commits/{sha}/pulls")
    if not any(
        p["merged_at"]
        and p["base"]["ref"] == "main"
        and p["head"]["ref"] == f"release/v{version}"
        and p["merge_commit_sha"] == sha
        for p in pulls
    ):
        raise ValueError("commit is not a merged version pull request")
    tag = f"v{version}"
    ref = api(f"git/ref/tags/{quote(tag)}", missing=True)
    tag_sha = None
    if ref:
        obj = ref["object"]
        while obj["type"] == "tag":
            obj = api(f"git/tags/{obj['sha']}")["object"]
        tag_sha = obj["sha"]
    release = api(f"releases/tags/{quote(tag)}", missing=True)
    decision(version, previous, sha, tag_sha, release)
    notes(version)
    expected_notes = Path(".coverage/release-notes.md").read_text()
    if release and (release["name"] != tag or release["body"] != expected_notes):
        raise ValueError("release title or notes differ from the validated commit")
    for existing_tag in git("tag", "--list", "v*").splitlines():
        if version_key(existing_tag[1:]) > version_key(version):
            raise ValueError("a newer version is already tagged")
    if not ref:
        api("git/refs", {"ref": f"refs/tags/{tag}", "sha": sha})
    if release is None:
        release = api(
            "releases",
            {
                "tag_name": tag,
                "target_commitish": sha,
                "name": tag,
                "body": expected_notes,
                "draft": True,
                "prerelease": not version_key(version)[1],
            },
        )
    for path in (Path("demo/showcase.mp4"), Path("demo/showcase.gif")):
        existing = next((a for a in release["assets"] if a["name"] == path.name), None)
        digest = "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()
        if existing:
            if existing.get("digest") != digest:
                raise ValueError(f"release asset mismatch: {path.name}")
            continue
        if not release["draft"]:
            raise ValueError("published release is missing an asset")
        subprocess.run(["gh", "release", "upload", tag, str(path)], check=True)
    if release["draft"]:
        api(
            f"releases/{release['id']}",
            {"draft": False, "make_latest": "false" if not version_key(version)[1] else "true"},
            method="PATCH",
        )
    print(f"release {tag} matches {sha}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("prepare", "preview", "publish"))
    parser.add_argument("--version")
    parser.add_argument("--base")
    args = parser.parse_args()
    Path(".coverage").mkdir(exist_ok=True)
    if args.command == "prepare":
        prepare(args.version)
    elif args.command == "preview":
        version, _, changed = validate_change(args.base)
        if changed:
            notes(version)
    else:
        publish(args.base)


if __name__ == "__main__":
    main()
