#!/bin/bash
# =============================================================================
# Template Plugin: python
# This file is meant to be sourced by setup.sh, not executed directly.
# =============================================================================
# This plugin provides Python development environment features including:
# - Python 3.12 devcontainer feature
# - uv package manager (fast, Rust-based)
# - VS Code extensions for Python development
# - ruff linter and formatter configuration
# - mypy type checker configuration
# - pytest with coverage configuration
# - Claude Code hooks for automatic formatting/linting
# - GitHub Actions workflow for quality checks (type check, lint, fmt, tests)
#
# =============================================================================

# Get the directory where this plugin is located
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# Required Functions
# =============================================================================

# Return plugin identifier
plugin_name() {
    echo "python"
}

# Return plugin description
plugin_description() {
    echo "Python development environment with uv"
}

# =============================================================================
# Hook Functions
# =============================================================================

# Copy GitHub Actions workflow files
plugin_copy() {
    local target_dir="$1"

    print_info "Copying Python quality check workflow..."

    # Create .github/workflows directory
    mkdir -p "${target_dir}/.github/workflows"

    # Copy workflow file
    local workflow="${PLUGIN_DIR}/.github/workflows/python-quality-check.yml"
    if [[ -f "$workflow" ]]; then
        local target_file="${target_dir}/.github/workflows/python-quality-check.yml"

        if [[ -f "$target_file" ]]; then
            echo -n "  python-quality-check.yml already exists. Overwrite? (y/n) [n]: "
            if check_tty_available; then
                read -r overwrite < /dev/tty
            else
                overwrite="n"
            fi
            if [[ "$overwrite" != "y" ]]; then
                print_info "Skipping python-quality-check.yml"
                return 0
            fi
        fi

        cp "$workflow" "$target_file"
        print_success "Created python-quality-check.yml"
    fi
}

# Post-copy processing - merge devcontainer.json, settings.json, and copy tool configs
plugin_post_copy() {
    local target_dir="$1"

    # Merge devcontainer.json features and extensions
    local target_devcontainer="${target_dir}/.devcontainer/devcontainer.json"
    local plugin_devcontainer="${PLUGIN_DIR}/.devcontainer/devcontainer.json"

    if [[ -f "$plugin_devcontainer" ]] && [[ -f "$target_devcontainer" ]]; then
        print_info "Merging Python devcontainer features..."
        local temp_file="${target_dir}/.devcontainer/devcontainer.json.tmp"

        # Merge devcontainer.json with special handling for features and extensions
        merge_devcontainer_json "$target_devcontainer" "$plugin_devcontainer" "$temp_file"
        mv "$temp_file" "$target_devcontainer"

        print_success "Python devcontainer features merged"
    fi

    # Merge Claude settings hooks
    local target_settings="${target_dir}/.claude/settings.json"
    local plugin_settings="${PLUGIN_DIR}/.claude/settings.json"

    if [[ -f "$plugin_settings" ]] && [[ -f "$target_settings" ]]; then
        print_info "Merging Python Claude settings..."
        local temp_file="${target_dir}/.claude/settings.json.tmp"

        # Merge settings with hook array concatenation
        merge_claude_settings_hooks "$target_settings" "$plugin_settings" "$temp_file"
        mv "$temp_file" "$target_settings"

        print_success "Python Claude settings merged"
    fi

    # Copy ruff.toml configuration
    local source_ruff="${PLUGIN_DIR}/ruff.toml"
    local target_ruff="${target_dir}/ruff.toml"

    if [[ -f "$source_ruff" ]]; then
        print_info "Copying ruff.toml..."
        copy_with_confirm "$source_ruff" "$target_ruff"
    fi

    # Create pyproject.toml from template
    local source_pyproject="${PLUGIN_DIR}/pyproject.toml.template"
    local target_pyproject="${target_dir}/pyproject.toml"

    if [[ -f "$source_pyproject" ]]; then
        print_info "Creating pyproject.toml..."

        if [[ -f "$target_pyproject" ]]; then
            echo -n "  pyproject.toml already exists. Overwrite? (y/n) [n]: "
            if check_tty_available; then
                read -r overwrite < /dev/tty
            else
                overwrite="n"
            fi
            if [[ "$overwrite" != "y" ]]; then
                print_info "Skipping pyproject.toml"
            else
                # Replace PROJECT_NAME placeholder with actual project name
                sed "s/{{PROJECT_NAME}}/${PROJECT_NAME}/g" "$source_pyproject" > "$target_pyproject"
                print_success "Created pyproject.toml"
            fi
        else
            sed "s/{{PROJECT_NAME}}/${PROJECT_NAME}/g" "$source_pyproject" > "$target_pyproject"
            print_success "Created pyproject.toml"
        fi
    fi

    # Create tests directory structure
    print_info "Creating tests directory structure..."
    mkdir -p "${target_dir}/tests/unit"
    mkdir -p "${target_dir}/tests/integration"
    mkdir -p "${target_dir}/tests/e2e"

    # Create __init__.py files
    touch "${target_dir}/tests/__init__.py"
    touch "${target_dir}/tests/unit/__init__.py"
    touch "${target_dir}/tests/integration/__init__.py"
    touch "${target_dir}/tests/e2e/__init__.py"

    # Create conftest.py for pytest
    cat > "${target_dir}/tests/conftest.py" << 'EOF'
"""Pytest configuration and fixtures."""

import pytest


@pytest.fixture
def sample_fixture():
    """Sample fixture for demonstration."""
    return {"key": "value"}
EOF

    print_success "Tests directory structure created"

    # Append Python setup commands to post.sh
    local target_post_sh="${target_dir}/.devcontainer/scripts/post.sh"

    if [[ -f "$target_post_sh" ]]; then
        print_info "Adding Python setup to post.sh..."

        cat >> "$target_post_sh" << 'EOF'

# -----------------------------------------------------------------------------
# Python Development Environment Setup
# -----------------------------------------------------------------------------
if command -v uv &> /dev/null; then
    echo "Setting up Python development environment..."

    # Create virtual environment if it doesn't exist
    if [[ ! -d ".venv" ]]; then
        echo "  - Creating virtual environment with uv..."
        uv venv
    fi

    # Install dependencies if pyproject.toml exists
    if [[ -f "pyproject.toml" ]]; then
        echo "  - Installing dependencies..."
        uv pip install -e ".[dev]"
    fi

    echo "Python development environment ready."
    echo "  - Virtual environment: .venv"
    echo "  - Activate: source .venv/bin/activate"
fi
EOF

        print_success "Python setup added to post.sh"
    fi

    # Create src directory with __init__.py
    mkdir -p "${target_dir}/src/${PROJECT_NAME}"
    touch "${target_dir}/src/${PROJECT_NAME}/__init__.py"

    # Create a sample main.py
    cat > "${target_dir}/src/${PROJECT_NAME}/__main__.py" << 'EOF'
"""Main entry point for the application."""


def main() -> None:
    """Main function."""
    print("Hello, World!")


if __name__ == "__main__":
    main()
EOF

    print_success "Created src directory structure"
}
