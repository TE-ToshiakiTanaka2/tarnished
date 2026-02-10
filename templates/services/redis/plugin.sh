#!/bin/bash
# =============================================================================
# Template Plugin: redis
# This file is meant to be sourced by setup.sh, not executed directly.
# =============================================================================
# This plugin provides Redis cache/broker service including:
# - Redis 7 service via docker-compose
# - redis-cli client in devcontainer
# - Health check configuration
# - Data persistence with named volume
# - REDIS_URL environment variable
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
    echo "Redis 7 cache/broker service with redis-cli client"
}

# =============================================================================
# Hook Functions
# =============================================================================

# Copy Redis docker-compose overlay to target directory
plugin_copy() {
    local target_dir="$1"

    print_info "Copying Redis docker-compose overlay..."

    local source_compose="${PLUGIN_DIR}/docker-compose.redis.yml"
    local target_compose="${target_dir}/docker-compose.redis.yml"

    if [[ -f "$source_compose" ]]; then
        copy_with_confirm "$source_compose" "$target_compose"
        print_success "Redis docker-compose overlay copied"
    fi
}

# Post-copy processing - merge docker-compose, devcontainer, and configure environment
plugin_post_copy() {
    local target_dir="$1"

    # -------------------------------------------------------------------------
    # Merge docker-compose.yml (add Redis service and volume)
    # -------------------------------------------------------------------------
    local target_compose="${target_dir}/docker-compose.yml"
    local overlay_compose="${target_dir}/docker-compose.redis.yml"

    if [[ -f "$target_compose" ]] && [[ -f "$overlay_compose" ]]; then
        print_info "Merging Redis service into docker-compose.yml..."
        local temp_file="${target_compose}.tmp"

        merge_docker_compose_services "$target_compose" "$overlay_compose" "$temp_file"
        mv "$temp_file" "$target_compose"

        print_success "Redis service merged into docker-compose.yml"
    fi

    # -------------------------------------------------------------------------
    # Add depends_on to the main app service (scoped to app service only)
    # The app service is identified by "working_dir: /workspace"
    # -------------------------------------------------------------------------
    if [[ -f "$target_compose" ]]; then
        print_info "Adding depends_on for Redis to app service..."
        local temp_file="${target_compose}.tmp"

        # Extract app service section to check for existing depends_on
        local app_section
        app_section=$(awk '/working_dir: \/workspace/,/^    command:/' "$target_compose")

        if echo "$app_section" | grep -q "^    depends_on:"; then
            # Add Redis to existing depends_on block within app service
            awk '
            /working_dir: \/workspace/ { in_app=1 }
            in_app && /^    depends_on:/ && !done {
                print
                print "      {{PROJECT_NAME}}-redis:"
                print "        condition: service_healthy"
                done=1
                next
            }
            in_app && /^    command:/ { in_app=0 }
            { print }
            ' "$target_compose" > "$temp_file"
        else
            # Insert new depends_on block after working_dir
            awk '
            /working_dir: \/workspace/ && !inserted {
                print
                print "    depends_on:"
                print "      {{PROJECT_NAME}}-redis:"
                print "        condition: service_healthy"
                inserted=1
                next
            }
            { print }
            ' "$target_compose" > "$temp_file"
        fi

        mv "$temp_file" "$target_compose"
        print_success "depends_on added for Redis"
    fi

    # Add Redis service to devcontainer.json runServices
    local target_devcontainer="${target_dir}/.devcontainer/devcontainer.json"

    if [[ -f "$target_devcontainer" ]]; then
        print_info "Adding Redis service to devcontainer.json runServices..."
        local temp_file="${target_devcontainer}.tmp"

        jq '.runServices += ["{{PROJECT_NAME}}-redis"]' \
            "$target_devcontainer" > "$temp_file"

        mv "$temp_file" "$target_devcontainer"
        print_success "Redis service added to devcontainer.json"
    fi

    # -------------------------------------------------------------------------
    # Merge devcontainer.json (add redis-cli feature)
    # -------------------------------------------------------------------------
    local plugin_devcontainer="${PLUGIN_DIR}/.devcontainer/devcontainer.json"

    if [[ -f "$plugin_devcontainer" ]] && [[ -f "$target_devcontainer" ]]; then
        print_info "Merging Redis devcontainer features..."
        local temp_file="${target_devcontainer}.tmp"

        merge_devcontainer_json "$target_devcontainer" "$plugin_devcontainer" "$temp_file"
        mv "$temp_file" "$target_devcontainer"

        print_success "Redis devcontainer features merged"
    fi

    # -------------------------------------------------------------------------
    # Add REDIS_URL to docker-compose app service environment (scoped to app service)
    # -------------------------------------------------------------------------
    if [[ -f "$target_compose" ]]; then
        print_info "Adding REDIS_URL to app service..."
        local temp_file="${target_compose}.tmp"

        # Extract app service section to check for existing environment
        local app_section
        app_section=$(awk '/working_dir: \/workspace/,/^    command:/' "$target_compose")

        if echo "$app_section" | grep -q "^    environment:"; then
            # Add to existing environment block within app service
            awk '
            /working_dir: \/workspace/ { in_app=1 }
            in_app && /^    environment:/ && !done {
                print
                print "      REDIS_URL: redis://{{PROJECT_NAME}}-redis:6379/0"
                done=1
                next
            }
            in_app && /^    command:/ { in_app=0 }
            { print }
            ' "$target_compose" > "$temp_file"
        else
            # Insert new environment block before "# Keep" comment or command
            awk '
            /working_dir: \/workspace/ { in_app=1 }
            in_app && (/^    # Keep/ || /^    command:/) && !inserted {
                print "    environment:"
                print "      REDIS_URL: redis://{{PROJECT_NAME}}-redis:6379/0"
                inserted=1
            }
            in_app && /^    command:/ { in_app=0 }
            { print }
            ' "$target_compose" > "$temp_file"
        fi

        mv "$temp_file" "$target_compose"
        print_success "REDIS_URL added to app service"
    fi

    # -------------------------------------------------------------------------
    # Add Redis setup to post.sh
    # -------------------------------------------------------------------------
    local target_post_sh="${target_dir}/.devcontainer/scripts/post.sh"

    if [[ -f "$target_post_sh" ]]; then
        print_info "Adding Redis setup to post.sh..."

        cat >> "$target_post_sh" << 'POSTEOF'

# -----------------------------------------------------------------------------
# Redis Client Setup
# -----------------------------------------------------------------------------
if command -v redis-cli &> /dev/null; then
    echo "Redis client is available."
    echo "  - redis-cli version: $(redis-cli --version)"
    echo "  - Connection: redis-cli -h {{PROJECT_NAME}}-redis"
    echo "  - REDIS_URL: redis://{{PROJECT_NAME}}-redis:6379/0"
fi
POSTEOF

        print_success "Redis setup added to post.sh"
    fi

    # Clean up the overlay file (it's been merged)
    if [[ -f "$overlay_compose" ]]; then
        rm -f "$overlay_compose"
        print_info "Cleaned up Redis overlay file"
    fi
}
