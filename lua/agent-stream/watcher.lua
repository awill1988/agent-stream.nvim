-- watcher.lua: libuv filesystem event management for loaded buffers
local M = {}

--- Watch entries per canonical path
---@type table<string, { handle: any, bufs: table<number, boolean>, timer: any }>
M.watches = {}

--- Timestamp of internal buffer writes to suppress self-diffing
---@type table<string, number>
M.internal_writes = {}

--- Normalize file path to canonical absolute string
---@param path string
---@return string
function M.normalize_path(path)
	if not path or path == "" then
		return ""
	end
	return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

--- Mark file as having an internal write event
---@param filepath string
function M.mark_internal_write(filepath)
	local norm = M.normalize_path(filepath)
	if norm ~= "" then
		M.internal_writes[norm] = vim.uv.now()
	end
end

--- Check if file was recently modified by Neovim itself
---@param filepath string
---@return boolean
function M.is_internal_write(filepath)
	local norm = M.normalize_path(filepath)
	local last = M.internal_writes[norm]
	if last and (vim.uv.now() - last) < 500 then
		return true
	end
	return false
end

--- Process file change after debounce window
---@param path string
---@param bufnr number
local function process_file_change(path, bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local config = require("agent-stream.config").get()
	local diff_engine = require("agent-stream.diff_engine")
	local attribution = require("agent-stream.attribution")
	local renderer = require("agent-stream.renderer")
	local explorer = require("agent-stream.explorer")

	diff_engine.diff_file_with_buffer(bufnr, path, function(diff_result)
		if not diff_result then
			renderer.clear(bufnr)
			explorer.clear_badge(path)
			return
		end

		attribution.detect(path, function(attr_info)
			-- Auto-reload if configured and buffer is unmodified
			local is_modified = vim.api.nvim_get_option_value("modified", { buf = bufnr })
			if config.auto_reload_unmodified and not is_modified then
				vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, diff_result.disk_lines)
				renderer.clear(bufnr)
				explorer.clear_badge(path)
				vim.notify(
					string.format("agent-stream: auto-reloaded clean buffer (%s)", attr_info.details),
					vim.log.levels.INFO
				)
				return
			end

			-- Render decorations
			renderer.render_diff(bufnr, diff_result, attr_info)
			explorer.set_badge(path, diff_result.stats, attr_info)
		end)
	end)
end

--- Attach watcher to a buffer's underlying file
---@param bufnr number
function M.watch_buffer(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local buftype = vim.api.nvim_get_option_value("buftype", { buf = bufnr })
	if buftype ~= "" then
		return
	end

	local raw_path = vim.api.nvim_buf_get_name(bufnr)
	if raw_path == "" then
		return
	end

	local path = M.normalize_path(raw_path)
	if vim.fn.filereadable(path) ~= 1 then
		return
	end

	local config = require("agent-stream.config").get()

	-- If already watching this path, link the buffer
	if M.watches[path] then
		M.watches[path].bufs[bufnr] = true
		return
	end

	local handle = vim.uv.new_fs_event()
	if not handle then
		return
	end

	local timer = vim.uv.new_timer()
	M.watches[path] = {
		handle = handle,
		bufs = { [bufnr] = true },
		timer = timer,
	}

	handle:start(path, {}, function(err, filename, events)
		if err then
			return
		end

		-- Filter out internal writes from :w
		if M.is_internal_write(path) then
			return
		end

		-- Debounce rapid edits
		if timer and not timer:is_closing() then
			timer:stop()
			timer:start(config.debounce_ms, 0, vim.schedule_wrap(function()
				local entry = M.watches[path]
				if not entry then
					return
				end
				for b, _ in pairs(entry.bufs) do
					process_file_change(path, b)
				end
			end))
		end
	end)
end

--- Unwatch buffer and release handle if no other buffers watch the path
---@param bufnr number
function M.unwatch_buffer(bufnr)
	for path, entry in pairs(M.watches) do
		if entry.bufs[bufnr] then
			entry.bufs[bufnr] = nil
			if vim.tbl_isempty(entry.bufs) then
				if entry.timer and not entry.timer:is_closing() then
					entry.timer:stop()
					entry.timer:close()
				end
				if entry.handle and not entry.handle:is_closing() then
					entry.handle:stop()
					entry.handle:close()
				end
				M.watches[path] = nil
			end
		end
	end
end

--- Stop all active watchers and clean up timers
function M.stop_all()
	for path, entry in pairs(M.watches) do
		if entry.timer and not entry.timer:is_closing() then
			entry.timer:stop()
			entry.timer:close()
		end
		if entry.handle and not entry.handle:is_closing() then
			entry.handle:stop()
			entry.handle:close()
		end
	end
	M.watches = {}
end

--- Initialize autocommands for buffer tracking
function M.setup()
	local group = vim.api.nvim_create_augroup("agent_stream_watcher", { clear = true })

	vim.api.nvim_create_autocmd({ "BufReadPost", "BufFilePost", "BufEnter" }, {
		group = group,
		callback = function(args)
			M.watch_buffer(args.buf)
		end,
	})

	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		callback = function(args)
			M.mark_internal_write(args.file)
		end,
	})

	vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
		group = group,
		callback = function(args)
			M.unwatch_buffer(args.buf)
			require("agent-stream.renderer").clear(args.buf)
		end,
	})

	-- Attach to existing open buffers
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(bufnr) then
			M.watch_buffer(bufnr)
		end
	end
end

return M
