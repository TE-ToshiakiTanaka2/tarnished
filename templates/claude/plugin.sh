#!/bin/bash
# =============================================================================
# Template Plugin: claude
# This file is meant to be sourced by setup.sh, not executed directly.
# =============================================================================
# This plugin provides Claude Code configuration including:
# - Custom slash commands (issue, implement, pr)
# - Custom erd: commands (brainstorm, estimate, design, etc.)
# - Claude Code settings with hooks
# - Deny check script
# - CLAUDE.md project context file
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
    echo "Claude Code configuration, custom commands, and erd commands"
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

    # Copy rules directory (language-agnostic rules; language-specific rules
    # ship from each language plugin under templates/languages/<lang>/.claude/rules/).
    # Refreshed always-latest at container start by refresh-assets.sh (#279).
    if [[ -d "${PLUGIN_DIR}/.claude/rules" ]]; then
        copy_dir_with_confirm "${PLUGIN_DIR}/.claude/rules" "${target_dir}/.claude/rules"
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
    # Claude Code Plugin Setup Integration
    # -------------------------------------------------------------------------

    # Copy plugin setup script to devcontainer scripts
    if [[ -d "${PLUGIN_DIR}/.devcontainer/scripts" ]]; then
        mkdir -p "${target_dir}/.devcontainer/scripts"
        for script in "${PLUGIN_DIR}/.devcontainer/scripts"/*.sh; do
            if [[ -f "$script" ]]; then
                local script_name
                script_name=$(basename "$script")
                copy_with_confirm "$script" "${target_dir}/.devcontainer/scripts/${script_name}"
            fi
        done
        make_scripts_executable "${target_dir}/.devcontainer/scripts"
    fi

    # Integrate plugin setup into post.sh
    local post_sh="${target_dir}/.devcontainer/scripts/post.sh"
    local plugin_marker="# Claude Code Plugin Setup"

    if [[ -f "$post_sh" ]] && ! grep -q "$plugin_marker" "$post_sh"; then
        print_info "Integrating Claude Code plugin setup into post.sh..."
        cat >> "$post_sh" << 'EOF'

# -----------------------------------------------------------------------------
# Claude Code Plugin Setup
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/setup_plugins.sh" ]]; then
    source "${SCRIPT_DIR}/setup_plugins.sh"
    setup_plugins
fi
EOF
        print_success "Claude Code plugin setup integrated into post.sh"
    fi
}
