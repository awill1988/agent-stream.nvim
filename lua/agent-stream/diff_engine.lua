local M = {}

---@class DiffHunk
---@field type "add"|"delete"|"change"
---@field orig_start number
---@field orig_count number
---@field new_start number
---@field new_count number
---@field new_lines string[]
---@field orig_lines string[]

---@class DiffStats
---@field added number
---@field deleted number
---@field changed number

---@class DiffResult
---@field bufnr number
---@field file string
---@field hunks DiffHunk[]
---@field stats DiffStats
---@field disk_lines string[]

-- Invariant: buffer text is immutable during diffing; raw disk lines are compared against memory buffers to emit non-destructive hunk deltas.

M.listeners = {
	diff_updated = {},
	diff_cleared = {},
}

function M.on(event, fn)
	if not M.listeners[event] then
		M.listeners[event] = {}
	end
	table.insert(M.listeners[event], fn)
end

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

function M.emit(event, payload)
	local list = M.listeners[event]
	if not list then
		return
	end
	for _, fn in ipairs(list) do
		pcall(fn, payload)
	end
end

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
