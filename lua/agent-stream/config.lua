local M = {}

---@class AgentStreamConfig
---@field log_level string Canonical log verbosity (trace, debug, info, warn, error)
---@field debounce_ms number Debounce window in ms for filesystem write events
---@field auto_reload_unmodified boolean Automatically apply changes if buffer has no local unsaved edits
---@field manage_autoread boolean Own buffer-local autoread while watching
---@field show_signs boolean Display gutter signs for diff hunks
---@field show_virtual_lines boolean Display deleted lines as virtual text lines
---@field show_explorer_badges boolean Decorate supported file explorers with change badges
---@field signs table<string, string> Sign characters for add, delete, change
---@field highlights table<string, table> Highlight definitions or linkages
---@field attribution table Attribution engine settings
---@field explorer table Explorer integration settings
---@field rpc table RPC server and socket settings
---@field keymaps false|table<string, string|false> Opt-in key mappings
---@field symbols table<string, string> Preview and badge symbols
---@field show_summary boolean Display review commands and change counts
---@field sign_priority integer Gutter sign priority
---@field review table Incoming-change review policy
---@field task_control table Optional terminal task controls
M.defaults = {
	log_level = (vim.env.LOG_LEVEL or "info"):lower(),
	debounce_ms = 150,
	auto_reload_unmodified = false,
	manage_autoread = true,
	show_signs = true,
	show_virtual_lines = true,
	show_explorer_badges = true,
	show_summary = true,
	sign_priority = 10,
	symbols = { badge = "", add = "+", change = ">" },
	signs = {
		add = "+",
		delete = "-",
		change = "~",
	},
	highlights = {
		AgentStreamAdd = { default = true, link = "DiffAdd" },
		AgentStreamDelete = { default = true, link = "DiffDelete" },
		AgentStreamChange = { default = true, link = "DiffChange" },
		AgentStreamSignAdd = { default = true, link = "Added" },
		AgentStreamSignDelete = { default = true, link = "Removed" },
		AgentStreamSignChange = { default = true, link = "Changed" },
		AgentStreamVirtDelete = { default = true, link = "Comment" },
		AgentStreamBadge = { default = true, link = "DiagnosticInfo" },
	},
	attribution = {
		enabled = false,
		check_tmux = false,
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
	keymaps = false,
	review = {
		mode = "manual",
		grace_period_ms = 3000,
	},
	task_control = false,
}

---@type AgentStreamConfig
M.values = vim.deepcopy(M.defaults)

local function apply_highlights()
	for group_name, hl_def in pairs(M.values.highlights) do
		pcall(vim.api.nvim_set_hl, 0, group_name, hl_def)
	end
end

---@param opts? table
---@return AgentStreamConfig
function M.setup(opts)
	opts = opts or {}
	assert(type(opts) == "table", "agent-stream: options must be a table")
	local values = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)
	assert(type(values.manage_autoread) == "boolean", "agent-stream: manage_autoread must be boolean")
	assert(type(values.review) == "table", "agent-stream: review must be a table")
	assert(
		vim.tbl_contains({ "manual", "optimistic" }, values.review.mode),
		"agent-stream: review.mode must be manual or optimistic"
	)
	assert(
		type(values.review.grace_period_ms) == "number"
			and values.review.grace_period_ms % 1 == 0
			and values.review.grace_period_ms >= 250,
		"agent-stream: review.grace_period_ms must be an integer of at least 250"
	)
	assert(
		type(values.task_control) == "table" or values.task_control == false or values.task_control == "auto",
		"agent-stream: task_control must be false, auto, or a table"
	)
	if values.task_control == "auto" then
		if vim.env.TMUX and vim.fn.executable("tmux") == 1 then
			values.attribution.enabled = true
			values.attribution.check_tmux = true
			values.task_control = require("agent-stream.transports.tmux")
		else
			values.task_control = false
		end
	end
	if values.task_control then
		for _, action in ipairs({ "interrupt", "resume" }) do
			assert(
				type(values.task_control[action]) == "function",
				"agent-stream: task_control." .. action .. " must be a function"
			)
		end
	end
	assert(type(values.keymaps) == "table" or values.keymaps == false, "agent-stream: invalid keymaps")
	for action, lhs in pairs(values.keymaps or {}) do
		assert(
			vim.tbl_contains({ "accept", "reject", "cancel", "resume", "next_hunk", "prev_hunk" }, action),
			"agent-stream: unknown mapping action"
		)
		assert(lhs == false or (type(lhs) == "string" and lhs ~= ""), "agent-stream: invalid mapping")
	end
	assert(
		type(values.sign_priority) == "number"
			and values.sign_priority % 1 == 0
			and values.sign_priority >= 0
			and values.sign_priority <= 65535,
		"agent-stream: sign_priority must be an integer from 0 to 65535"
	)
	for _, field in ipairs({ "signs", "symbols" }) do
		assert(type(values[field]) == "table", "agent-stream: invalid " .. field)
		for _, symbol in pairs(values[field]) do
			assert(
				type(symbol) == "string" and not symbol:find("%c"),
				"agent-stream: symbols must be single-line strings"
			)
			local width = vim.fn.strdisplaywidth(symbol)
			assert(width <= 2 and (symbol == "" or width > 0), "agent-stream: symbols must occupy at most two cells")
		end
	end
	-- Highlight attributes form a complete definition; links must not leak into color overrides.
	for name, definition in pairs(opts.highlights or {}) do
		values.highlights[name] = vim.deepcopy(definition)
	end
	M.values = values
	local group = vim.api.nvim_create_augroup("agent_stream_highlights", { clear = true })
	vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = apply_highlights })
	apply_highlights()
	return M.values
end

---@return AgentStreamConfig
function M.get()
	return M.values
end

return M
