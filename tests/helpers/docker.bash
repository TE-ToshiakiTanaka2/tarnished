#!/bin/bash
# =============================================================================
# Test Helper: Docker Operations
# Provides utilities for E2E testing with Docker containers
# =============================================================================

# Prevent multiple loading
if [[ -n "${_TEST_DOCKER_LOADED:-}" ]]; then
    return 0
fi
_TEST_DOCKER_LOADED=1

# =============================================================================
# Configuration
# =============================================================================

# Default container name prefix
E2E_CONTAINER_PREFIX="bats-e2e-test"

# Default timeout for container operations (seconds)
E2E_TIMEOUT=120

# =============================================================================
# Project Generation
# =============================================================================

# Generate a test project using setup.sh
# Arguments:
#   $1 - target directory
#   $2 - project name
#   $3 - languages (comma-separated, e.g., "python,node")
#   $4 - playwright enabled ("true" or "false")
generate_test_project() {
    local target_dir="$1"
    local project_name="$2"
    local languages="${3:-python}"
    local playwright="${4:-false}"
    local project_root

    project_root="$(get_project_root)"

    # Build the command
    local cmd=("${project_root}/setup.sh")
    cmd+=("--lang" "${languages}")
    cmd+=("--yes")

    if [[ "${playwright}" == "true" ]]; then
        cmd+=("--playwright")
    fi

    cmd+=("${project_name}")

    # Run setup.sh
    (
        cd "${target_dir}" || return 1
        "${cmd[@]}"
    )
}

# =============================================================================
# Docker Build Operations
# =============================================================================

# Build Docker image from a generated project
# Arguments:
#   $1 - project directory
#   $2 - image tag (optional, defaults to project name)
build_test_image() {
    local project_dir="$1"
    local image_tag="${2:-$(basename "${project_dir}")}"

    if [[ ! -f "${project_dir}/docker/Dockerfile.dev" ]]; then
        echo "Error: Dockerfile.dev not found in ${project_dir}/docker/" >&2
        return 1
    fi

    docker build \
        -f "${project_dir}/docker/Dockerfile.dev" \
        -t "${image_tag}" \
        "${project_dir}"
}

# Build using docker-compose
# Arguments:
#   $1 - project directory
build_with_compose() {
    local project_dir="$1"

    if [[ ! -f "${project_dir}/docker-compose.yml" ]]; then
        echo "Error: docker-compose.yml not found in ${project_dir}" >&2
        return 1
    fi

    (
        cd "${project_dir}" || return 1
        docker-compose build
    )
}

# =============================================================================
# Container Lifecycle
# =============================================================================

# Start a container from a built image
# Arguments:
#   $1 - image tag
#   $2 - container name (optional)
# Returns: container ID
start_container() {
    local image_tag="$1"
    local container_name="${2:-${E2E_CONTAINER_PREFIX}-$(date +%s)}"

    docker run -d \
        --name "${container_name}" \
        "${image_tag}" \
        tail -f /dev/null

    echo "${container_name}"
}

# Start container using docker-compose
# Arguments:
#   $1 - project directory
#   $2 - service name (optional, defaults to "dev")
start_with_compose() {
    local project_dir="$1"
    local service="${2:-dev}"

    (
        cd "${project_dir}" || return 1
        docker-compose up -d "${service}"
    )
}

# Stop and remove a container
# Arguments:
#   $1 - container name or ID
stop_container() {
    local container="$1"

    docker stop "${container}" 2>/dev/null || true
    docker rm -f "${container}" 2>/dev/null || true
}

# Stop containers using docker-compose
# Arguments:
#   $1 - project directory
stop_with_compose() {
    local project_dir="$1"

    (
        cd "${project_dir}" || return 1
        docker-compose down -v 2>/dev/null || true
    )
}

# =============================================================================
# Container Execution
# =============================================================================

# Execute a command in a running container
# Arguments:
#   $1 - container name or ID
#   $@ - command and arguments
exec_in_container() {
    local container="$1"
    shift

    docker exec "${container}" "$@"
}

# Execute a command using docker-compose
# Arguments:
#   $1 - project directory
#   $2 - service name
#   $@ - command and arguments
exec_with_compose() {
    local project_dir="$1"
    local service="$2"
    shift 2

    (
        cd "${project_dir}" || return 1
        docker-compose exec -T "${service}" "$@"
    )
}

# =============================================================================
# Verification Functions
# =============================================================================

# Verify that a command exists in the container
# Arguments:
#   $1 - container name or ID
#   $2 - command name
verify_command_exists() {
    local container="$1"
    local command_name="$2"

    exec_in_container "${container}" which "${command_name}" >/dev/null 2>&1
}

# Verify command version in container
# Arguments:
#   $1 - container name or ID
#   $2 - command name
#   $3 - version flag (optional, defaults to "--version")
get_command_version() {
    local container="$1"
    local command_name="$2"
    local version_flag="${3:---version}"

    exec_in_container "${container}" "${command_name}" "${version_flag}" 2>&1 | head -1
}

# Wait for container to be ready
# Arguments:
#   $1 - container name or ID
#   $2 - timeout in seconds (optional, defaults to E2E_TIMEOUT)
wait_for_container() {
    local container="$1"
    local timeout="${2:-${E2E_TIMEOUT}}"
    local elapsed=0

    while [[ ${elapsed} -lt ${timeout} ]]; do
        if docker exec "${container}" echo "ready" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
        ((elapsed++))
    done

    echo "Error: Container ${container} not ready after ${timeout} seconds" >&2
    return 1
}

