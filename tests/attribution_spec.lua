local attribution = require("agent-stream.attribution")

describe("attribution", function()
	it("parses tmux output and prioritizes known agents", function()
		local mock_output = table.concat({
			"%0:1200:nvim:/home/adam/projects:0",
			"%1:1300:codex:/home/adam/projects/agent-stream.nvim:1",
			"%2:1400:bash:/home/adam:0",
		}, "\n")

		local res = attribution.parse_tmux_panes(mock_output, "/home/adam/projects/agent-stream.nvim/test.lua")

		assert.is_not_nil(res)
		assert.are.same("tmux", res.source)
		assert.are.same("codex", res.name)
		assert.are.same("%1", res.pane_id)
		assert.are.same(1300, res.pid)
	end)

	it("returns nil when no matching tmux panes exist", function()
		local mock_output = table.concat({
			"%0:1200:nvim:/home/adam/projects:1",
		}, "\n")

		local res = attribution.parse_tmux_panes(mock_output, "/home/adam/projects/test.lua")
		assert.is_nil(res)
	end)
end)
