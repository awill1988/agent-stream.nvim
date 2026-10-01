-- actions.lua: user and programmatic actions to accept, reject, and navigate diffs
local M = {}

--- Accept incoming disk changes and update buffer
---@param bufnr? number Target buffer (defaults to current buffer)
function M.accept(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local renderer = require("agent-stream.renderer")
	local state = renderer.active_state[bufnr]

	if not state or not state.diff_result then
		vim.notify("agent-stream: no incoming diff to accept", vim.log.levels.INFO)
		return
	end

	local disk_lines = state.diff_result.disk_lines
	if not disk_lines then
		local filepath = state.diff_result.file
		local content = vim.fn.readfile(filepath)
		disk_lines = content
	end

	-- Apply lines to buffer
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, disk_lines)
	renderer.clear(bufnr)

	-- Notify file explorer of resolution
	require("agent-stream.explorer").clear_badge(state.diff_result.file)

	vim.notify("agent-stream: accepted external changes", vim.log.levels.INFO)
end

--- Reject incoming disk changes by overwriting disk with current buffer content
---@param bufnr? number Target buffer (defaults to current buffer)
function M.reject(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local renderer = require("agent-stream.renderer")
	local state = renderer.active_state[bufnr]

	if not state or not state.diff_result then
		vim.notify("agent-stream: no incoming diff to reject", vim.log.levels.INFO)
		return
	end

	local filepath = state.diff_result.file
	local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	-- Overwrite disk with buffer text
	local success, err = pcall(function()
		local content = table.concat(buf_lines, "\n") .. "\n"
		local fd = assert(vim.uv.fs_open(filepath, "w", 438 --[[ 0666 ]]))
		assert(vim.uv.fs_write(fd, content, 0))
		assert(vim.uv.fs_close(fd))
	end)

	if not success then
		vim.notify(string.format("agent-stream: failed to overwrite disk file: %s", err), vim.log.levels.ERROR)
		return
	end

	renderer.clear(bufnr)
	require("agent-stream.explorer").clear_badge(filepath)

	vim.notify("agent-stream: rejected external changes; restored buffer version to disk", vim.log.levels.WARN)
end

--- Navigate to next diff hunk
---@param bufnr? number
function M.next_hunk(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	require("agent-stream.renderer").jump_hunk(bufnr, 1)
end

--- Navigate to previous diff hunk
---@param bufnr? number
function M.prev_hunk(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	require("agent-stream.renderer").jump_hunk(bufnr, -1)
end

return M
