#!/bin/bash
# =============================================================================
# Template Plugin: python
# This file is meant to be sourced by setup.sh, not executed directly.
# =============================================================================
# This plugin provides Python development environment features including:
# - Python 3.12 devcontainer feature
# - uv package manager
# - VS Code extensions for Python development
# - Ruff linter/formatter configuration
# - mypy type checker configuration
# - pytest test framework configuration
# - Claude Code hooks for automatic linting/formatting
#
# =============================================================================

# Get the directory where this plugin is located
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# Required Functions
# =============================================================================

# Return plugin identifier
plugin_name() {
    echo "python"
}

# Return plugin description
plugin_description() {
    echo "Python 3.12 development environment with uv"
}

# =============================================================================
# Hook Functions
# =============================================================================

# Post-copy processing - merge devcontainer.json, settings.json, and copy tool configs
plugin_post_copy() {
    local target_dir="$1"

    # Merge devcontainer.json features and extensions
    local target_devcontainer="${target_dir}/.devcontainer/devcontainer.json"
    local plugin_devcontainer="${PLUGIN_DIR}/.devcontainer/devcontainer.json"

    if [[ -f "$plugin_devcontainer" ]] && [[ -f "$target_devcontainer" ]]; then
        print_info "Merging Python devcontainer features..."
        local temp_file="${target_dir}/.devcontainer/devcontainer.json.tmp"

        # Merge devcontainer.json with special handling for features and extensions
        merge_devcontainer_json "$target_devcontainer" "$plugin_devcontainer" "$temp_file"
        mv "$temp_file" "$target_devcontainer"

        print_success "Python devcontainer features merged"
    fi

    # Merge Claude settings hooks
    local target_settings="${target_dir}/.claude/settings.json"
    local plugin_settings="${PLUGIN_DIR}/.claude/settings.json"

    if [[ -f "$plugin_settings" ]] && [[ -f "$target_settings" ]]; then
        print_info "Merging Python Claude settings..."
        local temp_file="${target_dir}/.claude/settings.json.tmp"

        # Merge settings with hook array concatenation
        merge_claude_settings_hooks "$target_settings" "$plugin_settings" "$temp_file"
        mv "$temp_file" "$target_settings"

        print_success "Python Claude settings merged"
    fi

    # Copy tool configuration files
    local tool_configs=("ruff.toml" "mypy.ini" "pytest.ini")

    for config_file in "${tool_configs[@]}"; do
        local source_config="${PLUGIN_DIR}/${config_file}"
        local target_config="${target_dir}/${config_file}"

        if [[ -f "$source_config" ]]; then
            if [[ -f "$target_config" ]]; then
                print_warning "Skipping ${config_file} (already exists in target)"
            else
                print_info "Copying ${config_file}..."
                cp "$source_config" "$target_config"
                print_success "${config_file} copied"
            fi
        fi
    done
}
