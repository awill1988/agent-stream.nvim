.DEFAULT_GOAL := help
BASE_REF ?= origin/main
HEAD_REF ?= HEAD
LOG_LEVEL ?= info
NVIM = python3 scripts/nvim.py
TEST = $(NVIM) --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests { minimal_init = 'tests/minimal_init.lua' }"

.PHONY: help deps check test test-debug profile-memory lint format tooling-test smoke coverage hooks demo-media media-check run run-debug
help: ## display available targets
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "%-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

deps: ## bootstrap pinned test dependencies (PLENARY_DIR overrides plenary)
	python3 scripts/bootstrap.py

test: deps ## run isolated release tests
	LOG_LEVEL=$(LOG_LEVEL) $(TEST)

test-debug: deps ## run isolated debug tests
	LOG_LEVEL=debug $(TEST)

run: deps ## open an isolated development editor
	$(NVIM) -u tests/minimal_init.lua

run-debug: deps ## open an isolated development editor with verbose logging
	LOG_LEVEL=debug $(NVIM) -V1 -u tests/minimal_init.lua

profile-memory: deps ## measure setup memory overhead
	$(NVIM) --headless -u tests/minimal_init.lua -c "lua collectgarbage('collect'); local before = collectgarbage('count'); require('agent-stream').setup({}); collectgarbage('collect'); print(string.format('setup overhead: %.2f kb', collectgarbage('count') - before)); vim.cmd('qa!')"

lint: ## check lua, shell, python, and workflows
	stylua --check lua plugin tests scripts/coverage.lua demo/session.lua
	luacheck lua plugin tests scripts/coverage.lua demo/session.lua
	shellcheck bin/agent-ctl scripts/*.sh .githooks/*
	actionlint
	ruff check scripts
	ruff format --check scripts

format: ## format lua and python
	stylua lua plugin tests scripts/coverage.lua demo/session.lua
	ruff check --fix scripts
	ruff format scripts

tooling-test: ## test commit and release tooling
	python3 -m unittest discover -s scripts -p 'test_*.py'

smoke: ## verify commands from a clean consumer configuration
	$(NVIM) --consumer --headless -u tests/consumer_init.lua -c "lua local ok, err = pcall(dofile, 'tests/consumer.lua'); if not ok then print(err); vim.cmd('cquit') end"

coverage: deps ## aggregate subprocess coverage including unexecuted modules
	python3 -c "from pathlib import Path; p = Path('.coverage'); p.mkdir(exist_ok=True); [f.unlink() for f in p.glob('*.stats.out')]"
	COVERAGE=1 $(TEST)
	$(NVIM) --headless -u NONE -l scripts/coverage.lua

media-check: ## validate showcase encoding and readme references
	python3 scripts/media.py check

demo-media: ## render the edited recording with vhs and ffmpeg
	vhs demo/showcase.tape
	python3 scripts/media.py convert
	$(MAKE) media-check

hooks: ## opt in to repository hooks
	git config --local core.hooksPath .githooks

agent-review: ## review committed changes with the pinned local model
	bash scripts/review.sh --base "$(BASE_REF)" --head "$(HEAD_REF)"

check: lint tooling-test smoke coverage media-check ## run deterministic local and ci quality gates
