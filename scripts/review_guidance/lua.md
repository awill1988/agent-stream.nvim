# Lua and Neovim review

This project targets Neovim 0.11.7 or newer and LuaJIT's Lua 5.1 semantics.
Review observable behavior, using the complete file to resolve declarations
and control flow before drawing a conclusion from a diff excerpt.

## Lua semantics

- Locals are lexically scoped. A local declared inside a loop body is a new
  binding each iteration; closures retain that iteration's binding. Creating
  callbacks inside a loop is valid. A shared variable declared outside the
  loop can have different behavior: trace its actual assignments.
- Only `nil` and `false` are false; `0` and empty strings are true.
- Assigning `nil` removes a table entry. Removing existing entries during
  `pairs` iteration is permitted; inserting new entries has different rules.
- Functions compare by identity. Two separately created closures need not
  be equal, even if their bodies match.

[Lua 5.1 reference](https://www.lua.org/manual/5.1/manual.html#2.6)

## Neovim contracts

- `vim.keymap.set` replaces a mapping for the same mode and key. Repeated
  setup does not append duplicate mappings. Cleanup should remove mappings
  the plugin still owns and preserve mappings replaced by the user. Comparing
  the current callback with the saved callback is an ownership check.
- `nvim_create_augroup(name, { clear = true })` clears that group's old
  autocmds. `nvim_get_keymap` returns mapping descriptions, including callbacks.
- `nvim_set_option_value` supports explicit buffer-local scope. Restoring a
  saved local option and preserving a later user override are separate cases.
- libuv callbacks may require `vim.schedule` or `vim.schedule_wrap` before
  editor API access. Trace every asynchronous boundary and its validity checks.
  Synchronous Lua statements are not automatically separate event-loop turns.
- A validity guard after each asynchronous callback can protect against a
  detached buffer. Follow the guard before claiming a stale-buffer access.
- Extmarks and virtual lines decorate a buffer without modifying its text.
  A preview must preserve local edits; explicit accept/reject can change text.

[Neovim Lua API](https://neovim.io/doc/user/lua.html)
and [editor API](https://neovim.io/doc/user/api.html)

## Plenary tests

Plenary's `before_each(fn)` and `after_each(fn)` store callbacks in tables.
Its `it(description, fn)` runs the stored setup hooks, calls `fn`, then runs
the stored cleanup hooks. Hook declarations therefore belong BEFORE `it`.
Calling `after_each(fn)` registers `fn`; it does not execute `fn` immediately.
This is valid:

```lua
describe("buffer", function()
  local buf
  after_each(function() vim.api.nvim_buf_delete(buf, { force = true }) end)
  it("creates a buffer", function() buf = vim.api.nvim_create_buf(false, true) end)
end)
```

The buffer is created first and deleted afterward. Moving this hook below
`it` would leave that test without registered cleanup. Resolve variables from
the enclosing suite and setup hooks. Positive behavior and lifecycle cleanup
are valid assertions; a test need not contain a failing input.

[Pinned Plenary test runner](https://github.com/nvim-lua/plenary.nvim/blob/74b06c6c75e4eeb3108ec01852001636d85a932b/lua/plenary/busted.lua#L142-L176)

## Finding evidence

For a blocking finding, name the changed operation, the concrete trigger,
the violated contract, and the observed incorrect outcome. For example, a
timer callback that writes to a deleted buffer without a validity guard can
raise an API error. A loop-local closure alone does not demonstrate a defect.
These rules do not approve a file: report a defect when the execution trace
demonstrates it. When surrounding context is unavailable, identify the
uncertainty instead of inventing a missing declaration or implementation.
