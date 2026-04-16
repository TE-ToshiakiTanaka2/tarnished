#!/bin/bash
# =============================================================================
# MCP Server Setup Script
# =============================================================================
# This script configures MCP servers for Claude Code.
# It is sourced by post.sh during devcontainer initialization.
#
# Installs the following MCP servers:
# - context7: Library documentation lookup
# - serena: Semantic code navigation and analysis
# - playwright: Browser automation for e2e testing (optional, interactive only)
#
# Prerequisites:
# - Claude Code CLI
# - npx (Node.js)
# - uvx (uv) for serena
# =============================================================================

setup_mcp() {
    echo "Setting up MCP servers for Claude Code..."

    # Check Claude Code prerequisite
    if ! command -v claude &> /dev/null; then
        echo "  - Warning: Claude Code CLI is not installed"
        echo "  - MCP server setup requires Claude Code"
        echo "  - Skipping MCP setup"
        return 0
    fi

    echo "  - Claude Code CLI detected"

    # -----------------------------------------------------------------
    # context7: Library documentation lookup
    # -----------------------------------------------------------------
    if claude mcp list 2>/dev/null | grep -q "context7"; then
        echo "  - context7 already configured, skipping"
    else
        echo "  - Installing context7 MCP..."
        claude mcp add -s project context7 -- npx -y @upstash/context7-mcp
        echo "  - context7 MCP installed"
    fi

    # -----------------------------------------------------------------
    # serena: Semantic code navigation
    # -----------------------------------------------------------------
    if claude mcp list 2>/dev/null | grep -q "serena"; then
        echo "  - serena already configured, skipping"
    else
        if command -v uvx &> /dev/null; then
            echo "  - Installing serena MCP..."
            claude mcp add -s project serena -- uvx --from "git+https://github.com/oraios/serena" serena start-mcp-server --context ide-assistant --enable-web-dashboard false --enable-gui-log-window false
            echo "  - serena MCP installed"
        else
            echo "  - Warning: uvx not available, skipping serena MCP"
            echo "  - Install uv to enable serena: https://docs.astral.sh/uv/"
        fi
    fi

    # -----------------------------------------------------------------
    # playwright: Browser automation (optional, interactive prompt)
    # -----------------------------------------------------------------
    if claude mcp list 2>/dev/null | grep -q "playwright"; then
        echo "  - playwright already configured, skipping"
    elif type is_interactive &>/dev/null && is_interactive; then
        read -rp "  - Install Playwright MCP for browser testing? (y/N): " playwright_answer
        case "$playwright_answer" in
            [yY]|[yY][eE][sS])
                echo "  - Installing playwright MCP..."
                claude mcp add -s project playwright -- npx -y @anthropic-ai/mcp-server-playwright
                echo "  - playwright MCP installed"
                ;;
            *)
                echo "  - Skipping playwright MCP"
                ;;
        esac
    else
        echo "  - Non-interactive environment, skipping playwright MCP prompt"
    fi

    echo "  - MCP server setup complete"
}
