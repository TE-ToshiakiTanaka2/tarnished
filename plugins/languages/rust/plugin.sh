#!/bin/sh
# =============================================================================
# Rust Language Plugin
# =============================================================================
# Provides Rust development environment with rust-analyzer and common tools.

# Return devcontainer features JSON object
get_features() {
    cat << 'EOF'
    "ghcr.io/devcontainers/features/rust:1": {
      "version": "${PLUGIN_VAR_RUST_VERSION:-stable}",
      "profile": "default"
    }
EOF
}

# Return VSCode extensions JSON array
get_extensions() {
    cat << 'EOF'
        "rust-lang.rust-analyzer",
        "tamasfe.even-better-toml",
        "serayuzgur.crates"
EOF
}

# Return Dockerfile RUN commands
get_dockerfile_extras() {
    cat << 'EOF'
# Rust development dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    pkg-config \
    libssl-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
EOF
}

# Return post.sh setup script
get_post_setup() {
    # Use environment variables set during configuration
    version="${PLUGIN_VAR_RUST_VERSION:-stable}"
    components="${PLUGIN_VAR_RUST_COMPONENTS:-clippy rustfmt}"
    tools="${PLUGIN_VAR_CARGO_TOOLS:-cargo-watch cargo-edit}"

    cat << EOF
# -----------------------------------------------------------------------------
# Rust Setup
# -----------------------------------------------------------------------------
setup_rust() {
    echo "Setting up Rust development environment..."

    # Install rustup if not present
    if ! command -v rustup &> /dev/null; then
        echo "  - Installing rustup..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain $version
        . "\$HOME/.cargo/env"
    fi

    # Set default toolchain
    echo "  - Setting default toolchain to $version"
    rustup default $version

    # Install components
    echo "  - Installing components: $components"
    for component in $components; do
        rustup component add \$component 2>/dev/null || echo "    Warning: Could not install \$component"
    done

    # Install cargo tools
    echo "  - Installing cargo tools: $tools"
    for tool in $tools; do
        if ! command -v \$tool &> /dev/null; then
            cargo install \$tool 2>/dev/null || echo "    Warning: Could not install \$tool"
        fi
    done

    echo "  - Rust setup complete"
    rustc --version
    cargo --version
}
setup_rust
EOF
}

# Return Claude Code hooks JSON array
get_hooks() {
    cat << 'EOF'
      {
        "matcher": "Write(*.rs)",
        "hooks": [
          {
            "type": "command",
            "command": "cargo fmt -- --check $CLAUDE_FILE_PATH 2>/dev/null || true"
          }
        ]
      }
EOF
}
