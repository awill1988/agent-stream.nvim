local agent_stream = require("agent-stream")

describe("integration flow", function()
	local temp_file = "/tmp/agent_stream_integration_test.txt"

	before_each(function()
		local f = io.open(temp_file, "w")
		assert(f)
		f:write("line 1\nline 2\nline 3\n")
		f:close()
	end)

	after_each(function()
		pcall(os.remove, temp_file)
	end)

	it("detects external writes, streams diff, and accepts changes cleanly", function()
		agent_stream.setup({
			debounce_ms = 20,
			auto_reload_unmodified = false,
		})

		-- Open buffer
		vim.cmd.edit(temp_file)
		local bufnr = vim.api.nvim_get_current_buf()
		local lines_before = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		assert.are.same({ "line 1", "line 2", "line 3" }, lines_before)

		-- Simulate external agent edit
		local f = io.open(temp_file, "w")
		assert(f)
		f:write("line 1\ninjected agent line\nline 2\nline 3\n")
		f:close()

		-- Wait for libuv watcher & debounce to fire
		vim.wait(150, function()
			return agent_stream.renderer.active_state[bufnr] ~= nil
		end)

		local state = agent_stream.renderer.active_state[bufnr]
		assert.is_not_nil(state)
		assert.are.same(1, #state.diff_result.hunks)
		assert.are.same("add", state.diff_result.hunks[1].type)

		-- Verify buffer text itself is untouched before accept
		local lines_during = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		assert.are.same({ "line 1", "line 2", "line 3" }, lines_during)

		-- Accept diff
		agent_stream.accept(bufnr)

		-- Verify buffer now has the agent line
		local lines_after = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		assert.are.same({ "line 1", "injected agent line", "line 2", "line 3" }, lines_after)

		-- Verify active diff state cleared
		assert.is_nil(agent_stream.renderer.active_state[bufnr])

		-- Close buffer
		vim.api.nvim_buf_delete(bufnr, { force = true })
	end)

	it("rejects changes and restores buffer content to disk", function()
		agent_stream.setup({
			debounce_ms = 20,
			auto_reload_unmodified = false,
		})

		vim.cmd.edit(temp_file)
		local bufnr = vim.api.nvim_get_current_buf()

		-- Simulate external edit
		local f = io.open(temp_file, "w")
		assert(f)
		f:write("corrupted or unwanted line\n")
		f:close()

		vim.wait(150, function()
			return agent_stream.renderer.active_state[bufnr] ~= nil
		end)

		assert.is_not_nil(agent_stream.renderer.active_state[bufnr])

		-- Reject external change
		agent_stream.reject(bufnr)

		-- Verify disk is restored to buffer content
		local rf = io.open(temp_file, "r")
		assert(rf)
		local disk_restored = rf:read("*a")
		rf:close()

		assert.is_truthy(disk_restored:find("line 1\nline 2\nline 3"))
		assert.is_nil(agent_stream.renderer.active_state[bufnr])

		vim.api.nvim_buf_delete(bufnr, { force = true })
	end)
end)
