#!/bin/bash
# =============================================================================
# DevContainer Post-Create Script
# =============================================================================

set -e

echo "Running post-creation setup script..."

# -----------------------------------------------------------------------------
# Git Configuration
# -----------------------------------------------------------------------------
echo "Setting up Git configuration..."

# Create .gitconfig.local if it doesn't exist
if [ ! -f "$HOME/.gitconfig.local" ]; then
    cat > "$HOME/.gitconfig.local" << 'EOF'
[user]
    # name = Your Name
    # email = your.email@example.com
EOF
    echo "  - Created .gitconfig.local (edit to set your name/email)"
fi

# -----------------------------------------------------------------------------
# SSH Configuration
# -----------------------------------------------------------------------------
echo "Setting up SSH configuration..."

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# Create host_config if it doesn't exist
if [ ! -f "$HOME/.ssh/host_config" ]; then
    cat > "$HOME/.ssh/host_config" << 'EOF'
# Host-specific SSH configuration
# Add your host configurations here
EOF
    chmod 600 "$HOME/.ssh/host_config"
    echo "  - Created host_config"
fi

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
