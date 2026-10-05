local stream = require("agent-stream")

describe("autoread ownership", function()
	local buf, path
	local function setup(opts)
		stream.setup(
			vim.tbl_deep_extend(
				"force",
				{ rpc = { enabled = false }, attribution = { check_tmux = false } },
				opts or {}
			)
		)
	end
	before_each(function()
		path = vim.fn.tempname()
		vim.fn.writefile({ "original" }, path)
		setup({ manage_autoread = false })
		vim.cmd.edit(vim.fn.fnameescape(path))
		buf = vim.api.nvim_get_current_buf()
		vim.api.nvim_set_option_value("autoread", nil, { buf = buf, scope = "local" })
	end)
	after_each(function()
		stream.watcher.stop_all()
		if vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
		vim.fn.delete(path)
	end)
	it("restores inherited, true, and false local settings on detach", function()
		for _, value in ipairs({ "inherit", true, false }) do
			local expected = value == "inherit" and vim.NIL or value
			vim.api.nvim_set_option_value("autoread", expected, { buf = buf, scope = "local" })
			local global = vim.go.autoread
			setup()
			assert.is_false(vim.bo[buf].autoread)
			assert.are.equal(global, vim.go.autoread)
			stream.watcher.unwatch_buffer(buf)
			local restored = vim.api.nvim_get_option_value("autoread", { buf = buf, scope = "local" })
			if expected == vim.NIL then
				assert.is_nil(restored)
			else
				assert.are.equal(expected, restored)
			end
		end
	end)
	it("restores ownership on repeated setup and opt-out", function()
		setup()
		setup()
		setup({ manage_autoread = false })
		assert.is_nil(vim.api.nvim_get_option_value("autoread", { buf = buf, scope = "local" }))
	end)
	it("preserves a user's later local change", function()
		setup()
		vim.bo[buf].autoread = true
		-- OptionSet does not fire during startup in headless test processes.
		vim.api.nvim_exec_autocmds("OptionSet", { pattern = "autoread" })
		stream.watcher.unwatch_buffer(buf)
		assert.is_true(vim.bo[buf].autoread)
	end)
	it("does not reload a clean buffer during checktime", function()
		setup()
		vim.fn.writefile({ "external", "edit" }, path)
		vim.cmd.checktime()
		assert.are.same({ "original" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
		assert.is_true(vim.wait(3000, function()
			return stream.renderer.active_state[buf] ~= nil
		end))
	end)
	it("releases the previous path when a buffer is renamed", function()
		setup()
		local old = stream.watcher.normalize_path(path)
		vim.cmd.file(vim.fn.fnameescape(path .. "-new"))
		assert.is_nil(stream.watcher.watches[old])
		assert.is_nil(vim.api.nvim_get_option_value("autoread", { buf = buf, scope = "local" }))
	end)
	it("supports explicit plugin auto-reload without marking clean buffers modified", function()
		setup({ auto_reload_unmodified = true })
		vim.fn.writefile({ "external", "edit" }, path)
		vim.cmd.checktime()
		assert.is_true(vim.wait(3000, function()
			return vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "external"
		end))
		assert.is_false(vim.bo[buf].modified)
		assert.is_nil(stream.renderer.active_state[buf])
	end)
end)
