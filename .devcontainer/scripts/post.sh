#!/bin/bash
# =============================================================================
# DevContainer Post-Create Script
# =============================================================================

set -e

echo "Running post-creation setup script..."

# -----------------------------------------------------------------------------
# Environment Detection
# -----------------------------------------------------------------------------
is_interactive() {
    # Skip prompts if CI environment variable is set
    if [ -n "${CI:-}" ]; then
        return 1
    fi
    # Skip prompts if NONINTERACTIVE is set
    if [ -n "${NONINTERACTIVE:-}" ]; then
        return 1
    fi
    # Skip prompts if stdin is not a terminal
    if [ ! -t 0 ]; then
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# Setup sudo PATH for nvm-installed Node.js
# -----------------------------------------------------------------------------
setup_sudo_path() {
    echo "Setting up sudo PATH for nvm..."

    local nvm_bin
    nvm_bin=$(dirname "$(which node 2>/dev/null)" 2>/dev/null)

    if [ -z "$nvm_bin" ] || [ ! -d "$nvm_bin" ]; then
        echo "  - Node.js not found, skipping sudo PATH setup"
        return 0
    fi

    echo "  - Detected nvm bin path: $nvm_bin"

    if [ -f /etc/sudoers.d/nvm-path ]; then
        if grep -q "$nvm_bin" /etc/sudoers.d/nvm-path 2>/dev/null; then
            echo "  - sudo PATH already configured"
            return 0
        fi
    fi

    local current_secure_path
    current_secure_path=$(sudo grep -oP 'secure_path="\K[^"]+' /etc/sudoers 2>/dev/null || echo "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")

    if [[ "$current_secure_path" == *"$nvm_bin"* ]]; then
        echo "  - nvm path already in secure_path"
        return 0
    fi

    local new_secure_path="$nvm_bin:$current_secure_path"
    echo "Defaults secure_path=\"$new_secure_path\"" | sudo tee /etc/sudoers.d/nvm-path > /dev/null
    sudo chmod 0440 /etc/sudoers.d/nvm-path

    if sudo visudo -c -f /etc/sudoers.d/nvm-path >/dev/null 2>&1; then
        echo "  - sudo PATH configured successfully"
    else
        echo "  - Error: Invalid sudoers syntax, removing file"
        sudo rm -f /etc/sudoers.d/nvm-path
        return 1
    fi
}

setup_sudo_path

# -----------------------------------------------------------------------------
# Git Configuration
# -----------------------------------------------------------------------------
echo "Setting up Git configuration..."

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

setup_git_include

setup_gitconfig_local() {
    if [ -f "$HOME/.gitconfig.local" ]; then
        echo "  - .gitconfig.local already exists, skipping"
        return 0
    fi

    local name=""
    local email=""
    local needs_file=false

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

setup_ssh_include

setup_ssh_host_config() {
    if [ -f "$HOME/.ssh/host_config" ]; then
        echo "  - host_config already exists, skipping SSH check"
        return 0
    fi

    echo "  - Checking SSH agent connectivity..."

    local ssh_output
    local ssh_exit_code
    ssh_output=$(timeout 15 ssh -T -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=accept-new git@github.com 2>&1) || ssh_exit_code=$?

    if [ "${ssh_exit_code:-0}" -eq 124 ]; then
        echo "  - Warning: SSH connection timed out"
        echo "  - Continuing without host_config setup"
        return 0
    fi

    if [ "${ssh_exit_code:-0}" -eq 1 ] && echo "$ssh_output" | grep -q "successfully authenticated"; then
        echo "  - SSH agent working (GitHub authentication successful)"
        return 0
    fi

    if [ "${ssh_exit_code:-0}" -eq 255 ]; then
        echo "  - Warning: SSH connection failed (network error or timeout)"
        echo "  - Continuing without host_config setup"
        return 0
    fi

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
    mkdir -p "$HOME/.claude"
fi

echo "Post-creation setup script finished."

# -----------------------------------------------------------------------------
# Tarnished Asset Refresh
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -x "${SCRIPT_DIR}/refresh-assets.sh" ]]; then
    "${SCRIPT_DIR}/refresh-assets.sh" || true
fi

# -----------------------------------------------------------------------------
# Rust Development Tools Setup
# -----------------------------------------------------------------------------
if command -v cargo &> /dev/null; then
    echo "Installing Rust development tools..."

    # Install cargo-watch for auto-rebuild on file changes
    if ! command -v cargo-watch &> /dev/null; then
        echo "  - Installing cargo-watch..."
        cargo install --locked cargo-watch
    fi

    # Install cargo-edit for easy dependency management (cargo add/rm)
    if ! cargo add --version &> /dev/null 2>&1; then
        echo "  - Installing cargo-edit..."
        cargo install --locked cargo-edit
    fi

    echo "Rust development tools installed."
fi

# -----------------------------------------------------------------------------
# Claude Code Plugin Setup
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/setup_plugins.sh" ]]; then
    source "${SCRIPT_DIR}/setup_plugins.sh"
    setup_plugins
fi

# -----------------------------------------------------------------------------
# Codex CLI Setup
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/setup_codex.sh" ]]; then
    source "${SCRIPT_DIR}/setup_codex.sh"
    setup_codex
fi
