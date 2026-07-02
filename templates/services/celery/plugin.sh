#!/bin/bash
# =============================================================================
# Template Plugin: celery
# This file is meant to be sourced by setup.sh, not executed directly.
# =============================================================================
# This plugin provides Celery task queue service including:
# - Celery Worker service via docker-compose
# - Celery Beat scheduler service via docker-compose
# - Redis as broker/backend (requires redis plugin)
# - CELERY_BROKER_URL and CELERY_RESULT_BACKEND environment variables
# - pip install celery[redis] in post.sh
#
# Prerequisites:
# - Python language plugin must be selected
# - Redis service plugin must be selected (and loaded before this plugin)
#
# =============================================================================

# Get the directory where this plugin is located
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# Required Functions
# =============================================================================

# Return plugin identifier
plugin_name() {
    echo "celery"
}

# Return plugin description
plugin_description() {
    echo "Celery task queue with Worker + Beat (requires Python + Redis)"
}

# =============================================================================
# Hook Functions
# =============================================================================

# Copy Celery docker-compose overlay and Dockerfile to target directory
plugin_copy() {
    local target_dir="$1"

    print_info "Copying Celery docker-compose overlay..."

    local source_compose="${PLUGIN_DIR}/docker-compose.celery.yml"
    local target_compose="${target_dir}/docker-compose.celery.yml"

    if [[ -f "$source_compose" ]]; then
        copy_with_confirm "$source_compose" "$target_compose"
        print_success "Celery docker-compose overlay copied"
    fi

    # Copy Celery Dockerfile
    local source_dockerfile="${PLUGIN_DIR}/docker/Dockerfile.celery"
    local target_dockerfile="${target_dir}/docker/Dockerfile.celery"

    if [[ -f "$source_dockerfile" ]]; then
        mkdir -p "${target_dir}/docker"
        copy_with_confirm "$source_dockerfile" "$target_dockerfile"
        print_success "Celery Dockerfile copied"
    fi
}

# Post-copy processing - merge docker-compose and configure environment
plugin_post_copy() {
    local target_dir="$1"

    # -------------------------------------------------------------------------
    # Merge docker-compose.yml (add Celery Worker and Beat services)
    # -------------------------------------------------------------------------
    local target_compose="${target_dir}/docker-compose.yml"
    local overlay_compose="${target_dir}/docker-compose.celery.yml"

    if [[ -f "$target_compose" ]] && [[ -f "$overlay_compose" ]]; then
        print_info "Merging Celery services into docker-compose.yml..."
        local temp_file="${target_compose}.tmp"

        merge_docker_compose_services "$target_compose" "$overlay_compose" "$temp_file"
        mv "$temp_file" "$target_compose"

        print_success "Celery services merged into docker-compose.yml"
    fi

    # Add Celery services to devcontainer.json runServices
    local target_devcontainer="${target_dir}/.devcontainer/devcontainer.json"

    if [[ -f "$target_devcontainer" ]]; then
        print_info "Adding Celery services to devcontainer.json runServices..."
        local temp_file="${target_devcontainer}.tmp"

        jq '.runServices += ["{{PROJECT_NAME}}-celery-worker", "{{PROJECT_NAME}}-celery-beat"]' \
            "$target_devcontainer" > "$temp_file"

        mv "$temp_file" "$target_devcontainer"
        print_success "Celery services added to devcontainer.json"
    fi

    # -------------------------------------------------------------------------
    # Add CELERY environment variables to app service (scoped to app service)
    # The app service is identified by "working_dir: /workspace"
    # -------------------------------------------------------------------------
    if [[ -f "$target_compose" ]]; then
        print_info "Adding Celery environment variables to app service..."
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
                print "      CELERY_BROKER_URL: redis://{{PROJECT_NAME}}-redis:6379/0"
                print "      CELERY_RESULT_BACKEND: redis://{{PROJECT_NAME}}-redis:6379/1"
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
                print "      CELERY_BROKER_URL: redis://{{PROJECT_NAME}}-redis:6379/0"
                print "      CELERY_RESULT_BACKEND: redis://{{PROJECT_NAME}}-redis:6379/1"
                inserted=1
            }
            in_app && /^    command:/ { in_app=0 }
            { print }
            ' "$target_compose" > "$temp_file"
        fi

        mv "$temp_file" "$target_compose"
        print_success "Celery environment variables added to app service"
    fi

    # -------------------------------------------------------------------------
    # Add Celery setup to post.sh
    # -------------------------------------------------------------------------
    local target_post_sh="${target_dir}/.devcontainer/scripts/post.sh"

    if [[ -f "$target_post_sh" ]]; then
        print_info "Adding Celery setup to post.sh..."

        cat >> "$target_post_sh" << 'POSTEOF'

# -----------------------------------------------------------------------------
# Celery Setup
# -----------------------------------------------------------------------------
if command -v pip &> /dev/null || command -v uv &> /dev/null; then
    echo "Installing Celery with Redis support..."
    if command -v uv &> /dev/null; then
        uv pip install "celery[redis]" 2>/dev/null || true
    else
        pip install "celery[redis]" 2>/dev/null || true
    fi
    echo "Celery installed."
    echo "  - Broker: redis://{{PROJECT_NAME}}-redis:6379/0"
    echo "  - Backend: redis://{{PROJECT_NAME}}-redis:6379/1"
    echo "  - Worker: celery -A {{PROJECT_NAME}} worker --loglevel=info"
    echo "  - Beat: celery -A {{PROJECT_NAME}} beat --loglevel=info"
fi
POSTEOF

        print_success "Celery setup added to post.sh"
    fi

    # Clean up the overlay file (it's been merged)
    if [[ -f "$overlay_compose" ]]; then
        rm -f "$overlay_compose"
        print_info "Cleaned up Celery overlay file"
    fi
}
