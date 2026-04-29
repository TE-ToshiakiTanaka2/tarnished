#!/bin/bash
# =============================================================================
# Codex CLI Setup Script
# =============================================================================
# This script installs and configures the OpenAI Codex CLI.
# It is sourced by post.sh during devcontainer setup.
#
# Prerequisites: Node.js and npm must be available
# =============================================================================

setup_codex() {
    echo "Setting up OpenAI Codex CLI..."

    # Check if npm is available
    if ! command -v npm &> /dev/null; then
        echo "  [WARN] npm not found. Skipping Codex CLI installation."
        echo "  Install Node.js first, then run: npm install -g @openai/codex"
        return 0
    fi

    # Install Codex CLI globally.
    # The npm global prefix is user-writable under nvm but root-owned when Node
    # is installed system-wide (e.g. via the claude-code devcontainer feature,
    # which lands node at /usr/lib/node_modules). Use sudo only when the prefix
    # is not writable by the current user.
    if ! command -v codex &> /dev/null; then
        echo "  - Installing Codex CLI..."

        local npm_prefix
        npm_prefix=$(npm root -g 2>/dev/null || echo "")
        local install_cmd=(npm install -g @openai/codex)
        if [[ -z "$npm_prefix" ]]; then
            echo "  - Warning: 'npm root -g' did not resolve a prefix; attempting install without sudo"
        else
            # npm writes INTO the prefix dir if it exists, otherwise it creates
            # the prefix, so writability requirements differ in those two cases.
            local needs_sudo=false
            if [[ -e "$npm_prefix" ]]; then
                [[ ! -w "$npm_prefix" ]] && needs_sudo=true
            else
                [[ ! -w "$(dirname "$npm_prefix")" ]] && needs_sudo=true
            fi
            if [[ "$needs_sudo" == true ]]; then
                echo "  - npm global prefix '$npm_prefix' is not user-writable; using sudo"
                install_cmd=(sudo -E npm install -g @openai/codex)
            fi
        fi

        if "${install_cmd[@]}"; then
            echo "  - Codex CLI installed successfully"
        else
            echo "  [WARN] Failed to install Codex CLI (network error or npm issue)"
            echo "  You can install it manually later: ${install_cmd[*]}"
            return 0
        fi
    else
        echo "  - Codex CLI already installed: $(codex --version 2>/dev/null || echo 'unknown version')"
    fi

    echo "Codex CLI setup complete."
    echo "  To authenticate, run: codex (and follow the sign-in prompt)"
}
