#!/usr/bin/env bats
# =============================================================================
# E2E Tests: Rust Template
# =============================================================================
#
# These tests verify that a project created with the rust template
# can be built and run successfully using devcontainer CLI.
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

# Helper to create a rust project
create_rust_project() {
    local project_name="${1:-e2e-rust-test}"
    E2E_PROJECT_DIR="${TEST_TEMP_DIR}/${project_name}"
    mkdir -p "${E2E_PROJECT_DIR}"

    (cd "${E2E_PROJECT_DIR}" && "${PROJECT_ROOT}/setup.sh" --lang rust --yes "${project_name}") >/dev/null 2>&1

    echo "${E2E_PROJECT_DIR}"
}

# =============================================================================
# File Generation Tests
# =============================================================================

@test "e2e/rust: setup.sh generates all required files" {
    local project_dir
    project_dir=$(create_rust_project "rust-files-test")

    # Check core files
    assert_file_exists "${project_dir}/.devcontainer/devcontainer.json"
    assert_file_exists "${project_dir}/docker-compose.yml"
    assert_file_exists "${project_dir}/docker/Dockerfile.dev"

    # Check Rust-specific tool config files
    assert_file_exists "${project_dir}/rustfmt.toml"
    assert_file_exists "${project_dir}/clippy.toml"
}

@test "e2e/rust: devcontainer.json contains Rust features" {
    local project_dir
    project_dir=$(create_rust_project "rust-features-test")

    # Check for Rust feature
    run jq -e '.features | keys | any(contains("rust"))' "${project_dir}/.devcontainer/devcontainer.json"
    assert_success
}

@test "e2e/rust: devcontainer.json contains Rust VS Code extensions" {
    local project_dir
    project_dir=$(create_rust_project "rust-extensions-test")

    local extensions
    extensions=$(jq -r '.customizations.vscode.extensions | join(" ")' "${project_dir}/.devcontainer/devcontainer.json")

    # Check for required extensions
    [[ "${extensions}" == *"rust-lang.rust-analyzer"* ]]
    [[ "${extensions}" == *"tamasfe.even-better-toml"* ]]
    [[ "${extensions}" == *"vadimcn.vscode-lldb"* ]]
    [[ "${extensions}" == *"serayuzgur.crates"* ]]
}

@test "e2e/rust: rustfmt.toml has correct edition" {
    local project_dir
    project_dir=$(create_rust_project "rust-rustfmt-test")

    run grep -E 'edition\s*=\s*"2021"' "${project_dir}/rustfmt.toml"
    assert_success
}

@test "e2e/rust: clippy.toml has complexity threshold" {
    local project_dir
    project_dir=$(create_rust_project "rust-clippy-test")

    run grep -E 'cognitive-complexity-threshold\s*=' "${project_dir}/clippy.toml"
    assert_success
}

# =============================================================================
# Docker Build Tests
# =============================================================================

@test "e2e/rust: docker build succeeds" {
    local project_dir
    project_dir=$(create_rust_project "rust-build-test")

    # Build the Docker image
    run docker build -f "${project_dir}/docker/Dockerfile.dev" -t "e2e-rust-build-test" "${project_dir}"
    assert_success
}

@test "e2e/rust: docker-compose build succeeds" {
    local project_dir
    project_dir=$(create_rust_project "rust-compose-build")

    # Build using docker-compose
    run bash -c "cd '${project_dir}' && docker-compose build"
    assert_success
}

# =============================================================================
# Devcontainer Startup Tests
# =============================================================================

@test "e2e/rust: container starts successfully" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(create_rust_project "rust-startup-test")

    # Start devcontainer
    run start_devcontainer "${project_dir}"
    assert_success
}

# =============================================================================
# Command Availability Tests (using devcontainer CLI)
# =============================================================================

@test "e2e/rust: git is available in container" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(create_rust_project "rust-git-test")

    start_devcontainer "${project_dir}" >/dev/null 2>&1

    run verify_devcontainer_command "${project_dir}" "git"
    assert_success
}

@test "e2e/rust: rustc is available in container" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(create_rust_project "rust-rustc-test")

    start_devcontainer "${project_dir}" >/dev/null 2>&1

    run verify_devcontainer_command "${project_dir}" "rustc"
    assert_success
}

@test "e2e/rust: cargo is available in container" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(create_rust_project "rust-cargo-test")

    start_devcontainer "${project_dir}" >/dev/null 2>&1

    run verify_devcontainer_command "${project_dir}" "cargo"
    assert_success
}

@test "e2e/rust: rustfmt is available in container" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(create_rust_project "rust-rustfmt-cmd-test")

    start_devcontainer "${project_dir}" >/dev/null 2>&1

    run verify_devcontainer_command "${project_dir}" "rustfmt"
    assert_success
}

@test "e2e/rust: clippy is available via cargo" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(create_rust_project "rust-clippy-cmd-test")

    start_devcontainer "${project_dir}" >/dev/null 2>&1

    # clippy is invoked via cargo clippy
    run exec_in_devcontainer "${project_dir}" cargo clippy --version
    assert_success
}

@test "e2e/rust: rust-analyzer is available in container" {
    # Skip if devcontainer CLI is not available
    if ! check_devcontainer_cli; then
        skip "devcontainer CLI is not available"
    fi

    local project_dir
    project_dir=$(create_rust_project "rust-analyzer-test")

    start_devcontainer "${project_dir}" >/dev/null 2>&1

    run verify_devcontainer_command "${project_dir}" "rust-analyzer"
    assert_success
}

# =============================================================================
# Post.sh Execution Tests
# =============================================================================

@test "e2e/rust: post.sh is executable" {
    local project_dir
    project_dir=$(create_rust_project "rust-postsh-test")

    [[ -x "${project_dir}/.devcontainer/scripts/post.sh" ]]
}

# =============================================================================
# Claude Settings Tests
# =============================================================================

@test "e2e/rust: claude settings contain cargo fmt hooks" {
    local project_dir
    project_dir=$(create_rust_project "rust-claude-test")

    # Check if .claude/settings.json exists and contains cargo fmt
    if [[ -f "${project_dir}/.claude/settings.json" ]]; then
        run jq -e '.hooks.PostToolUse[]?.hooks[]?.command | select(. != null) | contains("cargo fmt")' "${project_dir}/.claude/settings.json"
        assert_success
    else
        skip "Claude settings not generated (claude template may not be enabled)"
    fi
}

@test "e2e/rust: claude settings contain cargo clippy hooks" {
    local project_dir
    project_dir=$(create_rust_project "rust-claude-clippy-test")

    # Check if .claude/settings.json exists and contains cargo clippy
    if [[ -f "${project_dir}/.claude/settings.json" ]]; then
        run jq -e '.hooks.PostToolUse[]?.hooks[]?.command | select(. != null) | contains("cargo clippy")' "${project_dir}/.claude/settings.json"
        assert_success
    else
        skip "Claude settings not generated (claude template may not be enabled)"
    fi
}
