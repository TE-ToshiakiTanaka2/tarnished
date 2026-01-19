#!/bin/bash
# =============================================================================
# SuperClaude Framework Setup Script
# =============================================================================
# This script sets up SuperClaude Framework for AI-assisted development.
# It is sourced by post.sh during devcontainer initialization.
#
# Prerequisites:
# - uv package manager
# - is_interactive() function (defined in core's post.sh)
#
# Optional:
# - Claude Code CLI (setup skipped if not available)
# =============================================================================

# SuperClaude Framework Setup
setup_superclaude() {
    echo "Setting up SuperClaude Framework..."

    # Check Claude Code prerequisite
    if ! command -v claude &> /dev/null; then
        echo "  - Warning: Claude Code CLI is not installed"
        echo "  - SuperClaude requires Claude Code to function"
        echo "  - Please install Claude Code first: https://claude.ai/code"
        echo "  - Skipping SuperClaude setup"
        return 0
    fi

    echo "  - Claude Code CLI detected"

    # Create Claude config directory
    mkdir -p "$HOME/.claude"

    # Install SuperClaude
    echo "  - Installing SuperClaude..."
    uv tool install superclaude
    uvx superclaude install

    # MCP servers configuration
    local mcp_servers="context7 sequential-thinking serena"

    # Prompt for Playwright in interactive mode
    if type is_interactive &>/dev/null && is_interactive; then
        read -rp "  - UI開発を行いますか？Playwright MCPをインストールします (y/N): " playwright_answer
        case "$playwright_answer" in
            [yY]|[yY][eE][sS])
                mcp_servers="$mcp_servers playwright"
                echo "  - Playwright MCP will be installed"
                ;;
            *)
                echo "  - Skipping Playwright MCP"
                ;;
        esac
    else
        echo "  - Non-interactive environment, skipping Playwright MCP prompt"
    fi

    # Configure MCP servers
    echo "  - Configuring MCP servers..."
    local mcp_cmd="uvx superclaude mcp"
    for server in $mcp_servers; do
        mcp_cmd="$mcp_cmd --servers $server"
    done
    # shellcheck disable=SC2086
    $mcp_cmd

    echo "  - SuperClaude setup complete"
}
