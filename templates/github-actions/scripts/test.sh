#!/bin/bash
# =============================================================================
# GitHub Actions Plugin - Test Runner
# =============================================================================
#
# This script runs tests for all GitHub Actions in the plugin.
# Tests are run locally and are not committed to git.
#
# Usage:
#   ./scripts/test.sh              # Run all tests
#   ./scripts/test.sh --coverage   # Run tests with coverage
#   ./scripts/test.sh --watch      # Run tests in watch mode
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
ACTIONS_DIR="${PLUGIN_DIR}/.github/actions"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
TEST_MODE="run"
for arg in "$@"; do
    case $arg in
        --coverage)
            TEST_MODE="coverage"
            shift
            ;;
        --watch)
            TEST_MODE="watch"
            shift
            ;;
        *)
            ;;
    esac
done

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}GitHub Actions Plugin - Test Runner${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Track results
TOTAL_ACTIONS=0
PASSED_ACTIONS=0
FAILED_ACTIONS=0
SKIPPED_ACTIONS=0

# Find all actions with package.json (indicating they have tests)
for action_dir in "${ACTIONS_DIR}"/*/; do
    action_name=$(basename "$action_dir")

    if [[ -f "${action_dir}/package.json" ]]; then
        TOTAL_ACTIONS=$((TOTAL_ACTIONS + 1))

        echo -e "${YELLOW}Testing: ${action_name}${NC}"
        echo "----------------------------------------"

        cd "$action_dir"

        # Install dependencies if node_modules doesn't exist
        if [[ ! -d "node_modules" ]]; then
            echo "Installing dependencies..."
            npm install --silent 2>/dev/null || true
        fi

        # Check if test script exists in package.json
        if grep -q '"test"' package.json 2>/dev/null; then
            case $TEST_MODE in
                coverage)
                    if npm test -- --coverage 2>&1; then
                        echo -e "${GREEN}✓ ${action_name}: PASSED${NC}"
                        PASSED_ACTIONS=$((PASSED_ACTIONS + 1))
                    else
                        echo -e "${RED}✗ ${action_name}: FAILED${NC}"
                        FAILED_ACTIONS=$((FAILED_ACTIONS + 1))
                    fi
                    ;;
                watch)
                    npm run test:watch
                    ;;
                *)
                    if npm test 2>&1; then
                        echo -e "${GREEN}✓ ${action_name}: PASSED${NC}"
                        PASSED_ACTIONS=$((PASSED_ACTIONS + 1))
                    else
                        echo -e "${RED}✗ ${action_name}: FAILED${NC}"
                        FAILED_ACTIONS=$((FAILED_ACTIONS + 1))
                    fi
                    ;;
            esac
        else
            echo -e "${YELLOW}⊘ ${action_name}: No tests found${NC}"
            SKIPPED_ACTIONS=$((SKIPPED_ACTIONS + 1))
        fi

        echo ""
        cd "$PLUGIN_DIR"
    fi
done

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Total Actions: ${TOTAL_ACTIONS}"
echo -e "${GREEN}Passed: ${PASSED_ACTIONS}${NC}"
echo -e "${RED}Failed: ${FAILED_ACTIONS}${NC}"
echo -e "${YELLOW}Skipped: ${SKIPPED_ACTIONS}${NC}"
echo ""

if [[ $FAILED_ACTIONS -gt 0 ]]; then
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
