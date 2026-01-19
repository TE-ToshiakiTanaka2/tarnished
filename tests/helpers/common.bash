#!/bin/bash
# =============================================================================
# Test Helper: Common Functions
# Provides shared utilities for all test types (unit, integration, e2e)
# =============================================================================

# Prevent multiple loading
if [[ -n "${_TEST_COMMON_LOADED:-}" ]]; then
    return 0
fi
_TEST_COMMON_LOADED=1

# =============================================================================
# Path Utilities
# =============================================================================

# Get the project root directory
get_project_root() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "$(cd "${script_dir}/../.." && pwd)"
}

# Get the tests directory
get_tests_dir() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "$(cd "${script_dir}/.." && pwd)"
}

# =============================================================================
# Source File Loading
# =============================================================================

# Load setup.sh functions for testing
# Note: This sources the file in a way that doesn't execute main()
load_setup_functions() {
    local project_root
    project_root="$(get_project_root)"

    # Source the file but prevent main() from running
    # We do this by checking if the file is being sourced
    (
        # Create a subshell to isolate the sourcing
        cd "${project_root}" || return 1

        # Export a flag to indicate we're in test mode
        export BATS_TEST_MODE=1

        # Source the setup.sh file
        # shellcheck source=/dev/null
        source "${project_root}/setup.sh"
    )
}

# Load common.sh functions for testing
load_common_functions() {
    local project_root
    project_root="$(get_project_root)"

    # shellcheck source=/dev/null
    source "${project_root}/scripts/lib/common.sh"
}

# Source setup.sh functions into current shell (for direct function access)
source_setup_functions() {
    local project_root
    project_root="$(get_project_root)"

    # We need to source in a way that skips the main execution
    # The setup.sh should have a guard for this
    export BATS_TEST_MODE=1
    export SCRIPT_DIR="${project_root}"
    export TEMPLATES_DIR="${project_root}/templates"

    # Source common.sh first (dependency)
    # shellcheck source=/dev/null
    source "${project_root}/scripts/lib/common.sh"

    # Now we need to extract functions from setup.sh without running main
    # We'll create a temporary file that sources setup.sh but replaces main
    local temp_setup
    temp_setup="$(mktemp)"

    # Copy setup.sh but replace the main call at the end
    sed 's/^main "\$@"$/# main "$@" # disabled for testing/' "${project_root}/setup.sh" > "${temp_setup}"

    # shellcheck source=/dev/null
    source "${temp_setup}"

    rm -f "${temp_setup}"
}

# =============================================================================
# Temporary Directory Management
# =============================================================================

# Global variable for temp directory
TEST_TEMP_DIR=""

# Setup a temporary directory for tests
setup_temp_dir() {
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR
}

# Teardown the temporary directory
teardown_temp_dir() {
    if [[ -n "${TEST_TEMP_DIR}" && -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
    TEST_TEMP_DIR=""
}

# =============================================================================
# Bats Library Loading
# =============================================================================

# Load all bats helper libraries
load_bats_libraries() {
    local tests_dir
    tests_dir="$(get_tests_dir)"

    # Load bats-support (must be first)
    # shellcheck source=/dev/null
    load "${tests_dir}/libs/bats-support/load.bash"

    # Load bats-assert
    # shellcheck source=/dev/null
    load "${tests_dir}/libs/bats-assert/load.bash"

    # Load bats-file
    # shellcheck source=/dev/null
    load "${tests_dir}/libs/bats-file/load.bash"
}

# =============================================================================
# Test Utilities
# =============================================================================

# Skip test if command not found
skip_if_command_not_found() {
    local cmd="$1"
    if ! command -v "${cmd}" &>/dev/null; then
        skip "${cmd} is not installed"
    fi
}

# Skip test if not running in Docker
skip_if_not_in_docker() {
    if [[ ! -f /.dockerenv ]]; then
        skip "Not running in Docker container"
    fi
}

# Create a test fixture file
create_fixture_file() {
    local filename="$1"
    local content="$2"
    local filepath="${TEST_TEMP_DIR}/${filename}"

    mkdir -p "$(dirname "${filepath}")"
    echo "${content}" > "${filepath}"
    echo "${filepath}"
}

# Create a test fixture JSON file
create_fixture_json() {
    local filename="$1"
    local json_content="$2"
    local filepath="${TEST_TEMP_DIR}/${filename}"

    mkdir -p "$(dirname "${filepath}")"
    echo "${json_content}" > "${filepath}"
    echo "${filepath}"
}

# =============================================================================
# Git Repository Utilities (for e2e tests)
# =============================================================================

# Initialize a test directory as a Git repository
# This is required for setup.sh which expects to run in a Git repository
# Usage: init_test_git_repo "/path/to/test/dir"
init_test_git_repo() {
    local target_dir="$1"

    if [[ -z "$target_dir" ]]; then
        echo "Error: target_dir is required" >&2
        return 1
    fi

    if [[ ! -d "$target_dir" ]]; then
        echo "Error: target_dir does not exist: $target_dir" >&2
        return 1
    fi

    (
        cd "$target_dir" || return 1

        # Initialize git repository
        git init -q

        # Configure git user for commits (required for commits to work)
        git config user.email "test@example.com"
        git config user.name "Test User"

        # Create initial commit (required for branch operations)
        touch .gitkeep
        git add .gitkeep
        git commit -q -m "Initial commit for test"

        # Add dummy origin remote (setup.sh requires origin to be configured)
        git remote add origin "https://github.com/test/test-repo.git"

        # Create develop branch (setup.sh expects to be on develop branch)
        git checkout -q -b develop
    )
}
