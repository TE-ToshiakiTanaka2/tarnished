#!/bin/bash
# =============================================================================
# Claude Code Plugin Setup Script
# =============================================================================
# This script installs Claude Code official plugins.
# It is sourced by post.sh during devcontainer initialization.
#
# Installs the following plugins:
# - context7: Library documentation lookup
# - serena: Semantic code navigation and analysis
# - playwright: Browser automation for e2e testing (optional, interactive only)
#
# Prerequisites:
# - Claude Code CLI
#
# Failure policy:
#   `setup_plugins` is best-effort: marketplace or plugin install failures are
#   reported as warnings and do NOT abort post.sh (which runs under `set -e`).
#   On a fresh container where `claude` has never been logged in, the
#   `is_claude_authenticated` pre-flight gate skips the entire flow with a
#   one-line guidance message so post.sh proceeds to subsequent steps (#273).
# =============================================================================

# Returns 0 iff `claude` has been logged in at least once on this machine,
# detected by the presence of a non-empty OAuth credentials file. Pure read-only
# check — no subprocess, no network — added in #273 to prevent first-run
# `claude plugins ...` calls from tripping `set -e` in post.sh.
is_claude_authenticated() {
    [[ -s "$HOME/.claude/.credentials.json" ]]
}

# Ensure the given marketplace (GitHub <owner>/<repo>) is registered in
# ~/.claude/plugins/known_marketplaces.json. Idempotent.
#
# Returns 0 if already registered or newly added, 1 on add failure.
ensure_claude_marketplace() {
    local marketplace_repo="$1"
    local marketplace_name="${marketplace_repo##*/}"

    if claude plugins marketplace list 2>/dev/null | grep -q "${marketplace_name}"; then
        echo "  - Marketplace ${marketplace_name} already registered, skipping"
        return 0
    fi

    echo "  - Registering marketplace ${marketplace_repo}..."
    if claude plugins marketplace add "${marketplace_repo}"; then
        echo "  - Marketplace ${marketplace_name} registered"
        return 0
    fi

    echo "  - Warning: failed to register marketplace ${marketplace_repo}" >&2
    return 1
}

# Install a single plugin from the given marketplace if not already installed.
# Always returns 0 so a single plugin failure does not abort the caller.
try_install_plugin() {
    local plugin_name="$1"
    local marketplace="$2"
    local plugins_output="$3"

    if echo "${plugins_output}" | grep -q "${plugin_name}"; then
        echo "  - ${plugin_name} already installed, skipping"
        return 0
    fi

    echo "  - Installing ${plugin_name} plugin..."
    if claude plugins install "${plugin_name}@${marketplace}" -s project; then
        echo "  - ${plugin_name} plugin installed"
    else
        echo "  - Warning: failed to install ${plugin_name} plugin" >&2
    fi
    return 0
}

setup_plugins() {
    echo "Setting up Claude Code plugins..."

    # Check Claude Code prerequisite
    if ! command -v claude &> /dev/null; then
        echo "  - Warning: Claude Code CLI is not installed"
        echo "  - Plugin setup requires Claude Code"
        echo "  - Skipping plugin setup"
        return 0
    fi

    # Pre-flight: skip cleanly when `claude` has never been logged in (#273).
    # Without this gate, every `claude plugins ...` call would fail with a
    # non-zero exit on first-run containers and (under `set -e` in post.sh)
    # abort the rest of the post-create flow.
    if ! is_claude_authenticated; then
        echo "  - Claude Code CLI detected, but not yet authenticated"
        echo "  - To install Claude plugins, run \`claude\` to log in,"
        echo "    then re-run .devcontainer/scripts/setup_plugins.sh"
        echo "  - Skipping plugin setup"
        return 0
    fi

    echo "  - Claude Code CLI detected"

    # Marketplace add is a hard prerequisite for any subsequent install.
    # If it fails, skip plugin install but still return 0 so post.sh continues.
    if ! ensure_claude_marketplace "anthropics/claude-plugins-official"; then
        echo "  - Skipping plugin installation due to marketplace registration failure"
        return 0
    fi

    # Wrap `claude plugins list` in an `if`-guard so a failed command
    # substitution cannot trip `set -e` in post.sh — symmetric with the
    # marketplace registration failure path above (#273 review).
    local plugins_output
    if ! plugins_output=$(claude plugins list 2>/dev/null); then
        echo "  - Warning: failed to query installed plugins; skipping plugin install" >&2
        return 0
    fi

    # -----------------------------------------------------------------
    # context7: Library documentation lookup
    # -----------------------------------------------------------------
    try_install_plugin "context7" "claude-plugins-official" "${plugins_output}"

    # -----------------------------------------------------------------
    # serena: Semantic code navigation
    # -----------------------------------------------------------------
    try_install_plugin "serena" "claude-plugins-official" "${plugins_output}"

    # -----------------------------------------------------------------
    # playwright: Browser automation (optional, interactive prompt)
    # -----------------------------------------------------------------
    if echo "${plugins_output}" | grep -q "playwright"; then
        echo "  - playwright already installed, skipping"
    elif type is_interactive &>/dev/null && is_interactive; then
        read -rp "  - Install Playwright plugin for browser testing? (y/N): " playwright_answer
        case "${playwright_answer}" in
            [yY]|[yY][eE][sS])
                try_install_plugin "playwright" "claude-plugins-official" "${plugins_output}"
                ;;
            *)
                echo "  - Skipping playwright plugin"
                ;;
        esac
    else
        echo "  - Non-interactive environment, skipping playwright plugin prompt"
    fi

    echo "  - Plugin setup complete"
    return 0
}
