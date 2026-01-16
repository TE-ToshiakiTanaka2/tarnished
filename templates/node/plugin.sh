#!/bin/bash
# =============================================================================
# Template Plugin: node
# This file is meant to be sourced by setup.sh, not executed directly.
# =============================================================================
# This plugin provides Node.js development environment features including:
# - Node.js 22.x (LTS) devcontainer feature
# - pnpm package manager
# - VS Code extensions for JavaScript/TypeScript
# - Biome linter/formatter configuration
# - TypeScript configuration
# - Vitest test framework configuration
# - GitHub Actions CI workflow
# - Additional Claude Code hooks for Node.js
#
# =============================================================================

# Get the directory where this plugin is located
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# Required Functions
# =============================================================================

# Return plugin identifier
plugin_name() {
    echo "node"
}

# Return plugin description
plugin_description() {
    echo "Node.js 22.x development environment"
}

# =============================================================================
# Hook Functions
# =============================================================================

# Post-copy processing - merge devcontainer.json and settings.json
plugin_post_copy() {
    local target_dir="$1"

    # Merge devcontainer.json features and extensions
    local target_devcontainer="${target_dir}/.devcontainer/devcontainer.json"
    local plugin_devcontainer="${PLUGIN_DIR}/.devcontainer/devcontainer.json"

    if [[ -f "$plugin_devcontainer" ]] && [[ -f "$target_devcontainer" ]]; then
        print_info "Merging Node.js devcontainer features..."
        local temp_file="${target_dir}/.devcontainer/devcontainer.json.tmp"

        # Merge devcontainer.json with special handling for features and extensions
        merge_devcontainer_json "$target_devcontainer" "$plugin_devcontainer" "$temp_file"
        mv "$temp_file" "$target_devcontainer"

        print_success "Node.js devcontainer features merged"
    fi

    # Merge Claude settings hooks
    local target_settings="${target_dir}/.claude/settings.json"
    local plugin_settings="${PLUGIN_DIR}/.claude/settings.json"

    if [[ -f "$plugin_settings" ]] && [[ -f "$target_settings" ]]; then
        print_info "Merging Node.js Claude settings..."
        local temp_file="${target_dir}/.claude/settings.json.tmp"

        # Merge settings with hook array concatenation
        merge_claude_settings_hooks "$target_settings" "$plugin_settings" "$temp_file"
        mv "$temp_file" "$target_settings"

        print_success "Node.js Claude settings merged"
    fi

    # Copy tool configuration files
    local tool_configs=("package.json" "biome.json" "tsconfig.json" "vitest.config.ts")

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

                if [[ -f "$target_workflow" ]]; then
                    print_warning "Skipping ${filename} (already exists in target)"
                else
                    print_info "Copying ${filename}..."
                    cp "$workflow_file" "$target_workflow"
                    print_success "${filename} copied"
                fi
            fi
        done
    fi

    # Copy test directory structure
    local source_tests="${PLUGIN_DIR}/tests"
    local target_tests="${target_dir}/tests"

    if [[ -d "$source_tests" ]]; then
        if [[ -d "$target_tests" ]]; then
            print_warning "Skipping tests directory (already exists in target)"
        else
            print_info "Copying tests directory..."
            cp -r "$source_tests" "$target_tests"
            print_success "tests directory copied"
        fi
    fi
}
