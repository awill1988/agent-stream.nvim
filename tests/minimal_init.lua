local plenary_dir = vim.env.PLENARY_DIR or ".deps/plenary.nvim"

vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.shadafile = "NONE"
vim.env.TMUX = nil
vim.env.TMUX_PANE = nil
vim.env.AGENT_NAME = nil
vim.env.AGENT_PID = nil
for _, server in ipairs(vim.fn.serverlist()) do
	vim.fn.serverstop(server)
end

if vim.env.COVERAGE == "1" then
	package.path = ".deps/luacov/src/?.lua;.deps/luacov/src/?/init.lua;" .. package.path
	require("luacov.runner").init({
		statsfile = ".coverage/" .. vim.fn.getpid() .. ".stats.out",
		include = { "lua/agent%-stream/", "plugin/agent%-stream" },
	})
	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			require("luacov.runner").shutdown()
		end,
	})
end

vim.opt.rtp:append(".")
if vim.fn.isdirectory(plenary_dir) == 1 then
	vim.opt.rtp:append(plenary_dir)
end

vim.cmd("runtime! plugin/plenary.vim")
vim.cmd("runtime! plugin/agent-stream.lua")
