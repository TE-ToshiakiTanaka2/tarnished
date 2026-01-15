#!/usr/bin/env bats
# =============================================================================
# E2E Tests: Python Template
# =============================================================================
#
# These tests verify that a project created with the python template
# can be built and run successfully using devcontainer CLI.
#
# IMPORTANT: These tests are meant to be run locally only, not in CI.
# They require Docker and devcontainer CLI to be available.
# =============================================================================

# Shared project name for container reuse
SHARED_PROJECT_NAME="python-e2e-shared"

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
        (cd "${shared_dir}" && "${PROJECT_ROOT}/setup.sh" --lang python --yes "${SHARED_PROJECT_NAME}") >/dev/null 2>&1
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

# Helper to create a python project
create_python_project() {
    local project_name="${1:-e2e-python-test}"
    E2E_PROJECT_DIR="${TEST_TEMP_DIR}/${project_name}"
    mkdir -p "${E2E_PROJECT_DIR}"

    (cd "${E2E_PROJECT_DIR}" && "${PROJECT_ROOT}/setup.sh" --lang python --yes "${project_name}") >/dev/null 2>&1

    echo "${E2E_PROJECT_DIR}"
}

# =============================================================================
# File Generation Tests
# =============================================================================

@test "e2e/python: setup.sh generates all required files" {
    local project_dir
    project_dir=$(create_python_project "python-files-test")

    # Check core files
    assert_file_exists "${project_dir}/.devcontainer/devcontainer.json"
    assert_file_exists "${project_dir}/docker-compose.yml"
    assert_file_exists "${project_dir}/docker/Dockerfile.dev"

    # Check Python-specific tool config files
    assert_file_exists "${project_dir}/ruff.toml"
    assert_file_exists "${project_dir}/mypy.ini"
    assert_file_exists "${project_dir}/pytest.ini"
}

@test "e2e/python: devcontainer.json contains Python features" {
    local project_dir
    project_dir=$(create_python_project "python-features-test")

    # Check for Python feature
    run jq -e '.features | keys | any(contains("python"))' "${project_dir}/.devcontainer/devcontainer.json"
    assert_success

    # Check for uv feature
    run jq -e '.features | keys | any(contains("uv"))' "${project_dir}/.devcontainer/devcontainer.json"
    assert_success
}

@test "e2e/python: devcontainer.json contains Python VS Code extensions" {
    local project_dir
    project_dir=$(create_python_project "python-extensions-test")

    local extensions
    extensions=$(jq -r '.customizations.vscode.extensions | join(" ")' "${project_dir}/.devcontainer/devcontainer.json")

    # Check for required extensions
    [[ "${extensions}" == *"ms-python.python"* ]]
    [[ "${extensions}" == *"ms-python.vscode-pylance"* ]]
    [[ "${extensions}" == *"charliermarsh.ruff"* ]]
    [[ "${extensions}" == *"ms-python.mypy-type-checker"* ]]
}

@test "e2e/python: ruff.toml has correct Python version" {
    local project_dir
    project_dir=$(create_python_project "python-ruff-test")

    run grep -E 'target-version\s*=\s*"py312"' "${project_dir}/ruff.toml"
    assert_success
}

@test "e2e/python: mypy.ini has correct Python version" {
    local project_dir
    project_dir=$(create_python_project "python-mypy-test")

    run grep -E 'python_version\s*=\s*3\.12' "${project_dir}/mypy.ini"
    assert_success
}

# =============================================================================
# Docker Build Tests
# =============================================================================

@test "e2e/python: docker build succeeds" {
    local project_dir
    project_dir=$(create_python_project "python-build-test")

    # Build the Docker image
    run docker build -f "${project_dir}/docker/Dockerfile.dev" -t "e2e-python-build-test" "${project_dir}"
    assert_success
}

@test "e2e/python: docker compose build succeeds" {
    local project_dir
    project_dir=$(create_python_project "python-compose-build")

    # Build using docker compose
    run bash -c "cd '${project_dir}' && docker compose build"
    assert_success
}

# =============================================================================
# Devcontainer Startup Tests
# =============================================================================

@test "e2e/python: container starts successfully" {
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

@test "e2e/python: git is available in container" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(ensure_shared_container)

    run verify_devcontainer_command "${project_dir}" "git"
    assert_success
}

@test "e2e/python: python is available in container" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(ensure_shared_container)

    run verify_devcontainer_command "${project_dir}" "python"
    assert_success
}

@test "e2e/python: uv is available in container" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(ensure_shared_container)

    run verify_devcontainer_command "${project_dir}" "uv"
    assert_success
}

@test "e2e/python: ruff is available in container" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(ensure_shared_container)

    # Use uvx to run ruff (uvx is uv's tool runner)
    run exec_in_devcontainer "${project_dir}" uvx ruff --version
    assert_success
}

@test "e2e/python: pip is available in container" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(ensure_shared_container)

    run verify_devcontainer_command "${project_dir}" "pip"
    assert_success
}

# =============================================================================
# Post.sh Execution Tests
# =============================================================================

@test "e2e/python: post.sh is executable" {
    local project_dir
    project_dir=$(create_python_project "python-postsh-test")

    [[ -x "${project_dir}/.devcontainer/scripts/post.sh" ]]
}

# =============================================================================
# Version Verification Tests
# =============================================================================

@test "e2e/python: python version is 3.12" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(ensure_shared_container)

    run get_devcontainer_command_version "${project_dir}" "python"
    assert_success
    # Should output version string containing "3.12"
    assert_output --regexp "3\.12"
}

# =============================================================================
# Claude Settings Tests
# =============================================================================

@test "e2e/python: claude settings contain ruff hooks" {
    local project_dir
    project_dir=$(create_python_project "python-claude-test")

    # Check if .claude/settings.json exists and contains ruff
    if [[ -f "${project_dir}/.claude/settings.json" ]]; then
        run jq -e '.hooks.PostToolUse[]?.hooks[]?.command | select(. != null) | contains("ruff")' "${project_dir}/.claude/settings.json"
        assert_success
    else
        skip "Claude settings not generated (claude template may not be enabled)"
    fi
}
