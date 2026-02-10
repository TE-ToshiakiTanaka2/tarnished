#!/usr/bin/env bats

# Tests for prompt_service_selection() parsing logic in setup.sh
# and PostgreSQL plugin interface verification.

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
    # Source common library
    source "${SCRIPT_DIR}/scripts/lib/common.sh"

    # Set up global variables that setup.sh defines
    declare -ga SELECTED_SERVICES=()
    declare -ga AVAILABLE_SERVICES=("postgresql")
    declare -gA SERVICE_DISPLAY_NAMES=(
        ["postgresql"]="PostgreSQL 16"
    )
    POSTGRESQL_ENABLED=false
}

# Helper: extract and test the parsing logic directly
# Simulates what prompt_service_selection does after reading input
parse_service_input() {
    local response="$1"
    local svc_count=${#AVAILABLE_SERVICES[@]}

    SELECTED_SERVICES=()

    if [[ -z "$response" ]] || [[ "$response" == "none" ]]; then
        :
    elif [[ "$response" == "all" ]]; then
        SELECTED_SERVICES=("${AVAILABLE_SERVICES[@]}")
    else
        IFS=',' read -ra nums <<< "$response"
        for num in "${nums[@]}"; do
            num=$(echo "$num" | tr -d ' ')
            if [[ "$num" =~ ^[0-9]+$ ]] && [[ "$num" -ge 1 ]] && [[ "$num" -le "$svc_count" ]]; then
                SELECTED_SERVICES+=("${AVAILABLE_SERVICES[$((num-1))]}")
            fi
        done
    fi

    # Set feature flags
    for svc in "${SELECTED_SERVICES[@]}"; do
        case "$svc" in
            postgresql) POSTGRESQL_ENABLED=true ;;
        esac
    done
}

# =============================================================================
# Service Selection Parsing Tests
# =============================================================================

@test "empty input selects no services" {
    parse_service_input ""
    assert_equal "${#SELECTED_SERVICES[@]}" "0"
    assert_equal "$POSTGRESQL_ENABLED" "false"
}

@test "'none' keyword selects no services" {
    parse_service_input "none"
    assert_equal "${#SELECTED_SERVICES[@]}" "0"
    assert_equal "$POSTGRESQL_ENABLED" "false"
}

@test "selecting '1' chooses postgresql" {
    parse_service_input "1"
    assert_equal "${#SELECTED_SERVICES[@]}" "1"
    assert_equal "${SELECTED_SERVICES[0]}" "postgresql"
    assert_equal "$POSTGRESQL_ENABLED" "true"
}

@test "'all' keyword selects all services" {
    parse_service_input "all"
    assert_equal "${#SELECTED_SERVICES[@]}" "1"
    assert_equal "${SELECTED_SERVICES[0]}" "postgresql"
    assert_equal "$POSTGRESQL_ENABLED" "true"
}

@test "out-of-range number is ignored" {
    parse_service_input "5"
    assert_equal "${#SELECTED_SERVICES[@]}" "0"
}

@test "zero is ignored" {
    parse_service_input "0"
    assert_equal "${#SELECTED_SERVICES[@]}" "0"
}

@test "non-numeric input is ignored" {
    parse_service_input "abc"
    assert_equal "${#SELECTED_SERVICES[@]}" "0"
}

# =============================================================================
# PostgreSQL Plugin Interface Tests
# =============================================================================

@test "postgresql plugin.sh has valid bash syntax" {
    run bash -n "${SCRIPT_DIR}/templates/services/postgresql/plugin.sh"
    assert_success
}

@test "postgresql plugin exports plugin_name function" {
    source "${SCRIPT_DIR}/templates/services/postgresql/plugin.sh"
    run plugin_name
    assert_success
    assert_output "postgresql"
}

@test "postgresql plugin exports plugin_description function" {
    source "${SCRIPT_DIR}/templates/services/postgresql/plugin.sh"
    run plugin_description
    assert_success
    assert_output "PostgreSQL 16 database service with psql client"
}

@test "postgresql plugin has plugin_copy function" {
    source "${SCRIPT_DIR}/templates/services/postgresql/plugin.sh"
    declare -f plugin_copy > /dev/null
    assert_equal "$?" "0"
}

@test "postgresql plugin has plugin_post_copy function" {
    source "${SCRIPT_DIR}/templates/services/postgresql/plugin.sh"
    declare -f plugin_post_copy > /dev/null
    assert_equal "$?" "0"
}

# =============================================================================
# PostgreSQL Template File Tests
# =============================================================================

@test "docker-compose.postgresql.yml exists" {
    [ -f "${SCRIPT_DIR}/templates/services/postgresql/docker-compose.postgresql.yml" ]
}

@test "docker-compose.postgresql.yml contains postgres:16 image" {
    run grep "image: postgres:16" "${SCRIPT_DIR}/templates/services/postgresql/docker-compose.postgresql.yml"
    assert_success
}

@test "docker-compose.postgresql.yml contains healthcheck" {
    run grep "pg_isready" "${SCRIPT_DIR}/templates/services/postgresql/docker-compose.postgresql.yml"
    assert_success
}

@test "docker-compose.postgresql.yml contains volume definition" {
    run grep "postgres-data" "${SCRIPT_DIR}/templates/services/postgresql/docker-compose.postgresql.yml"
    assert_success
}

@test "docker-compose.postgresql.yml contains PROJECT_NAME placeholder" {
    run grep "{{PROJECT_NAME}}" "${SCRIPT_DIR}/templates/services/postgresql/docker-compose.postgresql.yml"
    assert_success
}

@test "devcontainer.json exists for postgresql plugin" {
    [ -f "${SCRIPT_DIR}/templates/services/postgresql/.devcontainer/devcontainer.json" ]
}

@test "devcontainer.json contains postgresql-client feature" {
    run grep "postgresql-client" "${SCRIPT_DIR}/templates/services/postgresql/.devcontainer/devcontainer.json"
    assert_success
}

@test "devcontainer.json is valid JSON" {
    run jq '.' "${SCRIPT_DIR}/templates/services/postgresql/.devcontainer/devcontainer.json"
    assert_success
}

# =============================================================================
# Docker Compose Merge Integration Test
# =============================================================================

@test "postgresql docker-compose can be merged with base compose" {
    local temp_dir
    temp_dir=$(mktemp -d)

    # Create base docker-compose.yml
    cat > "${temp_dir}/base.yml" << 'YAML'
services:
  myapp:
    build:
      context: .
      dockerfile: docker/Dockerfile.dev
    container_name: myapp
    volumes:
      - .:/workspace:cached
    working_dir: /workspace
    command: sleep infinity
YAML

    # Copy postgresql overlay
    cp "${SCRIPT_DIR}/templates/services/postgresql/docker-compose.postgresql.yml" "${temp_dir}/overlay.yml"

    # Attempt merge
    merge_docker_compose_services "${temp_dir}/base.yml" "${temp_dir}/overlay.yml" "${temp_dir}/merged.yml"

    # Verify merged file exists and contains both services
    [ -f "${temp_dir}/merged.yml" ]
    grep -q "myapp" "${temp_dir}/merged.yml"
    grep -q "postgres" "${temp_dir}/merged.yml"

    # Cleanup
    rm -rf "$temp_dir"
}
