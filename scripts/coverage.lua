package.path = ".deps/luacov/src/?.lua;.deps/luacov/src/?/init.lua;" .. package.path
local stats = require("luacov.stats")
local merged = {}
local root = vim.fn.getcwd() .. "/"
for _, pattern in ipairs({ "lua/**/*.lua", "plugin/*.lua" }) do
	for _, file in ipairs(vim.fn.glob(pattern, false, true)) do
		merged[file] = { max = #vim.fn.readfile(file), max_hits = 0 }
	end
end
local inputs = vim.fn.glob(".coverage/*.stats.out", false, true)
assert(#inputs > 0, "no subprocess coverage collected")
for _, input in ipairs(inputs) do
	for file, data in pairs(assert(stats.load(input))) do
		if file:sub(1, #root) == root then
			file = file:sub(#root + 1)
		end
		file = file:gsub("^%./", "")
		local target = merged[file]
		if target then
			for line = 1, data.max do
				target[line] = (target[line] or 0) + (data[line] or 0)
				target.max_hits = math.max(target.max_hits, target[line])
			end
		end
	end
end
stats.save(".coverage/merged.out", merged)
require("luacov.runner").init({ statsfile = ".coverage/merged.out", reportfile = ".coverage/report.txt" })
require("luacov.runner").pause()
require("luacov.reporter").report()
local report = table.concat(vim.fn.readfile(".coverage/report.txt"), "\n")
local summary = assert(report:match("(Summary.*)"), "missing coverage summary")
vim.fn.writefile(vim.split("```text\n" .. summary .. "\n```", "\n"), ".coverage/summary.md")
print(summary)
vim.cmd("qa!")
