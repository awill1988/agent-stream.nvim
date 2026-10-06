local M = {}

M.config = require("agent-stream.config")
M.diff_engine = require("agent-stream.diff_engine")
M.watcher = require("agent-stream.watcher")
M.renderer = require("agent-stream.renderer")
M.actions = require("agent-stream.actions")
M.attribution = require("agent-stream.attribution")
M.explorer = require("agent-stream.explorer")
M.rpc = require("agent-stream.rpc")

M.accept = M.actions.accept
M.reject = M.actions.reject
M.cancel = M.actions.cancel
M.resume = M.actions.resume
M.statusline = M.actions.statusline
M.next_hunk = M.actions.next_hunk
M.prev_hunk = M.actions.prev_hunk
M.clear = M.renderer.clear
M.focus = M.rpc.focus
M.reveal = M.rpc.reveal
M.highlight = M.rpc.highlight
M.annotate = M.rpc.annotate

local owned_maps = {}
local function setup_keymaps(keymaps)
	for _, mapping in ipairs(owned_maps) do
		for _, current in ipairs(vim.api.nvim_get_keymap("n")) do
			if current.lhs == mapping.lhs and current.callback == mapping.callback then
				vim.keymap.del("n", current.lhs)
			end
		end
	end
	owned_maps = {}
	for action, lhs in pairs(keymaps or {}) do
		if lhs then
			local callback = function()
				M.actions[action]()
			end
			vim.keymap.set("n", lhs, callback, { desc = "agent-stream: " .. action:gsub("_", " ") })
			for _, mapping in ipairs(vim.api.nvim_get_keymap("n")) do
				if mapping.callback == callback then
					table.insert(owned_maps, { lhs = mapping.lhs, callback = callback })
				end
			end
		end
	end
end

local function clear_badge(payload)
	if payload and payload.file then
		M.explorer.clear_badge(payload.file)
	end
end

---@param opts? table
function M.setup(opts)
	local cfg = M.config.setup(opts)
	M.watcher.stop_all()
	M.watcher.setup()
	M.rpc.setup()
	setup_keymaps(cfg.keymaps)

	M.diff_engine.off("diff_cleared", clear_badge)
	M.diff_engine.on("diff_cleared", clear_badge)
end

---@return table
function M.status()
	local active_watches = 0
	for _, _ in pairs(M.watcher.watches) do
		active_watches = active_watches + 1
	end

	local active_diffs = 0
	for _, _ in pairs(M.renderer.active_state) do
		active_diffs = active_diffs + 1
	end

	return {
		active_watches = active_watches,
		active_diffs = active_diffs,
		optimistic = vim.tbl_count(M.actions.optimistic),
		server = vim.v.servername,
	}
end

return M
