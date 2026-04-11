#!/bin/bash
# =============================================================================
# Template Plugin: claude
# This file is meant to be sourced by setup.sh, not executed directly.
# =============================================================================
# This plugin provides Claude Code configuration including:
# - Custom slash commands (issue, implement, pr)
# - Claude Code settings with hooks
# - Deny check script
# - CLAUDE.md project context file
# - SuperClaude Framework setup (automatic integration with post.sh)
#
# =============================================================================

# Get the directory where this plugin is located
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# Required Functions
# =============================================================================

# Return plugin identifier
plugin_name() {
    echo "claude"
}

# Return plugin description
plugin_description() {
    echo "Claude Code configuration, custom commands, and SuperClaude setup"
}

# =============================================================================
# Hook Functions
# =============================================================================

# Copy Claude-specific template files to target directory
plugin_copy() {
    local target_dir="$1"

    print_info "Copying Claude Code template files..."

    # Ensure target .claude directory exists
    mkdir -p "${target_dir}/.claude"

    # Copy commands directory
    if [[ -d "${PLUGIN_DIR}/.claude/commands" ]]; then
        copy_dir_with_confirm "${PLUGIN_DIR}/.claude/commands" "${target_dir}/.claude/commands"
    fi

    # Copy skills directory
    if [[ -d "${PLUGIN_DIR}/.claude/skills" ]]; then
        copy_dir_with_confirm "${PLUGIN_DIR}/.claude/skills" "${target_dir}/.claude/skills"
    fi

    # Copy scripts directory
    if [[ -d "${PLUGIN_DIR}/.claude/scripts" ]]; then
        copy_dir_with_confirm "${PLUGIN_DIR}/.claude/scripts" "${target_dir}/.claude/scripts"
    fi

    # Copy CLAUDE.md
    if [[ -f "${PLUGIN_DIR}/CLAUDE.md" ]]; then
        copy_with_confirm "${PLUGIN_DIR}/CLAUDE.md" "${target_dir}/CLAUDE.md"
    fi

    print_success "Claude Code template files copied"
}

# Post-copy processing - merge settings and make scripts executable
plugin_post_copy() {
    local target_dir="$1"

    # Merge settings.json if both exist
    local target_settings="${target_dir}/.claude/settings.json"
    local plugin_settings="${PLUGIN_DIR}/.claude/settings.json"

    if [[ -f "$plugin_settings" ]] && [[ -f "$target_settings" ]]; then
        print_info "Merging Claude Code settings..."
        local temp_file="${target_dir}/.claude/settings.json.tmp"

        # Merge settings with permission and hook handling
        merge_claude_settings "$target_settings" "$plugin_settings" "$temp_file"
        mv "$temp_file" "$target_settings"

        print_success "Claude Code settings merged"
    elif [[ -f "$plugin_settings" ]]; then
        copy_with_confirm "$plugin_settings" "$target_settings"
    fi

    # Make scripts executable
    if [[ -d "${target_dir}/.claude/scripts" ]]; then
        make_scripts_executable "${target_dir}/.claude/scripts"
        print_success "Claude scripts made executable"
    fi

    # -------------------------------------------------------------------------
    # Devcontainer Features Integration (uv for SuperClaude)
    # -------------------------------------------------------------------------

    # Merge devcontainer.json features (uv package manager for SuperClaude)
    local target_devcontainer="${target_dir}/.devcontainer/devcontainer.json"
    local plugin_devcontainer="${PLUGIN_DIR}/.devcontainer/devcontainer.json"

    if [[ -f "$plugin_devcontainer" ]] && [[ -f "$target_devcontainer" ]]; then
        print_info "Merging Claude devcontainer features..."
        local temp_file="${target_dir}/.devcontainer/devcontainer.json.tmp"

        # Merge devcontainer.json with special handling for features and extensions
        merge_devcontainer_json "$target_devcontainer" "$plugin_devcontainer" "$temp_file"
        mv "$temp_file" "$target_devcontainer"

        print_success "Claude devcontainer features merged"
    fi

    # -------------------------------------------------------------------------
    # SuperClaude Framework Integration
    # -------------------------------------------------------------------------

    # Copy SuperClaude setup script to devcontainer scripts
    if [[ -d "${PLUGIN_DIR}/.devcontainer/scripts" ]]; then
        mkdir -p "${target_dir}/.devcontainer/scripts"
        for script in "${PLUGIN_DIR}/.devcontainer/scripts"/*.sh; do
            if [[ -f "$script" ]]; then
                local script_name
                script_name=$(basename "$script")
                copy_with_confirm "$script" "${target_dir}/.devcontainer/scripts/${script_name}"
            fi
        done
        # Make devcontainer scripts executable
        make_scripts_executable "${target_dir}/.devcontainer/scripts"
    fi

    # Integrate SuperClaude setup into post.sh
    local post_sh="${target_dir}/.devcontainer/scripts/post.sh"
    local superclaude_marker="# SuperClaude Framework"

    if [[ -f "$post_sh" ]] && ! grep -q "$superclaude_marker" "$post_sh"; then
        print_info "Integrating SuperClaude setup into post.sh..."
        cat >> "$post_sh" << 'EOF'

# -----------------------------------------------------------------------------
# SuperClaude Framework
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/setup_superclaude.sh" ]]; then
    source "${SCRIPT_DIR}/setup_superclaude.sh"
    setup_superclaude
fi
EOF
        print_success "SuperClaude setup integrated into post.sh"
    fi
}
