#!/usr/bin/env bats
# =============================================================================
# Integration Tests: CI Workflow Copy Functionality
# =============================================================================
# Tests for the GitHub Actions workflow and test file copying functionality
# added to Python and Node.js plugins.
# =============================================================================

# Load test helpers
setup() {
    load '../helpers/common'
    load '../helpers/mock'

    # Get project root
    PROJECT_ROOT="$(get_project_root)"

    # Source common.sh first
    source "${PROJECT_ROOT}/scripts/lib/common.sh"

    # Load bats libraries
    load_bats_libraries

    # Setup temp directory
    setup_temp_dir

    # Create target directory structure
    TARGET_DIR="${TEST_TEMP_DIR}/target"
    mkdir -p "${TARGET_DIR}/.devcontainer"
    mkdir -p "${TARGET_DIR}/.claude"
    mkdir -p "${TARGET_DIR}/.github/workflows"

    # Create minimal devcontainer.json
    echo '{"name": "test"}' > "${TARGET_DIR}/.devcontainer/devcontainer.json"

    # Create minimal claude settings.json with proper structure
    cat > "${TARGET_DIR}/.claude/settings.json" << 'EOF'
{
  "permissions": {
    "allow": [],
    "deny": []
  },
  "hooks": {
    "PreToolUse": [],
    "PostToolUse": []
  },
  "env": {}
}
EOF
}

teardown() {
    teardown_temp_dir
}

# =============================================================================
# Python Plugin - CI Workflow Tests
# =============================================================================

@test "python plugin: copies python-ci.yml workflow" {
    source "${PROJECT_ROOT}/templates/core/plugin.sh"
    source "${PROJECT_ROOT}/templates/python/plugin.sh"

    plugin_post_copy "${TARGET_DIR}"

    [[ -f "${TARGET_DIR}/.github/workflows/python-ci.yml" ]]
}

@test "python plugin: copies pyproject.toml" {
    source "${PROJECT_ROOT}/templates/core/plugin.sh"
    source "${PROJECT_ROOT}/templates/python/plugin.sh"

    plugin_post_copy "${TARGET_DIR}"

    [[ -f "${TARGET_DIR}/pyproject.toml" ]]
}

@test "python plugin: copies tests directory" {
    source "${PROJECT_ROOT}/templates/core/plugin.sh"
    source "${PROJECT_ROOT}/templates/python/plugin.sh"

    plugin_post_copy "${TARGET_DIR}"

    [[ -d "${TARGET_DIR}/tests" ]]
    [[ -d "${TARGET_DIR}/tests/unit" ]]
    [[ -d "${TARGET_DIR}/tests/integration" ]]
}

@test "python plugin: copies sample unit test" {
    source "${PROJECT_ROOT}/templates/core/plugin.sh"
    source "${PROJECT_ROOT}/templates/python/plugin.sh"

    plugin_post_copy "${TARGET_DIR}"

    [[ -f "${TARGET_DIR}/tests/unit/test_sample.py" ]]
}

@test "python plugin: copies sample integration test" {
    source "${PROJECT_ROOT}/templates/core/plugin.sh"
    source "${PROJECT_ROOT}/templates/python/plugin.sh"

    plugin_post_copy "${TARGET_DIR}"

    [[ -f "${TARGET_DIR}/tests/integration/test_sample_integration.py" ]]
}

@test "python plugin: skips workflow if already exists" {
    source "${PROJECT_ROOT}/templates/core/plugin.sh"
    source "${PROJECT_ROOT}/templates/python/plugin.sh"

    # Pre-create workflow file
    echo "existing workflow" > "${TARGET_DIR}/.github/workflows/python-ci.yml"

    plugin_post_copy "${TARGET_DIR}"

    # Should not be overwritten
    run cat "${TARGET_DIR}/.github/workflows/python-ci.yml"
    assert_output "existing workflow"
}

@test "python plugin: skips tests directory if already exists" {
    source "${PROJECT_ROOT}/templates/core/plugin.sh"
    source "${PROJECT_ROOT}/templates/python/plugin.sh"

    # Pre-create tests directory with marker file
    mkdir -p "${TARGET_DIR}/tests"
    echo "existing test" > "${TARGET_DIR}/tests/existing.py"

    plugin_post_copy "${TARGET_DIR}"

    # Should not be overwritten, marker file should still exist
    [[ -f "${TARGET_DIR}/tests/existing.py" ]]
}

@test "python plugin: skips pyproject.toml if already exists" {
    source "${PROJECT_ROOT}/templates/core/plugin.sh"
    source "${PROJECT_ROOT}/templates/python/plugin.sh"

    # Pre-create pyproject.toml
    echo "[project]" > "${TARGET_DIR}/pyproject.toml"
    echo "name = 'existing'" >> "${TARGET_DIR}/pyproject.toml"

    plugin_post_copy "${TARGET_DIR}"

    # Should not be overwritten
    run cat "${TARGET_DIR}/pyproject.toml"
    assert_output --partial "existing"
}

# =============================================================================
# Node.js Plugin - CI Workflow Tests
# =============================================================================

@test "node plugin: copies node-ci.yml workflow" {
    source "${PROJECT_ROOT}/templates/core/plugin.sh"
    source "${PROJECT_ROOT}/templates/node/plugin.sh"

    plugin_post_copy "${TARGET_DIR}"

    [[ -f "${TARGET_DIR}/.github/workflows/node-ci.yml" ]]
}

