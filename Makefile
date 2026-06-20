# RobloxMaze developer tasks. Tools are Rokit-pinned (see rokit.toml); their shims
# live in ~/.rokit/bin. Run `make install` once after cloning. Zero external deps.
SHELL := /usr/bin/env bash
export PATH := $(HOME)/.rokit/bin:$(PATH)

PROJECT := default.project.json

.PHONY: help install hooks serve build sourcemap fmt lint check serve-files

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  make %-12s %s\n", $$1, $$2}'

install: ## Install pinned tools (Rokit) + enable the git hooks
	rokit install
	@$(MAKE) hooks

hooks: ## Point git at the versioned pre-commit hook (.githooks)
	git config core.hooksPath .githooks
	@echo "git hooks enabled (.githooks/pre-commit)"

serve: ## Rojo serve to the Studio plugin (port 34873)
	rojo serve $(PROJECT)

build: ## Build a place file (gitignored)
	rojo build $(PROJECT) --output build.rbxlx

sourcemap: ## Refresh the LSP sourcemap
	rojo sourcemap $(PROJECT) --include-non-scripts -o sourcemap.json

fmt: ## Format with StyLua (writes changes)
	stylua .

lint: ## Lint with Selene
	selene .

check: ## CI-style gate: formatting + lint + build, no writes
	stylua --check .
	selene .
	rojo build $(PROJECT) --output /tmp/robloxmaze-check.rbxlx
	@echo "check: OK"

serve-files: ## HTTP server for the Studio code-sync fallback (see scripts/studio-sync.luau)
	./scripts/serve-files.sh
