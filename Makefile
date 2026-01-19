# =============================================================================
# Makefile for Shell Script Testing Infrastructure
# =============================================================================

.PHONY: all test test-unit test-integration test-e2e test-all test-setup test-clean help ensure-test-deps \
       test-actions test-actions-install test-actions-typecheck test-actions-lint test-actions-build \
       sync-actions-templates

# Default target
all: test

# =============================================================================
# Configuration
# =============================================================================

BATS := bats
TESTS_DIR := tests
UNIT_DIR := $(TESTS_DIR)/unit
INTEGRATION_DIR := $(TESTS_DIR)/integration
E2E_DIR := $(TESTS_DIR)/e2e

# Bats options
BATS_OPTS := --timing --print-output-on-failure

# GitHub Actions configuration
ACTIONS_DIR := .github/actions
ACTIONS := project-automation pr-status-update auto-tag
TEMPLATES_ACTIONS_DIR := templates/github-actions/.github

# =============================================================================
# Dependency Check
# =============================================================================

## Ensure test dependencies are installed (bats + submodules)
ensure-test-deps:
	@if ! command -v bats >/dev/null 2>&1; then \
		echo "Bats not found. Installing..."; \
		if command -v apt-get >/dev/null 2>&1; then \
			sudo apt-get update -qq && sudo apt-get install -y -qq bats; \
		elif command -v brew >/dev/null 2>&1; then \
			brew install bats-core; \
		else \
			echo "Error: Cannot install bats. Please install manually."; \
			exit 1; \
		fi; \
		echo "Bats installed: $$(bats --version)"; \
	fi
	@if [ -f ".gitmodules" ] && [ ! -f "$(TESTS_DIR)/libs/bats-support/load.bash" ]; then \
		echo "Initializing git submodules..."; \
		git submodule update --init --recursive; \
		echo "Submodules initialized."; \
	fi

# =============================================================================
# Test Targets
# =============================================================================

