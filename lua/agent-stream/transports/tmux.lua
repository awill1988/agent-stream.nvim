local M = {}

local resume_prompt =
	"Resume the interrupted task. The current file changes have been accepted. Continue from the current workspace state."

local function pane_is_safe(attribution)
	return attribution
		and attribution.source == "tmux"
		and type(attribution.pane_id) == "string"
		and attribution.pane_id:match("^%%%d+$")
end

local function run(args, callback)
	vim.system(args, { text = true }, function(result)
		vim.schedule(function()
			callback(
				result.code == 0,
				result.code == 0 and nil or vim.trim(result.stderr or "tmux task control failed")
			)
		end)
	end)
end

local function unavailable(callback)
	callback(false, "agent-stream: no verified tmux agent pane is available")
end

function M.interrupt(attribution, callback)
	if not pane_is_safe(attribution) or vim.fn.executable("tmux") ~= 1 then
		return unavailable(callback)
	end
	run({ "tmux", "send-keys", "-t", attribution.pane_id, "C-c" }, callback)
end

function M.resume(attribution, callback)
	if not pane_is_safe(attribution) or vim.fn.executable("tmux") ~= 1 then
		return unavailable(callback)
	end
	run({ "tmux", "send-keys", "-t", attribution.pane_id, "-l", resume_prompt }, function(ok, err)
		if ok then
			run({ "tmux", "send-keys", "-t", attribution.pane_id, "Enter" }, callback)
		else
			callback(false, err)
		end
	end)
end

return M
