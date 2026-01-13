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
    echo "Claude Code configuration and custom commands"
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
        cp -r "${PLUGIN_DIR}/.claude/commands" "${target_dir}/.claude/"
    fi

    # Copy scripts directory
    if [[ -d "${PLUGIN_DIR}/.claude/scripts" ]]; then
        cp -r "${PLUGIN_DIR}/.claude/scripts" "${target_dir}/.claude/"
    fi

    # Copy CLAUDE.md
    if [[ -f "${PLUGIN_DIR}/CLAUDE.md" ]]; then
        cp "${PLUGIN_DIR}/CLAUDE.md" "${target_dir}/"
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
        cp "$plugin_settings" "$target_settings"
    fi

    # Make scripts executable
    if [[ -d "${target_dir}/.claude/scripts" ]]; then
        make_scripts_executable "${target_dir}/.claude/scripts"
        print_success "Claude scripts made executable"
    fi
}
