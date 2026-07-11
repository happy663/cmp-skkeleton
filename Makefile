PLENARY_PATH ?= $(HOME)/.local/share/nvim/lazy/plenary.nvim
PLUGIN_PATH := $(shell pwd)

.PHONY: test
test:
	env -u NVIM_LISTEN_ADDRESS nvim --headless \
		-u test/minimal_init.lua \
		-c "lua require('plenary.test_harness').test_directory('test/', { minimal_init = 'test/minimal_init.lua' })" \
		-c "qa!"
