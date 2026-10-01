local diff_engine = require("agent-stream.diff_engine")

describe("diff_engine", function()
	it("detects no hunks for identical text", function()
		local orig = { "local a = 1", "local b = 2" }
		local new = { "local a = 1", "local b = 2" }
		local hunks, stats = diff_engine.compute_hunks(orig, new)

		assert.are.same(0, #hunks)
		assert.are.same(0, stats.added)
		assert.are.same(0, stats.deleted)
		assert.are.same(0, stats.changed)
	end)

	it("detects line additions correctly", function()
		local orig = { "line 1", "line 3" }
		local new = { "line 1", "line 2", "line 3" }
		local hunks, stats = diff_engine.compute_hunks(orig, new)

		assert.are.same(1, #hunks)
		assert.are.same("add", hunks[1].type)
		assert.are.same({ "line 2" }, hunks[1].new_lines)
		assert.are.same(1, stats.added)
	end)

	it("detects line deletions correctly", function()
		local orig = { "line 1", "line to remove", "line 3" }
		local new = { "line 1", "line 3" }
		local hunks, stats = diff_engine.compute_hunks(orig, new)

		assert.are.same(1, #hunks)
		assert.are.same("delete", hunks[1].type)
		assert.are.same({ "line to remove" }, hunks[1].orig_lines)
		assert.are.same(1, stats.deleted)
	end)

	it("detects line modifications correctly", function()
		local orig = { "print('before')" }
		local new = { "print('after')" }
		local hunks, stats = diff_engine.compute_hunks(orig, new)

		assert.are.same(1, #hunks)
		assert.are.same("change", hunks[1].type)
		assert.are.same({ "print('after')" }, hunks[1].new_lines)
		assert.are.same(1, stats.changed)
	end)

	it("dispatches events to registered listeners", function()
		local received = nil
		local handler = function(payload)
			received = payload
		end

		diff_engine.on("diff_updated", handler)
		diff_engine.emit("diff_updated", { bufnr = 42 })

		assert.are.same(42, received.bufnr)
		diff_engine.off("diff_updated", handler)

		received = nil
		diff_engine.emit("diff_updated", { bufnr = 99 })
		assert.is_nil(received)
	end)
end)
