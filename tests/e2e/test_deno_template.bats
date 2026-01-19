#!/usr/bin/env bats
# =============================================================================
# E2E Tests: Deno Template
# =============================================================================
#
# These tests verify that a project created with the deno template
# can be built and run successfully using devcontainer CLI.
#
# IMPORTANT: These tests are meant to be run locally only, not in CI.
# They require Docker and devcontainer CLI to be available.
# =============================================================================

# Shared project name for container reuse
SHARED_PROJECT_NAME="deno-e2e-shared"

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
        (cd "${shared_dir}" && "${PROJECT_ROOT}/setup.sh" --lang deno --yes "${SHARED_PROJECT_NAME}") >/dev/null 2>&1
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

# Helper to create a deno project
create_deno_project() {
    local project_name="${1:-e2e-deno-test}"
    E2E_PROJECT_DIR="${TEST_TEMP_DIR}/${project_name}"
    mkdir -p "${E2E_PROJECT_DIR}"
    init_test_git_repo "${E2E_PROJECT_DIR}"

    (cd "${E2E_PROJECT_DIR}" && "${PROJECT_ROOT}/setup.sh" --lang deno --yes "${project_name}") >/dev/null 2>&1

    echo "${E2E_PROJECT_DIR}"
}

# =============================================================================
# File Generation Tests
# =============================================================================

@test "e2e/deno: setup.sh generates all required files" {
    local project_dir
    project_dir=$(create_deno_project "deno-files-test")

    # Check core files
    assert_file_exists "${project_dir}/.devcontainer/devcontainer.json"
    assert_file_exists "${project_dir}/docker-compose.yml"
    assert_file_exists "${project_dir}/docker/Dockerfile.dev"

    # Check Deno-specific config file
    assert_file_exists "${project_dir}/deno.json"
}

@test "e2e/deno: devcontainer.json contains Deno features" {
    local project_dir
    project_dir=$(create_deno_project "deno-features-test")

    # Check for Deno feature
    run jq -e '.features | keys | any(contains("deno"))' "${project_dir}/.devcontainer/devcontainer.json"
    assert_success
}

@test "e2e/deno: devcontainer.json contains Deno VS Code extensions" {
    local project_dir
    project_dir=$(create_deno_project "deno-extensions-test")

    local extensions
    extensions=$(jq -r '.customizations.vscode.extensions | join(" ")' "${project_dir}/.devcontainer/devcontainer.json")

    # Check for required extensions
    [[ "${extensions}" == *"denoland.vscode-deno"* ]]
}

@test "e2e/deno: devcontainer.json has deno.enable setting" {
    local project_dir
    project_dir=$(create_deno_project "deno-settings-test")

    run jq -e '.customizations.vscode.settings["deno.enable"]' "${project_dir}/.devcontainer/devcontainer.json"
    assert_success
    assert_output "true"
}

@test "e2e/deno: deno.json is valid JSON" {
    local project_dir
    project_dir=$(create_deno_project "deno-json-valid-test")

    run jq -e '.' "${project_dir}/deno.json"
    assert_success
}

@test "e2e/deno: deno.json contains required tasks" {
    local project_dir
    project_dir=$(create_deno_project "deno-tasks-test")

    # Check for test task
    run jq -e '.tasks.test' "${project_dir}/deno.json"
    assert_success

    # Check for lint task
    run jq -e '.tasks.lint' "${project_dir}/deno.json"
    assert_success

    # Check for fmt task
    run jq -e '.tasks.fmt' "${project_dir}/deno.json"
    assert_success

    # Check for check task
    run jq -e '.tasks.check' "${project_dir}/deno.json"
    assert_success
}

@test "e2e/deno: deno.json contains imports" {
    local project_dir
    project_dir=$(create_deno_project "deno-imports-test")

    # Check for @std/assert import
    run jq -e '.imports["@std/assert"]' "${project_dir}/deno.json"
    assert_success

    # Check for @std/testing import
    run jq -e '.imports["@std/testing"]' "${project_dir}/deno.json"
    assert_success
}

@test "e2e/deno: deno.json contains compiler options" {
    local project_dir
    project_dir=$(create_deno_project "deno-compiler-test")

    run jq -e '.compilerOptions.strict' "${project_dir}/deno.json"
    assert_success
    assert_output "true"
}

# =============================================================================
# Docker Build Tests
# =============================================================================

@test "e2e/deno: docker build succeeds" {
    local project_dir
    project_dir=$(create_deno_project "deno-build-test")

    # Build the Docker image
    run docker build -f "${project_dir}/docker/Dockerfile.dev" -t "e2e-deno-build-test" "${project_dir}"
    assert_success
}

@test "e2e/deno: docker compose build succeeds" {
    local project_dir
    project_dir=$(create_deno_project "deno-compose-build")

    # Build using docker compose
    run bash -c "cd '${project_dir}' && docker compose build"
    assert_success
}

# =============================================================================
# Devcontainer Startup Tests
# =============================================================================

@test "e2e/deno: container starts successfully" {
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

@test "e2e/deno: git is available in container" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(ensure_shared_container)

    run verify_devcontainer_command "${project_dir}" "git"
    assert_success
}

@test "e2e/deno: curl is available in container" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(ensure_shared_container)

    run verify_devcontainer_command "${project_dir}" "curl"
    assert_success
}

