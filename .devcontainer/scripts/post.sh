#!/bin/bash
# =============================================================================
# DevContainer Post-Create Script
# =============================================================================

set -e

echo "Running post-creation setup script..."

DOTFILES_DIR="${PWD}"

# -----------------------------------------------------------------------------
# Setup dotfiles within DevContainer
# -----------------------------------------------------------------------------
echo "Setting up dotfiles..."

# Git configuration
if [ -f "$DOTFILES_DIR/config/git/.gitconfig" ]; then
    # Try to create symlink, but if .gitconfig is mounted (DevContainer),
    # use git's include directive instead
    if ln -snf "$DOTFILES_DIR/config/git/.gitconfig" "$HOME/.gitconfig" 2>/dev/null; then
        echo "  - Git config linked"
    else
        # File is mounted/busy, use include directive
        git config --global include.path "$DOTFILES_DIR/config/git/.gitconfig"
        echo "  - Git config included via include.path (mounted .gitconfig detected)"
    fi
fi

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
        read -rp "Enter your Git user name (leave empty to skip): " name
        if [ -n "$name" ]; then
            needs_file=true
        fi
    else
        echo "  - Git user.name already set: $existing_name"
    fi

    # Check if user.email is already configured
    local existing_email
    existing_email=$(git config --global user.email 2>/dev/null || echo "")
    if [ -z "$existing_email" ]; then
        read -rp "Enter your Git email (leave empty to skip): " email
        if [ -n "$email" ]; then
            needs_file=true
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

# SSH configuration
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [ -f "$DOTFILES_DIR/config/ssh/config" ]; then
    ln -snf "$DOTFILES_DIR/config/ssh/config" "$HOME/.ssh/config"
    chmod 600 "$HOME/.ssh/config"
    echo "  - SSH config linked"
fi

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
    local ssh_output
    local ssh_exit_code
    ssh_output=$(ssh -T -o ConnectTimeout=10 -o BatchMode=yes git@github.com 2>&1) || ssh_exit_code=$?

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

# Shell configuration (optional - DevContainer has its own setup)
# Uncomment if you want to use custom shell config
# ln -snf "$DOTFILES_DIR/config/shell/.bashrc" "$HOME/.bashrc"
# ln -snf "$DOTFILES_DIR/config/shell/.bash_profile" "$HOME/.bash_profile"

# -----------------------------------------------------------------------------
# SuperClaude Framework Setup
# -----------------------------------------------------------------------------
setup_superclaude() {
    echo "Setting up SuperClaude Framework..."

    # Check Claude Code prerequisite
    if ! command -v claude &> /dev/null; then
        echo "  - Error: Claude Code CLI is not installed"
        echo "  - SuperClaude requires Claude Code to function"
        echo "  - Please install Claude Code first: https://claude.ai/code"
        echo "  - Skipping SuperClaude setup"
        return 1
    fi

    echo "  - Claude Code CLI detected"

    # Create Claude config directory
    mkdir -p "$HOME/.claude"

    # Install SuperClaude
    echo "  - Installing SuperClaude..."
    uv tool install superclaude
    uvx superclaude install

    # Ask about Playwright (optional)
    local mcp_servers="context7 sequential-thinking serena"

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

    # Configure MCP servers
    echo "  - Configuring MCP servers..."
    local mcp_args=""
    for server in $mcp_servers; do
        mcp_args="$mcp_args --servers $server"
    done
    eval "uvx superclaude mcp $mcp_args"

    echo "  - SuperClaude setup complete"
}

setup_superclaude

# -----------------------------------------------------------------------------
# Test Environment Setup
# -----------------------------------------------------------------------------
echo "Setting up test environment..."

# Initialize git submodules for Bats-core
if [ -f "$DOTFILES_DIR/.gitmodules" ]; then
    cd "$DOTFILES_DIR"
    git submodule update --init --recursive
    echo "  - Bats-core test framework initialized"
fi

echo "Post-creation setup script finished."