local M = {}

-- Invariant: internal writes via BufWritePost take precedence over fs_event to prevent self-triggering diff feedback loops.

---@type table<string, { handle: any, bufs: table<number, boolean>, timer: any }>
M.watches = {}

---@type table<string, number>
M.internal_writes = {}

local autoread = {}
local setting_autoread = false

local function set_autoread(bufnr, value)
	setting_autoread = true
	local ok, err = pcall(vim.api.nvim_set_option_value, "autoread", value, { buf = bufnr, scope = "local" })
	setting_autoread = false
	if not ok then
		error(err)
	end
end

local function own_autoread(bufnr)
	if autoread[bufnr] or not require("agent-stream.config").get().manage_autoread then
		return
	end
	autoread[bufnr] =
		{ value = vim.api.nvim_get_option_value("autoread", { buf = bufnr, scope = "local" }), owned = true }
	set_autoread(bufnr, false)
end

local function restore_autoread(bufnr)
	local saved = autoread[bufnr]
	autoread[bufnr] = nil
	if
		saved
		and saved.owned
		and vim.api.nvim_buf_is_valid(bufnr)
		and vim.api.nvim_get_option_value("autoread", { buf = bufnr, scope = "local" }) == false
	then
		set_autoread(bufnr, saved.value)
	end
end

---@param path string
---@return string
function M.normalize_path(path)
	if not path or path == "" then
		return ""
	end
	return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

---@param filepath string
function M.mark_internal_write(filepath)
	local norm = M.normalize_path(filepath)
	if norm ~= "" then
		M.internal_writes[norm] = vim.uv.now()
	end
end

---@param filepath string
---@return boolean
function M.is_internal_write(filepath)
	local norm = M.normalize_path(filepath)
	local last = M.internal_writes[norm]
	return last ~= nil and (vim.uv.now() - last) < 500
end

local function process_file_change(path, bufnr)
	local entry = M.watches[path]
	local function active()
		return vim.api.nvim_buf_is_valid(bufnr) and entry ~= nil and M.watches[path] == entry and entry.bufs[bufnr]
	end
	if not active() then
		return
	end

	local config = require("agent-stream.config").get()
	local diff_engine = require("agent-stream.diff_engine")
	local attribution = require("agent-stream.attribution")
	local renderer = require("agent-stream.renderer")
	local explorer = require("agent-stream.explorer")

	diff_engine.diff_file_with_buffer(bufnr, path, function(diff_result)
		if not active() then
			return
		end
		if not diff_result then
			renderer.clear(bufnr)
			explorer.clear_badge(path)
			return
		end

		attribution.detect(path, function(attr_info)
			if not active() then
				return
			end
			local is_modified = vim.api.nvim_get_option_value("modified", { buf = bufnr })
			if config.auto_reload_unmodified and not is_modified then
				vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, diff_result.disk_lines)
				vim.bo[bufnr].modified = false
				renderer.clear(bufnr)
				explorer.clear_badge(path)
				vim.notify(
					string.format("agent-stream: auto-reloaded clean buffer (%s)", attr_info.details),
					vim.log.levels.INFO
				)
				return
			end

			renderer.render_diff(bufnr, diff_result, attr_info)
			explorer.set_badge(path, diff_result.stats, attr_info)
		end)
	end)
end

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

	if M.watches[path] then
		M.watches[path].bufs[bufnr] = true
		own_autoread(bufnr)
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

	local started = handle:start(path, {}, function(err, filename, events)
		if err or M.is_internal_write(path) then
			return
		end

		if timer and not timer:is_closing() then
			timer:stop()
			timer:start(
				config.debounce_ms,
				0,
				vim.schedule_wrap(function()
					local entry = M.watches[path]
					if not entry then
						return
					end
					for b, _ in pairs(entry.bufs) do
						process_file_change(path, b)
					end
				end)
			)
		end
	end)
	if started then
		own_autoread(bufnr)
	else
		M.unwatch_buffer(bufnr)
	end
end

---@param bufnr number
function M.unwatch_buffer(bufnr)
	restore_autoread(bufnr)
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

function M.stop_all()
	for bufnr in pairs(autoread) do
		restore_autoread(bufnr)
	end
	for _, entry in pairs(M.watches) do
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

function M.setup()
	local group = vim.api.nvim_create_augroup("agent_stream_watcher", { clear = true })
	vim.api.nvim_create_autocmd("OptionSet", {
		group = group,
		pattern = "autoread",
		callback = function()
			local saved = autoread[vim.api.nvim_get_current_buf()]
			if saved and not setting_autoread and vim.v.option_command ~= "setglobal" then
				saved.owned = false
			end
		end,
	})
	vim.api.nvim_create_autocmd("FileChangedShell", {
		group = group,
		callback = function(args)
			local saved = autoread[args.buf]
			if saved and saved.owned then
				vim.v.fcs_choice = ""
				process_file_change(M.normalize_path(vim.api.nvim_buf_get_name(args.buf)), args.buf)
			end
		end,
	})
	vim.api.nvim_create_autocmd("BufFilePre", {
		group = group,
		callback = function(args)
			M.unwatch_buffer(args.buf)
			require("agent-stream.renderer").clear(args.buf)
			require("agent-stream.explorer").clear_badge(M.normalize_path(args.file))
		end,
	})
	vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = M.stop_all })

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

	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(bufnr) then
			M.watch_buffer(bufnr)
		end
	end
end

return M
