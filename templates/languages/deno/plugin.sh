#!/bin/bash
# =============================================================================
# Template Plugin: deno
# This file is meant to be sourced by setup.sh, not executed directly.
# =============================================================================
# This plugin provides Deno development environment features including:
# - Deno 2.x (latest) devcontainer feature
# - Built-in formatter (deno fmt) configuration
# - Built-in linter (deno lint) configuration
# - Built-in test runner (deno test) with coverage
# - VS Code extension for Deno development
# - Claude Code hooks for automatic formatting
# - GitHub Actions workflow for quality checks (type check, lint, fmt, tests)
#
# Monorepo split (#263): deno.json, src/, tests/ are per-module
# (plugin_post_copy_module). devcontainer + Claude + post.sh edits are
# shared at root (plugin_post_copy_shared, marker-guarded).
# =============================================================================

# Get the directory where this plugin is located
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DENO_POSTSH_MARKER="# >>> deno post-create >>>"

# =============================================================================
# Required Functions
# =============================================================================

# Return plugin identifier
plugin_name() {
    echo "deno"
}

# Return plugin description
plugin_description() {
    echo "Deno development environment with built-in toolchain"
}

# =============================================================================
# Hook Functions
# =============================================================================

# Copy GitHub Actions workflow files
plugin_copy() {
    local target_dir="$1"

    print_info "Copying Deno quality check workflow..."

    # Create .github/workflows directory
    mkdir -p "${target_dir}/.github/workflows"

    # Copy workflow file
    local workflow="${PLUGIN_DIR}/.github/workflows/deno-quality-check.yml"
    if [[ -f "$workflow" ]]; then
        local target_file="${target_dir}/.github/workflows/deno-quality-check.yml"

        if [[ -f "$target_file" ]]; then
            echo -n "  deno-quality-check.yml already exists. Overwrite? (y/n) [n]: "
            if check_tty_available; then
                read -r overwrite < /dev/tty
            else
                overwrite="n"
            fi
            if [[ "$overwrite" != "y" ]]; then
                print_info "Skipping deno-quality-check.yml"
                return 0
            fi
        fi

        OVERWRITE_ALL=true copy_with_confirm "$workflow" "$target_file"
        print_success "Created deno-quality-check.yml"
    fi
}

