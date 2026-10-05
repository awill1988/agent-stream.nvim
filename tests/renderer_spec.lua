local renderer = require("agent-stream.renderer")

describe("renderer", function()
	local bufnr
	after_each(function()
		if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
			renderer.clear(bufnr)
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end
	end)
	it("renders extmarks and tracks state for buffer", function()
		bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line 1", "line 2", "line 3" })

		local diff_result = {
			bufnr = bufnr,
			file = "/tmp/test.lua",
			hunks = {
				{
					type = "add",
					orig_start = 2,
					orig_count = 0,
					new_start = 2,
					new_count = 1,
					new_lines = { "injected line" },
					orig_lines = {},
				},
			},
			stats = { added = 1, deleted = 0, changed = 0 },
			disk_lines = { "line 1", "injected line", "line 2", "line 3" },
		}

		renderer.render_diff(bufnr, diff_result, { details = "test" })

		local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, renderer.ns_id, 0, -1, {})
		assert.is_true(#extmarks >= 1)

		renderer.clear(bufnr)
		extmarks = vim.api.nvim_buf_get_extmarks(bufnr, renderer.ns_id, 0, -1, {})
		assert.are.same(0, #extmarks)

		vim.api.nvim_buf_delete(bufnr, { force = true })
	end)
end)
