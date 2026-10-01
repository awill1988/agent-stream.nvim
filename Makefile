.DEFAULT_GOAL := help

LOG_LEVEL ?= info

.PHONY: help
help: ## display available targets
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: test
test: ## run automated tests in release mode
	LOG_LEVEL=$(LOG_LEVEL) nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests { minimal_init = 'tests/minimal_init.lua' }"

.PHONY: test-debug
test-debug: ## run automated tests in debug mode
	LOG_LEVEL=debug nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests { minimal_init = 'tests/minimal_init.lua' }"

.PHONY: profile-memory
profile-memory: ## run memory profiling benchmark
	nvim --headless -u tests/minimal_init.lua -c "lua collectgarbage('collect'); local b1 = collectgarbage('count'); require('agent-stream').setup({}); collectgarbage('collect'); local b2 = collectgarbage('count'); print(string.format('memory baseline: %.2f kb | setup overhead: %.2f kb', b1, b2 - b1)); vim.cmd('q')"

.PHONY: lint
lint: ## validate syntax of all lua files
	nvim --headless -u tests/minimal_init.lua -c "lua local files = vim.fn.glob('lua/**/*.lua', false, true); for _, f in ipairs(files) do assert(loadfile(f))() end; print('syntax check passed: ' .. #files .. ' files verified'); vim.cmd('q')"

