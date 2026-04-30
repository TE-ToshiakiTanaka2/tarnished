#!/usr/bin/env bats

# Tests for prompt_service_selection() parsing logic in setup.sh
# and PostgreSQL/MySQL plugin interface verification.

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
    # Source common library
    source "${SCRIPT_DIR}/scripts/lib/common.sh"

    # Set up global variables that setup.sh defines
    declare -ga SELECTED_SERVICES=()
    declare -ga AVAILABLE_SERVICES=("postgresql" "mysql")
    declare -gA SERVICE_DISPLAY_NAMES=(
        ["postgresql"]="PostgreSQL 16"
        ["mysql"]="MySQL 8.0"
    )
    POSTGRESQL_ENABLED=false
    MYSQL_ENABLED=false
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
            mysql) MYSQL_ENABLED=true ;;
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
    assert_equal "${#SELECTED_SERVICES[@]}" "2"
    assert_equal "${SELECTED_SERVICES[0]}" "postgresql"
    assert_equal "${SELECTED_SERVICES[1]}" "mysql"
    assert_equal "$POSTGRESQL_ENABLED" "true"
    assert_equal "$MYSQL_ENABLED" "true"
}

@test "selecting '2' chooses mysql" {
    parse_service_input "2"
    assert_equal "${#SELECTED_SERVICES[@]}" "1"
    assert_equal "${SELECTED_SERVICES[0]}" "mysql"
    assert_equal "$MYSQL_ENABLED" "true"
}

