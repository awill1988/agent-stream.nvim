local M = {}

-- Invariant: accept commits disk state into buffer memory; reject overwrites disk state with buffer memory.

---@type table<number, { timer: any, attribution: table, accepted_lines: string[], cancelled: boolean }>
M.optimistic = {}

local function emit_state()
	vim.api.nvim_exec_autocmds("User", { pattern = "AgentStreamStateChanged", modeline = false })
end

local function stop_timer(state)
	if state.timer and not state.timer:is_closing() then
		state.timer:stop()
		state.timer:close()
	end
end

local function finish_optimistic(bufnr)
	local state = M.optimistic[bufnr]
	if not state then
		return false
	end
	stop_timer(state)
	M.optimistic[bufnr] = nil
	require("agent-stream.renderer").clear(bufnr)
	emit_state()
	return true
end

local function countdown(bufnr)
	local state = M.optimistic[bufnr]
	if not state then
		return
	end
	local remaining = math.max(0, state.deadline - vim.uv.now())
	local label = string.format("agent-stream: accepting in %.1fs · :AgentStreamCancel", remaining / 1000)
	require("agent-stream.renderer").render_status(bufnr, label)
	emit_state()
end

---@param diff_result DiffResult
---@return number
function M.get_first_changed_line(diff_result)
	if not diff_result or not diff_result.hunks or #diff_result.hunks == 0 then
		return 1
	end
	local first_hunk = diff_result.hunks[1]
	local line = first_hunk.new_start
	if not line or line < 1 then
		line = first_hunk.orig_start or 1
	end
	line = math.max(1, line)
	if diff_result.disk_lines and #diff_result.disk_lines > 0 then
		line = math.min(line, #diff_result.disk_lines)
	end
	return line
end

---@param bufnr number
---@param diff_result DiffResult
function M.navigate_to_first_change(bufnr, diff_result)
	local first_line = M.get_first_changed_line(diff_result)
	for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
		if vim.api.nvim_win_is_valid(win) then
			pcall(vim.api.nvim_win_call, win, function()
				vim.fn.winrestview({ topline = first_line, lnum = first_line, col = 0 })
			end)
		end
	end
end

---@param bufnr number
---@param diff_result DiffResult
---@param attribution table
function M.optimistic_accept(bufnr, diff_result, attribution)
	local current = M.optimistic[bufnr]
	if current then
		stop_timer(current)
	end
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, diff_result.disk_lines)
	vim.bo[bufnr].modified = false
	require("agent-stream.renderer").clear(bufnr)
	M.navigate_to_first_change(bufnr, diff_result)
	local grace_period_ms = require("agent-stream.config").get().review.grace_period_ms
	local state = {
		timer = vim.uv.new_timer(),
		attribution = attribution,
		accepted_lines = vim.deepcopy(diff_result.disk_lines),
		deadline = vim.uv.now() + grace_period_ms,
		cancelled = false,
	}
	M.optimistic[bufnr] = state
	countdown(bufnr)
	state.timer:start(
		0,
		100,
		vim.schedule_wrap(function()
			if M.optimistic[bufnr] ~= state then
				return
			end
			if vim.uv.now() >= state.deadline then
				finish_optimistic(bufnr)
				vim.notify("agent-stream: accepted external changes", vim.log.levels.INFO)
				return
			end
			countdown(bufnr)
		end)
	)
end

---@param bufnr number
function M.on_local_edit(bufnr)
	local state = M.optimistic[bufnr]
	if not state or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	if vim.deep_equal(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), state.accepted_lines) then
		return
	end
	stop_timer(state)
	M.optimistic[bufnr] = nil
	require("agent-stream.renderer").clear(bufnr)
	emit_state()
end

---@param bufnr number
function M.clear(bufnr)
	finish_optimistic(bufnr)
end

---@param bufnr? number
function M.accept(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if finish_optimistic(bufnr) then
		vim.notify("agent-stream: accepted external changes", vim.log.levels.INFO)
		return
	end
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

	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, disk_lines)
	renderer.clear(bufnr)
	require("agent-stream.explorer").clear_badge(state.diff_result.file)

	vim.notify("agent-stream: accepted external changes", vim.log.levels.INFO)
end

---@param bufnr? number
function M.cancel(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local state = M.optimistic[bufnr]
	if not state then
		vim.notify("agent-stream: no optimistic task to cancel", vim.log.levels.INFO)
		return
	end
	stop_timer(state)
	state.cancelled = true
	require("agent-stream.renderer").render_status(bufnr, "agent-stream: interrupting agent…")
	require("agent-stream.task_control").interrupt(state.attribution, function(ok, err)
		if M.optimistic[bufnr] ~= state then
			return
		end
		if not ok then
			vim.notify(err, vim.log.levels.ERROR)
			require("agent-stream.renderer").render_status(bufnr, "agent-stream: agent task was not interrupted")
			emit_state()
			return
		end
		require("agent-stream.renderer").render_status(bufnr, "agent-stream: interrupted · :AgentStreamResume")
		emit_state()
	end)
end

---@param bufnr? number
function M.resume(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local state = M.optimistic[bufnr]
	if not state or not state.cancelled then
		vim.notify("agent-stream: no interrupted task to resume", vim.log.levels.INFO)
		return
	end
	require("agent-stream.renderer").render_status(bufnr, "agent-stream: resuming agent…")
	require("agent-stream.task_control").resume(state.attribution, function(ok, err)
		if M.optimistic[bufnr] ~= state then
			return
		end
		if not ok then
			vim.notify(err, vim.log.levels.ERROR)
			require("agent-stream.renderer").render_status(bufnr, "agent-stream: agent task was not resumed")
			return
		end
		finish_optimistic(bufnr)
		vim.notify("agent-stream: resumed agent task", vim.log.levels.INFO)
	end)
end

---@param bufnr? number
---@return string
function M.statusline(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local state = M.optimistic[bufnr]
	if not state then
		return ""
	end
	if state.cancelled then
		return "agent: interrupted"
	end
	return string.format("agent: %.1fs", math.max(0, state.deadline - vim.uv.now()) / 1000)
end

---@param bufnr? number
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

---@param bufnr? number
function M.next_hunk(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	require("agent-stream.renderer").jump_hunk(bufnr, 1)
end

---@param bufnr? number
function M.prev_hunk(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	require("agent-stream.renderer").jump_hunk(bufnr, -1)
end

return M
