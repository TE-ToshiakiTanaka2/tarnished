#!/bin/bash
# =============================================================================
# DevContainer Post-Create Script
# =============================================================================

set -e

echo "Running post-creation setup script..."

# -----------------------------------------------------------------------------
# Environment Detection
# -----------------------------------------------------------------------------
# Check if we're running in an interactive environment
# Returns 0 (true) if interactive, 1 (false) if non-interactive (CI, automated tests, etc.)
is_interactive() {
    # Skip prompts if CI environment variable is set
    if [ -n "${CI:-}" ]; then
        echo "  [DEBUG] Non-interactive: CI=${CI}"
        return 1
    fi
    # Skip prompts if NONINTERACTIVE is set (common convention)
    if [ -n "${NONINTERACTIVE:-}" ]; then
        echo "  [DEBUG] Non-interactive: NONINTERACTIVE=${NONINTERACTIVE}"
        return 1
    fi
    # Skip prompts if stdin is not a terminal (non-interactive shell)
    if [ ! -t 0 ]; then
        echo "  [DEBUG] Non-interactive: stdin is not a TTY"
        return 1
    fi
    echo "  [DEBUG] Interactive mode detected"
    return 0
}

# -----------------------------------------------------------------------------
# Git Configuration
# -----------------------------------------------------------------------------
echo "Setting up Git configuration..."

# -----------------------------------------------------------------------------
# Setup .gitconfig.local with interactive prompts
# -----------------------------------------------------------------------------
setup_gitconfig_local() {
    # Skip if file already exists (idempotency)
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

setup_gitconfig_local

# -----------------------------------------------------------------------------
# SSH Configuration
# -----------------------------------------------------------------------------
echo "Setting up SSH configuration..."

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# -----------------------------------------------------------------------------
# Setup SSH host_config conditionally based on ssh-agent status
# -----------------------------------------------------------------------------
setup_ssh_host_config() {
    # Skip if file already exists (idempotency)
    if [ -f "$HOME/.ssh/host_config" ]; then
        echo "  - host_config already exists, skipping SSH check"
        return 0
    fi

    echo "  - Checking SSH agent connectivity..."

    # Test SSH connection to GitHub with timeout
    # Use both timeout command and SSH's ConnectTimeout for defense in depth
    local ssh_output
    local ssh_exit_code
    ssh_output=$(timeout 15 ssh -T -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=accept-new git@github.com 2>&1) || ssh_exit_code=$?

    # Check if timeout command killed the process (exit code 124)
    if [ "${ssh_exit_code:-0}" -eq 124 ]; then
        echo "  - Warning: SSH connection timed out"
        echo "  - Continuing without host_config setup"
        return 0
    fi

    # GitHub returns exit code 1 on successful authentication
    # (because it doesn't provide shell access)
    if [ "${ssh_exit_code:-0}" -eq 1 ] && echo "$ssh_output" | grep -q "successfully authenticated"; then
        echo "  - SSH agent working (GitHub authentication successful)"
        return 0
    fi

    # Check for network/timeout errors (exit code 255)
    if [ "${ssh_exit_code:-0}" -eq 255 ]; then
        echo "  - Warning: SSH connection failed (network error or timeout)"
        echo "  - Continuing without host_config setup"
        return 0
    fi

    # SSH agent not available - prompt for host_config creation
    echo "  - SSH agent not detected or authentication failed"

    # Skip prompt in non-interactive environments (CI, automated tests)
    if ! is_interactive; then
        echo "  - Non-interactive environment, skipping host_config prompt"
        return 0
    fi

    read -rp "Create SSH host_config for manual key configuration? [y/N]: " answer
    case "$answer" in
        [yY]|[yY][eE][sS])
            cat > "$HOME/.ssh/host_config" << 'EOF'
# Host-specific SSH configuration
# Add your host configurations here
#
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
# Claude Code Setup
# -----------------------------------------------------------------------------
if command -v claude &> /dev/null; then
    echo "Claude Code CLI is available"

    # Create Claude config directory
    mkdir -p "$HOME/.claude"

    # Note: MCP servers can be added here if needed
    # claude mcp add context7 -- npx -y @upstash/context7-mcp
fi

echo "Post-creation setup script finished."
