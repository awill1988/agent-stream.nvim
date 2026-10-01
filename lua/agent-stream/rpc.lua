-- rpc.lua: remote procedure call endpoints for external agent control
local M = {}

--- Namespace for temporary agent highlights and annotations
M.ns_id = vim.api.nvim_create_namespace("agent_stream_rpc")

--- Find or open a buffer for a given filepath
---@param filepath string
---@return number bufnr
local function ensure_buffer(filepath)
	local norm = vim.fs.normalize(vim.fn.fnamemodify(filepath, ":p"))
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(b) and vim.fs.normalize(vim.api.nvim_buf_get_name(b)) == norm then
			return b
		end
	end

	vim.cmd.edit(norm)
	return vim.api.nvim_get_current_buf()
end

--- Focus a file and navigate cursor
---@param filepath string Path to file
---@param line? number 1-indexed target line
---@param col? number 0-indexed target column
---@return boolean success
function M.focus(filepath, line, col)
	local bufnr = ensure_buffer(filepath)

	-- Switch to window displaying buffer if available
	local win = vim.fn.bufwinid(bufnr)
	if win ~= -1 then
		vim.api.nvim_set_current_win(win)
	else
		vim.api.nvim_set_current_buf(bufnr)
	end

	if line and line > 0 then
		local line_count = vim.api.nvim_buf_line_count(bufnr)
		local target_row = math.min(line, math.max(1, line_count))
		local target_col = col or 0
		pcall(vim.api.nvim_win_set_cursor, 0, { target_row, target_col })
	end

	return true
end

--- Reveal a file in file explorer (neo-tree or netrw)
---@param filepath string
---@return boolean
function M.reveal(filepath)
	local norm = vim.fs.normalize(vim.fn.fnamemodify(filepath, ":p"))
	local ok, _ = pcall(function()
		vim.cmd("Neotree reveal_file=" .. vim.fn.fnameescape(norm))
	end)
	return ok
end

--- Temporarily highlight a line range
---@param filepath string
---@param start_line number
---@param end_line number
---@param duration_ms? number
---@param hl_group? string
function M.highlight(filepath, start_line, end_line, duration_ms, hl_group)
	local bufnr = ensure_buffer(filepath)
	duration_ms = duration_ms or 1500
	hl_group = hl_group or "Visual"

	local line_count = vim.api.nvim_buf_line_count(bufnr)
	local s = math.max(0, math.min(start_line - 1, line_count - 1))
	local e = math.max(s, math.min(end_line - 1, line_count - 1))

	local ids = {}
	for row = s, e do
		local id = vim.api.nvim_buf_set_extmark(bufnr, M.ns_id, row, 0, {
			line_hl_group = hl_group,
		})
		table.insert(ids, id)
	end

	vim.defer_fn(function()
		if vim.api.nvim_buf_is_valid(bufnr) then
			for _, id in ipairs(ids) do
				pcall(vim.api.nvim_buf_del_extmark, bufnr, M.ns_id, id)
			end
		end
	end, duration_ms)
end

--- Annotate a buffer with a temporary agent message
---@param filepath string
---@param line number
---@param message string
---@param duration_ms? number
function M.annotate(filepath, line, message, duration_ms)
	local bufnr = ensure_buffer(filepath)
	duration_ms = duration_ms or 5000

	local line_count = vim.api.nvim_buf_line_count(bufnr)
	local row = math.max(0, math.min(line - 1, line_count - 1))

	local id = vim.api.nvim_buf_set_extmark(bufnr, M.ns_id, row, 0, {
		virt_lines = {
			{ { string.format(" 󰚩 [agent]: %s", message), "AgentStreamBadge" } },
		},
		virt_lines_above = true,
	})

	vim.defer_fn(function()
		if vim.api.nvim_buf_is_valid(bufnr) then
			pcall(vim.api.nvim_buf_del_extmark, bufnr, M.ns_id, id)
		end
	end, duration_ms)
end

--- Register server socket rendezvous file for CLI control
function M.setup()
	local servername = vim.v.servername
	if not servername or servername == "" then
		return
	end

	local uid = vim.uv.getuid()
	local rendezvous_path = string.format("/tmp/agent-stream-%s.server", uid)
	local f = io.open(rendezvous_path, "w")
	if f then
		f:write(servername)
		f:close()
	end
end

return M
