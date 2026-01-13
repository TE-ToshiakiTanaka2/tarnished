#!/bin/bash
# =============================================================================
# Template Plugin: core
# This file is meant to be sourced by setup.sh, not executed directly.
# =============================================================================
# This plugin provides the base devcontainer infrastructure including:
# - Docker configuration (Dockerfile.dev, docker-compose.yml)
# - Devcontainer configuration (devcontainer.json, post.sh)
# - Base Claude Code settings
#
# =============================================================================

# Get the directory where this plugin is located
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# Required Functions
# =============================================================================

# Return plugin identifier
plugin_name() {
    echo "core"
}

# Return plugin description
plugin_description() {
    echo "Base devcontainer infrastructure with Docker support"
}

# =============================================================================
# Hook Functions
# =============================================================================

# Copy core template files to target directory
plugin_copy() {
    local target_dir="$1"

    print_info "Copying core template files..."

    # Copy .devcontainer directory
    if [[ -d "${PLUGIN_DIR}/.devcontainer" ]]; then
        cp -r "${PLUGIN_DIR}/.devcontainer" "${target_dir}/"
    fi

    # Copy docker directory
    if [[ -d "${PLUGIN_DIR}/docker" ]]; then
        cp -r "${PLUGIN_DIR}/docker" "${target_dir}/"
    fi

    # Copy .claude directory (base settings)
    if [[ -d "${PLUGIN_DIR}/.claude" ]]; then
        cp -r "${PLUGIN_DIR}/.claude" "${target_dir}/"
    fi

    # Copy docker-compose.yml
    if [[ -f "${PLUGIN_DIR}/docker-compose.yml" ]]; then
        cp "${PLUGIN_DIR}/docker-compose.yml" "${target_dir}/"
    fi

    print_success "Core template files copied"
}

# Post-copy processing
plugin_post_copy() {
    local target_dir="$1"

    # Make post.sh executable
    if [[ -f "${target_dir}/.devcontainer/scripts/post.sh" ]]; then
        chmod +x "${target_dir}/.devcontainer/scripts/post.sh"
        print_success "Made post.sh executable"
    fi
}
