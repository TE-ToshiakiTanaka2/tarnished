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

    # Install Codex CLI globally
    if ! command -v codex &> /dev/null; then
        echo "  - Installing Codex CLI..."
        if npm install -g @openai/codex; then
            echo "  - Codex CLI installed successfully"
        else
            echo "  [WARN] Failed to install Codex CLI (network error or npm issue)"
            echo "  You can install it manually later: npm install -g @openai/codex"
            return 0
        fi
    else
        echo "  - Codex CLI already installed: $(codex --version 2>/dev/null || echo 'unknown version')"
    fi

    echo "Codex CLI setup complete."
    echo "  To authenticate, run: codex (and follow the sign-in prompt)"
}
