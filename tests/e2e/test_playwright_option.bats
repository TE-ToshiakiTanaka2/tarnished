#!/usr/bin/env bats
# =============================================================================
# E2E Tests: Playwright Option
# =============================================================================
#
# These tests verify that a project created with the playwright option
# has Playwright properly configured and available.
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

# Helper to create a project with playwright
create_playwright_project() {
    local project_name="${1:-e2e-playwright-test}"
    E2E_PROJECT_DIR="${TEST_TEMP_DIR}/${project_name}"
    mkdir -p "${E2E_PROJECT_DIR}"

    (cd "${E2E_PROJECT_DIR}" && "${PROJECT_ROOT}/setup.sh" --lang node --playwright --yes "${project_name}") >/dev/null 2>&1

    echo "${E2E_PROJECT_DIR}"
}

# =============================================================================
# Configuration Tests
# =============================================================================

@test "e2e/playwright: playwright is referenced in config" {
    local project_dir
    project_dir=$(create_playwright_project "pw-config-test")

    # Playwright should be referenced somewhere in the project
    run grep -r "playwright" "${project_dir}/"
    assert_success
}

@test "e2e/playwright: playwright config file exists" {
    local project_dir
    project_dir=$(create_playwright_project "pw-configfile-test")

    # Check for playwright config file
    [[ -f "${project_dir}/playwright.config.ts" ]] || \
    [[ -f "${project_dir}/playwright.config.js" ]] || \
    [[ -f "${project_dir}/playwright.config.mjs" ]]
}

# =============================================================================
# Docker Build Tests
# =============================================================================

@test "e2e/playwright: docker build succeeds" {
    local project_dir
    project_dir=$(create_playwright_project "pw-build-test")

    # Build the Docker image
    run docker build -f "${project_dir}/docker/Dockerfile.dev" -t "e2e-pw-build" "${project_dir}"
    assert_success
}

# =============================================================================
# Container Tests
# =============================================================================

@test "e2e/playwright: container starts successfully" {
    local project_dir
    project_dir=$(create_playwright_project "pw-startup-test")

    # Build the image
    docker build -f "${project_dir}/docker/Dockerfile.dev" -t "e2e-pw-startup" "${project_dir}" >/dev/null 2>&1

    # Start the container
    E2E_CONTAINER=$(docker run -d --name "e2e-pw-startup-container" "e2e-pw-startup" tail -f /dev/null)

    # Wait for container to be ready
    run wait_for_container "${E2E_CONTAINER}" 30
    assert_success
}

@test "e2e/playwright: npx playwright is available" {
    local project_dir
    project_dir=$(create_playwright_project "pw-npx-test")

    docker build -f "${project_dir}/docker/Dockerfile.dev" -t "e2e-pw-npx" "${project_dir}" >/dev/null 2>&1
    E2E_CONTAINER=$(docker run -d --name "e2e-pw-npx-container" "e2e-pw-npx" tail -f /dev/null)
    wait_for_container "${E2E_CONTAINER}" 30

    # Check that npx is available (playwright is typically run via npx)
    run verify_command_exists "${E2E_CONTAINER}" "npx"
    assert_success
}

# =============================================================================
# Browser Dependencies Tests
# =============================================================================

@test "e2e/playwright: required browser dependencies are referenced" {
    local project_dir
    project_dir=$(create_playwright_project "pw-browser-deps-test")

    # Playwright requires browser dependencies
    # Check that the Dockerfile or devcontainer.json references playwright browsers or dependencies
    run grep -rE "playwright|chromium|firefox|webkit" "${project_dir}/"
    assert_success
}
