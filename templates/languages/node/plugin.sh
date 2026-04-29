#!/bin/bash
# =============================================================================
# Template Plugin: node
# This file is meant to be sourced by setup.sh, not executed directly.
# =============================================================================
# This plugin provides Node.js/TypeScript development environment features including:
# - Node.js 22 LTS devcontainer feature
# - pnpm package manager (fast, disk-efficient)
# - VS Code extensions for TypeScript development
# - Biome linter and formatter configuration
# - TypeScript strict mode type checking
# - Vitest test runner with coverage configuration
# - Claude Code hooks for automatic formatting/linting
# - GitHub Actions workflow for quality checks (type check, lint, fmt, tests)
#
# Monorepo split (#263): biome.json, tsconfig.json, package.json,
# src/, and tests/ are per-module (plugin_post_copy_module).
# devcontainer + Claude + post.sh edits are shared at root
# (plugin_post_copy_shared, marker-guarded).
# =============================================================================

# Get the directory where this plugin is located
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

readonly NODE_POSTSH_MARKER="# >>> node (pnpm) post-create >>>"

# =============================================================================
# Required Functions
# =============================================================================

# Return plugin identifier
plugin_name() {
    echo "node"
}

# Return plugin description
plugin_description() {
    echo "Node.js/TypeScript development with pnpm"
}

# =============================================================================
# Hook Functions
# =============================================================================

# Copy GitHub Actions workflow files
plugin_copy() {
    local target_dir="$1"

    print_info "Copying Node.js quality check workflow..."

    # Create .github/workflows directory
    mkdir -p "${target_dir}/.github/workflows"

    # Copy workflow file
    local workflow="${PLUGIN_DIR}/.github/workflows/node-quality-check.yml"
    if [[ -f "$workflow" ]]; then
        local target_file="${target_dir}/.github/workflows/node-quality-check.yml"

        if [[ -f "$target_file" ]]; then
            echo -n "  node-quality-check.yml already exists. Overwrite? (y/n) [n]: "
            if check_tty_available; then
                read -r overwrite < /dev/tty
            else
                overwrite="n"
            fi
            if [[ "$overwrite" != "y" ]]; then
                print_info "Skipping node-quality-check.yml"
                return 0
            fi
        fi

        cp "$workflow" "$target_file"
        print_success "Created node-quality-check.yml"
    fi
}

# Shared root post-copy: devcontainer / claude / post.sh edits.
plugin_post_copy_shared() {
    local target_dir="$1"

    # Merge devcontainer.json features and extensions
    local target_devcontainer="${target_dir}/.devcontainer/devcontainer.json"
    local plugin_devcontainer="${PLUGIN_DIR}/.devcontainer/devcontainer.json"

    if [[ -f "$plugin_devcontainer" ]] && [[ -f "$target_devcontainer" ]]; then
        print_info "Merging Node.js devcontainer features..."
        local temp_file="${target_dir}/.devcontainer/devcontainer.json.tmp"

        merge_devcontainer_json "$target_devcontainer" "$plugin_devcontainer" "$temp_file"
        mv "$temp_file" "$target_devcontainer"

        print_success "Node.js devcontainer features merged"
    fi

    # Merge Claude settings hooks
    local target_settings="${target_dir}/.claude/settings.json"
    local plugin_settings="${PLUGIN_DIR}/.claude/settings.json"

    if [[ -f "$plugin_settings" ]] && [[ -f "$target_settings" ]]; then
        print_info "Merging Node.js Claude settings..."
        local temp_file="${target_dir}/.claude/settings.json.tmp"

        merge_claude_settings_hooks "$target_settings" "$plugin_settings" "$temp_file"
        mv "$temp_file" "$target_settings"

        print_success "Node.js Claude settings merged"
    fi

    # Copy Claude rules files
    local plugin_rules_dir="${PLUGIN_DIR}/.claude/rules"
    local target_rules_dir="${target_dir}/.claude/rules"

    if [[ -d "$plugin_rules_dir" ]]; then
        print_info "Copying TypeScript Claude rules..."
        copy_dir_with_confirm "$plugin_rules_dir" "$target_rules_dir"
        print_success "TypeScript Claude rules copied"
    fi

    # Append Node.js setup commands to post.sh (idempotent via marker, #263).
    local target_post_sh="${target_dir}/.devcontainer/scripts/post.sh"

    if [[ -f "$target_post_sh" ]]; then
        if grep -qF "$NODE_POSTSH_MARKER" "$target_post_sh"; then
            print_info "Node.js post.sh block already present, skipping"
        else
            print_info "Adding Node.js setup to post.sh..."

            cat >> "$target_post_sh" << EOF

${NODE_POSTSH_MARKER}
# -----------------------------------------------------------------------------
# Node.js Development Environment Setup
# -----------------------------------------------------------------------------
if command -v node &> /dev/null; then
    echo "Setting up Node.js development environment..."

    # Install pnpm if not available
    if ! command -v pnpm &> /dev/null; then
        echo "  - Installing pnpm..."
        corepack enable
        corepack prepare pnpm@latest --activate
    fi

    # Install dependencies if package.json exists at the project root
    if [[ -f "package.json" ]]; then
        echo "  - Installing dependencies with pnpm..."
        pnpm install
    fi

    echo "Node.js development environment ready."
    echo "  - Node.js: \$(node --version)"
    echo "  - pnpm: \$(pnpm --version)"
fi
# <<< node (pnpm) post-create <<<
EOF

            print_success "Node.js setup added to post.sh"
        fi
    fi
}

