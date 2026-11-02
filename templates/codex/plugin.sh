#!/bin/bash
# =============================================================================
# Template Plugin: codex
# This file is meant to be sourced by setup.sh, not executed directly.
# =============================================================================
# This plugin provides OpenAI Codex CLI integration including:
# - AGENTS.md template for primary or review agent role
# - Project-level Codex configuration (.codex/config.toml)
# - Codex repo-local workflow skills (.agents/skills)
# - Codex CLI installation script for post-creation setup (npm install -g
#   under the mise-managed Node from core's mise.toml; no devcontainer feature)
# - Claude Code integration settings for cross-agent handoff
#
# =============================================================================

# Get the directory where this plugin is located
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# Required Functions
# =============================================================================

# Return plugin identifier
plugin_name() {
    echo "codex"
}

# Return plugin description
plugin_description() {
    echo "OpenAI Codex CLI integration for primary or review workflows"
}

# =============================================================================
# Hook Functions
# =============================================================================

# Copy Codex-specific template files to target directory
plugin_copy() {
    local target_dir="$1"

    print_info "Copying Codex CLI template files..."

    # Copy AGENTS.md
    if [[ -f "${PLUGIN_DIR}/AGENTS.md" ]]; then
        copy_with_confirm "${PLUGIN_DIR}/AGENTS.md" "${target_dir}/AGENTS.md"
    fi

    # Copy .codex directory
    if [[ -d "${PLUGIN_DIR}/.codex" ]]; then
        copy_dir_with_confirm "${PLUGIN_DIR}/.codex" "${target_dir}/.codex"
    fi

    # Copy .agents directory for Codex repo-local skills
    if [[ -d "${PLUGIN_DIR}/.agents" ]]; then
        copy_dir_with_confirm "${PLUGIN_DIR}/.agents" "${target_dir}/.agents"
    fi

    print_success "Codex CLI template files copied"
}

# Post-copy processing - merge Claude settings and set up the CLI install script
plugin_post_copy() {
    local target_dir="$1"

    # -------------------------------------------------------------------------
    # Claude Code Settings Integration
    # -------------------------------------------------------------------------

    local target_settings="${target_dir}/.claude/settings.json"
    local plugin_settings="${PLUGIN_DIR}/.claude/settings.json"

    if [[ -f "$plugin_settings" ]] && [[ -f "$target_settings" ]]; then
        print_info "Merging Codex Claude settings..."
        local temp_file="${target_dir}/.claude/settings.json.tmp"

        merge_claude_settings_hooks "$target_settings" "$plugin_settings" "$temp_file"
        mv "$temp_file" "$target_settings"

        print_success "Codex Claude settings merged"
    fi

    # -------------------------------------------------------------------------
    # Codex CLI Installation Script
    # -------------------------------------------------------------------------

    # Copy setup script to devcontainer scripts
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

    # Integrate Codex setup into post.sh
    local post_sh="${target_dir}/.devcontainer/scripts/post.sh"
    local codex_marker="# Codex CLI Setup"

    # Inserted above the Claude Code plugin block when it already exists, so the
    # order stays mise -> Claude Code -> Codex CLI -> plugins (#325): plugins
    # need `claude`, and a Node.js bump removes both npm global CLIs.
    if [[ -f "$post_sh" ]] && ! grep -qxF "$codex_marker" "$post_sh"; then
        print_info "Integrating Codex CLI setup into post.sh..."
        post_sh_add_block "$post_sh" "$codex_marker" "# Claude Code Plugin Setup" << 'EOF'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/setup_codex.sh" ]]; then
    source "${SCRIPT_DIR}/setup_codex.sh"
    setup_codex
fi
EOF
        print_success "Codex CLI setup integrated into post.sh"
    fi

    # -------------------------------------------------------------------------
    # .gitignore Updates
    # -------------------------------------------------------------------------

    local gitignore="${target_dir}/.gitignore"
    touch "$gitignore"

    # Block 4: Codex CLI whitelist — ignore .codex/* and allow shared config only
    if ! grep -q "^# Codex CLI (track shared config only)$" "$gitignore" 2>/dev/null; then
        {
            echo ""
            echo "# Codex CLI (track shared config only)"
            echo ".codex/*"
            echo "!.codex/config.toml"
        } >> "$gitignore"
    fi

    # Block 5: Codex repo-local skills — track shared skills, ignore local overrides
    if ! grep -q "^# Codex Agent Skills (track shared workflow skills)$" "$gitignore" 2>/dev/null; then
        {
            echo ""
            echo "# Codex Agent Skills (track shared workflow skills)"
            echo ".agents/*"
            echo "!.agents/skills/"
            echo "!.agents/skills/**"
        } >> "$gitignore"
    fi
}
