#!/bin/bash
# =============================================================================
# Template Plugin: python
# This file is meant to be sourced by setup.sh, not executed directly.
# =============================================================================
# This plugin provides Python development environment features including:
# - Python 3.12 and the uv package manager (fast, Rust-based), declared in
#   mise.toml (no devcontainer feature, no Dockerfile.dev edits; the former
#   Dockerfile ENV block now lives in mise.toml [env])
# - VS Code extensions for Python development
# - ruff linter and formatter configuration
# - mypy type checker configuration
# - pytest with coverage configuration
# - Claude Code hooks for automatic formatting/linting
# - GitHub Actions workflow for quality checks (type check, lint, fmt, tests)
#
# In monorepo mode (#263) plugin_post_copy is dispatched as
# plugin_post_copy_shared(root) once + plugin_post_copy_module(<module>, name)
# per matching module. The legacy plugin_post_copy entry point is kept as a
# backward-compat shim that calls both with PROJECT_NAME as the module name.
# =============================================================================

# Get the directory where this plugin is located
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Marker for idempotent inserts (#263). Plain assignments because plugins
# may be sourced multiple times by setup.sh — `readonly` would fail on
# the second source.
PYTHON_POSTSH_MARKER="# >>> python (uv) post-create >>>"

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

        OVERWRITE_ALL=true copy_with_confirm "$workflow" "$target_file"
        print_success "Created python-quality-check.yml"
    fi
}

# -----------------------------------------------------------------------------
# Shared (root) post-copy hook (#263).
# Called once per loaded plugin in monorepo mode; in single mode invoked via
# the plugin_post_copy shim with target_dir = project root.
# -----------------------------------------------------------------------------
plugin_post_copy_shared() {
    local target_dir="$1"

    # Runtime versions live in mise.toml (#325). Existing entries are never
    # changed. Runs before any early return below so re-runs and --add-module
    # stay idempotent.
    mise_toml_ensure "${target_dir}/mise.toml" tools python '"3.12"' \
        || print_warning "Could not add tools.python to mise.toml"
    mise_toml_ensure "${target_dir}/mise.toml" tools uv '"0.13.6"' \
        || print_warning "Could not add tools.uv to mise.toml"
    mise_toml_ensure "${target_dir}/mise.toml" env UV_PYTHON '{ value = "{{ tools.python.path }}", tools = true }' \
        || print_warning "Could not add env.UV_PYTHON to mise.toml"
    mise_toml_ensure "${target_dir}/mise.toml" env PYTHONDONTWRITEBYTECODE '"1"' \
        || print_warning "Could not add env.PYTHONDONTWRITEBYTECODE to mise.toml"
    mise_toml_ensure "${target_dir}/mise.toml" env PYTHONUNBUFFERED '"1"' \
        || print_warning "Could not add env.PYTHONUNBUFFERED to mise.toml"
    mise_toml_ensure "${target_dir}/mise.toml" env UV_COMPILE_BYTECODE '"1"' \
        || print_warning "Could not add env.UV_COMPILE_BYTECODE to mise.toml"
    mise_toml_ensure "${target_dir}/mise.toml" env UV_LINK_MODE '"copy"' \
        || print_warning "Could not add env.UV_LINK_MODE to mise.toml"

    # Merge devcontainer.json customizations (extensions and settings)
    local target_devcontainer="${target_dir}/.devcontainer/devcontainer.json"
    local plugin_devcontainer="${PLUGIN_DIR}/.devcontainer/devcontainer.json"

    if [[ -f "$plugin_devcontainer" ]] && [[ -f "$target_devcontainer" ]]; then
        print_info "Merging Python devcontainer customizations..."
        local temp_file="${target_dir}/.devcontainer/devcontainer.json.tmp"

        merge_devcontainer_json "$target_devcontainer" "$plugin_devcontainer" "$temp_file"
        mv "$temp_file" "$target_devcontainer"

        print_success "Python devcontainer customizations merged"
    fi

    # Zed editor assets (no-op unless --zed was selected). Placed before the
    # post.sh marker branch below, which can `return` early on a re-run.
    apply_zed_assets "$target_dir" "$PLUGIN_DIR"

    # Merge Claude settings hooks
    local target_settings="${target_dir}/.claude/settings.json"
    local plugin_settings="${PLUGIN_DIR}/.claude/settings.json"

    if [[ -f "$plugin_settings" ]] && [[ -f "$target_settings" ]]; then
        print_info "Merging Python Claude settings..."
        local temp_file="${target_dir}/.claude/settings.json.tmp"

        merge_claude_settings_hooks "$target_settings" "$plugin_settings" "$temp_file"
        mv "$temp_file" "$target_settings"

        print_success "Python Claude settings merged"
    fi

    # Copy Claude rules files
    local plugin_rules_dir="${PLUGIN_DIR}/.claude/rules"
    local target_rules_dir="${target_dir}/.claude/rules"

    if [[ -d "$plugin_rules_dir" ]]; then
        print_info "Copying Python Claude rules..."
        copy_dir_with_confirm "$plugin_rules_dir" "$target_rules_dir"
        print_success "Python Claude rules copied"
    fi

    # Append Python setup block to post.sh. Markers + idempotency check
    # only apply in monorepo / add-module mode (NFR-1 keeps single-mode
    # output byte-identical to pre-#263).
    local target_post_sh="${target_dir}/.devcontainer/scripts/post.sh"

    if [[ -f "$target_post_sh" ]]; then
        local use_marker=false
        if [[ "${MONOREPO_MODE:-false}" == true ]] || [[ "${IS_ADD_MODULE_MODE:-false}" == true ]]; then
            use_marker=true
            if grep -qF "$PYTHON_POSTSH_MARKER" "$target_post_sh"; then
                print_info "Python post.sh block already present, skipping"
                return
            fi
        fi

        print_info "Adding Python setup to post.sh..."

        if [[ "$use_marker" == true ]]; then
            cat >> "$target_post_sh" << EOF

${PYTHON_POSTSH_MARKER}
# -----------------------------------------------------------------------------
# Python Development Environment Setup
# -----------------------------------------------------------------------------
if command -v uv &> /dev/null; then
    echo "Setting up Python development environment..."

    # Create virtual environment if it doesn't exist (single-project layout)
    if [[ ! -d ".venv" ]] && [[ -f "pyproject.toml" ]]; then
        echo "  - Creating virtual environment with uv..."
        uv venv --prompt {{PROJECT_NAME}}
    fi

    # Install dependencies if pyproject.toml exists
    if [[ -f "pyproject.toml" ]]; then
        echo "  - Installing dependencies..."
        uv pip install -e ".[dev]"
    fi

    echo "Python development environment ready."
fi
# <<< python (uv) post-create <<<
EOF
        else
            # Pre-#263 single-mode block (no markers, no .venv guard) —
            # preserves byte-identical output for NFR-1.
            cat >> "$target_post_sh" << 'EOF'

# -----------------------------------------------------------------------------
# Python Development Environment Setup
# -----------------------------------------------------------------------------
if command -v uv &> /dev/null; then
    echo "Setting up Python development environment..."

    # Create virtual environment if it doesn't exist
    if [[ ! -d ".venv" ]]; then
        echo "  - Creating virtual environment with uv..."
        uv venv --prompt {{PROJECT_NAME}}
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
        fi

        print_success "Python setup added to post.sh"
    fi
}