@test "node plugin: copies package.json" {
    source "${PROJECT_ROOT}/templates/core/plugin.sh"
    source "${PROJECT_ROOT}/templates/node/plugin.sh"

    plugin_post_copy "${TARGET_DIR}"

    [[ -f "${TARGET_DIR}/package.json" ]]
}

@test "node plugin: copies biome.json" {
    source "${PROJECT_ROOT}/templates/core/plugin.sh"
    source "${PROJECT_ROOT}/templates/node/plugin.sh"

    plugin_post_copy "${TARGET_DIR}"

    [[ -f "${TARGET_DIR}/biome.json" ]]
}

@test "node plugin: copies tsconfig.json" {
    source "${PROJECT_ROOT}/templates/core/plugin.sh"
    source "${PROJECT_ROOT}/templates/node/plugin.sh"

    plugin_post_copy "${TARGET_DIR}"

    [[ -f "${TARGET_DIR}/tsconfig.json" ]]
}

@test "node plugin: copies vitest.config.ts" {
    source "${PROJECT_ROOT}/templates/core/plugin.sh"
    source "${PROJECT_ROOT}/templates/node/plugin.sh"

    plugin_post_copy "${TARGET_DIR}"

    [[ -f "${TARGET_DIR}/vitest.config.ts" ]]
}

@test "node plugin: copies tests directory" {
    source "${PROJECT_ROOT}/templates/core/plugin.sh"
    source "${PROJECT_ROOT}/templates/node/plugin.sh"

    plugin_post_copy "${TARGET_DIR}"

    [[ -d "${TARGET_DIR}/tests" ]]
    [[ -d "${TARGET_DIR}/tests/unit" ]]
    [[ -d "${TARGET_DIR}/tests/integration" ]]
}

@test "node plugin: copies sample unit test" {
    source "${PROJECT_ROOT}/templates/core/plugin.sh"
    source "${PROJECT_ROOT}/templates/node/plugin.sh"

    plugin_post_copy "${TARGET_DIR}"

    [[ -f "${TARGET_DIR}/tests/unit/sample.test.ts" ]]
}

@test "node plugin: copies sample integration test" {
    source "${PROJECT_ROOT}/templates/core/plugin.sh"
    source "${PROJECT_ROOT}/templates/node/plugin.sh"

    plugin_post_copy "${TARGET_DIR}"

    [[ -f "${TARGET_DIR}/tests/integration/sample.integration.test.ts" ]]
}

@test "node plugin: skips workflow if already exists" {
    source "${PROJECT_ROOT}/templates/core/plugin.sh"
    source "${PROJECT_ROOT}/templates/node/plugin.sh"

    # Pre-create workflow file
    echo "existing workflow" > "${TARGET_DIR}/.github/workflows/node-ci.yml"

    plugin_post_copy "${TARGET_DIR}"

    # Should not be overwritten
    run cat "${TARGET_DIR}/.github/workflows/node-ci.yml"
    assert_output "existing workflow"
}

@test "node plugin: skips config files if already exist" {
    source "${PROJECT_ROOT}/templates/core/plugin.sh"
    source "${PROJECT_ROOT}/templates/node/plugin.sh"

    # Pre-create config files
    echo '{"name": "existing"}' > "${TARGET_DIR}/package.json"
    echo '{"existing": true}' > "${TARGET_DIR}/biome.json"

    plugin_post_copy "${TARGET_DIR}"

    # Should not be overwritten
    run cat "${TARGET_DIR}/package.json"
    assert_output --partial "existing"

    run cat "${TARGET_DIR}/biome.json"
    assert_output --partial "existing"
}

# =============================================================================
# Workflow File Content Tests
# =============================================================================

@test "python-ci.yml: contains lint job" {
    run cat "${PROJECT_ROOT}/templates/python/.github/workflows/python-ci.yml"
    assert_output --partial "lint:"
}

@test "python-ci.yml: contains unit-test job" {
    run cat "${PROJECT_ROOT}/templates/python/.github/workflows/python-ci.yml"
    assert_output --partial "unit-test:"
}

@test "python-ci.yml: contains integration-test job" {
    run cat "${PROJECT_ROOT}/templates/python/.github/workflows/python-ci.yml"
    assert_output --partial "integration-test:"
}

@test "python-ci.yml: uses uv for package management" {
    run cat "${PROJECT_ROOT}/templates/python/.github/workflows/python-ci.yml"
    assert_output --partial "astral-sh/setup-uv"
}

@test "node-ci.yml: contains lint job" {
    run cat "${PROJECT_ROOT}/templates/node/.github/workflows/node-ci.yml"
    assert_output --partial "lint:"
}

@test "node-ci.yml: contains unit-test job" {
    run cat "${PROJECT_ROOT}/templates/node/.github/workflows/node-ci.yml"
    assert_output --partial "unit-test:"
}

@test "node-ci.yml: contains integration-test job" {
    run cat "${PROJECT_ROOT}/templates/node/.github/workflows/node-ci.yml"
    assert_output --partial "integration-test:"
}

@test "node-ci.yml: uses pnpm for package management" {
    run cat "${PROJECT_ROOT}/templates/node/.github/workflows/node-ci.yml"
    assert_output --partial "pnpm/action-setup"
}
