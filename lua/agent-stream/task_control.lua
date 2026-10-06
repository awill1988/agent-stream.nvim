local M = {}

local function pane_is_safe(attribution)
	return attribution
		and attribution.source == "tmux"
		and type(attribution.pane_id) == "string"
		and attribution.pane_id:match("^%%%d+$") ~= nil
end

local function unavailable(callback)
	vim.schedule(function()
		callback(false, "agent-stream: no verified tmux agent pane is available")
	end)
end

local function run(args, callback)
	vim.system(args, { text = true }, function(result)
		vim.schedule(function()
			if result.code == 0 then
				callback(true)
			else
				callback(false, vim.trim(result.stderr or "tmux task control failed"))
			end
		end)
	end)
end

function M.interrupt(attribution, callback)
	local config = require("agent-stream.config").get().task_control
	if config.transport ~= "tmux" or not pane_is_safe(attribution) or vim.fn.executable("tmux") ~= 1 then
		return unavailable(callback)
	end
	run({ "tmux", "send-keys", "-t", attribution.pane_id, "C-c" }, callback)
end

function M.resume(attribution, callback)
	local config = require("agent-stream.config").get().task_control
	if config.transport ~= "tmux" or not pane_is_safe(attribution) or vim.fn.executable("tmux") ~= 1 then
		return unavailable(callback)
	end
	run({ "tmux", "send-keys", "-t", attribution.pane_id, "-l", config.resume_prompt }, function(ok, err)
		if not ok then
			callback(false, err)
			return
		end
		run({ "tmux", "send-keys", "-t", attribution.pane_id, "Enter" }, callback)
	end)
end

return M