# -----------------------------------------------------------------------------
# Module-scoped post-copy hook (#263).
# Called once per matching module in monorepo mode. In single mode, called
# via the shim with target_dir = project root and module_name = PROJECT_NAME.
# -----------------------------------------------------------------------------
plugin_post_copy_module() {
    local target_dir="$1"
    local module_name="$2"

    # Copy ruff.toml configuration
    local source_ruff="${PLUGIN_DIR}/ruff.toml"
    local target_ruff="${target_dir}/ruff.toml"

    if [[ -f "$source_ruff" ]]; then
        print_info "Copying ruff.toml to ${target_dir}..."
        copy_with_confirm "$source_ruff" "$target_ruff"
    fi

    # Create pyproject.toml from template (substituting module name for the
    # package id; in single mode module_name == PROJECT_NAME).
    local source_pyproject="${PLUGIN_DIR}/pyproject.toml.template"
    local target_pyproject="${target_dir}/pyproject.toml"

    if [[ -f "$source_pyproject" ]]; then
        print_info "Creating pyproject.toml in ${target_dir}..."

        if [[ -f "$target_pyproject" ]] && [[ "$OVERWRITE_ALL" != true ]]; then
            local overwrite="n"
            if check_tty_available; then
                echo -n "  pyproject.toml already exists in ${target_dir}. Overwrite? (y/n) [n]: "
                read -r overwrite < /dev/tty
            fi
            if [[ "$overwrite" != "y" ]]; then
                print_info "Skipping pyproject.toml in ${target_dir}"
            else
                sed "s/{{PROJECT_NAME}}/${module_name}/g" "$source_pyproject" > "$target_pyproject"
                print_success "Created pyproject.toml in ${target_dir}"
            fi
        else
            sed "s/{{PROJECT_NAME}}/${module_name}/g" "$source_pyproject" > "$target_pyproject"
            print_success "Created pyproject.toml in ${target_dir}"
        fi
    fi

    # Create tests directory structure
    print_info "Creating tests directory structure in ${target_dir}..."
    mkdir -p "${target_dir}/tests/unit"
    mkdir -p "${target_dir}/tests/integration"
    mkdir -p "${target_dir}/tests/e2e"

    touch "${target_dir}/tests/__init__.py"
    touch "${target_dir}/tests/unit/__init__.py"
    touch "${target_dir}/tests/integration/__init__.py"
    touch "${target_dir}/tests/e2e/__init__.py"

    # Create conftest.py for pytest if absent
    if [[ ! -f "${target_dir}/tests/conftest.py" ]]; then
        cat > "${target_dir}/tests/conftest.py" << 'EOF'
"""Pytest configuration and fixtures."""

import pytest


@pytest.fixture
def sample_fixture():
    """Sample fixture for demonstration."""
    return {"key": "value"}
EOF
    fi

    # Create src/<module_name>/ skeleton
    mkdir -p "${target_dir}/src/${module_name}"
    touch "${target_dir}/src/${module_name}/__init__.py"

    if [[ ! -f "${target_dir}/src/${module_name}/__main__.py" ]]; then
        cat > "${target_dir}/src/${module_name}/__main__.py" << 'EOF'
"""Main entry point for the application."""


def main() -> None:
    """Main function."""
    print("Hello, World!")


if __name__ == "__main__":
    main()
EOF
    fi

    print_success "Python module scaffold created in ${target_dir}"
}

# Backward-compat shim: in single-mode (or when called by an old orchestrator)
# this performs the full post-copy, which is identical to the pre-#263 body.
plugin_post_copy() {
    local target_dir="$1"
    plugin_post_copy_shared "$target_dir"
    plugin_post_copy_module "$target_dir" "${PROJECT_NAME}"
}
