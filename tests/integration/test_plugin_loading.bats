#!/usr/bin/env bats
# =============================================================================
# Integration Tests: Plugin Loading System
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

    # Initialize global variables that setup.sh uses
    export SCRIPT_DIR="${PROJECT_ROOT}"
    export TEMPLATES_DIR="${PROJECT_ROOT}/templates"
    export LOADED_PLUGINS=()
    export PLUGIN_NAMES=()
    export SELECTED_LANGUAGES=()
    export AVAILABLE_LANGUAGES=()
    export PLAYWRIGHT_ENABLED="false"
    export CORE_PLUGINS=("claude")
    declare -gA LANGUAGE_DISPLAY_NAMES=(
        ["node"]="Node.js/TypeScript"
    )

    # Extract key functions from setup.sh
    TEMP_FUNCTIONS="$(mktemp)"
    sed -n '/^load_plugin()/,/^}/p' "${PROJECT_ROOT}/setup.sh" > "${TEMP_FUNCTIONS}"
    sed -n '/^load_selected_plugins()/,/^}/p' "${PROJECT_ROOT}/setup.sh" >> "${TEMP_FUNCTIONS}"
    sed -n '/^execute_plugins_hook()/,/^}/p' "${PROJECT_ROOT}/setup.sh" >> "${TEMP_FUNCTIONS}"
    sed -n '/^discover_available_languages()/,/^}/p' "${PROJECT_ROOT}/setup.sh" >> "${TEMP_FUNCTIONS}"
    source "${TEMP_FUNCTIONS}"
    rm -f "${TEMP_FUNCTIONS}"
}

teardown() {
    teardown_temp_dir
}

# =============================================================================
# discover_available_languages Tests
# =============================================================================

