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
M.next_hunk = M.actions.next_hunk
M.prev_hunk = M.actions.prev_hunk
M.clear = M.renderer.clear
M.focus = M.rpc.focus
M.reveal = M.rpc.reveal
M.highlight = M.rpc.highlight
M.annotate = M.rpc.annotate

local function setup_keymaps(keymaps)
	if keymaps.accept then
		vim.keymap.set("n", keymaps.accept, function()
			M.actions.accept()
		end, { desc = "agent-stream: accept external changes" })
	end

	if keymaps.reject then
		vim.keymap.set("n", keymaps.reject, function()
			M.actions.reject()
		end, { desc = "agent-stream: reject external changes" })
	end

	if keymaps.next_hunk then
		vim.keymap.set("n", keymaps.next_hunk, function()
			M.actions.next_hunk()
		end, { desc = "agent-stream: jump to next hunk" })
	end

	if keymaps.prev_hunk then
		vim.keymap.set("n", keymaps.prev_hunk, function()
			M.actions.prev_hunk()
		end, { desc = "agent-stream: jump to prev hunk" })
	end
end

---@param opts? table
function M.setup(opts)
	local cfg = M.config.setup(opts)
	M.watcher.setup()
	M.rpc.setup()
	setup_keymaps(cfg.keymaps)

	M.diff_engine.on("diff_cleared", function(payload)
		if payload and payload.file then
			M.explorer.clear_badge(payload.file)
		end
	end)
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
		server = vim.v.servername,
	}
end

return M
