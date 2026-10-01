-- renderer.lua: non-destructive extmark decoration for buffer diffs
local M = {}

--- Namespace for all agent-stream buffer decorations
M.ns_id = vim.api.nvim_create_namespace("agent_stream")

--- Active diff states per buffer
---@type table<number, { diff_result: DiffResult, positions: number[], current_index: number }>
M.active_state = {}

--- Clear decorations and state for a buffer
---@param bufnr number
function M.clear(bufnr)
	if vim.api.nvim_buf_is_valid(bufnr) then
		vim.api.nvim_buf_clear_namespace(bufnr, M.ns_id, 0, -1)
	end
	M.active_state[bufnr] = nil
end

--- Clamp row to valid buffer line range
---@param bufnr number
---@param row number 0-indexed row
---@return number
local function clamp_row(bufnr, row)
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	if line_count == 0 then
		return 0
	end
	return math.max(0, math.min(row, line_count - 1))
end

--- Render diff decorations onto a buffer
---@param bufnr number
---@param diff_result DiffResult
---@param attribution AttributionInfo|nil
function M.render_diff(bufnr, diff_result, attribution)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local config = require("agent-stream.config").get()
	vim.api.nvim_buf_clear_namespace(bufnr, M.ns_id, 0, -1)

	local positions = {}
	local line_count = vim.api.nvim_buf_line_count(bufnr)

	-- Top-of-buffer summary badge
	local attr_label = attribution and attribution.details or "external"
	local stats_label = string.format("+%d -%d ~%d", diff_result.stats.added, diff_result.stats.deleted, diff_result.stats.changed)
	local summary_text = string.format(" 󰚩 [agent-stream: %s | %s] (<leader>aa accept / <leader>ar reject) ", attr_label, stats_label)

	pcall(vim.api.nvim_buf_set_extmark, bufnr, M.ns_id, 0, 0, {
		virt_lines = {
			{ { summary_text, "AgentStreamBadge" } },
		},
		virt_lines_above = true,
	})

	for _, hunk in ipairs(diff_result.hunks) do
		local hunk_line = math.max(1, hunk.orig_start)
		table.insert(positions, hunk_line)

		if hunk.type == "add" then
			local row = hunk.orig_start == 0 and 0 or clamp_row(bufnr, hunk.orig_start - 1)
			local virt_lines = {}

			if config.show_virtual_lines then
				for _, line in ipairs(hunk.new_lines) do
					table.insert(virt_lines, { { "+ " .. line, "AgentStreamAdd" } })
				end
			end

			local extmark_opts = {
				virt_lines = #virt_lines > 0 and virt_lines or nil,
				virt_lines_above = (hunk.orig_start == 0),
			}

			if config.show_signs then
				extmark_opts.sign_text = config.signs.add
				extmark_opts.sign_hl_group = "AgentStreamSignAdd"
			end

			pcall(vim.api.nvim_buf_set_extmark, bufnr, M.ns_id, row, 0, extmark_opts)

		elseif hunk.type == "delete" then
			for i = 0, math.max(0, hunk.orig_count - 1) do
				local row = clamp_row(bufnr, (hunk.orig_start - 1) + i)
				local extmark_opts = {
					line_hl_group = "AgentStreamDelete",
				}
				if config.show_signs and i == 0 then
					extmark_opts.sign_text = config.signs.delete
					extmark_opts.sign_hl_group = "AgentStreamSignDelete"
				end
				pcall(vim.api.nvim_buf_set_extmark, bufnr, M.ns_id, row, 0, extmark_opts)
			end

		elseif hunk.type == "change" then
			local first_row = clamp_row(bufnr, hunk.orig_start - 1)
			local virt_lines = {}

			if config.show_virtual_lines then
				for _, line in ipairs(hunk.new_lines) do
					table.insert(virt_lines, { { "➜ " .. line, "AgentStreamAdd" } })
				end
			end

			for i = 0, math.max(0, hunk.orig_count - 1) do
				local row = clamp_row(bufnr, (hunk.orig_start - 1) + i)
				local extmark_opts = {
					line_hl_group = "AgentStreamChange",
				}
				if i == 0 then
					if #virt_lines > 0 then
						extmark_opts.virt_lines = virt_lines
						extmark_opts.virt_lines_above = false
					end
					if config.show_signs then
						extmark_opts.sign_text = config.signs.change
						extmark_opts.sign_hl_group = "AgentStreamSignChange"
					end
				end
				pcall(vim.api.nvim_buf_set_extmark, bufnr, M.ns_id, row, 0, extmark_opts)
			end
		end
	end

	M.active_state[bufnr] = {
		diff_result = diff_result,
		positions = positions,
		current_index = 1,
	}
end

--- Navigate to next or previous hunk in buffer
---@param bufnr number
---@param direction 1|-1
function M.jump_hunk(bufnr, direction)
	local state = M.active_state[bufnr]
	if not state or #state.positions == 0 then
		vim.notify("agent-stream: no active diff hunks in buffer", vim.log.levels.INFO)
		return
	end

	local new_index = state.current_index + direction
	if new_index > #state.positions then
		new_index = 1
	elseif new_index < 1 then
		new_index = #state.positions
	end

	state.current_index = new_index
	local target_line = state.positions[new_index]
	local win = vim.fn.bufwinid(bufnr)
	if win ~= -1 then
		vim.api.nvim_win_set_cursor(win, { target_line, 0 })
	end
end

return M