@test "e2e/deno: jq is available in container" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(ensure_shared_container)

    run verify_devcontainer_command "${project_dir}" "jq"
    assert_success
}

@test "e2e/deno: deno is available in container" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(ensure_shared_container)

    run verify_devcontainer_command "${project_dir}" "deno"
    assert_success
}

# =============================================================================
# Post.sh Execution Tests
# =============================================================================

@test "e2e/deno: post.sh is executable" {
    local project_dir
    project_dir=$(create_deno_project "deno-postsh-test")

    [[ -x "${project_dir}/.devcontainer/scripts/post.sh" ]]
}

# =============================================================================
# Version Verification Tests
# =============================================================================

@test "e2e/deno: deno version is 2.x" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(ensure_shared_container)

    run get_devcontainer_command_version "${project_dir}" "deno"
    assert_success
    # Should output version string starting with "deno 2." (e.g., deno 2.1.4)
    assert_output --regexp "deno 2\.[0-9]+"
}

# =============================================================================
# CI Workflow Tests
# =============================================================================

@test "e2e/deno: setup.sh generates GitHub Actions workflow" {
    local project_dir
    project_dir=$(create_deno_project "deno-workflow-test")

    assert_file_exists "${project_dir}/.github/workflows/deno-ci.yml"
}

@test "e2e/deno: deno-ci.yml contains required jobs" {
    local project_dir
    project_dir=$(create_deno_project "deno-ci-jobs-test")

    # Check for lint job
    run grep -q "lint:" "${project_dir}/.github/workflows/deno-ci.yml"
    assert_success

    # Check for unit-test job
    run grep -q "unit-test:" "${project_dir}/.github/workflows/deno-ci.yml"
    assert_success

    # Check for integration-test job
    run grep -q "integration-test:" "${project_dir}/.github/workflows/deno-ci.yml"
    assert_success
}

@test "e2e/deno: deno-ci.yml uses denoland/setup-deno" {
    local project_dir
    project_dir=$(create_deno_project "deno-ci-setup-test")

    run grep -q "denoland/setup-deno" "${project_dir}/.github/workflows/deno-ci.yml"
    assert_success
}

@test "e2e/deno: deno-ci.yml includes fmt check" {
    local project_dir
    project_dir=$(create_deno_project "deno-ci-fmt-test")

    run grep -q "deno fmt --check" "${project_dir}/.github/workflows/deno-ci.yml"
    assert_success
}

@test "e2e/deno: deno-ci.yml includes lint" {
    local project_dir
    project_dir=$(create_deno_project "deno-ci-lint-test")

    run grep -q "deno lint" "${project_dir}/.github/workflows/deno-ci.yml"
    assert_success
}

@test "e2e/deno: deno-ci.yml includes type check" {
    local project_dir
    project_dir=$(create_deno_project "deno-ci-check-test")

    run grep -q "deno check" "${project_dir}/.github/workflows/deno-ci.yml"
    assert_success
}

# =============================================================================
# Tests Directory Tests
# =============================================================================

@test "e2e/deno: setup.sh generates tests directory" {
    local project_dir
    project_dir=$(create_deno_project "deno-tests-dir-test")

    [[ -d "${project_dir}/tests" ]]
    [[ -d "${project_dir}/tests/unit" ]]
    [[ -d "${project_dir}/tests/integration" ]]
}

@test "e2e/deno: tests directory contains sample tests" {
    local project_dir
    project_dir=$(create_deno_project "deno-sample-tests")

    assert_file_exists "${project_dir}/tests/unit/sample_test.ts"
    assert_file_exists "${project_dir}/tests/integration/sample_integration_test.ts"
}

@test "e2e/deno: sample unit test uses BDD style" {
    local project_dir
    project_dir=$(create_deno_project "deno-bdd-test")

    # Check for BDD imports
    run grep -q "@std/testing/bdd" "${project_dir}/tests/unit/sample_test.ts"
    assert_success

    # Check for describe/it usage
    run grep -q "describe(" "${project_dir}/tests/unit/sample_test.ts"
    assert_success

    run grep -q "it(" "${project_dir}/tests/unit/sample_test.ts"
    assert_success
}

# =============================================================================
# Claude Settings Tests
# =============================================================================

@test "e2e/deno: claude settings contain deno fmt hooks" {
    local project_dir
    project_dir=$(create_deno_project "deno-claude-test")

    # Check if .claude/settings.json exists and contains deno fmt
    if [[ -f "${project_dir}/.claude/settings.json" ]]; then
        run jq -e '.hooks.PostToolUse[]?.hooks[]?.command | select(. != null) | contains("deno fmt")' "${project_dir}/.claude/settings.json"
        assert_success
    else
        skip "Claude settings not generated (claude template may not be enabled)"
    fi
}

@test "e2e/deno: claude settings contain deno lint hooks" {
    local project_dir
    project_dir=$(create_deno_project "deno-claude-lint-test")

    # Check if .claude/settings.json exists and contains deno lint
    if [[ -f "${project_dir}/.claude/settings.json" ]]; then
        run jq -e '.hooks.PreToolUse[]?.hooks[]?.command | select(. != null) | contains("deno lint")' "${project_dir}/.claude/settings.json"
        assert_success
    else
        skip "Claude settings not generated (claude template may not be enabled)"
    fi
}
