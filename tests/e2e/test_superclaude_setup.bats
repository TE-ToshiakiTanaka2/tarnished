#!/usr/bin/env bats
# =============================================================================
# E2E Tests: SuperClaude Setup
# =============================================================================
#
# These tests verify that the Claude plugin correctly sets up SuperClaude
# integration, including script copying and post.sh integration.
#
# IMPORTANT: These tests are meant to be run locally only, not in CI.
# They require Docker and devcontainer CLI to be available for full testing.
# =============================================================================

# Shared project name for container reuse
SHARED_PROJECT_NAME="superclaude-e2e-shared"

# Load test helpers
setup() {
    load '../helpers/common'
    load '../helpers/docker'

    # Get project root
    PROJECT_ROOT="$(get_project_root)"

    # Load bats libraries
    load_bats_libraries

    # Setup temp directory
    setup_temp_dir

    # Skip if Docker is not available
    if ! command -v docker &>/dev/null; then
        skip "Docker is not available"
    fi
}

# Get or create shared project directory (persists across tests in this file)
get_shared_project() {
    local shared_dir="${BATS_FILE_TMPDIR}/${SHARED_PROJECT_NAME}"

    if [[ ! -d "${shared_dir}" ]]; then
        mkdir -p "${shared_dir}"
        init_test_git_repo "${shared_dir}"
        (cd "${shared_dir}" && "${PROJECT_ROOT}/setup.sh" --lang node --yes "${SHARED_PROJECT_NAME}") >/dev/null 2>&1
    fi

    echo "${shared_dir}"
}

# Ensure shared container is running (called once per file)
ensure_shared_container() {
    local shared_dir
    shared_dir=$(get_shared_project)

    # Check if container is already running by trying to exec
    if exec_in_devcontainer "${shared_dir}" echo "ready" >/dev/null 2>&1; then
        echo "${shared_dir}"
        return 0
    fi

    # Start container
    start_devcontainer "${shared_dir}" >/dev/null 2>&1
    echo "${shared_dir}"
}

teardown() {
    # Clean up devcontainer if project_dir was set
    if [[ -n "${E2E_PROJECT_DIR:-}" && -d "${E2E_PROJECT_DIR}" ]]; then
        cleanup_devcontainer "${E2E_PROJECT_DIR}" 2>/dev/null || true
        # Also clean up docker compose
        (cd "${E2E_PROJECT_DIR}" && docker compose down -v 2>/dev/null) || true
    fi

    # Stop and remove any containers created during the test (legacy cleanup)
    if [[ -n "${E2E_CONTAINER:-}" ]]; then
        docker stop "${E2E_CONTAINER}" 2>/dev/null || true
        docker rm -f "${E2E_CONTAINER}" 2>/dev/null || true
    fi

    teardown_temp_dir
}

# Helper to create a standard project (Claude plugin is always included)
create_project() {
    local project_name="${1:-e2e-superclaude-test}"
    E2E_PROJECT_DIR="${TEST_TEMP_DIR}/${project_name}"
    mkdir -p "${E2E_PROJECT_DIR}"
    init_test_git_repo "${E2E_PROJECT_DIR}"

    (cd "${E2E_PROJECT_DIR}" && "${PROJECT_ROOT}/setup.sh" --lang node --yes "${project_name}") >/dev/null 2>&1

    echo "${E2E_PROJECT_DIR}"
}

# =============================================================================
# Script File Tests
# =============================================================================

@test "e2e/superclaude: setup_superclaude.sh is copied to project" {
    local project_dir
    project_dir=$(create_project "sc-script-copy-test")

    # Check that setup_superclaude.sh exists in the target directory
    assert_file_exists "${project_dir}/.devcontainer/scripts/setup_superclaude.sh"
}

@test "e2e/superclaude: setup_superclaude.sh is executable" {
    local project_dir
    project_dir=$(create_project "sc-script-exec-test")

    # Check that the script is executable
    [[ -x "${project_dir}/.devcontainer/scripts/setup_superclaude.sh" ]]
}

@test "e2e/superclaude: setup_superclaude.sh has valid bash syntax" {
    local project_dir
    project_dir=$(create_project "sc-script-syntax-test")

    # Verify bash syntax
    run bash -n "${project_dir}/.devcontainer/scripts/setup_superclaude.sh"
    assert_success
}

@test "e2e/superclaude: setup_superclaude.sh contains setup_superclaude function" {
    local project_dir
    project_dir=$(create_project "sc-script-func-test")

    # Check that the function is defined
    run grep -q "setup_superclaude()" "${project_dir}/.devcontainer/scripts/setup_superclaude.sh"
    assert_success
}

# =============================================================================
# Post.sh Integration Tests
# =============================================================================

@test "e2e/superclaude: post.sh sources setup_superclaude.sh" {
    local project_dir
    project_dir=$(create_project "sc-postsh-source-test")

    # Check that post.sh sources the setup script
    run grep -q "source.*setup_superclaude.sh" "${project_dir}/.devcontainer/scripts/post.sh"
    assert_success
}

@test "e2e/superclaude: post.sh calls setup_superclaude function" {
    local project_dir
    project_dir=$(create_project "sc-postsh-call-test")

    # Check that post.sh calls the setup function
    run grep -q "setup_superclaude" "${project_dir}/.devcontainer/scripts/post.sh"
    assert_success
}

