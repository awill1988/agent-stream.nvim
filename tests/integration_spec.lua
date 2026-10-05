local stream = require("agent-stream")

describe("integration flow", function()
	local path, buf
	local original = { "line 1", "line 2", "line 3" }

	local function lines()
		return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	end

	local function external_write(content)
		-- macOS starts delivering file events after libuv enters its event loop.
		vim.defer_fn(function()
			vim.fn.writefile(content, path)
		end, 20)
		assert.is_true(
			vim.wait(3000, function()
				local state = stream.renderer.active_state[buf]
				return state ~= nil and vim.deep_equal(state.diff_result.disk_lines, content)
			end),
			"expected disk preview: "
				.. vim.inspect({
					expected = content,
					disk = vim.fn.readfile(path),
					status = stream.status(),
					state = stream.renderer.active_state[buf],
				})
		)
	end

	before_each(function()
		path = vim.fn.tempname()
		vim.fn.writefile(original, path)
		stream.setup({ debounce_ms = 20, attribution = { check_tmux = false }, rpc = { enabled = false } })
		vim.cmd.edit(vim.fn.fnameescape(path))
		buf = vim.api.nvim_get_current_buf()
		path = vim.api.nvim_buf_get_name(buf)
		assert.is_not_nil(stream.watcher.watches[stream.watcher.normalize_path(path)])
	end)

	after_each(function()
		stream.watcher.stop_all()
		if buf and vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
		vim.fn.delete(path)
	end)

	it("preserves local edits and undo state until acceptance", function()
		vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "local edit" })
		local before = lines()
		local undo = vim.fn.undotree()
		local incoming = { "line 1", "incoming", "line 2", "line 3" }
		external_write(incoming)
		assert.are.same(before, lines())
		assert.are.same(undo, vim.fn.undotree())
		stream.accept(buf)
		assert.are.same(incoming, lines())
		assert.is_nil(stream.renderer.active_state[buf])
	end)

	it("rejects by writing the current buffer including local edits to disk", function()
		vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "local edit" })
		local before = lines()
		external_write({ "unwanted" })
		stream.reject(buf)
		assert.are.same(before, vim.fn.readfile(path))
		assert.are.same(before, lines())
		assert.is_nil(stream.renderer.active_state[buf])
	end)

	it("previews successive writes and supports accept then reject", function()
		external_write({ "first" })
		external_write({ "second" })
		stream.accept(buf)
		assert.are.same({ "second" }, lines())
		external_write({ "third" })
		stream.reject(buf)
		assert.are.same({ "second" }, vim.fn.readfile(path))
	end)

	it("closes watcher handles and timers when the buffer is deleted", function()
		local entry = stream.watcher.watches[stream.watcher.normalize_path(path)]
		vim.api.nvim_buf_delete(buf, { force = true })
		assert.is_nil(next(stream.watcher.watches))
		assert.is_true(entry.handle:is_closing())
		assert.is_true(entry.timer:is_closing())
		assert.is_nil(stream.renderer.active_state[buf])
	end)

	it("replaces watcher registrations on setup and continues previewing writes", function()
		local path_key = stream.watcher.normalize_path(path)
		local previous = stream.watcher.watches[path_key]
		stream.setup({ debounce_ms = 20, attribution = { check_tmux = false }, rpc = { enabled = false } })
		assert.is_true(previous.handle:is_closing())
		assert.is_true(previous.timer:is_closing())
		assert.are_not.equal(previous, stream.watcher.watches[path_key])
		external_write({ "after setup" })
		assert.are.same(original, lines())
	end)
end)
