#!/usr/bin/env bats
# =============================================================================
# E2E Tests: Node.js Template
# =============================================================================
#
# These tests verify that a project created with the node template
# can be built and run successfully in Docker.
#
# IMPORTANT: These tests are meant to be run locally only, not in CI.
# They require Docker to be available and may take several minutes.
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
    # Stop and remove any containers created during the test
    if [[ -n "${E2E_CONTAINER:-}" ]]; then
        docker stop "${E2E_CONTAINER}" 2>/dev/null || true
        docker rm -f "${E2E_CONTAINER}" 2>/dev/null || true
    fi

    # Clean up docker-compose if project_dir was set
    if [[ -n "${E2E_PROJECT_DIR:-}" && -d "${E2E_PROJECT_DIR}" ]]; then
        (cd "${E2E_PROJECT_DIR}" && docker-compose down -v 2>/dev/null) || true
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
# Container Startup Tests
# =============================================================================

@test "e2e/node: container starts successfully" {
    local project_dir
    project_dir=$(create_node_project "node-startup-test")

    # Build the image
    docker build -f "${project_dir}/docker/Dockerfile.dev" -t "e2e-node-startup" "${project_dir}" >/dev/null 2>&1

    # Start the container
    E2E_CONTAINER=$(docker run -d --name "e2e-node-startup-container" "e2e-node-startup" tail -f /dev/null)

    # Wait for container to be ready
    run wait_for_container "${E2E_CONTAINER}" 30
    assert_success
}

# =============================================================================
# Command Availability Tests
# =============================================================================

@test "e2e/node: git is available in container" {
    local project_dir
    project_dir=$(create_node_project "node-git-test")

    docker build -f "${project_dir}/docker/Dockerfile.dev" -t "e2e-node-git" "${project_dir}" >/dev/null 2>&1
    E2E_CONTAINER=$(docker run -d --name "e2e-node-git-container" "e2e-node-git" tail -f /dev/null)
    wait_for_container "${E2E_CONTAINER}" 30

    run verify_command_exists "${E2E_CONTAINER}" "git"
    assert_success
}

@test "e2e/node: curl is available in container" {
    local project_dir
    project_dir=$(create_node_project "node-curl-test")

    docker build -f "${project_dir}/docker/Dockerfile.dev" -t "e2e-node-curl" "${project_dir}" >/dev/null 2>&1
    E2E_CONTAINER=$(docker run -d --name "e2e-node-curl-container" "e2e-node-curl" tail -f /dev/null)
    wait_for_container "${E2E_CONTAINER}" 30

    run verify_command_exists "${E2E_CONTAINER}" "curl"
    assert_success
}

@test "e2e/node: jq is available in container" {
    local project_dir
    project_dir=$(create_node_project "node-jq-test")

    docker build -f "${project_dir}/docker/Dockerfile.dev" -t "e2e-node-jq" "${project_dir}" >/dev/null 2>&1
    E2E_CONTAINER=$(docker run -d --name "e2e-node-jq-container" "e2e-node-jq" tail -f /dev/null)
    wait_for_container "${E2E_CONTAINER}" 30

    run verify_command_exists "${E2E_CONTAINER}" "jq"
    assert_success
}

@test "e2e/node: node is available in container" {
    local project_dir
    project_dir=$(create_node_project "node-node-test")

    docker build -f "${project_dir}/docker/Dockerfile.dev" -t "e2e-node-node" "${project_dir}" >/dev/null 2>&1
    E2E_CONTAINER=$(docker run -d --name "e2e-node-node-container" "e2e-node-node" tail -f /dev/null)
    wait_for_container "${E2E_CONTAINER}" 30

    run verify_command_exists "${E2E_CONTAINER}" "node"
    assert_success
}

@test "e2e/node: npm is available in container" {
    local project_dir
    project_dir=$(create_node_project "node-npm-test")

    docker build -f "${project_dir}/docker/Dockerfile.dev" -t "e2e-node-npm" "${project_dir}" >/dev/null 2>&1
    E2E_CONTAINER=$(docker run -d --name "e2e-node-npm-container" "e2e-node-npm" tail -f /dev/null)
    wait_for_container "${E2E_CONTAINER}" 30

    run verify_command_exists "${E2E_CONTAINER}" "npm"
    assert_success
}

@test "e2e/node: bun is available in container" {
    local project_dir
    project_dir=$(create_node_project "node-bun-test")

    docker build -f "${project_dir}/docker/Dockerfile.dev" -t "e2e-node-bun" "${project_dir}" >/dev/null 2>&1
    E2E_CONTAINER=$(docker run -d --name "e2e-node-bun-container" "e2e-node-bun" tail -f /dev/null)
    wait_for_container "${E2E_CONTAINER}" 30

    run verify_command_exists "${E2E_CONTAINER}" "bun"
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
    local project_dir
    project_dir=$(create_node_project "node-version-test")

    docker build -f "${project_dir}/docker/Dockerfile.dev" -t "e2e-node-version" "${project_dir}" >/dev/null 2>&1
    E2E_CONTAINER=$(docker run -d --name "e2e-node-version-container" "e2e-node-version" tail -f /dev/null)
    wait_for_container "${E2E_CONTAINER}" 30

    run get_command_version "${E2E_CONTAINER}" "node"
    assert_success
    # Should output version string containing "v" (e.g., v22.x.x)
    assert_output --regexp "v[0-9]+"
}
