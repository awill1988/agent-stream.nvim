local M = {}

---@param config table
---@param node table
---@param state table
---@return table|nil
function M.component(config, node, state)
	local settings = require("agent-stream.config").get()
	if not settings.show_explorer_badges or settings.explorer.provider ~= "neo-tree" then
		return nil
	end
	if not node or not node.path then
		return nil
	end

	local explorer = require("agent-stream.explorer")
	local entry = explorer.get_badge(node.path)
	if not entry then
		return nil
	end

	local stats = entry.stats or { added = 0, deleted = 0, changed = 0 }
	return {
		text = string.format(
			" %s+%d -%d",
			settings.symbols.badge == "" and "" or settings.symbols.badge .. " ",
			stats.added,
			stats.deleted
		),
		highlight = "AgentStreamBadge",
	}
end

function M.refresh()
	local manager = package.loaded["neo-tree.sources.manager"]
	if type(manager) == "table" and manager.refresh then
		pcall(manager.refresh, "filesystem")
	end
end

return M
