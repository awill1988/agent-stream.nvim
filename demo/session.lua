vim.opt.runtimepath:append(vim.fn.getcwd())
vim.cmd("runtime plugin/agent-stream.lua")
vim.opt.termguicolors = true
vim.opt.number = true
vim.opt.signcolumn = "yes:1"
vim.opt.laststatus = 2
vim.opt.showmode = false
vim.opt.ruler = false
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.opt.shortmess:append("I")
vim.opt.fillchars = { eob = " " }
vim.cmd("colorscheme habamax")
for _, server in ipairs(vim.fn.serverlist()) do
	vim.fn.serverstop(server)
end
local stream = require("agent-stream")
stream.setup({ debounce_ms = 80, attribution = { check_tmux = false }, rpc = { enabled = false } })
local path = assert(vim.env.DEMO_FILE)
local original = {
	"local M = {}",
	"",
	"function M.greet(name)",
	'  return "hello, " .. name',
	"end",
	"",
	"return M",
}
vim.fn.writefile(original, path)
vim.cmd.edit(vim.fn.fnameescape(path))
local buf = vim.api.nvim_get_current_buf()
local accepted = vim.deepcopy(original)
accepted[4] = '  return string.format("hello, %s!", name)'
table.insert(accepted, 4, '  name = name or "world"')
local rejected = vim.deepcopy(accepted)
rejected[5] = '  return "goodbye"'
local function caption(text)
	vim.opt.statusline = "  agent-stream.nvim  |  " .. text
	vim.cmd("redraw!")
end
local function write_external(lines)
	local code = "import pathlib,sys; pathlib.Path(sys.argv[1]).write_text(sys.argv[2])"
	local result = vim.system({ "python3", "-c", code, path, table.concat(lines, "\n") .. "\n" }):wait()
	assert(result.code == 0, result.stderr)
end
local function later(ms, fn)
	vim.defer_fn(function()
		local ok, err = pcall(fn)
		if not ok then
			vim.fn.writefile({ tostring(err) }, vim.env.DEMO_ERROR)
			vim.cmd("cquit")
		end
	end, ms)
end
caption("watching greet.lua | buffer stays yours")
later(4000, function()
	write_external(accepted)
	caption("external edit on disk | preview without changing the buffer")
end)
later(7000, function()
	assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), original))
	assert(stream.renderer.active_state[buf])
end)
later(9000, function()
	vim.cmd("colorscheme retrobox")
	caption("theme switched | preview inherits native colors")
end)
later(13000, function()
	vim.cmd("AgentStreamAccept")
	assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), accepted))
	caption(":AgentStreamAccept | incoming changes applied to buffer")
end)
later(21000, function()
	write_external(rejected)
	caption("second external edit | review before deciding")
end)
later(29000, function()
	assert(stream.renderer.active_state[buf])
	vim.cmd("AgentStreamReject")
	assert(vim.deep_equal(vim.fn.readfile(path), accepted))
	caption(":AgentStreamReject | buffer written back to disk")
end)
later(36000, function()
	stream.watcher.stop_all()
	vim.cmd("qa!")
end)
