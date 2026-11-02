#!/bin/bash
# =============================================================================
# Claude Code Setup Script
# =============================================================================
# Installs the Claude Code CLI with `npm install -g` (no sudo). It is sourced
# by post.sh during devcontainer setup, after the mise runtime block.
#
# Prerequisites: Node.js and npm from mise.toml (see setup_mise.sh)
# Override the package (for example to pin a version) without editing this
# file: CLAUDE_CODE_NPM_PACKAGE=@anthropic-ai/claude-code@<version>
# =============================================================================

setup_claude() {
    local helper_dir
    helper_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [[ ! -f "${helper_dir}/npm_global_cli.sh" ]]; then
        echo "  [WARN] npm_global_cli.sh not found. Skipping Claude Code installation."
        echo "  Run ./setup.sh --upgrade to restore it, or: npm install -g @anthropic-ai/claude-code"
        return 0
    fi

    # shellcheck source=/dev/null
    source "${helper_dir}/npm_global_cli.sh"
    install_npm_global_cli "Claude Code" "${CLAUDE_CODE_NPM_PACKAGE:-@anthropic-ai/claude-code}" "claude"

    if ! mkdir -p "$HOME/.claude" 2>/dev/null; then
        echo "  [WARN] could not create $HOME/.claude. Create it manually: mkdir -p \"\$HOME/.claude\""
    fi
    return 0
}
