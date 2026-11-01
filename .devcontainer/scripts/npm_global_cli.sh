#!/bin/bash
# =============================================================================
# Shared npm global CLI installer
# =============================================================================
# Library sourced by setup_claude.sh and setup_codex.sh. It defines only
# install_npm_global_cli and is not called from post.sh directly.
#
# Under a mise-managed Node, `npm install -g` writes into that Node version's
# own prefix (inside the mise data directory, owned by the current user), so
# no sudo is ever needed. A Node version bump therefore removes the CLIs until
# this runs again, which is why post.sh runs the mise block first.
#
# Like every post.sh helper it runs under `set -e`: it always returns 0, logs
# [WARN] with a recovery hint, and never calls sudo.
# =============================================================================

# Install an npm-distributed CLI globally when it does not already run.
# Usage: install_npm_global_cli <display_name> <package_spec> <command>
install_npm_global_cli() {
    local display_name="$1"
    local package_spec="$2"
    local command_name="$3"

    echo "Setting up ${display_name}..."

    # Run the command instead of trusting `command -v`: after a Node bump the
    # old shim still exists but fails for the newly selected Node.
    local version=""
    if version="$("$command_name" --version 2>/dev/null)"; then
        echo "  - ${display_name} already installed: ${version%%$'\n'*}"
        return 0
    fi

    if ! command -v npm &> /dev/null; then
        echo "  [WARN] npm not found. Skipping ${display_name} installation."
        echo "  Install Node.js first (mise install), then run: npm install -g ${package_spec}"
        return 0
    fi

    local prefix=""
    prefix="$(npm prefix -g 2>/dev/null || true)"
    if [[ -n "$prefix" ]] && [[ -d "$prefix" ]] && [[ ! -w "$prefix" ]]; then
        echo "  [WARN] The global npm prefix ${prefix} is not writable; sudo is never used."
        echo "  Install Node.js through mise (mise use node@22) and run: npm install -g ${package_spec}"
        return 0
    fi

    echo "  - Installing ${display_name}..."
    if ! npm install -g "$package_spec"; then
        echo "  [WARN] Failed to install ${display_name} (network error or npm issue)"
        echo "  You can install it manually later: npm install -g ${package_spec}"
        return 0
    fi

    hash -r
    if ! "$command_name" --version &> /dev/null && command -v mise &> /dev/null; then
        mise reshim &> /dev/null || true
        hash -r
    fi

    if "$command_name" --version &> /dev/null; then
        echo "  - ${display_name} installed successfully"
    else
        echo "  [WARN] ${display_name} was installed but '${command_name}' is not on PATH"
        echo "  Run 'mise reshim' or open a new shell, then check: ${command_name} --version"
    fi
    return 0
}
