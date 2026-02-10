#!/bin/bash
# =============================================================================
# Template Plugin: postgresql
# This file is meant to be sourced by setup.sh, not executed directly.
# =============================================================================
# This plugin provides PostgreSQL database service including:
# - PostgreSQL 16 service via docker-compose
# - psql client in devcontainer
# - Health check configuration
# - Data persistence with named volume
# - DATABASE_URL environment variable
#
# =============================================================================

# Get the directory where this plugin is located
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# Required Functions
# =============================================================================

# Return plugin identifier
plugin_name() {
    echo "postgresql"
}

# Return plugin description
plugin_description() {
    echo "PostgreSQL 16 database service with psql client"
}

# =============================================================================
# Hook Functions
# =============================================================================

# Copy PostgreSQL docker-compose overlay to target directory
plugin_copy() {
    local target_dir="$1"

    print_info "Copying PostgreSQL docker-compose overlay..."

    local source_compose="${PLUGIN_DIR}/docker-compose.postgresql.yml"
    local target_compose="${target_dir}/docker-compose.postgresql.yml"

    if [[ -f "$source_compose" ]]; then
        copy_with_confirm "$source_compose" "$target_compose"
        print_success "PostgreSQL docker-compose overlay copied"
    fi
}

# Post-copy processing - merge docker-compose, devcontainer, and configure environment
plugin_post_copy() {
    local target_dir="$1"

    # -------------------------------------------------------------------------
    # Merge docker-compose.yml (add PostgreSQL service and volume)
    # -------------------------------------------------------------------------
    local target_compose="${target_dir}/docker-compose.yml"
    local overlay_compose="${target_dir}/docker-compose.postgresql.yml"

    if [[ -f "$target_compose" ]] && [[ -f "$overlay_compose" ]]; then
        print_info "Merging PostgreSQL service into docker-compose.yml..."
        local temp_file="${target_compose}.tmp"

        merge_docker_compose_services "$target_compose" "$overlay_compose" "$temp_file"
        mv "$temp_file" "$target_compose"

        print_success "PostgreSQL service merged into docker-compose.yml"
    fi

    # Add depends_on to the main app service
    if [[ -f "$target_compose" ]]; then
        print_info "Adding depends_on for PostgreSQL to app service..."

        local temp_file="${target_compose}.tmp"

        # Insert depends_on block after the main service's working_dir line
        awk '
        /working_dir: \/workspace/ && !inserted {
            print
            print "    depends_on:"
            print "      {{PROJECT_NAME}}-db:"
            print "        condition: service_healthy"
            inserted=1
            next
        }
        { print }
        ' "$target_compose" > "$temp_file"

        mv "$temp_file" "$target_compose"
        print_success "depends_on added to app service"
    fi

    # Add PostgreSQL DB service to devcontainer.json runServices
    local target_devcontainer="${target_dir}/.devcontainer/devcontainer.json"

    if [[ -f "$target_devcontainer" ]]; then
        print_info "Adding PostgreSQL DB service to devcontainer.json runServices..."
        local temp_file="${target_devcontainer}.tmp"

        jq '.runServices += ["{{PROJECT_NAME}}-db"]' \
            "$target_devcontainer" > "$temp_file"

        mv "$temp_file" "$target_devcontainer"
        print_success "PostgreSQL DB service added to devcontainer.json"
    fi

    # -------------------------------------------------------------------------
    # Merge devcontainer.json (add psql client feature and VS Code extension)
    # -------------------------------------------------------------------------
    local plugin_devcontainer="${PLUGIN_DIR}/.devcontainer/devcontainer.json"

    if [[ -f "$plugin_devcontainer" ]] && [[ -f "$target_devcontainer" ]]; then
        print_info "Merging PostgreSQL devcontainer features..."
        local temp_file="${target_devcontainer}.tmp"

        merge_devcontainer_json "$target_devcontainer" "$plugin_devcontainer" "$temp_file"
        mv "$temp_file" "$target_devcontainer"

        print_success "PostgreSQL devcontainer features merged"
    fi

    # -------------------------------------------------------------------------
    # Add DATABASE_URL to docker-compose app service environment
    # -------------------------------------------------------------------------
    if [[ -f "$target_compose" ]]; then
        print_info "Adding DATABASE_URL to app service..."

        local temp_file="${target_compose}.tmp"

        # Add environment section with DATABASE_URL after depends_on block
        awk '
        /condition: service_healthy/ && !env_inserted {
            print
            print "    environment:"
            print "      DATABASE_URL: postgresql://postgres:postgres@{{PROJECT_NAME}}-db:5432/{{PROJECT_NAME}}"
            env_inserted=1
            next
        }
        { print }
        ' "$target_compose" > "$temp_file"

        mv "$temp_file" "$target_compose"
        print_success "DATABASE_URL added to app service"
    fi

    # -------------------------------------------------------------------------
    # Add PostgreSQL setup to post.sh
    # -------------------------------------------------------------------------
    local target_post_sh="${target_dir}/.devcontainer/scripts/post.sh"

    if [[ -f "$target_post_sh" ]]; then
        print_info "Adding PostgreSQL setup to post.sh..."

        cat >> "$target_post_sh" << 'POSTEOF'

# -----------------------------------------------------------------------------
# PostgreSQL Client Setup
# -----------------------------------------------------------------------------
if command -v psql &> /dev/null; then
    echo "PostgreSQL client is available."
    echo "  - psql version: $(psql --version)"
    echo "  - Connection: psql -h {{PROJECT_NAME}}-db -U postgres -d {{PROJECT_NAME}}"
    echo "  - DATABASE_URL: postgresql://postgres:postgres@{{PROJECT_NAME}}-db:5432/{{PROJECT_NAME}}"
fi
POSTEOF

        print_success "PostgreSQL setup added to post.sh"
    fi

    # Clean up the overlay file (it's been merged)
    if [[ -f "$overlay_compose" ]]; then
        rm -f "$overlay_compose"
        print_info "Cleaned up PostgreSQL overlay file"
    fi
}
