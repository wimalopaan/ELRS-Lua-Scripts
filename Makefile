SRC_DIR := src
TEST_DIR := test

LUA_DIRS := $(SRC_DIR) $(TEST_DIR)

.PHONY: help install-tools lint format format-check check

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "  install-tools  Install selene and stylua via cargo"
	@echo "  lint           Run selene linter"
	@echo "  format         Format Lua files with stylua"
	@echo "  format-check   Check formatting without modifying files"
	@echo "  check          Run format-check and lint"

install-tools:
	@command -v cargo >/dev/null 2>&1 || { echo "cargo is required (install Rust: https://rustup.rs)"; exit 1; }
	cargo install selene
	cargo install stylua --features lua52

lint:
	selene $(LUA_DIRS)

format:
	stylua $(LUA_DIRS)

format-check:
	stylua --check $(LUA_DIRS)

check: format-check lint
