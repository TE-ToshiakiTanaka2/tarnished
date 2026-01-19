#!/usr/bin/env bats
# =============================================================================
# E2E Tests: Neo4j Option
# =============================================================================
#
# These tests verify that a project created with the neo4j option
# has Neo4j properly configured.
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

# Helper to create a project with neo4j option
create_neo4j_project() {
    local project_name="${1:-e2e-neo4j-test}"
    E2E_PROJECT_DIR="${TEST_TEMP_DIR}/${project_name}"
    mkdir -p "${E2E_PROJECT_DIR}"
    init_test_git_repo "${E2E_PROJECT_DIR}"

    (cd "${E2E_PROJECT_DIR}" && "${PROJECT_ROOT}/setup.sh" --lang python --neo4j --yes "${project_name}") >/dev/null 2>&1

    echo "${E2E_PROJECT_DIR}"
}

# =============================================================================
# Configuration Tests
# =============================================================================

@test "e2e/neo4j: plugin loads correctly" {
    run bash -c "cd '${TEST_TEMP_DIR}' && '${PROJECT_ROOT}/setup.sh' --lang python --neo4j --dry-run -y test-project 2>&1"
    assert_success
    assert_output --partial "neo4j"
}

@test "e2e/neo4j: neo4j service is in docker-compose.yml" {
    local project_dir
    project_dir=$(create_neo4j_project "neo4j-config-test")

    # Neo4j service should be in docker-compose.yml
    run grep -E "^\s+neo4j:" "${project_dir}/docker-compose.yml"
    assert_success
}

@test "e2e/neo4j: neo4j:community image is configured" {
    local project_dir
    project_dir=$(create_neo4j_project "neo4j-image-test")

    # Neo4j community image should be configured
    run grep -E "image:\s*neo4j:community" "${project_dir}/docker-compose.yml"
    assert_success
}

@test "e2e/neo4j: neo4j_data volume is configured" {
    local project_dir
    project_dir=$(create_neo4j_project "neo4j-volume-test")

    # neo4j_data volume should be configured
    run grep -E "neo4j_data:" "${project_dir}/docker-compose.yml"
    assert_success
}

@test "e2e/neo4j: APOC plugin is configured" {
    local project_dir
    project_dir=$(create_neo4j_project "neo4j-apoc-test")

    # NEO4J_PLUGINS with apoc should be configured
    run grep -E "NEO4J_PLUGINS.*apoc" "${project_dir}/docker-compose.yml"
    assert_success
}

@test "e2e/neo4j: ports 7474 and 7687 are exposed" {
    local project_dir
    project_dir=$(create_neo4j_project "neo4j-ports-test")

    # Port 7474 (Browser) should be exposed
    run grep -E "7474:7474" "${project_dir}/docker-compose.yml"
    assert_success

    # Port 7687 (Bolt) should be exposed
    run grep -E "7687:7687" "${project_dir}/docker-compose.yml"
    assert_success
}

@test "e2e/neo4j: healthcheck is configured" {
    local project_dir
    project_dir=$(create_neo4j_project "neo4j-healthcheck-test")

    # cypher-shell healthcheck should be configured
    run grep -E "cypher-shell" "${project_dir}/docker-compose.yml"
    assert_success
}

@test "e2e/neo4j: VS Code extension is in devcontainer.json" {
    local project_dir
    project_dir=$(create_neo4j_project "neo4j-ext-test")

    # VS Code Cypher extension should be in devcontainer.json
    run grep -E "jakebathman.cypher-query-language" "${project_dir}/.devcontainer/devcontainer.json"
    assert_success
}

@test "e2e/neo4j: .env file is created" {
    local project_dir
    project_dir=$(create_neo4j_project "neo4j-env-test")

    # .env file should exist
    assert_file_exists "${project_dir}/.env"

    # .env should contain Neo4j variables
    run grep -E "NEO4J_USER" "${project_dir}/.env"
    assert_success

    run grep -E "NEO4J_PASSWORD" "${project_dir}/.env"
    assert_success
}

