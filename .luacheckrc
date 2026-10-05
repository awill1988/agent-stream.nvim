std = "luajit"
globals = { "vim" }
max_line_length = 140
ignore = { "212" }
files["tests/**/*.lua"] = { globals = { "describe", "it", "before_each", "after_each" }, ignore = { "212", "122", "143" } }
