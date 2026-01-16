#!/bin/bash
# =============================================================================
# Template Plugin: neo4j
# This file is meant to be sourced by setup.sh, not executed directly.
# =============================================================================
# This plugin provides Neo4j graph database support including:
# - Neo4j Community Docker service
# - APOC plugin for utility procedures
# - Data persistence with named volume
# - VS Code Cypher extension
# - Init scripts support (import directory)
#
# =============================================================================

# Get the directory where this plugin is located
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# Required Functions
# =============================================================================

# Return plugin identifier
plugin_name() {
    echo "neo4j"
}

# Return plugin description
plugin_description() {
    echo "Neo4j graph database support for GraphRAG"
}

# =============================================================================
# Hook Functions
# =============================================================================

# Post-copy processing - merge configurations for Neo4j
plugin_post_copy() {
    local target_dir="$1"

    # Merge docker-compose.yml with Neo4j service
    local target_compose="${target_dir}/docker-compose.yml"
    local plugin_compose="${PLUGIN_DIR}/docker/docker-compose.neo4j.yml"

    if [[ -f "$plugin_compose" ]] && [[ -f "$target_compose" ]]; then
        print_info "Merging Neo4j docker-compose configuration..."
        local temp_file="${target_dir}/docker-compose.yml.tmp"

        merge_docker_compose_services "$target_compose" "$plugin_compose" "$temp_file"
        mv "$temp_file" "$target_compose"

        print_success "Neo4j docker-compose configuration merged"
    fi

    # Merge devcontainer.json features and extensions
    local target_devcontainer="${target_dir}/.devcontainer/devcontainer.json"
    local plugin_devcontainer="${PLUGIN_DIR}/.devcontainer/devcontainer.json"

    if [[ -f "$plugin_devcontainer" ]] && [[ -f "$target_devcontainer" ]]; then
        print_info "Merging Neo4j devcontainer features..."
        local temp_file="${target_dir}/.devcontainer/devcontainer.json.tmp"

        merge_devcontainer_json "$target_devcontainer" "$plugin_devcontainer" "$temp_file"
        mv "$temp_file" "$target_devcontainer"

        print_success "Neo4j devcontainer features merged"
    fi

    # Copy .env.example if .env doesn't exist
    local env_example="${PLUGIN_DIR}/.env.example"
    local target_env="${target_dir}/.env"
    local target_env_example="${target_dir}/.env.example"

    if [[ -f "$env_example" ]]; then
        # Always copy .env.example as reference
        if [[ -f "$target_env_example" ]]; then
            # Append Neo4j variables to existing .env.example
            print_info "Appending Neo4j variables to .env.example..."
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
            # Append Neo4j variables to existing .env if not present
            if ! grep -q "NEO4J_USER" "$target_env" 2>/dev/null; then
                print_info "Appending Neo4j variables to .env..."
                echo "" >> "$target_env"
                cat "$env_example" >> "$target_env"
            fi
        fi
    fi

    # Copy init directory for import scripts
    local plugin_init="${PLUGIN_DIR}/init"
    local target_init="${target_dir}/init"

    if [[ -d "$plugin_init" ]]; then
        if [[ ! -d "$target_init" ]]; then
            print_info "Creating init directory for Neo4j import scripts..."
            cp -r "$plugin_init" "$target_init"
            print_success "Init directory created"
        fi
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
