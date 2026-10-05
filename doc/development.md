# Development

Tests bootstrap Plenary and LuaCov into `.deps/` at pinned commits. Set `PLENARY_DIR` to explicitly use another Plenary checkout. Tests use private configuration, state, sockets, and temporary files.

Install Neovim and Python 3.11 or newer. With Nix installed, the pinned tool environment supplies StyLua, Luacheck, ShellCheck, Actionlint, Ruff, FFmpeg, `git-cliff`, and Gitleaks:

```bash
scripts/tools.sh make check

# Release and debug test modes
make test
make test-debug
make profile-memory

# Interactive isolated editor
make run
make run-debug

# Optional tracked hooks; not enabled automatically
make hooks
```

`make check` runs formatting and lint checks, Python tooling tests, clean-consumer command registration, the regression suite with LuaCov, and media validation. `make coverage` merges process-specific statistics and includes every plugin module, including unexecuted files. Reports are in `.coverage/`; Actions publishes a summary and downloadable reports without an external service or percentage threshold.

Commit hooks enforce conventional lowercase subjects, optional ticket prefixes, 50-character subjects, 72-character body lines, and the repository attribution policy. Disable the opt-in hooks with `git config --local --unset core.hooksPath`.

### Showcase media

`demo/showcase.cast` records Neovim beside live Codex in tmux, with asserted accept/reject transitions. Idle periods are compressed while preserving terminal output. Credentials and raw logs remain outside Git. The recorder creates its own tmux server and leaves existing sessions alone. It requires an authenticated Codex CLI, tmux, and Neovim. `scripts/record_demo.py` and `demo/session.lua` remain a separate scripted fixture; they do not produce the live agent demonstration.

```bash
# Record a new session when intentionally refreshing the demonstration
python3 scripts/record_agent_demo.py --codex-home /path/to/your/codex/config

# Render the checked-in excerpt with VHS, then derive the GIF from the MP4
nix shell github:NixOS/nixpkgs/aa48d347080940b8a2b8d2f48228674e280a3514#vhs \
  github:NixOS/nixpkgs/aa48d347080940b8a2b8d2f48228674e280a3514#ffmpeg \
  -c make demo-media
```

The GIF uses FFmpeg `palettegen` and `paletteuse`, 1280-pixel width, 10 fps, infinite looping, and a size limit of 8 MiB. Ordinary CI validates media and README references. The manual `Render Media` workflow uploads rendered artifacts without committing them. Review both formats at README display size after rendering.

## Code review

Run `make agent-review BASE_REF=origin/main HEAD_REF=HEAD` after committing the proposed changes. This downloads checksum-verified Qwen2.5-Coder 0.5B GGUF weights and uses the pinned Nix `llama.cpp` runner. It requires no hosted model API key. Results are written to `.coverage/agent-review/`.

Every relevant source diff is reviewed in bounded chunks; binary media and generated terminal recordings are excluded. `REQUEST_CHANGES`, missing dependencies, invalid results, or incomplete inference fail the check. No heuristic fallback can approve a review. Findings are fallible and require investigation; deterministic tests remain separate gates. CI publishes summaries and artifacts without posting PR comments.

Pushes compare the previous and new commits; pull requests compare the base and head commits. Manual runs accept an explicit `base_sha` and otherwise review the target commit against its parent. Releases depend on both the test matrix and the review job. Post-push checks cannot prevent a direct push, so run the local review before publishing to `main`.

### Releases

`VERSION` starts at `0.0.0`, which never publishes. Run `Prepare Release` from `main` with an explicit increasing SemVer version, such as `0.1.0` or `0.1.0-rc.1`. It opens a version-only PR and explicitly dispatches CI with `GITHUB_TOKEN`; no personal access token is required. Repository settings must allow Actions to create pull requests.

CI generates a `git-cliff` release-note preview. After the release PR merges, all four Linux/macOS and minimum/stable jobs must pass before publication. The release targets the exact validated merge commit, attaches the MP4 and GIF, and marks prereleases as not latest. Configure branch protection to require the four `check` matrix jobs.

For recovery, dispatch `CI` from `main` with `release_sha` set to the full merged commit ID. This reruns the gates before resuming publication. Existing matching tags and assets are reused; mismatched tags, release metadata, or asset digests fail without overwriting them. A stale preparation branch without an open PR requires manual inspection.
