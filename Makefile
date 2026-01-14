# =============================================================================
# Makefile for Shell Script Testing Infrastructure
# =============================================================================

.PHONY: all test test-unit test-integration test-e2e test-all test-setup test-clean help ensure-test-deps

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
	@echo "  test-unit        Run unit tests only"
	@echo "  test-integration Run integration tests only"
	@echo "  test-e2e         Run E2E tests only (local execution)"
	@echo "  test             Run unit + integration tests (CI target)"
	@echo "  test-all         Run all tests (unit, integration, E2E)"
	@echo ""
	@echo "  ensure-test-deps Auto-install test dependencies if missing"
	@echo "  test-setup       Setup test environment (install bats)"
	@echo "  test-clean       Clean test artifacts"
	@echo ""
	@echo "  lint             Run shellcheck on all shell scripts"
	@echo "  lint-tests       Run shellcheck on test helpers"
	@echo ""
	@echo "  help             Show this help message"
