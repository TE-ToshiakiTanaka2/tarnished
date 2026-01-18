#!/bin/bash
# =============================================================================
# Template Plugin: redis
# This file is meant to be sourced by setup.sh, not executed directly.
# =============================================================================
# This plugin provides Redis cache/session support including:
# - Redis 7 Docker service
# - Data persistence with named volume
# - Password authentication
# - Init scripts support
#
# =============================================================================

# Get the directory where this plugin is located
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# Required Functions
# =============================================================================

# Return plugin identifier
plugin_name() {
    echo "redis"
}

# Return plugin description
plugin_description() {
    echo "Redis 7 cache/session support"
}

# =============================================================================
# Hook Functions
# =============================================================================

# Post-copy processing - merge configurations for Redis
plugin_post_copy() {
    local target_dir="$1"

    # Merge docker-compose.yml with Redis service
    local target_compose="${target_dir}/docker-compose.yml"
    local plugin_compose="${PLUGIN_DIR}/docker/docker-compose.redis.yml"

    if [[ -f "$plugin_compose" ]] && [[ -f "$target_compose" ]]; then
        print_info "Merging Redis docker-compose configuration..."
        local temp_file="${target_dir}/docker-compose.yml.tmp"

        merge_docker_compose_services "$target_compose" "$plugin_compose" "$temp_file"
        mv "$temp_file" "$target_compose"

        print_success "Redis docker-compose configuration merged"
    fi

    # Merge devcontainer.json features and extensions
    local target_devcontainer="${target_dir}/.devcontainer/devcontainer.json"
    local plugin_devcontainer="${PLUGIN_DIR}/.devcontainer/devcontainer.json"

    if [[ -f "$plugin_devcontainer" ]] && [[ -f "$target_devcontainer" ]]; then
        print_info "Merging Redis devcontainer features..."
        local temp_file="${target_dir}/.devcontainer/devcontainer.json.tmp"

        merge_devcontainer_json "$target_devcontainer" "$plugin_devcontainer" "$temp_file"
        mv "$temp_file" "$target_devcontainer"

        print_success "Redis devcontainer features merged"
    fi

    # Copy .env.example if .env doesn't exist
    local env_example="${PLUGIN_DIR}/.env.example"
    local target_env="${target_dir}/.env"
    local target_env_example="${target_dir}/.env.example"

    if [[ -f "$env_example" ]]; then
        # Always copy .env.example as reference
        if [[ -f "$target_env_example" ]]; then
            # Append Redis variables to existing .env.example
            print_info "Appending Redis variables to .env.example..."
            echo "" >> "$target_env_example"
            cat "$env_example" >> "$target_env_example"
        else
            cp "$env_example" "$target_env_example"
        fi

        # Create .env from example if it doesn't exist
        if [[ ! -f "$target_env" ]]; then
            print_info "Creating .env from .env.example..."
            cp "$target_env_example" "$target_env"
            print_success ".env file created"
        else
            # Append Redis variables to existing .env if not present
            if ! grep -q "REDIS_PASSWORD" "$target_env" 2>/dev/null; then
                print_info "Appending Redis variables to .env..."
                echo "" >> "$target_env"
                cat "$env_example" >> "$target_env"
            fi
        fi
    fi

    # Copy init directory for initialization scripts
    local plugin_init="${PLUGIN_DIR}/init"
    local target_init="${target_dir}/init"

    if [[ -d "$plugin_init" ]]; then
        print_info "Copying init directory for Redis initialization scripts..."
        copy_dir_with_confirm "$plugin_init" "$target_init"
    fi

    # Update .gitignore to include .env
    local gitignore="${target_dir}/.gitignore"
    if ! grep -q "^\.env$" "$gitignore" 2>/dev/null; then
        print_info "Adding .env to .gitignore..."
        {
            echo ""
            echo "# Environment variables (contains secrets)"
            echo ".env"
        } >> "$gitignore"
    fi
}
