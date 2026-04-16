#!/bin/bash
# =============================================================================
# Claude Code Plugin Setup Script
# =============================================================================
# This script installs Claude Code official plugins.
# It is sourced by post.sh during devcontainer initialization.
#
# Installs the following plugins:
# - context7: Library documentation lookup
# - serena: Semantic code navigation and analysis
# - playwright: Browser automation for e2e testing (optional, interactive only)
#
# Prerequisites:
# - Claude Code CLI
# =============================================================================

setup_plugins() {
    echo "Setting up Claude Code plugins..."

    # Check Claude Code prerequisite
    if ! command -v claude &> /dev/null; then
        echo "  - Warning: Claude Code CLI is not installed"
        echo "  - Plugin setup requires Claude Code"
        echo "  - Skipping plugin setup"
        return 0
    fi

    echo "  - Claude Code CLI detected"

    local plugins_output
    plugins_output=$(claude plugins list 2>/dev/null)

    # -----------------------------------------------------------------
    # context7: Library documentation lookup
    # -----------------------------------------------------------------
    if echo "$plugins_output" | grep -q "context7"; then
        echo "  - context7 already installed, skipping"
    else
        echo "  - Installing context7 plugin..."
        claude plugins install context7@claude-plugins-official -s project
        echo "  - context7 plugin installed"
    fi

    # -----------------------------------------------------------------
    # serena: Semantic code navigation
    # -----------------------------------------------------------------
    if echo "$plugins_output" | grep -q "serena"; then
        echo "  - serena already installed, skipping"
    else
        echo "  - Installing serena plugin..."
        claude plugins install serena@claude-plugins-official -s project
        echo "  - serena plugin installed"
    fi

    # -----------------------------------------------------------------
    # playwright: Browser automation (optional, interactive prompt)
    # -----------------------------------------------------------------
    if echo "$plugins_output" | grep -q "playwright"; then
        echo "  - playwright already installed, skipping"
    elif type is_interactive &>/dev/null && is_interactive; then
        read -rp "  - Install Playwright plugin for browser testing? (y/N): " playwright_answer
        case "$playwright_answer" in
            [yY]|[yY][eE][sS])
                echo "  - Installing playwright plugin..."
                claude plugins install playwright@claude-plugins-official -s project
                echo "  - playwright plugin installed"
                ;;
            *)
                echo "  - Skipping playwright plugin"
                ;;
        esac
    else
        echo "  - Non-interactive environment, skipping playwright plugin prompt"
    fi

    echo "  - Plugin setup complete"
}
