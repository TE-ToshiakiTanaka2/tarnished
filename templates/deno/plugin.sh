#!/bin/bash
# =============================================================================
# Template Plugin: deno
# This file is meant to be sourced by setup.sh, not executed directly.
# =============================================================================
# This plugin provides Deno development environment features including:
# - Deno 2.1.x (Stable) devcontainer feature
# - VS Code Deno extension
# - deno.json configuration (tasks, imports, compiler options)
# - Deno.test with BDD style (@std/testing/bdd)
# - GitHub Actions CI workflow
# - Claude Code hooks for automatic formatting/linting
#
# =============================================================================

# Get the directory where this plugin is located
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# Required Functions
# =============================================================================

# Return plugin identifier
plugin_name() {
    echo "deno"
}

# Return plugin description
plugin_description() {
    echo "Deno 2.x development environment"
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
        print_info "Merging Deno devcontainer features..."
        local temp_file="${target_dir}/.devcontainer/devcontainer.json.tmp"

        # Merge devcontainer.json with special handling for features and extensions
        merge_devcontainer_json "$target_devcontainer" "$plugin_devcontainer" "$temp_file"
        mv "$temp_file" "$target_devcontainer"

        print_success "Deno devcontainer features merged"
    fi

    # Merge Claude settings hooks
    local target_settings="${target_dir}/.claude/settings.json"
    local plugin_settings="${PLUGIN_DIR}/.claude/settings.json"

    if [[ -f "$plugin_settings" ]] && [[ -f "$target_settings" ]]; then
        print_info "Merging Deno Claude settings..."
        local temp_file="${target_dir}/.claude/settings.json.tmp"

        # Merge settings with hook array concatenation
        merge_claude_settings_hooks "$target_settings" "$plugin_settings" "$temp_file"
        mv "$temp_file" "$target_settings"

        print_success "Deno Claude settings merged"
    fi

    # Copy tool configuration files
    local tool_configs=("deno.json")

    for config_file in "${tool_configs[@]}"; do
        local source_config="${PLUGIN_DIR}/${config_file}"
        local target_config="${target_dir}/${config_file}"

        if [[ -f "$source_config" ]]; then
            print_info "Copying ${config_file}..."
            copy_with_confirm "$source_config" "$target_config"
        fi
    done

    # Copy GitHub Actions workflow
    local source_workflows="${PLUGIN_DIR}/.github/workflows"
    local target_workflows="${target_dir}/.github/workflows"

    if [[ -d "$source_workflows" ]]; then
        mkdir -p "$target_workflows"
        for workflow_file in "${source_workflows}"/*.yml; do
            if [[ -f "$workflow_file" ]]; then
                local filename
                filename=$(basename "$workflow_file")
                local target_workflow="${target_workflows}/${filename}"
                print_info "Copying ${filename}..."
                copy_with_confirm "$workflow_file" "$target_workflow"
            fi
        done
    fi

    # Copy test directory structure
    local source_tests="${PLUGIN_DIR}/tests"
    local target_tests="${target_dir}/tests"

    if [[ -d "$source_tests" ]]; then
        print_info "Copying tests directory..."
        copy_dir_with_confirm "$source_tests" "$target_tests"
    fi
}