# =============================================================================
# Cleanup Functions
# =============================================================================

# Cleanup all E2E test containers
cleanup_e2e_containers() {
    local containers
    containers=$(docker ps -a --filter "name=${E2E_CONTAINER_PREFIX}" -q)

    if [[ -n "${containers}" ]]; then
        echo "${containers}" | xargs docker rm -f 2>/dev/null || true
    fi
}

# Cleanup test images
# Arguments:
#   $1 - image tag pattern (optional, defaults to E2E_CONTAINER_PREFIX)
# shellcheck disable=SC2120
cleanup_test_images() {
    local pattern="${1:-${E2E_CONTAINER_PREFIX}}"

    docker images --filter "reference=${pattern}*" -q | \
        xargs -r docker rmi -f 2>/dev/null || true
}

# Full E2E cleanup
e2e_full_cleanup() {
    cleanup_e2e_containers
    cleanup_test_images
}

# =============================================================================
# Devcontainer CLI Operations
# =============================================================================

# Check if devcontainer CLI is available
# Returns: 0 if available, 1 otherwise
check_devcontainer_cli() {
    command -v devcontainer &>/dev/null
}

# Build and start a devcontainer
# Arguments:
#   $1 - workspace folder path
# Outputs:
#   Container ID on success
#   Sets E2E_DEVCONTAINER_ID variable
start_devcontainer() {
    local workspace_folder="$1"
    local output
    local container_id

    if ! check_devcontainer_cli; then
        echo "Error: devcontainer CLI not available" >&2
        return 1
    fi

    # Start devcontainer and capture output
    output=$(devcontainer up \
        --workspace-folder "${workspace_folder}" \
        --remove-existing-container 2>&1)

    # Extract container ID from JSON output
    container_id=$(echo "${output}" | grep -o '"containerId":"[^"]*"' | cut -d'"' -f4)

    if [[ -z "${container_id}" ]]; then
        echo "Error: Failed to start devcontainer" >&2
        echo "Output: ${output}" >&2
        return 1
    fi

    # Export for use in tests
    # shellcheck disable=SC2034
    E2E_DEVCONTAINER_ID="${container_id}"
    echo "${container_id}"
}

# Execute command in a devcontainer
# Arguments:
#   $1 - workspace folder path
#   $@ - command and arguments to execute
exec_in_devcontainer() {
    local workspace_folder="$1"
    shift

    if ! check_devcontainer_cli; then
        echo "Error: devcontainer CLI not available" >&2
        return 1
    fi

    devcontainer exec --workspace-folder "${workspace_folder}" "$@"
}

# Stop and cleanup a devcontainer
# Arguments:
#   $1 - workspace folder path or container ID
cleanup_devcontainer() {
    local workspace_or_container="$1"

    # If it looks like a container ID (64 hex chars or short ID)
    if [[ "${workspace_or_container}" =~ ^[a-f0-9]+$ ]]; then
        docker stop "${workspace_or_container}" 2>/dev/null || true
        docker rm -f "${workspace_or_container}" 2>/dev/null || true
    else
        # It's a workspace folder - try to find and stop the container
        if check_devcontainer_cli; then
            local container_id
            # Try to get existing container ID
            container_id=$(devcontainer up \
                --workspace-folder "${workspace_or_container}" \
                --expect-existing-container 2>/dev/null | \
                grep -o '"containerId":"[^"]*"' | cut -d'"' -f4 || true)

            if [[ -n "${container_id}" ]]; then
                docker stop "${container_id}" 2>/dev/null || true
                docker rm -f "${container_id}" 2>/dev/null || true
            fi
        fi
    fi

    # Also clean up any associated images with the workspace name
    local workspace_name
    workspace_name=$(basename "${workspace_or_container}" 2>/dev/null || echo "${workspace_or_container}")
    docker images --filter "reference=*${workspace_name}*" -q 2>/dev/null | \
        xargs -r docker rmi -f 2>/dev/null || true
}

# Verify that a command exists in a devcontainer
# Arguments:
#   $1 - workspace folder path
#   $2 - command name
verify_devcontainer_command() {
    local workspace_folder="$1"
    local command_name="$2"

    exec_in_devcontainer "${workspace_folder}" which "${command_name}" >/dev/null 2>&1
}

# Get command version in a devcontainer
# Arguments:
#   $1 - workspace folder path
#   $2 - command name
#   $3 - version flag (optional, defaults to "--version")
get_devcontainer_command_version() {
    local workspace_folder="$1"
    local command_name="$2"
    local version_flag="${3:---version}"

    exec_in_devcontainer "${workspace_folder}" "${command_name}" "${version_flag}" 2>&1 | head -1
}

# Wait for devcontainer to be ready
# Arguments:
#   $1 - workspace folder path
#   $2 - timeout in seconds (optional, defaults to E2E_TIMEOUT)
wait_for_devcontainer() {
    local workspace_folder="$1"
    local timeout="${2:-${E2E_TIMEOUT}}"
    local elapsed=0

    while [[ ${elapsed} -lt ${timeout} ]]; do
        if exec_in_devcontainer "${workspace_folder}" echo "ready" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
        ((elapsed++))
    done

    echo "Error: Devcontainer not ready after ${timeout} seconds" >&2
    return 1
}
