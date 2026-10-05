local M = {}

-- Seam: external processes communicate via Neovim RPC socket rendezvous at /tmp/agent-stream-<uid>.server.

M.ns_id = vim.api.nvim_create_namespace("agent_stream_rpc")

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

---@param filepath string
---@param line? number
---@param col? number
---@return boolean
function M.focus(filepath, line, col)
	local bufnr = ensure_buffer(filepath)

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

---@param filepath string
---@return boolean
function M.reveal(filepath)
	if require("agent-stream.config").get().explorer.provider ~= "neo-tree" then
		return false
	end
	local norm = vim.fs.normalize(vim.fn.fnamemodify(filepath, ":p"))
	local ok, _ = pcall(function()
		vim.cmd("Neotree reveal_file=" .. vim.fn.fnameescape(norm))
	end)
	return ok
end

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

---@param filepath string
---@param line number
---@param message string
---@param duration_ms? number
function M.annotate(filepath, line, message, duration_ms)
	local bufnr = ensure_buffer(filepath)
	duration_ms = duration_ms or 5000

	local line_count = vim.api.nvim_buf_line_count(bufnr)
	local row = math.max(0, math.min(line - 1, line_count - 1))
	local badge = require("agent-stream.config").get().symbols.badge

	local id = vim.api.nvim_buf_set_extmark(bufnr, M.ns_id, row, 0, {
		virt_lines = {
			{ { string.format(" %s[agent]: %s", badge == "" and "" or badge .. " ", message), "AgentStreamBadge" } },
		},
		virt_lines_above = true,
	})

	vim.defer_fn(function()
		if vim.api.nvim_buf_is_valid(bufnr) then
			pcall(vim.api.nvim_buf_del_extmark, bufnr, M.ns_id, id)
		end
	end, duration_ms)
end

function M.setup()
	if not require("agent-stream.config").get().rpc.enabled then
		return
	end
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
