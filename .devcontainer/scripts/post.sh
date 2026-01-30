#!/bin/bash
# =============================================================================
# DevContainer Post-Create Script
# =============================================================================

set -e

echo "Running post-creation setup script..."

# -----------------------------------------------------------------------------
# Environment Detection
# -----------------------------------------------------------------------------
# Returns 0 (true) if interactive, 1 (false) if non-interactive
is_interactive() {
    if [ -n "${CI:-}" ]; then
        return 1
    fi
    if [ -n "${NONINTERACTIVE:-}" ]; then
        return 1
    fi
    if [ ! -t 0 ]; then
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# Setup Git Configuration
# -----------------------------------------------------------------------------
# Creates .gitconfig.local as fallback when host's .gitconfig is not mounted
setup_gitconfig_local() {
    if [ -f "$HOME/.gitconfig.local" ]; then
        echo "  - .gitconfig.local already exists, skipping"
        return 0
    fi

    local name=""
    local email=""
    local needs_file=false

    # Check if user.name is already configured
    local existing_name
    existing_name=$(git config --global user.name 2>/dev/null || echo "")
    if [ -z "$existing_name" ]; then
        if is_interactive; then
            read -rp "Enter your Git user name (leave empty to skip): " name
            if [ -n "$name" ]; then
                needs_file=true
            fi
        else
            echo "  - Non-interactive environment, skipping Git user.name prompt"
        fi
    else
        echo "  - Git user.name already set: $existing_name"
    fi

    # Check if user.email is already configured
    local existing_email
    existing_email=$(git config --global user.email 2>/dev/null || echo "")
    if [ -z "$existing_email" ]; then
        if is_interactive; then
            read -rp "Enter your Git email (leave empty to skip): " email
            if [ -n "$email" ]; then
                needs_file=true
            fi
        else
            echo "  - Non-interactive environment, skipping Git email prompt"
        fi
    else
        echo "  - Git user.email already set: $existing_email"
    fi

    # Create .gitconfig.local only if values were provided
    if [ "$needs_file" = true ]; then
        {
            echo "[user]"
            [ -n "$name" ] && echo "    name = $name"
            [ -n "$email" ] && echo "    email = $email"
        } > "$HOME/.gitconfig.local"
        echo "  - Created .gitconfig.local with your settings"
    elif [ -z "$existing_name" ] && [ -z "$existing_email" ]; then
        echo "  - No Git user configuration provided, skipping .gitconfig.local"
    fi
}

echo "Setting up Git configuration..."
setup_gitconfig_local

# -----------------------------------------------------------------------------
# Setup SSH Configuration
# -----------------------------------------------------------------------------
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# Creates host_config template when SSH agent is not available
setup_ssh_host_config() {
    if [ -f "$HOME/.ssh/host_config" ]; then
        echo "  - host_config already exists, skipping SSH check"
        return 0
    fi

    echo "  - Checking SSH agent connectivity..."

    local ssh_output
    local ssh_exit_code
    ssh_output=$(timeout 15 ssh -T -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=accept-new git@github.com 2>&1) || ssh_exit_code=$?

    # Timeout (exit code 124)
    if [ "${ssh_exit_code:-0}" -eq 124 ]; then
        echo "  - Warning: SSH connection timed out"
        return 0
    fi

    # GitHub returns exit code 1 on successful authentication
    if [ "${ssh_exit_code:-0}" -eq 1 ] && echo "$ssh_output" | grep -q "successfully authenticated"; then
        echo "  - SSH agent working (GitHub authentication successful)"
        return 0
    fi

    # Network error (exit code 255)
    if [ "${ssh_exit_code:-0}" -eq 255 ]; then
        echo "  - Warning: SSH connection failed (network error)"
        return 0
    fi

    # SSH agent not available - prompt for host_config creation
    echo "  - SSH agent not detected or authentication failed"

    if ! is_interactive; then
        echo "  - Non-interactive environment, skipping host_config prompt"
        return 0
    fi

    read -rp "Create SSH host_config for manual key configuration? [y/N]: " answer
    case "$answer" in
        [yY]|[yY][eE][sS])
            cat > "$HOME/.ssh/host_config" << 'EOF'
# Host-specific SSH configuration
# Example:
# Host github.com
#     IdentityFile ~/.ssh/id_ed25519
#     IdentitiesOnly yes
EOF
            chmod 600 "$HOME/.ssh/host_config"
            echo "  - Created host_config template"
            ;;
        *)
            echo "  - Skipping host_config creation"
            ;;
    esac
}

setup_ssh_host_config

# -----------------------------------------------------------------------------
# SuperClaude Framework Setup
# -----------------------------------------------------------------------------
setup_superclaude() {
    echo "Setting up SuperClaude Framework..."

    if ! command -v claude &> /dev/null; then
        echo "  - Error: Claude Code CLI is not installed"
        echo "  - Please install Claude Code first: https://claude.ai/code"
        echo "  - Skipping SuperClaude setup"
        return 1
    fi

    echo "  - Claude Code CLI detected"

    mkdir -p "$HOME/.claude"

    echo "  - Installing SuperClaude..."
    uv tool install superclaude
    uvx superclaude install

    # Configure MCP servers
    echo "  - Configuring MCP servers..."
    local mcp_servers="context7 sequential-thinking serena"
    local mcp_cmd="uvx superclaude mcp"
    for server in $mcp_servers; do
        mcp_cmd="$mcp_cmd --servers $server"
    done
    # shellcheck disable=SC2086
    $mcp_cmd

    echo "  - SuperClaude setup complete"
}

setup_superclaude

echo "Post-creation setup complete!"