# Shared root post-copy: devcontainer / claude / post.sh edits.
plugin_post_copy_shared() {
    local target_dir="$1"

    # Merge devcontainer.json features and extensions
    local target_devcontainer="${target_dir}/.devcontainer/devcontainer.json"
    local plugin_devcontainer="${PLUGIN_DIR}/.devcontainer/devcontainer.json"

    if [[ -f "$plugin_devcontainer" ]] && [[ -f "$target_devcontainer" ]]; then
        print_info "Merging Deno devcontainer features..."
        local temp_file="${target_dir}/.devcontainer/devcontainer.json.tmp"

        merge_devcontainer_json "$target_devcontainer" "$plugin_devcontainer" "$temp_file"
        mv "$temp_file" "$target_devcontainer"

        print_success "Deno devcontainer features merged"
    fi

    # Merge Claude settings hooks
    local target_settings="${target_dir}/.claude/settings.json"
    local plugin_settings="${PLUGIN_DIR}/.claude/settings.json"

    if [[ -f "$plugin_settings" ]] && [[ -f "$target_settings" ]]; then
        print_info "Merging Deno Claude settings..."
        local temp_file="${target_dir}/.claude/settings.json.tmp"

        merge_claude_settings_hooks "$target_settings" "$plugin_settings" "$temp_file"
        mv "$temp_file" "$target_settings"

        print_success "Deno Claude settings merged"
    fi

    # Copy Claude rules files
    local plugin_rules_dir="${PLUGIN_DIR}/.claude/rules"
    local target_rules_dir="${target_dir}/.claude/rules"

    if [[ -d "$plugin_rules_dir" ]]; then
        print_info "Copying Deno Claude rules..."
        copy_dir_with_confirm "$plugin_rules_dir" "$target_rules_dir"
        print_success "Deno Claude rules copied"
    fi

    # Append Deno setup commands to post.sh. Markers + idempotency check
    # only in monorepo / add-module mode (NFR-1).
    local target_post_sh="${target_dir}/.devcontainer/scripts/post.sh"

    if [[ -f "$target_post_sh" ]]; then
        local use_marker=false
        if [[ "${MONOREPO_MODE:-false}" == true ]] || [[ "${IS_ADD_MODULE_MODE:-false}" == true ]]; then
            use_marker=true
            if grep -qF "$DENO_POSTSH_MARKER" "$target_post_sh"; then
                print_info "Deno post.sh block already present, skipping"
                return
            fi
        fi

        print_info "Adding Deno setup to post.sh..."

        if [[ "$use_marker" == true ]]; then
            cat >> "$target_post_sh" << EOF

${DENO_POSTSH_MARKER}
# -----------------------------------------------------------------------------
# Deno Development Environment Setup
# -----------------------------------------------------------------------------
if command -v deno &> /dev/null; then
    echo "Setting up Deno development environment..."

    # Cache dependencies if deno.json exists at the project root
    if [[ -f "deno.json" ]]; then
        echo "  - Caching dependencies..."
        deno install
    fi

    echo "Deno development environment ready."
    echo "  - Deno: \$(deno --version | head -1)"
fi
# <<< deno post-create <<<
EOF
        else
            # Pre-#263 single-mode block (no markers).
            cat >> "$target_post_sh" << 'EOF'

# -----------------------------------------------------------------------------
# Deno Development Environment Setup
# -----------------------------------------------------------------------------
if command -v deno &> /dev/null; then
    echo "Setting up Deno development environment..."

    # Cache dependencies if deno.json exists
    if [[ -f "deno.json" ]]; then
        echo "  - Caching dependencies..."
        deno install
    fi

    echo "Deno development environment ready."
    echo "  - Deno: $(deno --version | head -1)"
fi
EOF
        fi

        print_success "Deno setup added to post.sh"
    fi
}

# Module-scoped post-copy: per-module deno.json, src/, tests/.
plugin_post_copy_module() {
    local target_dir="$1"
    local _module_name="$2"   # currently unused; kept for contract symmetry

    # Copy deno.json configuration
    local source_deno_json="${PLUGIN_DIR}/deno.json"
    local target_deno_json="${target_dir}/deno.json"

    if [[ -f "$source_deno_json" ]]; then
        print_info "Copying deno.json to ${target_dir}..."
        copy_with_confirm "$source_deno_json" "$target_deno_json"
    fi

    # Create source and tests directory structure
    print_info "Creating project directory structure in ${target_dir}..."
    mkdir -p "${target_dir}/src"
    mkdir -p "${target_dir}/tests/unit"
    mkdir -p "${target_dir}/tests/integration"
    mkdir -p "${target_dir}/tests/e2e"

    # Create a sample src/main.ts (skip if existing)
    if [[ ! -f "${target_dir}/src/main.ts" ]]; then
        cat > "${target_dir}/src/main.ts" << 'EOF'
/**
 * Main entry point for the application.
 */

export function main(): void {
  console.log("Hello, World!");
}

if (import.meta.main) {
  main();
}
EOF
    fi

    # Create a sample test file (skip if existing)
    if [[ ! -f "${target_dir}/tests/unit/main_test.ts" ]]; then
        cat > "${target_dir}/tests/unit/main_test.ts" << 'EOF'
import { assertEquals } from "jsr:@std/assert";
import { main } from "../../src/main.ts";

Deno.test("main runs without error", () => {
  main();
});

Deno.test("sample assertion", () => {
  assertEquals(1 + 1, 2);
});
EOF
    fi

    print_success "Deno module scaffold created in ${target_dir}"
}

# Backward-compat shim.
plugin_post_copy() {
    local target_dir="$1"
    plugin_post_copy_shared "$target_dir"
    plugin_post_copy_module "$target_dir" "${PROJECT_NAME}"
}