@test "e2e/neo4j: .env.example file is created" {
    local project_dir
    project_dir=$(create_neo4j_project "neo4j-env-example-test")

    # .env.example file should exist
    assert_file_exists "${project_dir}/.env.example"
}

@test "e2e/neo4j: .env is in .gitignore" {
    local project_dir
    project_dir=$(create_neo4j_project "neo4j-gitignore-test")

    # .env should be in .gitignore
    run grep -E "^\.env$" "${project_dir}/.gitignore"
    assert_success
}

@test "e2e/neo4j: init directory is created" {
    local project_dir
    project_dir=$(create_neo4j_project "neo4j-init-test")

    # init directory should exist
    run test -d "${project_dir}/init"
    assert_success
}

@test "e2e/neo4j: docker-compose.yml is valid" {
    local project_dir
    project_dir=$(create_neo4j_project "neo4j-compose-valid-test")

    # docker compose config should succeed
    run bash -c "cd '${project_dir}' && docker compose config > /dev/null"
    assert_success
}

# =============================================================================
# Combined Option Tests
# =============================================================================

@test "e2e/neo4j: neo4j and docker options work together" {
    local project_name="neo4j-docker-test"
    E2E_PROJECT_DIR="${TEST_TEMP_DIR}/${project_name}"
    mkdir -p "${E2E_PROJECT_DIR}"
    init_test_git_repo "${E2E_PROJECT_DIR}"

    # Create project with both neo4j and docker
    run bash -c "cd '${E2E_PROJECT_DIR}' && '${PROJECT_ROOT}/setup.sh' --lang python --neo4j --docker --yes '${project_name}'"
    assert_success

    # Neo4j service should be present
    run grep -E "^\s+neo4j:" "${E2E_PROJECT_DIR}/docker-compose.yml"
    assert_success

    # Docker-in-Docker feature should also be present
    run grep -E "docker-in-docker" "${E2E_PROJECT_DIR}/.devcontainer/devcontainer.json"
    assert_success
}

@test "e2e/neo4j: neo4j and postgresql options work together" {
    local project_name="neo4j-postgresql-test"
    E2E_PROJECT_DIR="${TEST_TEMP_DIR}/${project_name}"
    mkdir -p "${E2E_PROJECT_DIR}"
    init_test_git_repo "${E2E_PROJECT_DIR}"

    # Create project with both neo4j and postgresql
    run bash -c "cd '${E2E_PROJECT_DIR}' && '${PROJECT_ROOT}/setup.sh' --lang python --neo4j --postgresql --yes '${project_name}'"
    assert_success

    # Neo4j service should be present
    run grep -E "^\s+neo4j:" "${E2E_PROJECT_DIR}/docker-compose.yml"
    assert_success

    # PostgreSQL db service should also be present
    run grep -E "^\s+db:" "${E2E_PROJECT_DIR}/docker-compose.yml"
    assert_success
}

@test "e2e/neo4j: all optional features work together" {
    local project_name="neo4j-all-features-test"
    E2E_PROJECT_DIR="${TEST_TEMP_DIR}/${project_name}"
    mkdir -p "${E2E_PROJECT_DIR}"
    init_test_git_repo "${E2E_PROJECT_DIR}"

    # Create project with all optional features
    run bash -c "cd '${E2E_PROJECT_DIR}' && '${PROJECT_ROOT}/setup.sh' --lang python --neo4j --postgresql --docker --yes '${project_name}'"
    assert_success

    # All features should be present
    run grep -E "^\s+neo4j:" "${E2E_PROJECT_DIR}/docker-compose.yml"
    assert_success

    run grep -E "^\s+db:" "${E2E_PROJECT_DIR}/docker-compose.yml"
    assert_success

    run grep -E "docker-in-docker" "${E2E_PROJECT_DIR}/.devcontainer/devcontainer.json"
    assert_success
}
