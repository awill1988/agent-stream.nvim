for _, name in ipairs({
	"Accept",
	"Reject",
	"NextHunk",
	"PrevHunk",
	"Clear",
	"Focus",
	"Reveal",
	"Highlight",
	"Annotate",
	"Status",
}) do
	assert(vim.fn.exists(":AgentStream" .. name) == 2, "missing command: " .. name)
end
for _, server in ipairs(vim.fn.serverlist()) do
	vim.fn.serverstop(server)
end
require("agent-stream").setup({ rpc = { enabled = false }, attribution = { check_tmux = false } })
assert(require("agent-stream").status().active_watches == 0)
vim.cmd("qa!")