## Run unit tests only
test-unit: ensure-test-deps
	@echo "Running unit tests..."
	@if [ -d "$(UNIT_DIR)" ] && [ -n "$$(ls -A $(UNIT_DIR)/*.bats 2>/dev/null)" ]; then \
		$(BATS) $(BATS_OPTS) $(UNIT_DIR)/*.bats; \
	else \
		echo "No unit tests found in $(UNIT_DIR)"; \
	fi

## Run integration tests only
test-integration: ensure-test-deps
	@echo "Running integration tests..."
	@if [ -d "$(INTEGRATION_DIR)" ] && [ -n "$$(ls -A $(INTEGRATION_DIR)/*.bats 2>/dev/null)" ]; then \
		$(BATS) $(BATS_OPTS) $(INTEGRATION_DIR)/*.bats; \
	else \
		echo "No integration tests found in $(INTEGRATION_DIR)"; \
	fi

## Run E2E tests only (local execution)
test-e2e: ensure-test-deps
	@echo "Running E2E tests (this may take a while)..."
	@if [ -d "$(E2E_DIR)" ] && [ -n "$$(ls -A $(E2E_DIR)/*.bats 2>/dev/null)" ]; then \
		$(BATS) $(BATS_OPTS) $(E2E_DIR)/*.bats; \
	else \
		echo "No E2E tests found in $(E2E_DIR)"; \
	fi

## Run unit and integration tests (CI target)
test: test-unit test-integration
	@echo "All CI tests completed."

## Run all tests (unit, integration, and E2E)
test-all: test-unit test-integration test-e2e
	@echo "All tests completed."

# =============================================================================
# Setup and Cleanup
# =============================================================================

## Setup test environment (install bats if needed)
test-setup:
	@echo "Setting up test environment..."
	@if ! command -v bats >/dev/null 2>&1; then \
		echo "Installing bats-core..."; \
		if command -v apt-get >/dev/null 2>&1; then \
			sudo apt-get update && sudo apt-get install -y bats; \
		elif command -v brew >/dev/null 2>&1; then \
			brew install bats-core; \
		else \
			echo "Please install bats-core manually: https://github.com/bats-core/bats-core"; \
			exit 1; \
		fi; \
	else \
		echo "bats is already installed: $$(bats --version)"; \
	fi
	@echo "Initializing git submodules..."
	@git submodule update --init --recursive
	@echo "Test environment setup complete."

## Clean test artifacts
test-clean:
	@echo "Cleaning test artifacts..."
	@rm -rf $(TESTS_DIR)/tmp
	@rm -rf $(TESTS_DIR)/.bats-run-*
	@echo "Test artifacts cleaned."

# =============================================================================
# CI Target
# =============================================================================

## CI test target (same as test, for GitHub Actions)
ci-test: test

# =============================================================================
# GitHub Actions Testing
# =============================================================================

## Install dependencies for all GitHub Actions
test-actions-install:
	@echo "Installing dependencies for GitHub Actions..."
	@for action in $(ACTIONS); do \
		echo "  Installing $$action..."; \
		cd $(ACTIONS_DIR)/$$action && pnpm install --frozen-lockfile && cd - > /dev/null; \
	done
	@echo "Dependencies installed."

## Run typecheck for all GitHub Actions
test-actions-typecheck: test-actions-install
	@echo "Running typecheck for GitHub Actions..."
	@for action in $(ACTIONS); do \
		echo "  Typechecking $$action..."; \
		cd $(ACTIONS_DIR)/$$action && pnpm run typecheck && cd - > /dev/null; \
	done
	@echo "Typecheck completed."

## Run lint for all GitHub Actions
test-actions-lint: test-actions-install
	@echo "Running lint for GitHub Actions..."
	@for action in $(ACTIONS); do \
		echo "  Linting $$action..."; \
		cd $(ACTIONS_DIR)/$$action && pnpm run lint && cd - > /dev/null; \
	done
	@echo "Lint completed."

## Build all GitHub Actions
test-actions-build: test-actions-install
	@echo "Building GitHub Actions..."
	@for action in $(ACTIONS); do \
		echo "  Building $$action..."; \
		cd $(ACTIONS_DIR)/$$action && pnpm run build && cd - > /dev/null; \
	done
	@echo "Build completed."

## Run full check for all GitHub Actions (install → typecheck → lint → build → test)
test-actions: test-actions-install
	@echo "Running full check for GitHub Actions..."
	@for action in $(ACTIONS); do \
		echo ""; \
		echo "=== Testing $$action ==="; \
		echo "  [1/4] Typechecking..." && (cd $(ACTIONS_DIR)/$$action && pnpm run typecheck) && \
		echo "  [2/4] Linting..." && (cd $(ACTIONS_DIR)/$$action && pnpm run lint) && \
		echo "  [3/4] Building..." && (cd $(ACTIONS_DIR)/$$action && pnpm run build) && \
		echo "  [4/4] Testing..." && (cd $(ACTIONS_DIR)/$$action && pnpm run test); \
	done
	@echo ""
	@echo "All GitHub Actions checks completed successfully."

## Sync GitHub Actions build artifacts to templates
sync-actions-templates: test-actions-build
	@echo "Syncing GitHub Actions to templates..."
	@for action in $(ACTIONS); do \
		echo "  Syncing $$action..."; \
		mkdir -p $(TEMPLATES_ACTIONS_DIR)/actions/$$action/dist; \
		cp $(ACTIONS_DIR)/$$action/action.yml $(TEMPLATES_ACTIONS_DIR)/actions/$$action/; \
		rm -rf $(TEMPLATES_ACTIONS_DIR)/actions/$$action/dist/*; \
		cp -r $(ACTIONS_DIR)/$$action/dist/* $(TEMPLATES_ACTIONS_DIR)/actions/$$action/dist/; \
	done
	@echo "  Syncing workflows..."
	@cp .github/workflows/project-automation.yml $(TEMPLATES_ACTIONS_DIR)/workflows/
	@cp .github/workflows/pr-status-update.yml $(TEMPLATES_ACTIONS_DIR)/workflows/
	@cp .github/workflows/auto-tag.yml $(TEMPLATES_ACTIONS_DIR)/workflows/
	@echo "  Syncing version.yml..."
	@cp .github/version.yml $(TEMPLATES_ACTIONS_DIR)/
	@echo "Sync completed."

# =============================================================================
# Linting
# =============================================================================

## Run shellcheck on all shell scripts
lint:
	@echo "Running shellcheck..."
	@find . -name "*.sh" -not -path "./tests/libs/*" -not -path "./.git/*" | xargs shellcheck

## Run shellcheck on test helpers
lint-tests:
	@echo "Running shellcheck on test helpers..."
	@find $(TESTS_DIR)/helpers -name "*.bash" | xargs shellcheck

# =============================================================================
# Help
# =============================================================================

## Show this help message
help:
	@echo "Available targets:"
	@echo ""
	@echo "Shell Script Testing:"
	@echo "  test-unit        Run unit tests only"
	@echo "  test-integration Run integration tests only"
	@echo "  test-e2e         Run E2E tests only (local execution)"
	@echo "  test             Run unit + integration tests (CI target)"
	@echo "  test-all         Run all tests (unit, integration, E2E)"
	@echo ""
	@echo "GitHub Actions Testing:"
	@echo "  test-actions          Run full check (typecheck → lint → build → test)"
	@echo "  test-actions-install  Install dependencies for all actions"
	@echo "  test-actions-typecheck Run typecheck for all actions"
	@echo "  test-actions-lint     Run lint for all actions"
	@echo "  test-actions-build    Build all actions"
	@echo "  sync-actions-templates Sync build artifacts to templates/"
	@echo ""
	@echo "Setup and Cleanup:"
	@echo "  ensure-test-deps Auto-install test dependencies if missing"
	@echo "  test-setup       Setup test environment (install bats)"
	@echo "  test-clean       Clean test artifacts"
	@echo ""
	@echo "Linting:"
	@echo "  lint             Run shellcheck on all shell scripts"
	@echo "  lint-tests       Run shellcheck on test helpers"
	@echo ""
	@echo "  help             Show this help message"
