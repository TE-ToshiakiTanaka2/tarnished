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

# Shared project name for container reuse
SHARED_PROJECT_NAME="node-e2e-shared"

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

@test "e2e/node: docker compose build succeeds" {
    local project_dir
    project_dir=$(create_node_project "node-compose-build")

    # Build using docker compose
    run bash -c "cd '${project_dir}' && docker compose build"
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

    # Use shared container
    run ensure_shared_container
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
    project_dir=$(ensure_shared_container)

    run verify_devcontainer_command "${project_dir}" "git"
    assert_success
}

@test "e2e/node: curl is available in container" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(ensure_shared_container)

    run verify_devcontainer_command "${project_dir}" "curl"
    assert_success
}

@test "e2e/node: jq is available in container" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(ensure_shared_container)

    run verify_devcontainer_command "${project_dir}" "jq"
    assert_success
}

@test "e2e/node: node is available in container" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(ensure_shared_container)

    run verify_devcontainer_command "${project_dir}" "node"
    assert_success
}

@test "e2e/node: npm is available in container" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(ensure_shared_container)

    run verify_devcontainer_command "${project_dir}" "npm"
    assert_success
}

@test "e2e/node: bun is available in container" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(ensure_shared_container)

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
    project_dir=$(ensure_shared_container)

    run get_devcontainer_command_version "${project_dir}" "node"
    assert_success
    # Should output version string containing "v" (e.g., v22.x.x)
    assert_output --regexp "v[0-9]+"
}

# =============================================================================
# CI Workflow Tests
# =============================================================================

@test "e2e/node: setup.sh generates GitHub Actions workflow" {
    local project_dir
    project_dir=$(create_node_project "node-workflow-test")

    assert_file_exists "${project_dir}/.github/workflows/node-ci.yml"
}

@test "e2e/node: node-ci.yml contains required jobs" {
    local project_dir
    project_dir=$(create_node_project "node-ci-jobs-test")

    # Check for lint job
    run grep -q "lint:" "${project_dir}/.github/workflows/node-ci.yml"
    assert_success

    # Check for unit-test job
    run grep -q "unit-test:" "${project_dir}/.github/workflows/node-ci.yml"
    assert_success

    # Check for integration-test job
    run grep -q "integration-test:" "${project_dir}/.github/workflows/node-ci.yml"
    assert_success
}

@test "e2e/node: node-ci.yml uses pnpm" {
    local project_dir
    project_dir=$(create_node_project "node-ci-pnpm-test")

    run grep -q "pnpm/action-setup" "${project_dir}/.github/workflows/node-ci.yml"
    assert_success
}

@test "e2e/node: setup.sh generates package.json" {
    local project_dir
    project_dir=$(create_node_project "node-package-test")

    assert_file_exists "${project_dir}/package.json"
}

@test "e2e/node: package.json contains required scripts" {
    local project_dir
    project_dir=$(create_node_project "node-scripts-test")

    # Check for lint script
    run jq -e '.scripts.lint' "${project_dir}/package.json"
    assert_success

    # Check for test scripts
    run jq -e '.scripts.test' "${project_dir}/package.json"
    assert_success

    run jq -e '.scripts["test:unit"]' "${project_dir}/package.json"
    assert_success

    run jq -e '.scripts["test:integration"]' "${project_dir}/package.json"
    assert_success
}

@test "e2e/node: package.json contains required devDependencies" {
    local project_dir
    project_dir=$(create_node_project "node-deps-test")

    # Check for biome
    run jq -e '.devDependencies["@biomejs/biome"]' "${project_dir}/package.json"
    assert_success

    # Check for typescript
    run jq -e '.devDependencies.typescript' "${project_dir}/package.json"
    assert_success

    # Check for vitest
    run jq -e '.devDependencies.vitest' "${project_dir}/package.json"
    assert_success
}

@test "e2e/node: setup.sh generates biome.json" {
    local project_dir
    project_dir=$(create_node_project "node-biome-test")

    assert_file_exists "${project_dir}/biome.json"
}

@test "e2e/node: biome.json is valid JSON" {
    local project_dir
    project_dir=$(create_node_project "node-biome-valid-test")

    run jq -e '.' "${project_dir}/biome.json"
    assert_success
}

@test "e2e/node: setup.sh generates tsconfig.json" {
    local project_dir
    project_dir=$(create_node_project "node-tsconfig-test")

    assert_file_exists "${project_dir}/tsconfig.json"
}

@test "e2e/node: tsconfig.json is valid JSON" {
    local project_dir
    project_dir=$(create_node_project "node-tsconfig-valid-test")

    run jq -e '.' "${project_dir}/tsconfig.json"
    assert_success
}

@test "e2e/node: setup.sh generates vitest.config.ts" {
    local project_dir
    project_dir=$(create_node_project "node-vitest-test")

    assert_file_exists "${project_dir}/vitest.config.ts"
}

@test "e2e/node: setup.sh generates tests directory" {
    local project_dir
    project_dir=$(create_node_project "node-tests-dir-test")

    [[ -d "${project_dir}/tests" ]]
    [[ -d "${project_dir}/tests/unit" ]]
    [[ -d "${project_dir}/tests/integration" ]]
}

@test "e2e/node: tests directory contains sample tests" {
    local project_dir
    project_dir=$(create_node_project "node-sample-tests")

    assert_file_exists "${project_dir}/tests/unit/sample.test.ts"
    assert_file_exists "${project_dir}/tests/integration/sample.integration.test.ts"
}
