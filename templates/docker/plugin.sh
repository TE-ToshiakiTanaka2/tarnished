#!/bin/bash
# =============================================================================
# Template Plugin: docker
# This file is meant to be sourced by setup.sh, not executed directly.
# =============================================================================
# This plugin provides Docker-in-Docker (DinD) support including:
# - Docker-in-Docker devcontainer feature
# - Docker Compose v2
# - VS Code Docker extension
#
# =============================================================================

# Get the directory where this plugin is located
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# Required Functions
# =============================================================================

# Return plugin identifier
plugin_name() {
    echo "docker"
}

# Return plugin description
plugin_description() {
    echo "Docker-in-Docker (DinD) support"
}

# =============================================================================
# Hook Functions
# =============================================================================

# Post-copy processing - merge devcontainer.json for Docker-in-Docker
plugin_post_copy() {
    local target_dir="$1"

    # Merge devcontainer.json features and extensions
    local target_devcontainer="${target_dir}/.devcontainer/devcontainer.json"
    local plugin_devcontainer="${PLUGIN_DIR}/.devcontainer/devcontainer.json"

    if [[ -f "$plugin_devcontainer" ]] && [[ -f "$target_devcontainer" ]]; then
        print_info "Merging Docker-in-Docker devcontainer features..."
        local temp_file="${target_dir}/.devcontainer/devcontainer.json.tmp"

        # Merge devcontainer.json with special handling for features and extensions
        merge_devcontainer_json "$target_devcontainer" "$plugin_devcontainer" "$temp_file"
        mv "$temp_file" "$target_devcontainer"

        print_success "Docker-in-Docker devcontainer features merged"
    fi
}
