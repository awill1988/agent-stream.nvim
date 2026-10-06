local M = {}

function M.interrupt(attribution, callback)
	local control = require("agent-stream.config").get().task_control
	if control then
		return control.interrupt(attribution, callback)
	end
	callback(false, "agent-stream: automatic acceptance stopped; no task transport is configured")
end

function M.resume(attribution, callback)
	local control = require("agent-stream.config").get().task_control
	if control then
		return control.resume(attribution, callback)
	end
	callback(false, "agent-stream: no task transport is configured")
end

return M