@test "discover_available_languages: finds template languages" {
    discover_available_languages

    # At least node should be discovered (it has plugin.sh)
    [[ ${#AVAILABLE_LANGUAGES[@]} -gt 0 ]]
}

@test "discover_available_languages: finds node language" {
    discover_available_languages

    # Node should be in available languages
    local found=false
    for lang in "${AVAILABLE_LANGUAGES[@]}"; do
        if [[ "$lang" == "node" ]]; then
            found=true
            break
        fi
    done
    [[ "$found" == "true" ]]
}

# =============================================================================
# load_plugin Tests
# =============================================================================

@test "load_plugin: loads core plugin successfully" {
    run load_plugin "${TEMPLATES_DIR}/core/plugin.sh"
    assert_success
}

@test "load_plugin: loads node plugin successfully" {
    # First load core as it's typically a dependency
    load_plugin "${TEMPLATES_DIR}/core/plugin.sh"

    run load_plugin "${TEMPLATES_DIR}/node/plugin.sh"
    assert_success
}

@test "load_plugin: loads claude plugin successfully" {
    load_plugin "${TEMPLATES_DIR}/core/plugin.sh"

    run load_plugin "${TEMPLATES_DIR}/claude/plugin.sh"
    assert_success
}

@test "load_plugin: loads playwright plugin successfully" {
    load_plugin "${TEMPLATES_DIR}/core/plugin.sh"

    run load_plugin "${TEMPLATES_DIR}/playwright/plugin.sh"
    assert_success
}

@test "load_plugin: fails for non-existent plugin" {
    run load_plugin "/nonexistent/plugin.sh"
    assert_failure
    assert_output --partial "Failed to load plugin"
}

@test "load_plugin: makes plugin_name function available" {
    load_plugin "${TEMPLATES_DIR}/core/plugin.sh"

    # plugin_name function should be available
    run plugin_name
    assert_success
    assert_output "core"
}

# =============================================================================
# load_selected_plugins Tests
# =============================================================================

@test "load_selected_plugins: loads core plugin" {
    LOADED_PLUGINS=()
    PLUGIN_NAMES=()
    SELECTED_LANGUAGES=("node")
    PLAYWRIGHT_ENABLED="false"

    load_selected_plugins

    # Core should be loaded
    [[ " ${PLUGIN_NAMES[*]} " =~ " core " ]]
}

@test "load_selected_plugins: loads selected language plugins" {
    LOADED_PLUGINS=()
    PLUGIN_NAMES=()
    SELECTED_LANGUAGES=("node")
    PLAYWRIGHT_ENABLED="false"

    load_selected_plugins

    # Node should be in the loaded plugins
    [[ " ${PLUGIN_NAMES[*]} " =~ " node " ]]
}

@test "load_selected_plugins: loads claude plugin by default" {
    LOADED_PLUGINS=()
    PLUGIN_NAMES=()
    SELECTED_LANGUAGES=("node")
    PLAYWRIGHT_ENABLED="false"

    load_selected_plugins

    # Claude should be loaded as a core plugin
    [[ " ${PLUGIN_NAMES[*]} " =~ " claude " ]]
}

@test "load_selected_plugins: loads playwright plugin when enabled" {
    LOADED_PLUGINS=()
    PLUGIN_NAMES=()
    SELECTED_LANGUAGES=("node")
    PLAYWRIGHT_ENABLED="true"

    load_selected_plugins

    [[ " ${PLUGIN_NAMES[*]} " =~ " playwright " ]]
}

@test "load_selected_plugins: does not load playwright when disabled" {
    LOADED_PLUGINS=()
    PLUGIN_NAMES=()
    SELECTED_LANGUAGES=("node")
    PLAYWRIGHT_ENABLED="false"

    load_selected_plugins

    [[ ! " ${PLUGIN_NAMES[*]} " =~ " playwright " ]]
}

# =============================================================================
# execute_plugins_hook Tests
# =============================================================================

@test "execute_plugins_hook: executes hook on loaded plugins" {
    # Load some plugins first
    LOADED_PLUGINS=()
    PLUGIN_NAMES=()
    load_plugin "${TEMPLATES_DIR}/core/plugin.sh"
    LOADED_PLUGINS+=("${TEMPLATES_DIR}/core/plugin.sh")
    PLUGIN_NAMES+=("core")

    # Execute a hook (plugin_name is always defined)
    run execute_plugins_hook "plugin_name"
    assert_success
}

@test "execute_plugins_hook: handles non-existent hook gracefully" {
    LOADED_PLUGINS=()
    PLUGIN_NAMES=()
    load_plugin "${TEMPLATES_DIR}/core/plugin.sh"
    LOADED_PLUGINS+=("${TEMPLATES_DIR}/core/plugin.sh")
    PLUGIN_NAMES+=("core")

    # Execute a hook that doesn't exist
    run execute_plugins_hook "nonexistent_hook"
    assert_success
}

@test "execute_plugins_hook: passes target_dir to hooks" {
    LOADED_PLUGINS=()
    PLUGIN_NAMES=()
    load_plugin "${TEMPLATES_DIR}/core/plugin.sh"
    LOADED_PLUGINS+=("${TEMPLATES_DIR}/core/plugin.sh")
    PLUGIN_NAMES+=("core")

    # Create a temp target directory
    local target="${TEST_TEMP_DIR}/target"
    mkdir -p "${target}"

    # plugin_copy hook should receive target_dir
    run execute_plugins_hook "plugin_copy" "${target}"
    assert_success
}

# =============================================================================
# Plugin Interface Tests
# =============================================================================

@test "core plugin: has required plugin_name function" {
    source "${TEMPLATES_DIR}/core/plugin.sh"

    run plugin_name
    assert_success
    assert_output "core"
}

@test "core plugin: has required plugin_description function" {
    source "${TEMPLATES_DIR}/core/plugin.sh"

    run plugin_description
    assert_success
    # Just verify it outputs something
    [[ -n "$output" ]]
}

@test "node plugin: has required plugin_name function" {
    source "${TEMPLATES_DIR}/core/plugin.sh"
    source "${TEMPLATES_DIR}/node/plugin.sh"

    run plugin_name
    assert_success
    assert_output "node"
}

@test "node plugin: has required plugin_description function" {
    source "${TEMPLATES_DIR}/core/plugin.sh"
    source "${TEMPLATES_DIR}/node/plugin.sh"

    run plugin_description
    assert_success
    [[ -n "$output" ]]
}

@test "claude plugin: has required plugin_name function" {
    source "${TEMPLATES_DIR}/core/plugin.sh"
    source "${TEMPLATES_DIR}/claude/plugin.sh"

    run plugin_name
    assert_success
    assert_output "claude"
}

@test "playwright plugin: has required plugin_name function" {
    source "${TEMPLATES_DIR}/core/plugin.sh"
    source "${TEMPLATES_DIR}/playwright/plugin.sh"

    run plugin_name
    assert_success
    assert_output "playwright"
}

# =============================================================================
# Plugin Copy Hook Tests
# =============================================================================

@test "core plugin: plugin_copy creates .devcontainer" {
    source "${TEMPLATES_DIR}/core/plugin.sh"

    local target="${TEST_TEMP_DIR}/target"
    mkdir -p "${target}"

    plugin_copy "${target}"

    [[ -d "${target}/.devcontainer" ]]
}

@test "core plugin: plugin_copy creates docker directory" {
    source "${TEMPLATES_DIR}/core/plugin.sh"

    local target="${TEST_TEMP_DIR}/target"
    mkdir -p "${target}"

    plugin_copy "${target}"

    [[ -d "${target}/docker" ]]
}

@test "node plugin: plugin_copy copies node files" {
    source "${TEMPLATES_DIR}/core/plugin.sh"
    source "${TEMPLATES_DIR}/node/plugin.sh"

    local target="${TEST_TEMP_DIR}/target"
    mkdir -p "${target}"

    run plugin_copy "${target}"
    assert_success
    # Node plugin should copy its files (package.json or other node-specific files)
    # Check that some files were copied
    [[ -f "${target}/package.json" ]] || [[ -d "${target}/.devcontainer" ]] || [[ -n "$(ls -A ${target})" ]]
}
