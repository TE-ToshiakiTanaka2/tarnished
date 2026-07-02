#!/bin/bash
# =============================================================================
# Template Plugin: go
# This file is meant to be sourced by setup.sh, not executed directly.
# =============================================================================
# This plugin provides Go development environment features including:
# - Go stable (latest) devcontainer feature
# - gofmt formatter (standard, included with the toolchain)
# - golangci-lint linter (installed in post.sh)
# - gotestsum test runner (installed in post.sh)
# - VS Code extensions for Go development
# - Claude Code hooks for automatic formatting/vetting
# - GitHub Actions workflow for quality checks (build, vet, fmt, lint, tests)
#
# Monorepo split (#263): .golangci.yml is per-module (plugin_post_copy_module);
# devcontainer + Claude + post.sh edits are shared at root
# (plugin_post_copy_shared). Go does not auto-scaffold go.mod or src/ — that
# remains the user's choice via `go mod init`. Mirrors the Rust precedent.
# =============================================================================

# Get the directory where this plugin is located
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GO_POSTSH_MARKER="# >>> go (toolchain) post-create >>>"

# =============================================================================
# Required Functions
# =============================================================================

# Return plugin identifier
plugin_name() {
    echo "go"
}

# Return plugin description
plugin_description() {
    echo "Go development environment with golangci-lint and gotestsum"
}

# =============================================================================
# Hook Functions
# =============================================================================

# Copy GitHub Actions workflow files
plugin_copy() {
    local target_dir="$1"

    print_info "Copying Go quality check workflow..."

    # Create .github/workflows directory
    mkdir -p "${target_dir}/.github/workflows"

    # Copy workflow file
    local workflow="${PLUGIN_DIR}/.github/workflows/go-quality-check.yml"
    if [[ -f "$workflow" ]]; then
        local target_file="${target_dir}/.github/workflows/go-quality-check.yml"

        if [[ -f "$target_file" ]]; then
            echo -n "  go-quality-check.yml already exists. Overwrite? (y/n) [n]: "
            if check_tty_available; then
                read -r overwrite < /dev/tty
            else
                overwrite="n"
            fi
            if [[ "$overwrite" != "y" ]]; then
                print_info "Skipping go-quality-check.yml"
                return 0
            fi
        fi

        # User has either confirmed overwrite or the target did not exist;
        # bypass copy_with_confirm's own prompt so the message UX above
        # remains the source of truth (#265).
        OVERWRITE_ALL=true copy_with_confirm "$workflow" "$target_file"
        print_success "Created go-quality-check.yml"
    fi
}

# Shared root post-copy work: devcontainer / claude / post.sh edits.
plugin_post_copy_shared() {
    local target_dir="$1"

    # Merge devcontainer.json features and extensions
    local target_devcontainer="${target_dir}/.devcontainer/devcontainer.json"
    local plugin_devcontainer="${PLUGIN_DIR}/.devcontainer/devcontainer.json"

    if [[ -f "$plugin_devcontainer" ]] && [[ -f "$target_devcontainer" ]]; then
        print_info "Merging Go devcontainer features..."
        local temp_file="${target_dir}/.devcontainer/devcontainer.json.tmp"

        merge_devcontainer_json "$target_devcontainer" "$plugin_devcontainer" "$temp_file"
        mv "$temp_file" "$target_devcontainer"

        print_success "Go devcontainer features merged"
    fi

    # Merge Claude settings hooks
    local target_settings="${target_dir}/.claude/settings.json"
    local plugin_settings="${PLUGIN_DIR}/.claude/settings.json"

    if [[ -f "$plugin_settings" ]] && [[ -f "$target_settings" ]]; then
        print_info "Merging Go Claude settings..."
        local temp_file="${target_dir}/.claude/settings.json.tmp"

        merge_claude_settings_hooks "$target_settings" "$plugin_settings" "$temp_file"
        mv "$temp_file" "$target_settings"

        print_success "Go Claude settings merged"
    fi

    # Copy Claude rules files
    local plugin_rules_dir="${PLUGIN_DIR}/.claude/rules"
    local target_rules_dir="${target_dir}/.claude/rules"

    if [[ -d "$plugin_rules_dir" ]]; then
        print_info "Copying Go Claude rules..."
        copy_dir_with_confirm "$plugin_rules_dir" "$target_rules_dir"
        print_success "Go Claude rules copied"
    fi

    # Append Go setup commands to post.sh. Always marker-guarded — Go is
    # new (no pre-#263 baseline to preserve), so block-level idempotency
    # applies uniformly in single and monorepo modes.
    local target_post_sh="${target_dir}/.devcontainer/scripts/post.sh"

    if [[ -f "$target_post_sh" ]]; then
        if grep -qF "$GO_POSTSH_MARKER" "$target_post_sh"; then
            print_info "Go post.sh block already present, skipping"
            return
        fi

        print_info "Adding Go setup to post.sh..."

        cat >> "$target_post_sh" << EOF

${GO_POSTSH_MARKER}
# -----------------------------------------------------------------------------
# Go Development Tools Setup
# -----------------------------------------------------------------------------
if command -v go &> /dev/null; then
    echo "Installing Go development tools..."

    # Install gotestsum for readable test output
    if ! command -v gotestsum &> /dev/null; then
        echo "  - Installing gotestsum..."
        go install gotest.tools/gotestsum@latest
    fi

    # Install golangci-lint
    if ! command -v golangci-lint &> /dev/null; then
        echo "  - Installing golangci-lint..."
        go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
    fi

    echo "Go development tools installed."
fi
# <<< go (toolchain) post-create <<<
EOF

        print_success "Go setup added to post.sh"
    fi
}

# Module-scoped post-copy work: per-module lint config.
plugin_post_copy_module() {
    local target_dir="$1"
    local _module_name="$2"   # currently unused; kept for contract symmetry

    local tool_configs=(".golangci.yml")

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
