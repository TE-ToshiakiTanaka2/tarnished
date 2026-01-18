#!/bin/bash
# =============================================================================
# Template Plugin: playwright
# This file is meant to be sourced by setup.sh, not executed directly.
# =============================================================================
# This plugin provides Playwright E2E testing support including:
# - Playwright devcontainer feature
# - VS Code Playwright extension
# - Browser dependencies
#
# =============================================================================

# Get the directory where this plugin is located
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# Required Functions
# =============================================================================

# Return plugin identifier
plugin_name() {
    echo "playwright"
}

# Return plugin description
plugin_description() {
    echo "Playwright E2E testing support"
}

# =============================================================================
# Hook Functions
# =============================================================================

# Post-copy processing - merge devcontainer.json for Playwright
plugin_post_copy() {
    local target_dir="$1"

    # Copy playwright.config.mjs if it exists
    local plugin_config="${PLUGIN_DIR}/playwright.config.mjs"
    if [[ -f "$plugin_config" ]]; then
        print_info "Copying Playwright configuration file..."
        copy_with_confirm "$plugin_config" "${target_dir}/playwright.config.mjs"
    fi

    # Create tests/e2e directory for Playwright tests
    if [[ ! -d "${target_dir}/tests/e2e" ]]; then
        mkdir -p "${target_dir}/tests/e2e"
        print_info "Created tests/e2e directory for Playwright tests"
    fi

    # Merge devcontainer.json features and extensions
    local target_devcontainer="${target_dir}/.devcontainer/devcontainer.json"
    local plugin_devcontainer="${PLUGIN_DIR}/.devcontainer/devcontainer.json"

    if [[ -f "$plugin_devcontainer" ]] && [[ -f "$target_devcontainer" ]]; then
        print_info "Merging Playwright devcontainer features..."
        local temp_file="${target_dir}/.devcontainer/devcontainer.json.tmp"

        # Merge devcontainer.json with special handling for features and extensions
        merge_devcontainer_json "$target_devcontainer" "$plugin_devcontainer" "$temp_file"
        mv "$temp_file" "$target_devcontainer"

        print_success "Playwright devcontainer features merged"
    fi

    # Append Playwright setup commands to post.sh
    local target_post_sh="${target_dir}/.devcontainer/scripts/post.sh"

    if [[ -f "$target_post_sh" ]]; then
        print_info "Adding Playwright setup to post.sh..."

        cat >> "$target_post_sh" << 'EOF'

# -----------------------------------------------------------------------------
# Playwright Browser Setup
# -----------------------------------------------------------------------------
if command -v npx &> /dev/null; then
    echo "Installing Playwright browsers..."

    # Install Chromium browser with dependencies
    # Use CI=1 and npx --yes to prevent interactive prompts
    # Redirect stdin from /dev/null for additional safety
    CI=1 npx --yes playwright install --with-deps chromium < /dev/null || true

    echo "Playwright browsers installed."
fi
EOF

        print_success "Playwright setup added to post.sh"
    fi
}
