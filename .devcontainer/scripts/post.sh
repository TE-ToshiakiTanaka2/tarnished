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
# Ensure .gitconfig includes .gitconfig.local
setup_git_include() {
    local include_path
    include_path=$(git config --global --get include.path 2>/dev/null || echo "")

    if [ "$include_path" != ".gitconfig.local" ]; then
        git config --global include.path ".gitconfig.local"
        echo "  - Configured git to include .gitconfig.local"
    else
        echo "  - Git already configured to include .gitconfig.local"
    fi
}

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
setup_git_include
setup_gitconfig_local

# -----------------------------------------------------------------------------
# Setup SSH Configuration
# -----------------------------------------------------------------------------
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# Ensure ~/.ssh/config includes host_config
setup_ssh_include() {
    local ssh_config="$HOME/.ssh/config"

    if [ ! -f "$ssh_config" ]; then
        # Create minimal SSH config with include directive
        cat > "$ssh_config" << 'EOF'
# Include host-specific configuration
Include host_config
EOF
        chmod 600 "$ssh_config"
        echo "  - Created SSH config with host_config include"
    elif ! grep -q "^Include host_config" "$ssh_config" 2>/dev/null; then
        # Add include directive at the beginning of existing config
        # (SSH Include must be at the top to work correctly)
        local temp_config
        temp_config=$(mktemp)
        {
            echo "# Include host-specific configuration"
            echo "Include host_config"
            echo ""
            cat "$ssh_config"
        } > "$temp_config"
        mv "$temp_config" "$ssh_config"
        chmod 600 "$ssh_config"
        echo "  - Added host_config include to existing SSH config"
    else
        echo "  - SSH config already includes host_config"
    fi
}

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

setup_ssh_include
setup_ssh_host_config

# -----------------------------------------------------------------------------
# Rust Development Setup
# -----------------------------------------------------------------------------
setup_rust() {
    echo "Setting up Rust development environment..."

    # Check if Rust is installed (should be via DevContainer feature)
    if ! command -v rustc &> /dev/null; then
        echo "  - Warning: Rust is not installed"
        echo "  - Rust should be installed via DevContainer feature"
        return 1
    fi

    echo "  - Rust $(rustc --version | cut -d' ' -f2) detected"
    echo "  - Cargo $(cargo --version | cut -d' ' -f2) detected"

    # Ensure common components are installed
    echo "  - Verifying Rust components..."
    rustup component add clippy rustfmt 2>/dev/null || true

    # Fetch project dependencies if Cargo.toml exists
    if [ -f "/workspace/Cargo.toml" ]; then
        echo "  - Fetching project dependencies..."
        cd /workspace && cargo fetch 2>/dev/null || true
        echo "  - Dependencies fetched"
    fi

    echo "  - Rust setup complete"
}

setup_rust

# -----------------------------------------------------------------------------
# Code Quality Tools Setup
# -----------------------------------------------------------------------------
setup_code_quality_tools() {
    echo "Setting up code quality tools..."

    # Install codespell for code spell checking
    if command -v uv &> /dev/null; then
        echo "  - Installing codespell..."
        uv tool install codespell 2>/dev/null || true
        echo "  - codespell installed"
    else
        echo "  - Warning: uv not found, skipping codespell installation"
    fi

    # Verify shellcheck (should be installed via Dockerfile)
    if command -v shellcheck &> /dev/null; then
        echo "  - shellcheck $(shellcheck --version | head -2 | tail -1) detected"
    else
        echo "  - Warning: shellcheck not found"
        echo "  - Install via: sudo apt-get install shellcheck"
    fi

    echo "  - Code quality tools setup complete"
}

setup_code_quality_tools

# -----------------------------------------------------------------------------
# Claude Code Plugin Setup
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/setup_plugins.sh" ]]; then
    source "${SCRIPT_DIR}/setup_plugins.sh"
    setup_plugins
fi

echo "Post-creation setup complete!"
