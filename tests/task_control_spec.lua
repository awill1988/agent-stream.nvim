local config = require("agent-stream.config")
local task_control = require("agent-stream.task_control")

describe("tmux task control", function()
	local original_system
	local original_executable
	local calls

	before_each(function()
		config.setup({ task_control = { transport = "tmux", resume_prompt = "resume now" } })
		calls = {}
		original_system = vim.system
		original_executable = vim.fn.executable
		vim.fn.executable = function(command)
			return command == "tmux" and 1 or original_executable(command)
		end
		vim.system = function(args, _, callback)
			table.insert(calls, args)
			callback({ code = 0, stderr = "" })
		end
	end)

	after_each(function()
		vim.system = original_system
		vim.fn.executable = original_executable
	end)

	it("interrupts only a verified tmux pane", function()
		local completed
		task_control.interrupt({ source = "tmux", pane_id = "%8" }, function(ok)
			completed = ok
		end)
		assert.is_true(vim.wait(1000, function()
			return completed ~= nil
		end))
		assert.is_true(completed)
		assert.are.same({ "tmux", "send-keys", "-t", "%8", "C-c" }, calls[1])
	end)

	it("sends the configured resume prompt and enter separately", function()
		local completed
		task_control.resume({ source = "tmux", pane_id = "%8" }, function(ok)
			completed = ok
		end)
		assert.is_true(vim.wait(1000, function()
			return completed ~= nil
		end))
		assert.is_true(completed)
		assert.are.same({ "tmux", "send-keys", "-t", "%8", "-l", "resume now" }, calls[1])
		assert.are.same({ "tmux", "send-keys", "-t", "%8", "Enter" }, calls[2])
	end)

	it("refuses an unverified pane", function()
		local completed
		task_control.interrupt({ source = "external", pane_id = "%8" }, function(ok)
			completed = ok
		end)
		assert.is_true(vim.wait(1000, function()
			return completed ~= nil
		end))
		assert.is_false(completed)
		assert.are.same({}, calls)
	end)
end)
