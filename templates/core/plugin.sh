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
# In monorepo mode (#263) plugin_post_copy additionally seeds (or
# extends) modules.json from the registered MODULES array and writes
# per-module CLAUDE.md files from module.CLAUDE.md.template.
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
        copy_dir_with_confirm "${PLUGIN_DIR}/.devcontainer" "${target_dir}/.devcontainer"
    fi

    # Copy docker directory
    if [[ -d "${PLUGIN_DIR}/docker" ]]; then
        copy_dir_with_confirm "${PLUGIN_DIR}/docker" "${target_dir}/docker"
    fi

    # Copy .claude directory (base settings)
    if [[ -d "${PLUGIN_DIR}/.claude" ]]; then
        copy_dir_with_confirm "${PLUGIN_DIR}/.claude" "${target_dir}/.claude"
    fi

    # Copy docker-compose.yml
    if [[ -f "${PLUGIN_DIR}/docker-compose.yml" ]]; then
        copy_with_confirm "${PLUGIN_DIR}/docker-compose.yml" "${target_dir}/docker-compose.yml"
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

# Monorepo registry helpers (#263). Invoked directly by setup.sh after the
# orchestrator finishes, NOT through the plugin_post_copy hook — this keeps
# the registry-maintenance logic decoupled from the plugin pipeline so
# add-module mode can skip the entire core plugin without losing the
# modules.json update.

# Seed modules.json from the template if missing, then add or replace each
# MODULES entry in turn. Replace path is taken when the module already
# exists — by which point setup.sh::check_add_module_conflict has already
# prompted/honored the overwrite decision (FR-9).
core_seed_modules_json() {
    local target_dir="$1"

    if [[ ! -f "${target_dir}/modules.json" ]]; then
        local template="${PLUGIN_DIR}/modules.json.template"
        if [[ -f "$template" ]]; then
            cp "$template" "${target_dir}/modules.json"
            print_success "Seeded modules.json"
        else
            # Fallback: minimal inline template if the file is missing.
            echo '{"version": 1, "modules": []}' > "${target_dir}/modules.json"
            print_warning "modules.json.template missing; wrote inline default"
        fi
    fi

    local entry name lang
    for entry in "${MODULES[@]}"; do
        name="${entry%%:*}"
        lang="${entry#*:}"

        if find_module_by_name "$target_dir" "$name"; then
            replace_module_entry "$target_dir" "$name" "$lang" ""
            print_success "Updated modules.json entry: $name"
        else
            local rc=0
            add_module_entry "$target_dir" "$name" "$lang" "" || rc=$?
            if [[ $rc -eq 0 ]]; then
                print_success "Added modules.json entry: $name"
            else
                print_warning "Could not register module '$name' (rc=$rc)"
            fi
        fi
    done
}

# Write a CLAUDE.md stub for each module, substituting MODULE_NAME,
# MODULE_LANGUAGE, and PROJECT_NAME placeholders. Existing files are
# preserved unless --overwrite is set.
core_write_per_module_claude_md() {
    local target_dir="$1"
    local template="${PLUGIN_DIR}/module.CLAUDE.md.template"

    if [[ ! -f "$template" ]]; then
        return
    fi

    local entry name lang module_dir target_md
    for entry in "${MODULES[@]}"; do
        name="${entry%%:*}"
        lang="${entry#*:}"
        module_dir="${target_dir}/${name}"
        target_md="${module_dir}/CLAUDE.md"

        mkdir -p "$module_dir"

        if [[ -f "$target_md" ]] && [[ "${OVERWRITE_ALL:-false}" != true ]]; then
            print_info "Skipped ${name}/CLAUDE.md (already exists)"
            continue
        fi

        sed -e "s|{{MODULE_NAME}}|${name}|g" \
            -e "s|{{MODULE_LANGUAGE}}|${lang}|g" \
            -e "s|{{PROJECT_NAME}}|${PROJECT_NAME}|g" \
            "$template" > "$target_md"
        print_success "Wrote ${name}/CLAUDE.md"
    done
}
