-- tests/minimal_init.lua: test environment bootstrapper
local plenary_dir = vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim")

vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false

vim.opt.rtp:append(".")
if vim.fn.isdirectory(plenary_dir) == 1 then
	vim.opt.rtp:append(plenary_dir)
end

vim.cmd("runtime! plugin/plenary.vim")
vim.cmd("runtime! plugin/agent-stream.lua")
