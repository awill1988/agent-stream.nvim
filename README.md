# agent-stream.nvim

A Neovim plugin that monitors, streams, and decorates file modifications made by external processes and autonomous agents (e.g. background LLMs, tmux workers, or CLI tools) in real time without requiring agent modifications or editor locking.

## Architecture

```
                          ┌────────────────────────────────┐
                          │ External Process / Tmux Pane   │
                          │   (Codex, Claude, Script)      │
                          └──────┬──────────────────┬──────┘
                                 │ write(2)         │ agent-ctl (RPC)
                                 ▼                  ▼
┌──────────────────────────────────────────────┬───────────────────────────────┐
│ Linux Filesystem                             │ Neovim (agent-stream.nvim)    │
│                                              │                               │
│  [ target_file.lua ] ── vim.uv.fs_event ────►│ Watcher Engine                │
│                                              │      │                        │
│                                              │      ▼                        │
│  [ active buffers  ] ───────────────────────►│ Diff Engine (vim.diff)        │
│                                              │      │                        │
│                                              │      ▼                        │
│  [ tmux /proc ] ──── process attribution ───►│ Event Stream                  │
│                                              │      │                        │
│                                              │      ├─► Extmarks & VirtLines │
│                                              │      ├─► Sign Column Markers  │
│                                              │      └─► Neo-tree Status Badges│
└──────────────────────────────────────────────┴───────────────────────────────┘
```

### Agent Fingerprinting & Signatures

Standard POSIX metadata (`mtime`, `ctime`, `uid`, `gid`) does not distinguish between an automated agent and a human user running within the same user principal. `agent-stream.nvim` solves this through:

1. **Tmux Sibling Tracking**: Inspects sibling pane process hierarchies (`tmux list-panes`) to associate disk writes with active agent processes (e.g. `codex`, `claude`, `aider`, `python`).
2. **Buffer Change-Tick Isolation**: Distinguishes internal edits (`BufWritePost` / `b:changedtick`) from external writes.
3. **Decoupled Diff Engine**: Generates real-time unified hunk events and renders them non-destructively as virtual lines and gutter signs, leaving the buffer text and undo tree intact until explicitly accepted or rejected.

---

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "awill1988/agent-stream.nvim",
  config = function()
    require("agent-stream").setup({
      debounce_ms = 150,
      auto_reload_unmodified = false,
      show_signs = true,
      show_virtual_lines = true,
      show_explorer_badges = true,
      attribution = {
        enabled = true,
        check_tmux = true,
        check_proc = true,
      },
      explorer = {
        provider = "neo-tree",
      },
      keymaps = {
        accept = "<leader>aa",
        reject = "<leader>ar",
        next_hunk = "]a",
        prev_hunk = "[a",
      },
    })
  end,
}
```

---

## Keybindings

| Keybinding | Action |
| :--- | :--- |
| `<leader>aa` | **Accept**: Applies external changes cleanly into the buffer |
| `<leader>ar` | **Reject**: Restores buffer version and rewrites file to disk |
| `]a` | Jump to next external diff hunk |
| `[a` | Jump to previous external diff hunk |

---

## Commands

- `:AgentStreamAccept [bufnr]` - Accept external changes into buffer
- `:AgentStreamReject [bufnr]` - Reject external changes and preserve buffer
- `:AgentStreamNextHunk` - Jump to next hunk
- `:AgentStreamPrevHunk` - Jump to previous hunk
- `:AgentStreamClear` - Clear visual decorations on current buffer
- `:AgentStreamFocus <file> [line] [col]` - Focus file and position cursor
- `:AgentStreamReveal <file>` - Reveal target file in file explorer
- `:AgentStreamHighlight <file> <start> <end> [ms]` - Temporarily highlight lines
- `:AgentStreamAnnotate <file> <line> <message>` - Render virtual comment from agent
- `:AgentStreamStatus` - Display active watches, diffs, and server socket

---

## Neo-Tree Integration

To display real-time change badges in `neo-tree.nvim`, register the component:

```lua
require("neo-tree").setup({
  filesystem = {
    components = {
      agent_stream_badge = require("agent-stream.explorer.neo_tree").component,
    },
    renderers = {
      file = {
        { "icon" },
        { "name", use_git_status_colors = true },
        { "agent_stream_badge" },
      },
    },
  },
})
```

---

## CLI Control (`agent-ctl`)

A standalone CLI script is included under `bin/agent-ctl` for automated scripts, git hooks, and tmux sessions:

```bash
# Focus Neovim on file and jump to line 42
agent-ctl focus src/main.rs 42 0

# Reveal file in tree
agent-ctl reveal src/main.rs

# Flash a highlight over edited region for 2 seconds
agent-ctl highlight src/main.rs 40 45 2000

# Display a virtual banner from agent
agent-ctl annotate src/main.rs 42 "refactoring error handling"
```

---

## Development & Testing

```bash
# Run tests
make test

# Run tests in debug mode
make test-debug

# Run memory profiling
make profile-memory

# Check syntax
make lint
```

## License

MIT