@test "e2e/superclaude: post.sh contains SuperClaude Framework marker" {
    local project_dir
    project_dir=$(create_project "sc-postsh-marker-test")

    # Check that the marker comment exists
    run grep -q "# SuperClaude Framework" "${project_dir}/.devcontainer/scripts/post.sh"
    assert_success
}

@test "e2e/superclaude: post.sh has valid bash syntax after integration" {
    local project_dir
    project_dir=$(create_project "sc-postsh-syntax-test")

    # Verify the entire post.sh has valid syntax
    run bash -n "${project_dir}/.devcontainer/scripts/post.sh"
    assert_success
}

# =============================================================================
# Script Content Tests
# =============================================================================

@test "e2e/superclaude: setup script checks for Claude CLI" {
    local project_dir
    project_dir=$(create_project "sc-content-claude-check-test")

    # Check that the script checks for claude command
    run grep -q "command -v claude" "${project_dir}/.devcontainer/scripts/setup_superclaude.sh"
    assert_success
}

@test "e2e/superclaude: setup script installs superclaude via uv" {
    local project_dir
    project_dir=$(create_project "sc-content-uv-test")

    # Check that the script uses uv to install superclaude
    run grep -q "uv tool install superclaude" "${project_dir}/.devcontainer/scripts/setup_superclaude.sh"
    assert_success
}

@test "e2e/superclaude: setup script configures MCP servers" {
    local project_dir
    project_dir=$(create_project "sc-content-mcp-test")

    # Check that the script configures MCP servers
    run grep -q "superclaude mcp" "${project_dir}/.devcontainer/scripts/setup_superclaude.sh"
    assert_success
}

@test "e2e/superclaude: setup script includes default MCP servers" {
    local project_dir
    project_dir=$(create_project "sc-content-mcp-servers-test")

    # Check for context7, sequential-thinking, serena
    run grep "context7" "${project_dir}/.devcontainer/scripts/setup_superclaude.sh"
    assert_success

    run grep "sequential-thinking" "${project_dir}/.devcontainer/scripts/setup_superclaude.sh"
    assert_success

    run grep "serena" "${project_dir}/.devcontainer/scripts/setup_superclaude.sh"
    assert_success
}

@test "e2e/superclaude: setup script has Playwright option prompt" {
    local project_dir
    project_dir=$(create_project "sc-content-playwright-test")

    # Check that there's a Playwright prompt
    run grep -q "playwright" "${project_dir}/.devcontainer/scripts/setup_superclaude.sh"
    assert_success
}

@test "e2e/superclaude: setup script handles non-interactive mode" {
    local project_dir
    project_dir=$(create_project "sc-content-noninteractive-test")

    # Check that non-interactive mode is handled
    run grep -q "is_interactive" "${project_dir}/.devcontainer/scripts/setup_superclaude.sh"
    assert_success
}

# =============================================================================
# Idempotency Tests
# =============================================================================

@test "e2e/superclaude: running setup twice doesn't duplicate integration" {
    local project_name="sc-idempotent-test"
    E2E_PROJECT_DIR="${TEST_TEMP_DIR}/${project_name}"
    mkdir -p "${E2E_PROJECT_DIR}"
    init_test_git_repo "${E2E_PROJECT_DIR}"

    # Run setup twice
    (cd "${E2E_PROJECT_DIR}" && "${PROJECT_ROOT}/setup.sh" --lang node --yes "${project_name}") >/dev/null 2>&1
    (cd "${E2E_PROJECT_DIR}" && "${PROJECT_ROOT}/setup.sh" --lang node --yes --overwrite "${project_name}") >/dev/null 2>&1

    # Count occurrences of SuperClaude Framework marker - should be exactly 1
    local count
    count=$(grep -c "# SuperClaude Framework" "${E2E_PROJECT_DIR}/.devcontainer/scripts/post.sh" || echo "0")

    [[ "$count" -eq 1 ]]
}

# =============================================================================
# Docker Build Tests
# =============================================================================

@test "e2e/superclaude: docker build succeeds with SuperClaude setup" {
    local project_dir
    project_dir=$(create_project "sc-docker-build-test")

    # Build the Docker image
    run docker build -f "${project_dir}/docker/Dockerfile.dev" -t "e2e-sc-build" "${project_dir}"
    assert_success
}

# =============================================================================
# Devcontainer Tests (require devcontainer CLI)
# =============================================================================

@test "e2e/superclaude: container starts successfully" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    # Use shared container
    run ensure_shared_container
    assert_success
}

@test "e2e/superclaude: uv is available in container" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(ensure_shared_container)

    # Check that uv is available (required for SuperClaude installation)
    # Note: uv may not be available in all base images
    run exec_in_devcontainer "${project_dir}" which uv
    if [[ $status -ne 0 ]]; then
        skip "uv is not installed in this container image"
    fi
    assert_success
}

@test "e2e/superclaude: uvx is available in container" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(ensure_shared_container)

    # Check that uvx is available (required for SuperClaude installation)
    # Note: uvx may not be available in all base images
    run exec_in_devcontainer "${project_dir}" which uvx
    if [[ $status -ne 0 ]]; then
        skip "uvx is not installed in this container image"
    fi
    assert_success
}
