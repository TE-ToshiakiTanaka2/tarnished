#!/bin/bash
# =============================================================================
# Codex CLI Setup Script
# =============================================================================
# This script installs and configures the OpenAI Codex CLI with
# `npm install -g` (no sudo). It is sourced by post.sh during devcontainer
# setup, after the mise runtime and Claude Code blocks, so a Node.js version
# change is followed by a reinstall of the CLI.
#
# Prerequisites: Node.js and npm from mise.toml; npm_global_cli.sh (shipped by
# the core template) in the same directory.
# Override the package (for example to pin a version) without editing this
# file: CODEX_NPM_PACKAGE=@openai/codex@<version>
# =============================================================================

setup_codex() {
    local helper_dir
    helper_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [[ ! -f "${helper_dir}/npm_global_cli.sh" ]]; then
        echo "  [WARN] npm_global_cli.sh not found. Skipping Codex CLI installation."
        echo "  Run ./setup.sh --upgrade to restore it, or: npm install -g @openai/codex"
        return 0
    fi

    # shellcheck source=/dev/null
    source "${helper_dir}/npm_global_cli.sh"
    install_npm_global_cli "OpenAI Codex CLI" "${CODEX_NPM_PACKAGE:-@openai/codex}" "codex"

    echo "Codex CLI setup complete."
    echo "  To authenticate, run: codex (and follow the sign-in prompt)"
    return 0
}
