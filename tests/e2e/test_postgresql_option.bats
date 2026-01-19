#!/usr/bin/env bats
# =============================================================================
# E2E Tests: PostgreSQL Option
# =============================================================================
#
# These tests verify that a project created with the postgresql option
# has PostgreSQL properly configured.
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
        # Also clean up docker compose
        (cd "${E2E_PROJECT_DIR}" && docker compose down -v 2>/dev/null) || true
    fi

    teardown_temp_dir
}

# Helper to create a project with postgresql option
create_postgresql_project() {
    local project_name="${1:-e2e-postgresql-test}"
    E2E_PROJECT_DIR="${TEST_TEMP_DIR}/${project_name}"
    mkdir -p "${E2E_PROJECT_DIR}"
    init_test_git_repo "${E2E_PROJECT_DIR}"

    (cd "${E2E_PROJECT_DIR}" && "${PROJECT_ROOT}/setup.sh" --lang node --postgresql --yes "${project_name}") >/dev/null 2>&1

    echo "${E2E_PROJECT_DIR}"
}

# =============================================================================
# Configuration Tests
# =============================================================================

@test "e2e/postgresql: plugin loads correctly" {
    run bash -c "cd '${TEST_TEMP_DIR}' && '${PROJECT_ROOT}/setup.sh' --lang node --postgresql --dry-run -y test-project 2>&1"
    assert_success
    assert_output --partial "postgresql"
}

@test "e2e/postgresql: db service is in docker-compose.yml" {
    local project_dir
    project_dir=$(create_postgresql_project "postgresql-config-test")

    # PostgreSQL db service should be in docker-compose.yml
    run grep -E "^\s+db:" "${project_dir}/docker-compose.yml"
    assert_success
}

@test "e2e/postgresql: postgres:17 image is configured" {
    local project_dir
    project_dir=$(create_postgresql_project "postgresql-image-test")

    # PostgreSQL 17 image should be configured
    run grep -E "image:\s*postgres:17" "${project_dir}/docker-compose.yml"
    assert_success
}

@test "e2e/postgresql: postgres_data volume is configured" {
    local project_dir
    project_dir=$(create_postgresql_project "postgresql-volume-test")

    # postgres_data volume should be configured
    run grep -E "postgres_data:" "${project_dir}/docker-compose.yml"
    assert_success
}

@test "e2e/postgresql: healthcheck is configured" {
    local project_dir
    project_dir=$(create_postgresql_project "postgresql-healthcheck-test")

    # pg_isready healthcheck should be configured
    run grep -E "pg_isready" "${project_dir}/docker-compose.yml"
    assert_success
}

@test "e2e/postgresql: VS Code extension is in devcontainer.json" {
    local project_dir
    project_dir=$(create_postgresql_project "postgresql-ext-test")

    # VS Code PostgreSQL extension should be in devcontainer.json
    run grep -E "ckolkman.vscode-postgres" "${project_dir}/.devcontainer/devcontainer.json"
    assert_success
}

@test "e2e/postgresql: .env file is created" {
    local project_dir
    project_dir=$(create_postgresql_project "postgresql-env-test")

    # .env file should exist
    assert_file_exists "${project_dir}/.env"

    # .env should contain PostgreSQL variables
    run grep -E "POSTGRES_USER" "${project_dir}/.env"
    assert_success

    run grep -E "POSTGRES_PASSWORD" "${project_dir}/.env"
    assert_success

    run grep -E "POSTGRES_DB" "${project_dir}/.env"
    assert_success
}

@test "e2e/postgresql: .env.example file is created" {
    local project_dir
    project_dir=$(create_postgresql_project "postgresql-env-example-test")

    # .env.example file should exist
    assert_file_exists "${project_dir}/.env.example"
}

@test "e2e/postgresql: .env is in .gitignore" {
    local project_dir
    project_dir=$(create_postgresql_project "postgresql-gitignore-test")

    # .env should be in .gitignore
    run grep -E "^\.env$" "${project_dir}/.gitignore"
    assert_success
}

@test "e2e/postgresql: init directory is created" {
    local project_dir
    project_dir=$(create_postgresql_project "postgresql-init-test")

    # init directory should exist
    run test -d "${project_dir}/init"
    assert_success
}

@test "e2e/postgresql: docker-compose.yml is valid" {
    local project_dir
    project_dir=$(create_postgresql_project "postgresql-compose-valid-test")

    # docker compose config should succeed
    run bash -c "cd '${project_dir}' && docker compose config > /dev/null"
    assert_success
}

# =============================================================================
# Combined Option Tests
# =============================================================================

@test "e2e/postgresql: postgresql and docker options work together" {
    local project_name="postgresql-docker-test"
    E2E_PROJECT_DIR="${TEST_TEMP_DIR}/${project_name}"
    mkdir -p "${E2E_PROJECT_DIR}"
    init_test_git_repo "${E2E_PROJECT_DIR}"

    # Create project with both postgresql and docker
    run bash -c "cd '${E2E_PROJECT_DIR}' && '${PROJECT_ROOT}/setup.sh' --lang node --postgresql --docker --yes '${project_name}'"
    assert_success

    # PostgreSQL db service should be present
    run grep -E "^\s+db:" "${E2E_PROJECT_DIR}/docker-compose.yml"
    assert_success

    # Docker-in-Docker feature should also be present
    run grep -E "docker-in-docker" "${E2E_PROJECT_DIR}/.devcontainer/devcontainer.json"
    assert_success
}

@test "e2e/postgresql: postgresql and playwright options work together" {
    local project_name="postgresql-playwright-test"
    E2E_PROJECT_DIR="${TEST_TEMP_DIR}/${project_name}"
    mkdir -p "${E2E_PROJECT_DIR}"
    init_test_git_repo "${E2E_PROJECT_DIR}"

    # Create project with both postgresql and playwright
    run bash -c "cd '${E2E_PROJECT_DIR}' && '${PROJECT_ROOT}/setup.sh' --lang node --postgresql --playwright --yes '${project_name}'"
    assert_success

    # PostgreSQL db service should be present
    run grep -E "^\s+db:" "${E2E_PROJECT_DIR}/docker-compose.yml"
    assert_success

    # Playwright should also be present
    run grep -E "playwright" "${E2E_PROJECT_DIR}/.devcontainer/devcontainer.json"
    assert_success
}

@test "e2e/postgresql: all optional features work together" {
    local project_name="postgresql-all-features-test"
    E2E_PROJECT_DIR="${TEST_TEMP_DIR}/${project_name}"
    mkdir -p "${E2E_PROJECT_DIR}"
    init_test_git_repo "${E2E_PROJECT_DIR}"

    # Create project with all optional features
    run bash -c "cd '${E2E_PROJECT_DIR}' && '${PROJECT_ROOT}/setup.sh' --lang node --postgresql --docker --playwright --yes '${project_name}'"
    assert_success

    # All features should be present
    run grep -E "^\s+db:" "${E2E_PROJECT_DIR}/docker-compose.yml"
    assert_success

    run grep -E "docker-in-docker" "${E2E_PROJECT_DIR}/.devcontainer/devcontainer.json"
    assert_success

    run grep -E "playwright" "${E2E_PROJECT_DIR}/.devcontainer/devcontainer.json"
    assert_success
}
