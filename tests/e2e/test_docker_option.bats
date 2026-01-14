#!/usr/bin/env bats
# =============================================================================
# E2E Tests: Docker Option
# =============================================================================
#
# These tests verify that a project created with the docker option
# has Docker-in-Docker properly configured.
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

# Helper to create a project with docker option
create_docker_project() {
    local project_name="${1:-e2e-docker-test}"
    E2E_PROJECT_DIR="${TEST_TEMP_DIR}/${project_name}"
    mkdir -p "${E2E_PROJECT_DIR}"

    (cd "${E2E_PROJECT_DIR}" && "${PROJECT_ROOT}/setup.sh" --lang node --docker --yes "${project_name}") >/dev/null 2>&1

    echo "${E2E_PROJECT_DIR}"
}

# =============================================================================
# Configuration Tests
# =============================================================================

@test "e2e/docker: docker-in-docker feature is in devcontainer.json" {
    local project_dir
    project_dir=$(create_docker_project "docker-config-test")

    # Docker-in-Docker feature should be in devcontainer.json
    run grep -E "docker-in-docker" "${project_dir}/.devcontainer/devcontainer.json"
    assert_success
}

@test "e2e/docker: docker extension is in devcontainer.json" {
    local project_dir
    project_dir=$(create_docker_project "docker-ext-test")

    # VS Code Docker extension should be in devcontainer.json
    run grep -E "ms-azuretools.vscode-docker" "${project_dir}/.devcontainer/devcontainer.json"
    assert_success
}

@test "e2e/docker: docker compose version is set to v2" {
    local project_dir
    project_dir=$(create_docker_project "docker-compose-test")

    # Docker Compose v2 should be configured
    run grep -E "dockerDashComposeVersion.*v2" "${project_dir}/.devcontainer/devcontainer.json"
    assert_success
}

# =============================================================================
# Docker Build Tests
# =============================================================================

@test "e2e/docker: docker build succeeds" {
    local project_dir
    project_dir=$(create_docker_project "docker-build-test")

    # Build the Docker image
    run docker build -f "${project_dir}/docker/Dockerfile.dev" -t "e2e-docker-build" "${project_dir}"
    assert_success
}

# =============================================================================
# Devcontainer Tests
# =============================================================================

@test "e2e/docker: container starts successfully" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(create_docker_project "docker-startup-test")

    # Start devcontainer
    run start_devcontainer "${project_dir}"
    assert_success
}

@test "e2e/docker: docker command is available in container" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(create_docker_project "docker-cmd-test")

    start_devcontainer "${project_dir}" >/dev/null 2>&1

    # Check that docker is available inside the container
    run verify_devcontainer_command "${project_dir}" "docker"
    assert_success
}

@test "e2e/docker: docker-compose command is available in container" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(create_docker_project "docker-compose-cmd-test")

    start_devcontainer "${project_dir}" >/dev/null 2>&1

    # Check that docker-compose is available inside the container
    run verify_devcontainer_command "${project_dir}" "docker-compose"
    assert_success
}

# =============================================================================
# Combined Option Tests
# =============================================================================

@test "e2e/docker: docker and playwright options work together" {
    local project_name="docker-playwright-test"
    E2E_PROJECT_DIR="${TEST_TEMP_DIR}/${project_name}"
    mkdir -p "${E2E_PROJECT_DIR}"

    # Create project with both docker and playwright
    run bash -c "cd '${E2E_PROJECT_DIR}' && '${PROJECT_ROOT}/setup.sh' --lang node --docker --playwright --yes '${project_name}'"
    assert_success

    # Docker-in-Docker feature should be present
    run grep -E "docker-in-docker" "${E2E_PROJECT_DIR}/.devcontainer/devcontainer.json"
    assert_success

    # Playwright should also be present
    run grep -E "playwright" "${E2E_PROJECT_DIR}/.devcontainer/devcontainer.json"
    assert_success
}