@test "selecting '1,2' chooses postgresql and mysql" {
    parse_service_input "1,2"
    assert_equal "${#SELECTED_SERVICES[@]}" "2"
    assert_equal "${SELECTED_SERVICES[0]}" "postgresql"
    assert_equal "${SELECTED_SERVICES[1]}" "mysql"
    assert_equal "$POSTGRESQL_ENABLED" "true"
    assert_equal "$MYSQL_ENABLED" "true"
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

# =============================================================================
# PostgreSQL plugin_post_copy Integration Tests
# =============================================================================

@test "plugin_post_copy does not add docker-compose.postgresql.yml to dockerComposeFile" {
    local temp_dir
    temp_dir=$(mktemp -d)

    # Set up directory structure
    mkdir -p "${temp_dir}/.devcontainer/scripts"

    # Create base docker-compose.yml with working_dir line
    cat > "${temp_dir}/docker-compose.yml" << 'YAML'
services:
  testapp:
    build:
      context: .
      dockerfile: docker/Dockerfile.dev
    container_name: testapp
    volumes:
      - .:/workspace:cached
    working_dir: /workspace
    command: sleep infinity
YAML

    # Copy postgresql overlay
    cp "${SCRIPT_DIR}/templates/services/postgresql/docker-compose.postgresql.yml" \
       "${temp_dir}/docker-compose.postgresql.yml"

    # Create base devcontainer.json
    cat > "${temp_dir}/.devcontainer/devcontainer.json" << 'JSON'
{
  "name": "testapp",
  "dockerComposeFile": ["../docker-compose.yml"],
  "service": "testapp",
  "runServices": ["testapp"],
  "workspaceFolder": "/workspace"
}
JSON

    # Create post.sh
    cat > "${temp_dir}/.devcontainer/scripts/post.sh" << 'BASH'
#!/bin/bash
echo "post-create"
BASH

    # Source and run plugin_post_copy
    source "${SCRIPT_DIR}/templates/services/postgresql/plugin.sh"
    plugin_post_copy "$temp_dir"

    # Verify dockerComposeFile does NOT contain postgresql overlay
    run jq -r '.dockerComposeFile | length' "${temp_dir}/.devcontainer/devcontainer.json"
    assert_success
    assert_output "1"

    run jq -r '.dockerComposeFile[0]' "${temp_dir}/.devcontainer/devcontainer.json"
    assert_success
    assert_output "../docker-compose.yml"

    # Cleanup
    rm -rf "$temp_dir"
}

@test "plugin_post_copy adds DB service to runServices" {
    local temp_dir
    temp_dir=$(mktemp -d)

    # Set up directory structure
    mkdir -p "${temp_dir}/.devcontainer/scripts"

    # Create base docker-compose.yml
    cat > "${temp_dir}/docker-compose.yml" << 'YAML'
services:
  testapp:
    build:
      context: .
      dockerfile: docker/Dockerfile.dev
    container_name: testapp
    volumes:
      - .:/workspace:cached
    working_dir: /workspace
    command: sleep infinity
YAML

    # Copy postgresql overlay
    cp "${SCRIPT_DIR}/templates/services/postgresql/docker-compose.postgresql.yml" \
       "${temp_dir}/docker-compose.postgresql.yml"

    # Create base devcontainer.json
    cat > "${temp_dir}/.devcontainer/devcontainer.json" << 'JSON'
{
  "name": "testapp",
  "dockerComposeFile": ["../docker-compose.yml"],
  "service": "testapp",
  "runServices": ["testapp"],
  "workspaceFolder": "/workspace"
}
JSON

    # Create post.sh
    cat > "${temp_dir}/.devcontainer/scripts/post.sh" << 'BASH'
#!/bin/bash
echo "post-create"
BASH

    # Source and run plugin_post_copy
    source "${SCRIPT_DIR}/templates/services/postgresql/plugin.sh"
    plugin_post_copy "$temp_dir"

    # Verify runServices contains the DB service
    run jq -r '.runServices | length' "${temp_dir}/.devcontainer/devcontainer.json"
    assert_success
    assert_output "2"

    run jq -r '.runServices[1]' "${temp_dir}/.devcontainer/devcontainer.json"
    assert_success
    assert_output "{{PROJECT_NAME}}-db"

    # Cleanup
    rm -rf "$temp_dir"
}

# =============================================================================
# MySQL Plugin Interface Tests
# =============================================================================

@test "mysql plugin.sh has valid bash syntax" {
    run bash -n "${SCRIPT_DIR}/templates/services/mysql/plugin.sh"
    assert_success
}

@test "mysql plugin exports plugin_name function" {
    source "${SCRIPT_DIR}/templates/services/mysql/plugin.sh"
    run plugin_name
    assert_success
    assert_output "mysql"
}

@test "mysql plugin exports plugin_description function" {
    source "${SCRIPT_DIR}/templates/services/mysql/plugin.sh"
    run plugin_description
    assert_success
    assert_output "MySQL 8.0 database service with mysql client"
}

@test "mysql plugin has plugin_copy function" {
    source "${SCRIPT_DIR}/templates/services/mysql/plugin.sh"
    declare -f plugin_copy > /dev/null
    assert_equal "$?" "0"
}

@test "mysql plugin has plugin_post_copy function" {
    source "${SCRIPT_DIR}/templates/services/mysql/plugin.sh"
    declare -f plugin_post_copy > /dev/null
    assert_equal "$?" "0"
}

# =============================================================================
# MySQL Template File Tests
# =============================================================================

@test "docker-compose.mysql.yml exists" {
    [ -f "${SCRIPT_DIR}/templates/services/mysql/docker-compose.mysql.yml" ]
}

@test "docker-compose.mysql.yml contains mysql:8.0 image" {
    run grep "image: mysql:8.0" "${SCRIPT_DIR}/templates/services/mysql/docker-compose.mysql.yml"
    assert_success
}

@test "docker-compose.mysql.yml contains healthcheck" {
    run grep "mysqladmin" "${SCRIPT_DIR}/templates/services/mysql/docker-compose.mysql.yml"
    assert_success
}

@test "docker-compose.mysql.yml contains volume definition" {
    run grep "mysql-data" "${SCRIPT_DIR}/templates/services/mysql/docker-compose.mysql.yml"
    assert_success
}

@test "docker-compose.mysql.yml contains PROJECT_NAME placeholder" {
    run grep "{{PROJECT_NAME}}" "${SCRIPT_DIR}/templates/services/mysql/docker-compose.mysql.yml"
    assert_success
}

@test "devcontainer.json exists for mysql plugin" {
    [ -f "${SCRIPT_DIR}/templates/services/mysql/.devcontainer/devcontainer.json" ]
}

@test "devcontainer.json contains mysql-client feature" {
    run grep "mysql-client" "${SCRIPT_DIR}/templates/services/mysql/.devcontainer/devcontainer.json"
    assert_success
}

@test "mysql devcontainer.json is valid JSON" {
    run jq '.' "${SCRIPT_DIR}/templates/services/mysql/.devcontainer/devcontainer.json"
    assert_success
}

# =============================================================================
# MySQL Docker Compose Merge Integration Test
# =============================================================================

@test "mysql docker-compose can be merged with base compose" {
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

    # Copy mysql overlay
    cp "${SCRIPT_DIR}/templates/services/mysql/docker-compose.mysql.yml" "${temp_dir}/overlay.yml"

    # Attempt merge
    merge_docker_compose_services "${temp_dir}/base.yml" "${temp_dir}/overlay.yml" "${temp_dir}/merged.yml"

    # Verify merged file exists and contains both services
    [ -f "${temp_dir}/merged.yml" ]
    grep -q "myapp" "${temp_dir}/merged.yml"
    grep -q "mysql" "${temp_dir}/merged.yml"

    # Cleanup
    rm -rf "$temp_dir"
}

# =============================================================================
# MySQL plugin_post_copy Integration Tests
# =============================================================================

@test "mysql plugin_post_copy does not add docker-compose.mysql.yml to dockerComposeFile" {
    local temp_dir
    temp_dir=$(mktemp -d)

    # Set up directory structure
    mkdir -p "${temp_dir}/.devcontainer/scripts"

    # Create base docker-compose.yml with working_dir line
    cat > "${temp_dir}/docker-compose.yml" << 'YAML'
services:
  testapp:
    build:
      context: .
      dockerfile: docker/Dockerfile.dev
    container_name: testapp
    volumes:
      - .:/workspace:cached
    working_dir: /workspace
    command: sleep infinity
YAML

    # Copy mysql overlay
    cp "${SCRIPT_DIR}/templates/services/mysql/docker-compose.mysql.yml" \
       "${temp_dir}/docker-compose.mysql.yml"

    # Create base devcontainer.json
    cat > "${temp_dir}/.devcontainer/devcontainer.json" << 'JSON'
{
  "name": "testapp",
  "dockerComposeFile": ["../docker-compose.yml"],
  "service": "testapp",
  "runServices": ["testapp"],
  "workspaceFolder": "/workspace"
}
JSON

    # Create post.sh
    cat > "${temp_dir}/.devcontainer/scripts/post.sh" << 'BASH'
#!/bin/bash
echo "post-create"
BASH

    # Source and run plugin_post_copy
    source "${SCRIPT_DIR}/templates/services/mysql/plugin.sh"
    plugin_post_copy "$temp_dir"

    # Verify dockerComposeFile does NOT contain mysql overlay
    run jq -r '.dockerComposeFile | length' "${temp_dir}/.devcontainer/devcontainer.json"
    assert_success
    assert_output "1"

    run jq -r '.dockerComposeFile[0]' "${temp_dir}/.devcontainer/devcontainer.json"
    assert_success
    assert_output "../docker-compose.yml"

    # Cleanup
    rm -rf "$temp_dir"
}

@test "mysql plugin_post_copy adds DB service to runServices" {
    local temp_dir
    temp_dir=$(mktemp -d)

    # Set up directory structure
    mkdir -p "${temp_dir}/.devcontainer/scripts"

    # Create base docker-compose.yml
    cat > "${temp_dir}/docker-compose.yml" << 'YAML'
services:
  testapp:
    build:
      context: .
      dockerfile: docker/Dockerfile.dev
    container_name: testapp
    volumes:
      - .:/workspace:cached
    working_dir: /workspace
    command: sleep infinity
YAML

    # Copy mysql overlay
    cp "${SCRIPT_DIR}/templates/services/mysql/docker-compose.mysql.yml" \
       "${temp_dir}/docker-compose.mysql.yml"

    # Create base devcontainer.json
    cat > "${temp_dir}/.devcontainer/devcontainer.json" << 'JSON'
{
  "name": "testapp",
  "dockerComposeFile": ["../docker-compose.yml"],
  "service": "testapp",
  "runServices": ["testapp"],
  "workspaceFolder": "/workspace"
}
JSON

    # Create post.sh
    cat > "${temp_dir}/.devcontainer/scripts/post.sh" << 'BASH'
#!/bin/bash
echo "post-create"
BASH

    # Source and run plugin_post_copy
    source "${SCRIPT_DIR}/templates/services/mysql/plugin.sh"
    plugin_post_copy "$temp_dir"

    # Verify runServices contains the DB service
    run jq -r '.runServices | length' "${temp_dir}/.devcontainer/devcontainer.json"
    assert_success
    assert_output "2"

    run jq -r '.runServices[1]' "${temp_dir}/.devcontainer/devcontainer.json"
    assert_success
    assert_output "{{PROJECT_NAME}}-db"

    # Cleanup
    rm -rf "$temp_dir"
}
