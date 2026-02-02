#!/bin/bash
# =============================================================================
# Template Plugin: rust
# This file is meant to be sourced by setup.sh, not executed directly.
# =============================================================================
# This plugin provides Rust development environment features including:
# - Rust stable (latest) devcontainer feature
# - Cargo package manager with cargo-watch and cargo-edit
# - VS Code extensions for Rust development
# - rustfmt formatter configuration
# - clippy linter configuration
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
    echo "rust"
}

# Return plugin description
plugin_description() {
    echo "Rust development environment with Cargo"
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
        print_info "Merging Rust devcontainer features..."
        local temp_file="${target_dir}/.devcontainer/devcontainer.json.tmp"

        # Merge devcontainer.json with special handling for features and extensions
        merge_devcontainer_json "$target_devcontainer" "$plugin_devcontainer" "$temp_file"
        mv "$temp_file" "$target_devcontainer"

        print_success "Rust devcontainer features merged"
    fi

    # Merge Claude settings hooks
    local target_settings="${target_dir}/.claude/settings.json"
    local plugin_settings="${PLUGIN_DIR}/.claude/settings.json"

    if [[ -f "$plugin_settings" ]] && [[ -f "$target_settings" ]]; then
        print_info "Merging Rust Claude settings..."
        local temp_file="${target_dir}/.claude/settings.json.tmp"

        # Merge settings with hook array concatenation
        merge_claude_settings_hooks "$target_settings" "$plugin_settings" "$temp_file"
        mv "$temp_file" "$target_settings"

        print_success "Rust Claude settings merged"
    fi

    # Copy tool configuration files
    local tool_configs=("rustfmt.toml" "clippy.toml")

    for config_file in "${tool_configs[@]}"; do
        local source_config="${PLUGIN_DIR}/${config_file}"
        local target_config="${target_dir}/${config_file}"

        if [[ -f "$source_config" ]]; then
            print_info "Copying ${config_file}..."
            copy_with_confirm "$source_config" "$target_config"
        fi
    done

    # Append Rust setup commands to post.sh
    local target_post_sh="${target_dir}/.devcontainer/scripts/post.sh"

    if [[ -f "$target_post_sh" ]]; then
        print_info "Adding Rust setup to post.sh..."

        cat >> "$target_post_sh" << 'EOF'

# -----------------------------------------------------------------------------
# Rust Development Tools Setup
# -----------------------------------------------------------------------------
if command -v cargo &> /dev/null; then
    echo "Installing Rust development tools..."

    # Install cargo-watch for auto-rebuild on file changes
    if ! command -v cargo-watch &> /dev/null; then
        echo "  - Installing cargo-watch..."
        cargo install --locked cargo-watch
    fi

    # Install cargo-edit for easy dependency management (cargo add/rm)
    if ! cargo add --version &> /dev/null 2>&1; then
        echo "  - Installing cargo-edit..."
        cargo install --locked cargo-edit
    fi

    echo "Rust development tools installed."
fi
EOF

        print_success "Rust setup added to post.sh"
    fi
}
