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
# - GitHub Actions workflow for quality checks (type check, clippy, fmt, tests)
#
# Monorepo split (#263): rustfmt.toml + clippy.toml are per-module
# (plugin_post_copy_module); devcontainer + Claude + post.sh edits are
# shared at root (plugin_post_copy_shared). Rust does not auto-scaffold
# Cargo.toml or src/ — that remains the user's choice via `cargo init`.
# =============================================================================

# Get the directory where this plugin is located
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RUST_POSTSH_MARKER="# >>> rust (cargo) post-create >>>"

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

# Copy GitHub Actions workflow files
plugin_copy() {
    local target_dir="$1"

    print_info "Copying Rust quality check workflow..."

    # Create .github/workflows directory
    mkdir -p "${target_dir}/.github/workflows"

    # Copy workflow file
    local workflow="${PLUGIN_DIR}/.github/workflows/rust-quality-check.yml"
    if [[ -f "$workflow" ]]; then
        local target_file="${target_dir}/.github/workflows/rust-quality-check.yml"

        if [[ -f "$target_file" ]]; then
            echo -n "  rust-quality-check.yml already exists. Overwrite? (y/n) [n]: "
            if check_tty_available; then
                read -r overwrite < /dev/tty
            else
                overwrite="n"
            fi
            if [[ "$overwrite" != "y" ]]; then
                print_info "Skipping rust-quality-check.yml"
                return 0
            fi
        fi

        cp "$workflow" "$target_file"
        print_success "Created rust-quality-check.yml"
    fi
}

# Shared root post-copy work: devcontainer / claude / post.sh edits.
plugin_post_copy_shared() {
    local target_dir="$1"

    # Merge devcontainer.json features and extensions
    local target_devcontainer="${target_dir}/.devcontainer/devcontainer.json"
    local plugin_devcontainer="${PLUGIN_DIR}/.devcontainer/devcontainer.json"

    if [[ -f "$plugin_devcontainer" ]] && [[ -f "$target_devcontainer" ]]; then
        print_info "Merging Rust devcontainer features..."
        local temp_file="${target_dir}/.devcontainer/devcontainer.json.tmp"

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

        merge_claude_settings_hooks "$target_settings" "$plugin_settings" "$temp_file"
        mv "$temp_file" "$target_settings"

        print_success "Rust Claude settings merged"
    fi

    # Copy Claude rules files
    local plugin_rules_dir="${PLUGIN_DIR}/.claude/rules"
    local target_rules_dir="${target_dir}/.claude/rules"

    if [[ -d "$plugin_rules_dir" ]]; then
        print_info "Copying Rust Claude rules..."
        copy_dir_with_confirm "$plugin_rules_dir" "$target_rules_dir"
        print_success "Rust Claude rules copied"
    fi

    # Append Rust setup commands to post.sh. Markers + idempotency check
    # only in monorepo / add-module mode (NFR-1 keeps single-mode bytes).
    local target_post_sh="${target_dir}/.devcontainer/scripts/post.sh"

    if [[ -f "$target_post_sh" ]]; then
        local use_marker=false
        if [[ "${MONOREPO_MODE:-false}" == true ]] || [[ "${IS_ADD_MODULE_MODE:-false}" == true ]]; then
            use_marker=true
            if grep -qF "$RUST_POSTSH_MARKER" "$target_post_sh"; then
                print_info "Rust post.sh block already present, skipping"
                return
            fi
        fi

        print_info "Adding Rust setup to post.sh..."

        if [[ "$use_marker" == true ]]; then
            cat >> "$target_post_sh" << EOF

${RUST_POSTSH_MARKER}
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
# <<< rust (cargo) post-create <<<
EOF
        else
            # Pre-#263 single-mode block (no markers).
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
        fi

        print_success "Rust setup added to post.sh"
    fi
}

# Module-scoped post-copy work: per-module lint configs.
plugin_post_copy_module() {
    local target_dir="$1"
    local _module_name="$2"   # currently unused; kept for contract symmetry

    local tool_configs=("rustfmt.toml" "clippy.toml")

    for config_file in "${tool_configs[@]}"; do
        local source_config="${PLUGIN_DIR}/${config_file}"
        local target_config="${target_dir}/${config_file}"

        if [[ -f "$source_config" ]]; then
            print_info "Copying ${config_file} to ${target_dir}..."
            copy_with_confirm "$source_config" "$target_config"
        fi
    done
}

# Backward-compat shim.
plugin_post_copy() {
    local target_dir="$1"
    plugin_post_copy_shared "$target_dir"
    plugin_post_copy_module "$target_dir" "${PROJECT_NAME}"
}
