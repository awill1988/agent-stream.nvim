local watcher = require("agent-stream.watcher")

describe("watcher", function()
	it("normalizes paths consistently", function()
		local p1 = watcher.normalize_path("./tests/minimal_init.lua")
		local p2 = watcher.normalize_path("tests/minimal_init.lua")

		assert.is_not_nil(p1)
		assert.are.same(p1, p2)
		assert.are.same("", watcher.normalize_path(""))
	end)

	it("identifies internal writes within debounce window", function()
		local test_path = "/tmp/agent_stream_test.lua"
		assert.is_false(watcher.is_internal_write(test_path))

		watcher.mark_internal_write(test_path)
		assert.is_true(watcher.is_internal_write(test_path))
	end)
end)
