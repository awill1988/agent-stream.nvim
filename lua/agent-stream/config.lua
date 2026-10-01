-- config.lua: configuration management and highlight group registration
local M = {}

---@class AgentStreamConfig
---@field log_level string Canonical log verbosity (trace, debug, info, warn, error)
---@field debounce_ms number Debounce window in ms for filesystem write events
---@field auto_reload_unmodified boolean Automatically apply changes if buffer has no local unsaved edits
---@field show_signs boolean Display gutter signs for diff hunks
---@field show_virtual_lines boolean Display deleted lines as virtual text lines
---@field show_explorer_badges boolean Decorate supported file explorers with change badges
---@field signs table<string, string> Sign characters for add, delete, change
---@field highlights table<string, table> Highlight definitions or linkages
---@field attribution table Attribution engine settings
---@field explorer table Explorer integration settings
---@field rpc table RPC server and socket settings
---@field keymaps table<string, string|false> Default key mappings
M.defaults = {
	log_level = (vim.env.LOG_LEVEL or "info"):lower(),
	debounce_ms = 150,
	auto_reload_unmodified = false,
	show_signs = true,
	show_virtual_lines = true,
	show_explorer_badges = true,
	signs = {
		add = "+",
		delete = "-",
		change = "~",
	},
	highlights = {
		AgentStreamAdd = { default = true, link = "DiffAdd" },
		AgentStreamDelete = { default = true, link = "DiffDelete" },
		AgentStreamChange = { default = true, link = "DiffChange" },
		AgentStreamSignAdd = { default = true, link = "GitSignsAdd" },
		AgentStreamSignDelete = { default = true, link = "GitSignsDelete" },
		AgentStreamSignChange = { default = true, link = "GitSignsChange" },
		AgentStreamVirtDelete = { default = true, link = "Comment" },
		AgentStreamBadge = { default = true, link = "DiagnosticInfo" },
	},
	attribution = {
		enabled = true,
		check_tmux = true,
		check_proc = true,
	},
	explorer = {
		provider = "neo-tree",
		auto_reveal = false,
	},
	rpc = {
		enabled = true,
		socket_name = "agent-stream.sock",
	},
	keymaps = {
		accept = "<leader>aa",
		reject = "<leader>ar",
		next_hunk = "]a",
		prev_hunk = "[a",
	},
}

---@type AgentStreamConfig
M.values = vim.deepcopy(M.defaults)

--- Setup highlight groups according to config
local function apply_highlights()
	for group_name, hl_def in pairs(M.values.highlights) do
		pcall(vim.api.nvim_set_hl, 0, group_name, hl_def)
	end
end

--- Apply user options over defaults
---@param opts? table User options
---@return AgentStreamConfig
function M.setup(opts)
	opts = opts or {}
	M.values = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)
	apply_highlights()
	return M.values
end

--- Get current configuration value
---@return AgentStreamConfig
function M.get()
	return M.values
end

return M
