NVIM ?= nvim

.PHONY: test
test:
	$(NVIM) --headless -u NONE -i NONE -n -l tests/run.lua
