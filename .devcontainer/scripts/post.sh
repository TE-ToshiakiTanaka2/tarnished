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

    if is_interactive; then
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

setup_superclaude

# -----------------------------------------------------------------------------
# Test Environment Setup
# -----------------------------------------------------------------------------
echo "Setting up test environment..."

# Install bats-core for shell script testing
setup_bats() {
    if command -v bats >/dev/null 2>&1; then
        echo "  - Bats already installed: $(bats --version)"
        return 0
    fi

    echo "  - Installing bats-core..."
    sudo apt-get update -qq && sudo apt-get install -y -qq bats
    echo "  - Bats installed: $(bats --version)"
}

setup_bats

# Initialize git submodules for Bats helper libraries
if [ -f "$DOTFILES_DIR/.gitmodules" ]; then
    cd "$DOTFILES_DIR"
    git submodule update --init --recursive
    echo "  - Bats helper libraries initialized"
fi

echo "Post-creation setup script finished."