# Architecture

```
                          ┌────────────────────────────────┐
                          │ External Process / Tmux Pane   │
                          │   (Codex, Claude, Script)      │
                          └──────┬──────────────────┬──────┘
                                 │ write(2)         │ agent-ctl (RPC)
                                 ▼                  ▼
┌──────────────────────────────────────────────┬───────────────────────────────┐
│ Filesystem                                   │ Neovim (agent-stream.nvim)    │
│                                              │                               │
│  [ target_file.lua ] ── vim.uv.fs_event ────►│ Watcher Engine                │
│                                              │      │                        │
│                                              │      ▼                        │
│  [ active buffers  ] ───────────────────────►│ Diff Engine (vim.diff)        │
│                                              │      │                        │
│                                              │      ▼                        │
│  [ tmux / env ] ─── attribution hints ──────►│ Event Stream                  │
│                                              │      │                        │
│                                              │      ├─► Extmarks & VirtLines │
│                                              │      ├─► Sign Column Markers  │
│                                              │      └─► Neo-tree Status Badges│
└──────────────────────────────────────────────┴───────────────────────────────┘
```

### Agent Fingerprinting & Signatures

Standard POSIX metadata (`mtime`, `ctime`, `uid`, `gid`) does not identify which process wrote a file. Attribution is heuristic, not proof of the writer's identity:

1. **Attribution hints**: Uses `AGENT_NAME` when present; otherwise scores tmux panes by command, working-directory prefix, and active status. It does not traverse process ancestry or inspect `/proc`; `check_proc` is currently unused.
2. **Internal-write suppression**: `BufWritePost` suppresses events for that path for 500 ms. This is a timing heuristic, not change-tick isolation, and can suppress an external write in the same window.
3. **Buffer-preserving previews**: Compares disk contents with the buffer and renders virtual lines and gutter signs without changing buffer text or undo history. Accept replaces buffer contents with the previewed disk snapshot; reject overwrites the file with current buffer contents, including unsaved edits.
