-- neo_tree.lua: neo-tree renderer component and event integrations
local M = {}

--- Neo-tree component to display agent-stream activity badge
---@param config table Component configuration
---@param node table Neo-tree node
---@param state table Neo-tree state
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
	local badge_text = string.format(" 󰚩 +%d -%d", stats.added, stats.deleted)

	return {
		text = badge_text,
		highlight = "AgentStreamBadge",
	}
end

--- Trigger neo-tree UI refresh if loaded
function M.refresh()
	local ok, manager = pcall(require, "neo-tree.sources.manager")
	if ok and manager and manager.refresh then
		pcall(manager.refresh, "filesystem")
	end
end

return M
