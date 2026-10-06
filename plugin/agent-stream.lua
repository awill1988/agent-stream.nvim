if vim.g.loaded_agent_stream then
	return
end
vim.g.loaded_agent_stream = true

local agent_stream = require("agent-stream")

vim.api.nvim_create_user_command("AgentStreamAccept", function(opts)
	local bufnr = tonumber(opts.args)
	agent_stream.accept(bufnr)
end, {
	nargs = "?",
	desc = "Accept external file changes into current buffer",
})

vim.api.nvim_create_user_command("AgentStreamReject", function(opts)
	local bufnr = tonumber(opts.args)
	agent_stream.reject(bufnr)
end, {
	nargs = "?",
	desc = "Reject external file changes and restore buffer content to disk",
})

vim.api.nvim_create_user_command("AgentStreamCancel", function(opts)
	local bufnr = tonumber(opts.args)
	agent_stream.cancel(bufnr)
end, {
	nargs = "?",
	desc = "Interrupt the optimistic agent task without reverting accepted changes",
})

vim.api.nvim_create_user_command("AgentStreamResume", function(opts)
	local bufnr = tonumber(opts.args)
	agent_stream.resume(bufnr)
end, {
	nargs = "?",
	desc = "Send the configured resume instruction to an interrupted agent task",
})

vim.api.nvim_create_user_command("AgentStreamNextHunk", function()
	agent_stream.next_hunk()
end, {
	desc = "Jump cursor to next external diff hunk",
})

vim.api.nvim_create_user_command("AgentStreamPrevHunk", function()
	agent_stream.prev_hunk()
end, {
	desc = "Jump cursor to previous external diff hunk",
})

vim.api.nvim_create_user_command("AgentStreamClear", function()
	agent_stream.clear(vim.api.nvim_get_current_buf())
end, {
	desc = "Clear all external diff decorations for current buffer",
})

vim.api.nvim_create_user_command("AgentStreamFocus", function(opts)
	local parts = vim.split(opts.args, "%s+", { trimempty = true })
	if #parts < 1 then
		vim.notify("usage: AgentStreamFocus <file> [line] [col]", vim.log.levels.ERROR)
		return
	end
	agent_stream.focus(parts[1], tonumber(parts[2]), tonumber(parts[3]))
end, {
	nargs = "+",
	complete = "file",
	desc = "Focus a file and navigate cursor",
})

vim.api.nvim_create_user_command("AgentStreamReveal", function(opts)
	if opts.args == "" then
		vim.notify("usage: AgentStreamReveal <file>", vim.log.levels.ERROR)
		return
	end
	agent_stream.reveal(opts.args)
end, {
	nargs = 1,
	complete = "file",
	desc = "Reveal file in file explorer",
})

vim.api.nvim_create_user_command("AgentStreamHighlight", function(opts)
	local parts = vim.split(opts.args, "%s+", { trimempty = true })
	if #parts < 3 then
		vim.notify("usage: AgentStreamHighlight <file> <start_line> <end_line> [ms]", vim.log.levels.ERROR)
		return
	end
	agent_stream.highlight(parts[1], tonumber(parts[2]), tonumber(parts[3]), tonumber(parts[4]))
end, {
	nargs = "+",
	complete = "file",
	desc = "Temporarily highlight a line range",
})

vim.api.nvim_create_user_command("AgentStreamAnnotate", function(opts)
	local parts = vim.split(opts.args, "%s+", { trimempty = true })
	if #parts < 3 then
		vim.notify("usage: AgentStreamAnnotate <file> <line> <message>", vim.log.levels.ERROR)
		return
	end
	local file = parts[1]
	local line = tonumber(parts[2])
	local msg = table.concat(parts, " ", 3)
	agent_stream.annotate(file, line, msg)
end, {
	nargs = "+",
	complete = "file",
	desc = "Render temporary virtual agent comment",
})

vim.api.nvim_create_user_command("AgentStreamStatus", function()
	local status = agent_stream.status()
	vim.notify(
		string.format(
			"agent-stream: %d active watches, %d active diffs, %d optimistic accepts, server: %s",
			status.active_watches,
			status.active_diffs,
			status.optimistic,
			status.server or "none"
		),
		vim.log.levels.INFO
	)
end, {
	desc = "Display agent-stream runtime status",
})