# Module-scoped post-copy: per-module package.json, lint configs, src/, tests/.
plugin_post_copy_module() {
    local target_dir="$1"
    local module_name="$2"

    # Copy tool configuration files
    local tool_configs=("biome.json" "tsconfig.json")
    local config_file
    for config_file in "${tool_configs[@]}"; do
        local source_config="${PLUGIN_DIR}/${config_file}"
        local target_config="${target_dir}/${config_file}"

        if [[ -f "$source_config" ]]; then
            print_info "Copying ${config_file} to ${target_dir}..."
            copy_with_confirm "$source_config" "$target_config"
        fi
    done

    # Create package.json from template (use module_name as the package name)
    local source_package="${PLUGIN_DIR}/package.json.template"
    local target_package="${target_dir}/package.json"

    if [[ -f "$source_package" ]]; then
        print_info "Creating package.json in ${target_dir}..."

        if [[ -f "$target_package" ]] && [[ "$OVERWRITE_ALL" != true ]]; then
            local overwrite="n"
            if check_tty_available; then
                echo -n "  package.json already exists in ${target_dir}. Overwrite? (y/n) [n]: "
                read -r overwrite < /dev/tty
            fi
            if [[ "$overwrite" != "y" ]]; then
                print_info "Skipping package.json in ${target_dir}"
            else
                sed "s/{{PROJECT_NAME}}/${module_name}/g" "$source_package" > "$target_package"
                print_success "Created package.json in ${target_dir}"
            fi
        else
            sed "s/{{PROJECT_NAME}}/${module_name}/g" "$source_package" > "$target_package"
            print_success "Created package.json in ${target_dir}"
        fi
    fi

    # Create source and tests directory structure
    print_info "Creating project directory structure in ${target_dir}..."
    mkdir -p "${target_dir}/src"
    mkdir -p "${target_dir}/tests/unit"
    mkdir -p "${target_dir}/tests/integration"
    mkdir -p "${target_dir}/tests/e2e"

    # Create a sample src/index.ts (skip if existing)
    if [[ ! -f "${target_dir}/src/index.ts" ]]; then
        cat > "${target_dir}/src/index.ts" << 'EOF'
/**
 * Main entry point for the application.
 */

export function main(): void {
  console.log("Hello, World!");
}

main();
EOF
    fi

    # Create a sample test file (skip if existing)
    if [[ ! -f "${target_dir}/tests/unit/index.test.ts" ]]; then
        cat > "${target_dir}/tests/unit/index.test.ts" << 'EOF'
import { describe, expect, it } from "vitest";

describe("sample", () => {
  it("should pass", () => {
    expect(true).toBe(true);
  });
});
EOF
    fi

    print_success "Node.js module scaffold created in ${target_dir}"
}

# Backward-compat shim.
plugin_post_copy() {
    local target_dir="$1"
    plugin_post_copy_shared "$target_dir"
    plugin_post_copy_module "$target_dir" "${PROJECT_NAME}"
}
