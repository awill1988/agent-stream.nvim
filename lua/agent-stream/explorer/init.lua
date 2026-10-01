local M = {}

---@type table<string, { stats: DiffStats, attribution: AttributionInfo|nil }>
M.badges = {}

---@param filepath string
---@param stats DiffStats
---@param attribution AttributionInfo|nil
function M.set_badge(filepath, stats, attribution)
	M.badges[filepath] = {
		stats = stats,
		attribution = attribution,
	}

	local config = require("agent-stream.config").get()
	if config.show_explorer_badges and config.explorer.provider == "neo-tree" then
		require("agent-stream.explorer.neo_tree").refresh()
	end
end

---@param filepath string
function M.clear_badge(filepath)
	if M.badges[filepath] then
		M.badges[filepath] = nil
		local config = require("agent-stream.config").get()
		if config.show_explorer_badges and config.explorer.provider == "neo-tree" then
			require("agent-stream.explorer.neo_tree").refresh()
		end
	end
end

---@param filepath string
---@return { stats: DiffStats, attribution: AttributionInfo|nil }|nil
function M.get_badge(filepath)
	return M.badges[filepath]
end

return M
