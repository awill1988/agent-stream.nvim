-- diff_engine.lua: line-level diff calculation and event streaming
local M = {}

---@class DiffHunk
---@field type "add"|"delete"|"change"
---@field orig_start number 1-indexed start line in original buffer
---@field orig_count number Number of lines in original buffer
---@field new_start number 1-indexed start line in new disk content
---@field new_count number Number of lines in new disk content
---@field new_lines string[] Lines from disk content
---@field orig_lines string[] Lines from original buffer

---@class DiffStats
---@field added number Total added lines
---@field deleted number Total deleted lines
---@field changed number Total modified lines

---@class DiffResult
---@field bufnr number Neovim buffer handle
---@field file string Absolute path to file
---@field hunks DiffHunk[] List of parsed hunks
---@field stats DiffStats Aggregated modification counts
---@field disk_lines string[] Raw lines read from disk

--- Event listeners map
---@type table<string, function[]>
M.listeners = {
	diff_updated = {},
	diff_cleared = {},
}

--- Register an event listener
---@param event "diff_updated"|"diff_cleared"
---@param fn function
function M.on(event, fn)
	if not M.listeners[event] then
		M.listeners[event] = {}
	end
	table.insert(M.listeners[event], fn)
end

--- Unregister an event listener
---@param event "diff_updated"|"diff_cleared"
---@param fn function
function M.off(event, fn)
	local list = M.listeners[event]
	if not list then
		return
	end
	for i = #list, 1, -1 do
		if list[i] == fn then
			table.remove(list, i)
		end
	end
end

--- Dispatch event to listeners
---@param event "diff_updated"|"diff_cleared"
---@param payload any
function M.emit(event, payload)
	local list = M.listeners[event]
	if not list then
		return
	end
	for _, fn in ipairs(list) do
		pcall(fn, payload)
	end
end

--- Split text into lines, handling CRLF and trailing newline
---@param text string
---@return string[]
local function text_to_lines(text)
	if text == "" then
		return {}
	end
	local normalized = text:gsub("\r\n", "\n")
	if normalized:sub(-1) == "\n" then
		normalized = normalized:sub(1, -2)
	end
	return vim.split(normalized, "\n", { plain = true })
end

--- Compute diff hunks between buffer lines and disk lines
---@param orig_lines string[] Buffer lines
---@param new_lines string[] Disk lines
---@return DiffHunk[], DiffStats
function M.compute_hunks(orig_lines, new_lines)
	local orig_text = #orig_lines > 0 and (table.concat(orig_lines, "\n") .. "\n") or ""
	local new_text = #new_lines > 0 and (table.concat(new_lines, "\n") .. "\n") or ""

	local raw_indices = vim.diff(orig_text, new_text, {
		result_type = "indices",
		algorithm = "histogram",
	}) or {}

	local hunks = {}
	local stats = { added = 0, deleted = 0, changed = 0 }

	for _, raw in ipairs(raw_indices) do
		local start_a, count_a, start_b, count_b = raw[1], raw[2], raw[3], raw[4]
		local hunk_type = "change"

		if count_a == 0 and count_b > 0 then
			hunk_type = "add"
			stats.added = stats.added + count_b
		elseif count_a > 0 and count_b == 0 then
			hunk_type = "delete"
			stats.deleted = stats.deleted + count_a
		else
			hunk_type = "change"
			stats.changed = stats.changed + math.max(count_a, count_b)
		end

		local slice_new = {}
		if count_b > 0 then
			for i = start_b, start_b + count_b - 1 do
				table.insert(slice_new, new_lines[i] or "")
			end
		end

		local slice_orig = {}
		if count_a > 0 then
			for i = start_a, start_a + count_a - 1 do
				table.insert(slice_orig, orig_lines[i] or "")
			end
		end

		table.insert(hunks, {
			type = hunk_type,
			orig_start = start_a,
			orig_count = count_a,
			new_start = start_b,
			new_count = count_b,
			new_lines = slice_new,
			orig_lines = slice_orig,
		})
	end

	return hunks, stats
end

--- Read a file asynchronously using libuv
---@param filepath string
---@param callback fun(err: string|nil, content: string|nil)
function M.read_file_async(filepath, callback)
	vim.uv.fs_open(filepath, "r", 438 --[[ 0666 ]], function(err_open, fd)
		if err_open or not fd then
			callback(err_open or "failed to open file", nil)
			return
		end

		vim.uv.fs_fstat(fd, function(err_stat, stat)
			if err_stat or not stat then
				vim.uv.fs_close(fd, function() end)
				callback(err_stat or "failed to stat file", nil)
				return
			end

			local size = stat.size
			if size == 0 then
				vim.uv.fs_close(fd, function() end)
				callback(nil, "")
				return
			end

			vim.uv.fs_read(fd, size, 0, function(err_read, data)
				vim.uv.fs_close(fd, function() end)
				if err_read then
					callback(err_read, nil)
					return
				end
				callback(nil, data or "")
			end)
		end)
	end)
end

--- Compare disk file with loaded buffer and stream events
---@param bufnr number
---@param filepath string
---@param callback? fun(result: DiffResult|nil)
function M.diff_file_with_buffer(bufnr, filepath, callback)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		if callback then
			callback(nil)
		end
		return
	end

	M.read_file_async(filepath, function(err, content)
		if err or not content then
			if callback then
				callback(nil)
			end
			return
		end

		vim.schedule(function()
			if not vim.api.nvim_buf_is_valid(bufnr) then
				if callback then
					callback(nil)
				end
				return
			end

			local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
			local disk_lines = text_to_lines(content)
			local hunks, stats = M.compute_hunks(buf_lines, disk_lines)

			if #hunks == 0 then
				M.emit("diff_cleared", {
					bufnr = bufnr,
					file = filepath,
				})
				if callback then
					callback(nil)
				end
				return
			end

			---@type DiffResult
			local result = {
				bufnr = bufnr,
				file = filepath,
				hunks = hunks,
				stats = stats,
				disk_lines = disk_lines,
			}

			M.emit("diff_updated", result)

			if callback then
				callback(result)
			end
		end)
	end)
end

return M
