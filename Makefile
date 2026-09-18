# container-ui — native SwiftUI GUI + TUI for apple/container

.DEFAULT_GOAL := build

.PHONY: build
build: ## Debug build of both the GUI and the TUI
	swift build

.PHONY: release
release: ## Optimized release build
	swift build -c release

.PHONY: app
app: release ## Build Container.app bundle (GUI)
	@scripts/bundle.sh release

.PHONY: run
run: app ## Build and launch the GUI app
	open build/Container.app

.PHONY: tui
tui: ## Build and run the terminal UI
	swift build -c release --product ctui
	.build/release/ctui

.PHONY: install
install: app ## Copy the app to /Applications and symlink ctui into /usr/local/bin
	rm -rf /Applications/Container.app
	cp -R build/Container.app /Applications/
	ln -sf "$(PWD)/.build/release/ctui" /usr/local/bin/ctui
	@echo "Installed Container.app and ctui"

.PHONY: clean
clean:
	rm -rf .build build

.PHONY: help
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'
