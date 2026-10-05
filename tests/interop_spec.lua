local stream = require("agent-stream")
local config = stream.config

describe("interoperability", function()
	local buf, original_notify, manager, preload, original_open, original_leader
	local function setup(opts)
		return stream.setup(vim.tbl_deep_extend("force", { rpc = { enabled = false } }, opts or {}))
	end

	before_each(function()
		original_notify = vim.notify
		original_open = io.open
		original_leader = vim.g.mapleader
		manager = package.loaded["neo-tree.sources.manager"]
		preload = package.preload["neo-tree.sources.manager"]
		vim.cmd.colorscheme("habamax")
		setup()
	end)

	after_each(function()
		vim.notify = original_notify
		io.open = original_open
		package.loaded["neo-tree.sources.manager"] = manager
		package.preload["neo-tree.sources.manager"] = preload
		setup()
		for _, lhs in ipairs({ "<F6>", "<F7>", ",aa" }) do
			pcall(vim.keymap.del, "n", lhs)
		end
		vim.g.mapleader = original_leader
		stream.watcher.stop_all()
		if buf and vim.api.nvim_buf_is_valid(buf) then
			stream.renderer.clear(buf)
			vim.api.nvim_buf_delete(buf, { force = true })
		end
		stream.explorer.badges = {}
		vim.cmd.colorscheme("habamax")
	end)

	it("restores native links across colorschemes and backgrounds", function()
		for _, background in ipairs({ "light", "dark" }) do
			vim.o.background = background
			for _, theme in ipairs({ "default", "habamax", "retrobox" }) do
				vim.cmd.colorscheme(theme)
				assert.are.equal("Added", vim.api.nvim_get_hl(0, { name = "AgentStreamSignAdd" }).link)
				assert.are.equal("Removed", vim.api.nvim_get_hl(0, { name = "AgentStreamSignDelete" }).link)
				assert.are.equal("Changed", vim.api.nvim_get_hl(0, { name = "AgentStreamSignChange" }).link)
			end
		end
	end)

	it("preserves theme definitions and replaces complete explicit definitions", function()
		vim.api.nvim_set_hl(0, "AgentStreamAdd", { fg = "#123456" })
		setup()
		vim.api.nvim_exec_autocmds("ColorScheme", {})
		assert.are.equal(0x123456, vim.api.nvim_get_hl(0, { name = "AgentStreamAdd" }).fg)
		setup({ highlights = { AgentStreamAdd = { fg = "#abcdef" } } })
		assert.is_nil(config.get().highlights.AgentStreamAdd.link)
		vim.cmd.colorscheme("default")
		assert.are.equal(0xabcdef, vim.api.nvim_get_hl(0, { name = "AgentStreamAdd" }).fg)
		setup({ highlights = { AgentStreamAdd = { default = true, fg = "#123456" } } })
		assert.are.equal(0xabcdef, vim.api.nvim_get_hl(0, { name = "AgentStreamAdd" }).fg)
	end)

	it("installs only opted-in mappings and removes only owned mappings", function()
		assert.is_false(config.get().keymaps)
		vim.g.mapleader = ","
		setup({ keymaps = { accept = "<leader>aa", reject = "<F6>", next_hunk = false } })
		assert.is_function(vim.fn.maparg(",aa", "n", false, true).callback)
		local replacement = function() end
		vim.keymap.set("n", "<F6>", replacement)
		setup({ keymaps = { accept = "<F7>" } })
		assert.are.equal("", vim.fn.maparg(",aa", "n"))
		assert.are.equal(replacement, vim.fn.maparg("<F6>", "n", false, true).callback)
		setup()
		assert.are.equal("", vim.fn.maparg("<F7>", "n"))
		assert.are.equal(replacement, vim.fn.maparg("<F6>", "n", false, true).callback)
	end)

	it("preserves editor options, notifications, and singleton registrations", function()
		local function options()
			return {
				vim.wo.signcolumn,
				vim.wo.number,
				vim.wo.wrap,
				vim.o.background,
				vim.o.termguicolors,
				vim.o.autoread,
			}
		end
		local before = options()
		local notify = function() end
		vim.notify = notify
		local listeners = #stream.diff_engine.listeners.diff_cleared
		local count = #vim.api.nvim_get_autocmds({ group = "agent_stream_watcher" })
		setup()
		setup()
		assert.are.same(before, options())
		assert.are.equal(notify, vim.notify)
		assert.are.equal(listeners, #stream.diff_engine.listeners.diff_cleared)
		assert.are.equal(count, #vim.api.nvim_get_autocmds({ group = "agent_stream_watcher" }))
		assert.are.equal(1, #vim.api.nvim_get_autocmds({ group = "agent_stream_highlights" }))
	end)

	it("does not load neo-tree during background updates and honors disabled badges", function()
		package.loaded["neo-tree.sources.manager"] = nil
		local loads = 0
		package.preload["neo-tree.sources.manager"] = function()
			loads = loads + 1
			error("unexpected load")
		end
		stream.explorer.set_badge("example", { added = 1, deleted = 0, changed = 0 })
		assert.are.equal(0, loads)
		local refreshes = 0
		package.loaded["neo-tree.sources.manager"] = {
			refresh = function()
				refreshes = refreshes + 1
			end,
		}
		setup({ show_explorer_badges = false })
		stream.explorer.clear_badge("example")
		stream.explorer.set_badge("example", { added = 1, deleted = 0 })
		assert.are.equal(0, refreshes)
		assert.is_nil(require("agent-stream.explorer.neo_tree").component({}, { path = "example" }, {}))
		setup({ explorer = { provider = false } })
		assert.is_false(stream.reveal("example"))
	end)

	it("does not publish rpc discovery when disabled", function()
		io.open = function()
			error("unexpected file access")
		end
		setup()
		io.open = original_open
	end)

	it("shares custom badge symbols with explorer components and annotations", function()
		setup({ symbols = { badge = "*" } })
		buf = vim.api.nvim_create_buf(false, true)
		local path = vim.fn.tempname()
		vim.api.nvim_buf_set_name(buf, path)
		stream.explorer.set_badge(path, { added = 2, deleted = 1 })
		local component = require("agent-stream.explorer.neo_tree").component({}, { path = path }, {})
		assert.are.equal(" * +2 -1", component.text)
		stream.annotate(path, 1, "review", 1)
		local marks = vim.api.nvim_buf_get_extmarks(buf, stream.rpc.ns_id, 0, -1, { details = true })
		assert.are.equal(" * [agent]: review", marks[1][4].virt_lines[1][1][1])
		assert.is_true(vim.wait(1000, function()
			return #vim.api.nvim_buf_get_extmarks(buf, stream.rpc.ns_id, 0, -1, {}) == 0
		end))
	end)

	it("rejects invalid symbols and priorities before replacing configuration", function()
		local before = config.get()
		for _, opts in ipairs({
			{ symbols = { add = "abc" } },
			{ signs = { add = "\n" } },
			{ sign_priority = -1 },
			{ sign_priority = 65536 },
			{ sign_priority = 1.5 },
			{ keymaps = true },
		}) do
			assert.has_error(function()
				config.setup(opts)
			end)
			assert.are.equal(before, config.get())
		end
	end)

	it("renders configurable symbols without disturbing other decorations or buffer contents", function()
		buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "before" })
		local ns = vim.api.nvim_create_namespace("interop_neighbor")
		vim.api.nvim_buf_set_extmark(
			buf,
			ns,
			0,
			0,
			{ sign_text = "!", sign_hl_group = "DiagnosticError", priority = 20 }
		)
		local diff = {
			hunks = { { type = "change", orig_start = 1, orig_count = 1, new_lines = { "after" } } },
			stats = { added = 0, deleted = 0, changed = 1 },
		}
		setup({ symbols = { badge = "*", change = "=>" }, sign_priority = 12 })
		stream.renderer.render_diff(buf, diff)
		local marks = vim.api.nvim_buf_get_extmarks(buf, stream.renderer.ns_id, 0, -1, { details = true })
		assert.are.equal(2, #marks)
		local summary, change
		for _, mark in ipairs(marks) do
			if mark[4].sign_text then
				change = mark[4]
			else
				summary = mark[4]
			end
		end
		assert.is_truthy(summary.virt_lines[1][1][1]:find(":AgentStreamAccept", 1, true))
		assert.are.equal("=> after", change.virt_lines[1][1][1])
		assert.are.equal(12, change.priority)
		assert.are.same({ "before" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
		setup({ show_summary = false, show_signs = false, show_virtual_lines = false })
		stream.renderer.render_diff(buf, diff)
		marks = vim.api.nvim_buf_get_extmarks(buf, stream.renderer.ns_id, 0, -1, { details = true })
		assert.are.equal(1, #marks)
		assert.is_nil(marks[1][4].sign_text)
		assert.is_nil(marks[1][4].virt_lines)
		stream.renderer.clear(buf)
		assert.are.equal(1, #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}))
	end)
end)
