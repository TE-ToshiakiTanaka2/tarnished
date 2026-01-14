#!/usr/bin/env bats
# =============================================================================
# E2E Tests: Node.js Template
# =============================================================================
#
# These tests verify that a project created with the node template
# can be built and run successfully using devcontainer CLI.
#
# IMPORTANT: These tests are meant to be run locally only, not in CI.
# They require Docker and devcontainer CLI to be available.
# =============================================================================

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

teardown() {
    # Clean up devcontainer if project_dir was set
    if [[ -n "${E2E_PROJECT_DIR:-}" && -d "${E2E_PROJECT_DIR}" ]]; then
        cleanup_devcontainer "${E2E_PROJECT_DIR}" 2>/dev/null || true
        # Also clean up docker-compose
        (cd "${E2E_PROJECT_DIR}" && docker-compose down -v 2>/dev/null) || true
    fi

    # Stop and remove any containers created during the test (legacy cleanup)
    if [[ -n "${E2E_CONTAINER:-}" ]]; then
        docker stop "${E2E_CONTAINER}" 2>/dev/null || true
        docker rm -f "${E2E_CONTAINER}" 2>/dev/null || true
    fi

    teardown_temp_dir
}

# Helper to create a node project
create_node_project() {
    local project_name="${1:-e2e-node-test}"
    E2E_PROJECT_DIR="${TEST_TEMP_DIR}/${project_name}"
    mkdir -p "${E2E_PROJECT_DIR}"

    (cd "${E2E_PROJECT_DIR}" && "${PROJECT_ROOT}/setup.sh" --lang node --yes "${project_name}") >/dev/null 2>&1

    echo "${E2E_PROJECT_DIR}"
}

# =============================================================================
# Docker Build Tests
# =============================================================================

@test "e2e/node: docker build succeeds" {
    local project_dir
    project_dir=$(create_node_project "node-build-test")

    # Build the Docker image
    run docker build -f "${project_dir}/docker/Dockerfile.dev" -t "e2e-node-build-test" "${project_dir}"
    assert_success
}

@test "e2e/node: docker-compose build succeeds" {
    local project_dir
    project_dir=$(create_node_project "node-compose-build")

    # Build using docker-compose
    run bash -c "cd '${project_dir}' && docker-compose build"
    assert_success
}

# =============================================================================
# Devcontainer Startup Tests
# =============================================================================

@test "e2e/node: container starts successfully" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(create_node_project "node-startup-test")

    # Start devcontainer
    run start_devcontainer "${project_dir}"
    assert_success
}

# =============================================================================
# Command Availability Tests (using devcontainer CLI)
# =============================================================================

@test "e2e/node: git is available in container" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(create_node_project "node-git-test")

    start_devcontainer "${project_dir}" >/dev/null 2>&1

    run verify_devcontainer_command "${project_dir}" "git"
    assert_success
}

@test "e2e/node: curl is available in container" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(create_node_project "node-curl-test")

    start_devcontainer "${project_dir}" >/dev/null 2>&1

    run verify_devcontainer_command "${project_dir}" "curl"
    assert_success
}

@test "e2e/node: jq is available in container" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(create_node_project "node-jq-test")

    start_devcontainer "${project_dir}" >/dev/null 2>&1

    run verify_devcontainer_command "${project_dir}" "jq"
    assert_success
}

@test "e2e/node: node is available in container" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(create_node_project "node-node-test")

    start_devcontainer "${project_dir}" >/dev/null 2>&1

    run verify_devcontainer_command "${project_dir}" "node"
    assert_success
}

@test "e2e/node: npm is available in container" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(create_node_project "node-npm-test")

    start_devcontainer "${project_dir}" >/dev/null 2>&1

    run verify_devcontainer_command "${project_dir}" "npm"
    assert_success
}

@test "e2e/node: bun is available in container" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(create_node_project "node-bun-test")

    start_devcontainer "${project_dir}" >/dev/null 2>&1

    run verify_devcontainer_command "${project_dir}" "bun"
    assert_success
}

# =============================================================================
# Post.sh Execution Tests
# =============================================================================

@test "e2e/node: post.sh is executable" {
    local project_dir
    project_dir=$(create_node_project "node-postsh-test")

    [[ -x "${project_dir}/.devcontainer/scripts/post.sh" ]]
}

# =============================================================================
# Version Verification Tests
# =============================================================================

@test "e2e/node: node version is available" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(create_node_project "node-version-test")

    start_devcontainer "${project_dir}" >/dev/null 2>&1

    run get_devcontainer_command_version "${project_dir}" "node"
    assert_success
    # Should output version string containing "v" (e.g., v22.x.x)
    assert_output --regexp "v[0-9]+"
}
