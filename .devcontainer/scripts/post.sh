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

# Create .gitconfig.local if it doesn't exist
if [ ! -f "$HOME/.gitconfig.local" ]; then
    cat > "$HOME/.gitconfig.local" << 'EOF'
[user]
    # name = Your Name
    # email = your.email@example.com
EOF
    echo "  - Created .gitconfig.local (edit to set your name/email)"
fi

# SSH configuration
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [ -f "$DOTFILES_DIR/config/ssh/config" ]; then
    ln -snf "$DOTFILES_DIR/config/ssh/config" "$HOME/.ssh/config"
    chmod 600 "$HOME/.ssh/config"
    echo "  - SSH config linked"
fi

# Create host_config if it doesn't exist
if [ ! -f "$HOME/.ssh/host_config" ]; then
    cat > "$HOME/.ssh/host_config" << 'EOF'
# Host-specific SSH configuration
# Add your host configurations here
EOF
    chmod 600 "$HOME/.ssh/host_config"
    echo "  - Created host_config"
fi

# Shell configuration (optional - DevContainer has its own setup)
# Uncomment if you want to use custom shell config
# ln -snf "$DOTFILES_DIR/config/shell/.bashrc" "$HOME/.bashrc"
# ln -snf "$DOTFILES_DIR/config/shell/.bash_profile" "$HOME/.bash_profile"

# -----------------------------------------------------------------------------
# Claude Code Setup
# -----------------------------------------------------------------------------
if command -v claude &> /dev/null; then
    echo "Claude Code CLI is available"

    # Create Claude config directory
    mkdir -p "$HOME/.claude"

    # Note: MCP servers can be added here if needed
    # claude mcp add context7 -- npx -y @upstash/context7-mcp
    # claude mcp add sequential-thinking -s user -- npx -y @modelcontextprotocol/server-sequential-thinking
fi

# Add SuperClaude Framework
echo "Add SuperClaude Framework..."
uv tool install superclaude
uvx superclaude install
uvx superclaude mcp --servers context7 --servers sequential-thinking --servers serena

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