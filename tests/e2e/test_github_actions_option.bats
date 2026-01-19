#!/usr/bin/env bats
# =============================================================================
# E2E Tests: GitHub Actions Option
# =============================================================================
#
# These tests verify that a project created with the github-actions option
# has the auto-tag action and related files properly configured.
#
# =============================================================================

# Load test helpers
setup() {
    load '../helpers/common'

    # Get project root
    PROJECT_ROOT="$(get_project_root)"

    # Load bats libraries
    load_bats_libraries

    # Setup temp directory
    setup_temp_dir
}

teardown() {
    teardown_temp_dir
}

# Helper to create a project with github-actions option
create_github_actions_project() {
    local project_name="${1:-e2e-github-actions-test}"
    local project_dir="${TEST_TEMP_DIR}/${project_name}"
    mkdir -p "${project_dir}"
    init_test_git_repo "${project_dir}"

    (cd "${project_dir}" && "${PROJECT_ROOT}/setup.sh" --lang node --github-actions --yes "${project_name}") >/dev/null 2>&1

    echo "${project_dir}"
}

# =============================================================================
# Plugin Loading Tests
# =============================================================================

@test "e2e/github-actions: plugin is loaded when --github-actions flag is used" {
    local project_name="github-actions-load-test"
    local project_dir="${TEST_TEMP_DIR}/${project_name}"
    mkdir -p "${project_dir}"
    init_test_git_repo "${project_dir}"

    # Run setup with --github-actions and capture output
    run bash -c "cd '${project_dir}' && '${PROJECT_ROOT}/setup.sh' --lang node --github-actions --yes '${project_name}' 2>&1"
    assert_success

    # Check that github-actions plugin was loaded
    assert_output --partial "github-actions"
}

# =============================================================================
# Auto-Tag Action Tests
# =============================================================================

@test "e2e/github-actions: auto-tag action directory exists" {
    local project_dir
    project_dir=$(create_github_actions_project "auto-tag-dir-test")

    # Auto-tag action directory should exist
    assert_dir_exists "${project_dir}/.github/actions/auto-tag"
}

@test "e2e/github-actions: auto-tag action.yml exists" {
    local project_dir
    project_dir=$(create_github_actions_project "auto-tag-action-test")

    # action.yml should exist
    assert_file_exists "${project_dir}/.github/actions/auto-tag/action.yml"
}

@test "e2e/github-actions: auto-tag action.yml has correct content" {
    local project_dir
    project_dir=$(create_github_actions_project "auto-tag-content-test")

    # action.yml should contain the action name
    run grep -E "name:.*Auto Tag" "${project_dir}/.github/actions/auto-tag/action.yml"
    assert_success
}

@test "e2e/github-actions: auto-tag dist/index.js exists" {
    local project_dir
    project_dir=$(create_github_actions_project "auto-tag-dist-test")

    # Compiled dist/index.js should exist
    assert_file_exists "${project_dir}/.github/actions/auto-tag/dist/index.js"
}

# =============================================================================
# Workflow Tests
# =============================================================================

@test "e2e/github-actions: auto-tag workflow exists" {
    local project_dir
    project_dir=$(create_github_actions_project "workflow-test")

    # auto-tag.yml workflow should exist
    assert_file_exists "${project_dir}/.github/workflows/auto-tag.yml"
}

@test "e2e/github-actions: auto-tag workflow has correct trigger" {
    local project_dir
    project_dir=$(create_github_actions_project "workflow-trigger-test")

    # Workflow should trigger on pull_request closed
    run grep -E "pull_request:" "${project_dir}/.github/workflows/auto-tag.yml"
    assert_success

    run grep -E "types:.*closed" "${project_dir}/.github/workflows/auto-tag.yml"
    assert_success
}

@test "e2e/github-actions: auto-tag workflow uses local action" {
    local project_dir
    project_dir=$(create_github_actions_project "workflow-action-test")

    # Workflow should use the local action
    run grep -E "uses:.*\./.github/actions/auto-tag" "${project_dir}/.github/workflows/auto-tag.yml"
    assert_success
}

# =============================================================================
# Configuration Tests
# =============================================================================

@test "e2e/github-actions: version.yml config exists" {
    local project_dir
    project_dir=$(create_github_actions_project "config-test")

    # version.yml should exist
    assert_file_exists "${project_dir}/.github/version.yml"
}

@test "e2e/github-actions: version.yml has versioning section" {
    local project_dir
    project_dir=$(create_github_actions_project "config-content-test")

    # version.yml should have versioning configuration
    run grep -E "versioning:" "${project_dir}/.github/version.yml"
    assert_success
}

@test "e2e/github-actions: version.yml has branch_prefixes" {
    local project_dir
    project_dir=$(create_github_actions_project "config-prefixes-test")

    # version.yml should have branch_prefixes
    run grep -E "branch_prefixes:" "${project_dir}/.github/version.yml"
    assert_success
}

@test "e2e/github-actions: version.yml has major/minor/patch prefixes" {
    local project_dir
    project_dir=$(create_github_actions_project "config-types-test")

    # version.yml should have all prefix types
    run grep -E "major:" "${project_dir}/.github/version.yml"
    assert_success

    run grep -E "minor:" "${project_dir}/.github/version.yml"
    assert_success

    run grep -E "patch:" "${project_dir}/.github/version.yml"
    assert_success
}

# =============================================================================
# Combined Option Tests
# =============================================================================

@test "e2e/github-actions: github-actions and docker options work together" {
    local project_name="github-actions-docker-test"
    local project_dir="${TEST_TEMP_DIR}/${project_name}"
    mkdir -p "${project_dir}"
    init_test_git_repo "${project_dir}"

    # Create project with both github-actions and docker
    run bash -c "cd '${project_dir}' && '${PROJECT_ROOT}/setup.sh' --lang node --github-actions --docker --yes '${project_name}'"
    assert_success

    # Auto-tag action should be present
    assert_dir_exists "${project_dir}/.github/actions/auto-tag"

    # Docker feature should also be present
    run grep -E "docker-in-docker" "${project_dir}/.devcontainer/devcontainer.json"
    assert_success
}

@test "e2e/github-actions: github-actions and playwright options work together" {
    local project_name="github-actions-playwright-test"
    local project_dir="${TEST_TEMP_DIR}/${project_name}"
    mkdir -p "${project_dir}"
    init_test_git_repo "${project_dir}"

    # Create project with both github-actions and playwright
    run bash -c "cd '${project_dir}' && '${PROJECT_ROOT}/setup.sh' --lang node --github-actions --playwright --yes '${project_name}'"
    assert_success

    # Auto-tag action should be present
    assert_dir_exists "${project_dir}/.github/actions/auto-tag"

    # Playwright should also be present
    run grep -E "playwright" "${project_dir}/.devcontainer/devcontainer.json"
    assert_success
}

@test "e2e/github-actions: works with python language template" {
    local project_name="github-actions-python-test"
    local project_dir="${TEST_TEMP_DIR}/${project_name}"
    mkdir -p "${project_dir}"
    init_test_git_repo "${project_dir}"

    # Create project with python and github-actions
    run bash -c "cd '${project_dir}' && '${PROJECT_ROOT}/setup.sh' --lang python --github-actions --yes '${project_name}'"
    assert_success

    # Auto-tag action should be present
    assert_dir_exists "${project_dir}/.github/actions/auto-tag"
    assert_file_exists "${project_dir}/.github/workflows/auto-tag.yml"
}
