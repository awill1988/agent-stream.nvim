local M = {}

---@class AttributionInfo
---@field source "tmux"|"env"|"proc"|"external"
---@field name string Identifier for process or agent
---@field pid number|nil Process ID if identified
---@field pane_id string|nil Tmux pane identifier if identified
---@field details string Human-readable summary for statusline/badge

-- Attribution uses environment and tmux hints; it cannot identify the writer with certainty.

local KNOWN_AGENTS = {
	codex = true,
	claude = true,
	aider = true,
	gemini = true,
	chatgpt = true,
	node = true,
	python = true,
	python3 = true,
	ruby = true,
	cargo = true,
	go = true,
}

---@param output string tmux list-panes output
---@param target_file string
---@return AttributionInfo|nil
function M.parse_tmux_panes(output, target_file)
	local lines = vim.split(output or "", "\n", { trimempty = true })
	local candidates = {}

	for _, line in ipairs(lines) do
		local parts = vim.split(line, ":", { plain = true })
		if #parts >= 4 then
			local pane_id = parts[1]
			local pid = tonumber(parts[2])
			local cmd = (parts[3] or ""):lower()
			local path = parts[4] or ""
			local active = parts[5] or "0"

			if cmd ~= "nvim" and cmd ~= "vim" then
				local score = 0
				if KNOWN_AGENTS[cmd] then
					score = score + 10
				end
				if path ~= "" and target_file:sub(1, #path) == path then
					score = score + 5
				end
				if active == "1" then
					score = score + 2
				end

				table.insert(candidates, {
					score = score,
					pane_id = pane_id,
					pid = pid,
					cmd = cmd,
					path = path,
				})
			end
		end
	end

	table.sort(candidates, function(a, b)
		return a.score > b.score
	end)

	if #candidates > 0 and candidates[1].score > 0 then
		local best = candidates[1]
		return {
			source = "tmux",
			name = best.cmd,
			pid = best.pid,
			pane_id = best.pane_id,
			details = string.format("tmux %s [%s]", best.pane_id, best.cmd),
		}
	end

	return nil
end

---@param filepath string
---@param callback fun(info: AttributionInfo)
function M.detect(filepath, callback)
	local config = require("agent-stream.config").get()
	if not config.attribution.enabled then
		callback({
			source = "external",
			name = "external process",
			pid = nil,
			pane_id = nil,
			details = "external process",
		})
		return
	end

	if vim.env.AGENT_NAME then
		callback({
			source = "env",
			name = vim.env.AGENT_NAME:lower(),
			pid = tonumber(vim.env.AGENT_PID),
			pane_id = vim.env.TMUX_PANE,
			details = string.format("env agent [%s]", vim.env.AGENT_NAME:lower()),
		})
		return
	end

	if config.attribution.check_tmux and vim.env.TMUX then
		vim.system({
			"tmux",
			"list-panes",
			"-a",
			"-F",
			"#{pane_id}:#{pane_pid}:#{pane_current_command}:#{pane_current_path}:#{pane_active}",
		}, { text = true }, function(result)
			vim.schedule(function()
				if result.code == 0 and result.stdout then
					local found = M.parse_tmux_panes(result.stdout, filepath)
					if found then
						callback(found)
						return
					end
				end

				callback({
					source = "external",
					name = "external process",
					pid = nil,
					pane_id = nil,
					details = "external process",
				})
			end)
		end)
		return
	end

	callback({
		source = "external",
		name = "external process",
		pid = nil,
		pane_id = nil,
		details = "external process",
	})
end

return M
