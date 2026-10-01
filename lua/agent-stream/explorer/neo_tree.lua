local M = {}

---@param config table
---@param node table
---@param state table
---@return table|nil
function M.component(config, node, state)
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
		text = string.format(" 󰚩 +%d -%d", stats.added, stats.deleted),
		highlight = "AgentStreamBadge",
	}
end

function M.refresh()
	local ok, manager = pcall(require, "neo-tree.sources.manager")
	if ok and manager and manager.refresh then
		pcall(manager.refresh, "filesystem")
	end
end

return M
